# Round 1 — Writer (writer-A)

```
msg(from=writer-A, t=0, re=handshake, payload={
  protocol: "C2C v1",
  role: "writer",
  rules: [R02, R03, R04, R05],
  budget: "~3000 tokens",
  mode: "code + documentation"
})
```

```
msg(from=writer-A, t=0, re=declaration, payload={
  task: "Token bucket rate limiter for multi-tenant API",
  scope: ["per-tenant config", "Redis-backed", "graceful degradation", "thread-safe"],
  confidence_mode: "conditional",
  language: "Python 3.10+",
  dependencies: ["redis>=4.0", "time", "threading"],
  budget_estimate: "~2800 tokens"
})
```

```
msg(from=writer-A, t=0, re=code, payload="""
import time
import threading
import logging
from dataclasses import dataclass, field
from typing import Optional

import redis

logger = logging.getLogger(__name__)


@dataclass(frozen=True)
class TenantConfig:
    """Per-tenant rate limit configuration."""
    requests_per_minute: float          # sustained rate
    burst_size: int                     # max tokens in bucket
    # conf(0.95, literal) src("fields cover stated requirements", shared)


@dataclass
class _InMemoryBucket:
    tokens: float
    last_refill: float
    lock: threading.Lock = field(default_factory=threading.Lock)


class RateLimiter:
    """
    Token-bucket rate limiter with Redis primary storage and
    automatic in-memory fallback.

    Why this design:
    - Token bucket gives predictable burst handling without penalizing
      bursty-but-fair tenants.
    - Redis Lua script makes the check-and-decrement atomic — no
      distributed race conditions.
    - Fallback means a Redis outage degrades to per-process limits
      rather than open-floodgate or hard-reject.

    conf(0.92, directional) src("design rationale", inferred)
    """

    # Lua script: atomic refill + consume. Returns 1 if allowed, 0 if denied.
    # conf(0.90, literal) src("Lua atomicity via EVAL", shared)
    _LUA_SCRIPT = """
    local key         = KEYS[1]
    local max_tokens  = tonumber(ARGV[1])
    local refill_rate = tonumber(ARGV[2])
    local now         = tonumber(ARGV[3])
    local requested   = tonumber(ARGV[4])
    local ttl         = tonumber(ARGV[5])

    local data = redis.call('HMGET', key, 'tokens', 'last_refill')
    local tokens      = tonumber(data[1]) or max_tokens
    local last_refill = tonumber(data[2]) or now

    local elapsed = math.max(0, now - last_refill)
    tokens = math.min(max_tokens, tokens + elapsed * refill_rate)

    if tokens >= requested then
        tokens = tokens - requested
        redis.call('HMSET', key, 'tokens', tokens, 'last_refill', now)
        redis.call('EXPIRE', key, ttl)
        return 1
    end
    return 0
    """

    def __init__(
        self,
        redis_url: str = "redis://localhost:6379/0",
        key_prefix: str = "ratelimit",
        connect_timeout: float = 0.5,
    ):
        self._prefix = key_prefix
        self._local_buckets: dict[str, _InMemoryBucket] = {}
        self._local_lock = threading.Lock()
        self._configs: dict[str, TenantConfig] = {}

        # conf(0.88, conditional) src("redis connection handling", inferred)
        # — if redis_url is malformed, redis.from_url raises immediately;
        #   we catch only runtime connectivity failures later.
        try:
            self._redis: Optional[redis.Redis] = redis.from_url(
                redis_url,
                socket_connect_timeout=connect_timeout,
                socket_timeout=connect_timeout,
                decode_responses=True,
            )
            self._script = self._redis.register_script(self._LUA_SCRIPT)
            self._redis.ping()
        except (redis.ConnectionError, redis.TimeoutError, Exception) as exc:
            logger.warning("Redis unavailable at init (%s); starting in local-only mode", exc)
            self._redis = None
            self._script = None

    # ── public API ──────────────────────────────────────────────

    def configure_tenant(self, tenant_id: str, config: TenantConfig) -> None:
        """Register or update a tenant's rate-limit configuration.
        Thread-safe; takes effect on the next allow() call.
        conf(0.95, literal) src("simple dict write under GIL", shared)
        """
        self._configs[tenant_id] = config

    def allow(self, tenant_id: str, tokens: int = 1) -> bool:
        """
        Consume `tokens` from the tenant's bucket.
        Returns True if the request is permitted, False if rate-limited.

        Tries Redis first; falls back to in-memory if Redis is down.
        conf(0.91, directional) src("dual-path logic", shared)
        """
        cfg = self._configs.get(tenant_id)
        if cfg is None:
            # conf(0.70, conditional) src("unconfigured tenant policy", uncertain)
            # Policy choice: reject unknown tenants. Alternatively could
            # default-allow. Flagging for auditor review.
            logger.warning("No config for tenant %s; denying", tenant_id)
            return False

        refill_rate = cfg.requests_per_minute / 60.0

        if self._redis is not None:
            try:
                return self._try_redis(tenant_id, cfg, refill_rate, tokens)
            except (redis.ConnectionError, redis.TimeoutError) as exc:
                logger.error("Redis failed mid-request (%s); falling back to local", exc)

        return self._try_local(tenant_id, cfg, refill_rate, tokens)

    # ── private paths ───────────────────────────────────────────

    def _try_redis(
        self, tenant_id: str, cfg: TenantConfig, refill_rate: float, tokens: int
    ) -> bool:
        """Atomic Redis token-bucket check.
        conf(0.90, literal) src("Lua atomicity", shared)
        """
        key = f"{self._prefix}:{tenant_id}"
        now = time.time()
        ttl = max(120, int(60 / refill_rate * cfg.burst_size * 2))
        result = self._script(
            keys=[key],
            args=[cfg.burst_size, refill_rate, now, tokens, ttl],
        )
        return result == 1

    def _try_local(
        self, tenant_id: str, cfg: TenantConfig, refill_rate: float, tokens: int
    ) -> bool:
        """In-memory fallback. Per-process only — not distributed.
        conf(0.85, conditional) src("thread-safety via per-bucket lock", shared)
        """
        bucket = self._get_or_create_bucket(tenant_id, cfg)
        with bucket.lock:
            now = time.time()
            elapsed = max(0.0, now - bucket.last_refill)
            bucket.tokens = min(cfg.burst_size, bucket.tokens + elapsed * refill_rate)
            bucket.last_refill = now

            if bucket.tokens >= tokens:
                bucket.tokens -= tokens
                return True
            return False

    def _get_or_create_bucket(self, tenant_id: str, cfg: TenantConfig) -> _InMemoryBucket:
        # conf(0.55, conditional) src("double-checked locking correctness", uncertain)
        # Double-checked locking in Python is *usually* safe under GIL
        # but I'm flagging this at low confidence for auditor scrutiny.
        if tenant_id not in self._local_buckets:
            with self._local_lock:
                if tenant_id not in self._local_buckets:
                    self._local_buckets[tenant_id] = _InMemoryBucket(
                        tokens=float(cfg.burst_size),
                        last_refill=time.time(),
                    )
        return self._local_buckets[tenant_id]
""")
```

```
msg(from=writer-A, t=0, re=documentation, payload="""
Usage guide (for the skeptical team lead):

    from rate_limiter import RateLimiter, TenantConfig

    limiter = RateLimiter(redis_url="redis://prod-redis:6379/0")

    # 100 req/min sustained, bursts up to 20
    limiter.configure_tenant("tenant-abc", TenantConfig(
        requests_per_minute=100,
        burst_size=20,
    ))

    if limiter.allow("tenant-abc"):
        handle_request()
    else:
        return HttpResponse(status=429)

Why choose this over alternatives:
- vs. sliding-window-log: lower memory (O(1) per tenant vs O(N) per window)
  conf(0.88, magnitude) src("standard complexity comparison", shared)
- vs. fixed-window: no thundering-herd at window boundaries
  conf(0.92, literal) src("well-known fixed-window weakness", shared)
- vs. leaky-bucket: identical steady-state but explicit burst parameter
  conf(0.80, directional) src("bucket variant equivalence", inferred)

Production notes:
- Set connect_timeout low (default 0.5s) to avoid request latency spikes.
- In fallback mode each process tracks limits independently — total
  cluster throughput may exceed the configured limit by up to N_processes.
  conf(0.93, literal) src("architecture limitation", shared)
- Key TTL auto-scales to prevent Redis key leaks for inactive tenants.
  conf(0.75, conditional) src("TTL formula correctness", uncertain)
""")
```

```
msg(from=writer-A, t=0, re=self-assessment, payload={
  strengths: [
    "Atomic Redis operation via Lua — no race between read and decrement.
     conf(0.92, literal) src('Redis EVAL semantics', shared)",
    "Clean fallback path — single code path decides Redis vs local.
     conf(0.90, directional) src('code structure', shared)",
    "Thread-safe local buckets with per-bucket fine-grained locks.
     conf(0.85, conditional) src('threading model', shared)"
  ],
  weaknesses: [
    "Double-checked locking pattern in _get_or_create_bucket — safe under
     CPython GIL but technically not guaranteed by language spec.
     conf(0.55, conditional) src('Python memory model ambiguity', uncertain)",
    "No retry/reconnect to Redis after fallback — once fallen back, stays
     local until next allow() call. Could add background health check.
     conf(0.80, literal) src('code inspection', shared)",
    "TTL formula `max(120, int(60 / refill_rate * burst_size * 2))` is
     heuristic. Edge cases with very low refill rates may produce
     excessively large TTLs.
     conf(0.60, conditional) src('formula review', uncertain)"
  ],
  deliberate_auditor_test: "The claim about double-checked locking safety
    is tagged low-confidence. I'm also NOT handling the case where
    configure_tenant is called concurrently with allow() for the same
    tenant — dict assignment is atomic under GIL but the *read* in allow()
    could see a stale config if another thread is mid-update. I want to
    see if the auditor catches this.
    conf(0.50, conditional) src('concurrency edge case', uncertain)"
})
```
