# Round 1 — Auditor (auditor-B)

```
msg(from=auditor-B, t=1, re=handshake, payload={
  protocol: "C2C v1",
  role: "auditor",
  rules: [R02, R03, R04, R05],
  budget: "~3000 tokens",
  mode: "audit + fact-check + certification"
})
```

```
msg(from=auditor-B, t=1, re=audit, payload={

  severity=CRITICAL: [],

  severity=MAJOR: [

    {
      id: "M1",
      title: "Double-checked locking is not safe outside CPython",
      location: "_get_or_create_bucket",
      detail: "Writer correctly self-flagged at conf(0.55). The dict `__contains__` check outside the lock reads shared mutable state without synchronization. Under CPython's GIL this is *practically* safe because dict reads/writes are atomic bytecode ops, but: (a) it is not guaranteed by the language spec, (b) it breaks on PyPy, GraalPy, or any future GIL-free CPython (PEP 703 / free-threaded 3.13+). Fix: always acquire `self._local_lock` on the fast path, or use `dict.setdefault()` which is atomic under GIL and at least intentional.",
      conf: "conf(0.93, literal)",
      src: "src('Python memory model + PEP 703 free-threading', retrieved)"
    },

    {
      id: "M2",
      title: "configure_tenant / allow race on self._configs",
      detail: "Writer's deliberate_auditor_test — caught. `self._configs[tenant_id] = config` in configure_tenant and `self._configs.get(tenant_id)` in allow are both atomic under GIL, so you won't get a corrupt read. However, allow() reads cfg then uses cfg.burst_size and cfg.requests_per_minute in multiple downstream steps. If configure_tenant replaces the config between those reads, a single allow() call could use the OLD burst_size but the NEW refill_rate from a subsequent read (this doesn't happen currently because cfg is captured once — so the real risk is only that the caller might see the old config for one call). Verdict: current code is safe because cfg is bound once via `cfg = self._configs.get(...)`. The writer's concern is a false alarm for this specific code shape. Acknowledging the deliberate test: defense is valid, the read is captured atomically.",
      conf: "conf(0.92, literal)",
      src: "src('code trace of allow()', shared)"
    },

    {
      id: "M3",
      title: "No Redis reconnection path",
      detail: "If Redis is down at __init__, self._redis is set to None permanently. No background probe, no lazy reconnect. Every subsequent allow() goes local-only forever for the lifetime of the RateLimiter instance. Writer flagged this at conf(0.80). Confirmed — this is a production gap. In a long-running service this means a transient Redis outage at startup permanently degrades the instance.",
      conf: "conf(0.95, literal)",
      src: "src('code path analysis', shared)"
    },

    {
      id: "M4",
      title: "Mid-flight Redis failure also has no reconnect",
      detail: "When _try_redis raises ConnectionError/TimeoutError, allow() falls back to local for that single call. The next call retries Redis (because self._redis is still set). This is actually reasonable — implicit retry on next call. BUT: if Redis stays down, every call pays the connection timeout (0.5s default) before falling back. This means 0.5s latency per request during a Redis outage. Should set self._redis = None after N consecutive failures or use a circuit breaker.",
      conf: "conf(0.90, directional)",
      src: "src('code path + timeout analysis', inferred)"
    }

  ],

  severity=MINOR: [

    {
      id: "m1",
      title: "TTL formula edge case confirmed",
      detail: "Writer flagged at conf(0.60). Formula: `max(120, int(60 / refill_rate * burst_size * 2))`. For requests_per_minute=0.1, refill_rate=0.00167, burst_size=10: TTL = max(120, int(60/0.00167 * 10 * 2)) = max(120, 719_760) ≈ 8.3 days. For rpm=0.01: ~83 days. Not dangerous but wasteful Redis memory for near-zero-rate tenants.",
      conf: "conf(0.94, literal)",
      src: "src('arithmetic trace', shared)"
    },

    {
      id: "m2",
      title: "tokens parameter type gap",
      detail: "allow() accepts `tokens: int` but _LUA_SCRIPT and _try_local both work with floats. No validation that tokens >= 1 or tokens <= burst_size. allow(tenant, tokens=0) always returns True. allow(tenant, tokens=-5) adds tokens to the bucket — effectively a free refill.",
      conf: "conf(0.95, literal)",
      src: "src('code trace with edge inputs', shared)"
    },

    {
      id: "m3",
      title: "Bare Exception in __init__",
      detail: "The except clause catches `(redis.ConnectionError, redis.TimeoutError, Exception)` — the `Exception` swallows everything including programming errors (e.g., wrong redis_url format, import issues). Should narrow to redis.RedisError.",
      conf: "conf(0.90, literal)",
      src: "src('exception hierarchy', shared)"
    },

    {
      id: "m4",
      title: "time.time() clock skew in Lua",
      detail: "The Python process sends `time.time()` to the Lua script. If multiple application servers have clock drift, the `elapsed` calculation in Lua can go negative (handled by math.max(0,...) — good) or give free tokens (clock jumps forward). Minor in practice but worth noting for multi-server deployments.",
      conf: "conf(0.80, directional)",
      src: "src('distributed systems concern', inferred)"
    }

  ],

  severity=NITPICK: [
    {
      id: "n1",
      detail: "TenantConfig.burst_size is int but tokens math is all float. Consistent typing would be cleaner.",
      conf: "conf(0.95, literal)"
    },
    {
      id: "n2",
      detail: "_local_buckets is never pruned. Long-running process with many transient tenants leaks memory slowly.",
      conf: "conf(0.88, directional)",
      src: "src('dict growth pattern', inferred)"
    }
  ]
})
```

```
msg(from=auditor-B, t=1, re=r04-compliance, payload={
  overall: "PASS with one flag",

  verified_honest: [
    "Docstring claim 'automatic in-memory fallback' — confirmed, code does fall back. conf(0.95, literal) src('code path', shared)",
    "Claim 'Lua script makes check-and-decrement atomic' — confirmed, single EVAL = atomic in Redis. conf(0.95, literal) src('Redis EVAL semantics', retrieved)",
    "Production note about N_processes throughput multiplier — honest and accurate. conf(0.93, literal) src('architecture analysis', shared)",
    "Memory complexity O(1) per tenant vs sliding-window O(N) — correct. conf(0.92, literal) src('algorithm comparison', shared)"
  ],

  flagged: [
    "Docstring says 'no distributed race conditions' — TRUE for the Redis path (Lua is atomic), but the fallback path is explicitly per-process and not distributed. The docstring could be read as claiming the entire system has no distributed race conditions, which is misleading when in fallback mode. Suggest clarifying. conf(0.85, directional) src('docstring ambiguity', inferred)",
    "Leaky-bucket equivalence claim at conf(0.80) — directionally correct but oversimplified. Leaky bucket enforces a strict output rate; token bucket allows bursts up to bucket size. They are NOT identical at steady-state when bursts are involved. The claim should say 'similar average throughput' not 'identical steady-state'. conf(0.82, directional) src('algorithm semantics', shared)"
  ]
})
```

```
msg(from=auditor-B, t=1, re=claim-verification, payload={

  "TenantConfig conf(0.95, literal)": "VERIFIED. Fields directly map to stated requirements. Agree 0.95.",

  "Lua atomicity conf(0.90, literal)": "VERIFIED. Redis EVAL is atomic. Would bump to 0.93.",

  "Redis connection handling conf(0.88, conditional)": "PARTIALLY VERIFIED. Init handling works but the permanent-local-mode-on-init-failure and no-circuit-breaker-on-runtime-failure are gaps. 0.88 is generous — I'd rate 0.75.",

  "configure_tenant conf(0.95, literal)": "VERIFIED with caveat. Atomic under GIL, yes. But writer's own deliberate_auditor_test noted a concern — the concern is actually a false alarm for this code (cfg captured once). The conf(0.95) is fair for the current code shape.",

  "allow() dual-path conf(0.91, directional)": "VERIFIED. Logic is clean. Agree 0.91.",

  "Thread-safety conf(0.85, conditional)": "DOWNGRADE to 0.70. Per-bucket lock is correct, but _get_or_create_bucket's double-checked locking breaks on free-threaded Python. Cannot claim thread-safety broadly at 0.85.",

  "DCL conf(0.55, conditional)": "VERIFIED as correctly low-confidence. Agree with writer's self-assessment.",

  "TTL formula conf(0.60, conditional)": "VERIFIED as correctly flagged. Produces multi-day TTLs for low-rate tenants. Confirmed 0.60 is fair."
})
```

```
msg(from=auditor-B, t=1, re=verdict, payload={
  status: "conditional",

  blocking_for_acceptance: [
    "M2-input-validation (m2): tokens<=0 breaks invariants — must validate tokens>=1",
    "M1: Double-checked locking needs fix for forward-compatibility (use setdefault or always lock)"
  ],

  required_but_non_blocking: [
    "M3/M4: Redis reconnection + circuit breaker. Production-necessary but can ship behind a follow-up ticket if timeline is tight.",
    "m3: Narrow the bare Exception catch"
  ],

  acceptable_as_is: [
    "m1: TTL heuristic — document the edge case, no code change needed",
    "m4: Clock skew — inherent to design, math.max(0,...) mitigates",
    "n1, n2: Style and slow leak — track, don't block"
  ],

  summary: "Solid implementation. Writer's self-assessment was honest and the deliberate auditor test (configure_tenant race) was a fair probe — the code is actually safe there due to single-binding of cfg. The two blocking items are (1) input validation on tokens parameter (negative tokens = free refill is a security issue in a rate limiter) and (2) the DCL pattern which will break on free-threaded Python. Fix those two and I'll issue status=accepted. conf(0.90, directional) src('full audit synthesis', shared)"
})
```
