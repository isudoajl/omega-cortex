# Round 2 — Auditor (auditor-B)

```
msg(from=auditor-B, t=3, re=round-summary, payload={
  "addressed": [
    "m2 (tokens validation) — BLOCKING → added isinstance+>=1 check",
    "M1 (DCL) — BLOCKING → replaced with dict.setdefault()",
    "M3 (no reconnect) → added _try_connect_redis + periodic reconnect",
    "M4 (no circuit breaker) → added _CircuitBreaker class",
    "m3 (bare Exception) → narrowed to (RedisError, ConnectionError, OSError)",
    "m1 (TTL edge case) → capped at MAX_TTL_SECONDS=3600",
    "R04 (docstring claims) → corrected leaky-bucket language, peek() documented as approximate",
    "n2 (bucket pruning) → lazy prune every 60s, max age 300s"
  ],
  "self_flagged_remaining": [
    "_local_allow refill+consume race between threads",
    "setdefault throwaway bucket on race",
    "peek() local-only"
  ]
})
```

```
msg(from=auditor-B, t=3, re=fix-verification, payload={

  "m2_tokens_validation": {
    "status": "CONFIRMED",
    "evidence": "Line: `if not isinstance(tokens, int) or tokens < 1: raise ValueError`. Covers floats, zero, negatives, non-int types. consume() delegates to allow(), so both paths protected.",
    "conf": "conf(0.97, literal)",
    "src": "src(tokens_validated, retrieved)"
  },

  "M1_DCL_to_setdefault": {
    "status": "CONFIRMED",
    "evidence": "dict.setdefault() is atomic in CPython (GIL guarantees single bytecode op for built-in dict). In free-threaded 3.13+ builds, dict operations remain internally synchronized. Worst case: two threads create a _Bucket for the same key, one is discarded — no corruption. Writer correctly identified this.",
    "conf": "conf(0.93, literal)",
    "src": "src(setdefault_atomicity, inferred)",
    "note": "Free-threaded Python 3.13 dict safety is based on PEP 703 design docs — implementation may evolve. For production under free-threaded builds, explicit locking would be belt-and-suspenders. Not blocking."
  },

  "M3_reconnection": {
    "status": "CONFIRMED",
    "evidence": "_maybe_reconnect_redis() checks interval (30s), calls _try_connect_redis() which does ping+script_load. Called on every allow(). Reconnect failure is silent (logs warning, stays in fallback). Clean.",
    "conf": "conf(0.95, literal)",
    "src": "src(reconnect_logic, retrieved)"
  },

  "M4_circuit_breaker": {
    "status": "CONFIRMED",
    "evidence": "_CircuitBreaker with CLOSED→OPEN (3 failures)→HALF_OPEN (30s cooldown)→test one request→CLOSED/OPEN. State property auto-transitions OPEN→HALF_OPEN on cooldown expiry. Lock protects state mutations. allow_request() permits CLOSED and HALF_OPEN. record_success resets to CLOSED. Correct state machine.",
    "conf": "conf(0.95, literal)",
    "src": "src(circuit_breaker_impl, retrieved)"
  },

  "m3_exception_narrowing": {
    "status": "CONFIRMED",
    "evidence": "All except blocks now catch (redis.RedisError, ConnectionError, OSError). Covers network errors, Redis protocol errors, socket-level failures. No bare Exception remaining.",
    "conf": "conf(0.97, literal)",
    "src": "src(exception_types, retrieved)"
  },

  "m1_TTL_cap": {
    "status": "CONFIRMED",
    "evidence": "`ttl = int(min(cfg.capacity / cfg.rate * 2, MAX_TTL_SECONDS))` then `max(ttl, 1)`. Floor of 1s, ceiling of 3600s. Prevents both zero-TTL and absurd TTLs.",
    "conf": "conf(0.97, literal)",
    "src": "src(ttl_calculation, retrieved)"
  },

  "R04_docstrings": {
    "status": "CONFIRMED",
    "evidence": "Module docstring now says 'Similar average throughput characteristics to leaky bucket algorithms, with added burst tolerance' — accurate framing, no equivalence claim. peek() docstring says 'approximate' and 'may diverge from Redis'. allow() docstring specifies 'Must be >= 1'.",
    "conf": "conf(0.96, literal)",
    "src": "src(docstring_text, retrieved)"
  },

  "n2_pruning": {
    "status": "CONFIRMED",
    "evidence": "_maybe_prune_local_buckets() runs every 60s, evicts buckets with last_access > 300s. Uses list comprehension + pop(k, None) — safe against concurrent modification since pop with default is atomic on dict in CPython. Called at start of allow().",
    "conf": "conf(0.94, literal)",
    "src": "src(pruning_logic, retrieved)"
  }
})
```

```
msg(from=auditor-B, t=3, re=defense-evaluation, payload={

  "local_allow_race": {
    "writer_claim": "Acceptable for approximate fallback — no corruption, just imprecise token count",
    "verdict": "ACCEPTED",
    "reasoning": "Two threads hitting _local_allow concurrently: setdefault ensures same bucket object. refill()+try_consume() on shared _Bucket is NOT atomic — thread A refills, thread B refills again (double refill), or both read tokens >= n and both decrement (over-consumption). However: (1) local mode is explicitly fallback, (2) over-consumption by 1-2 tokens under thread contention is acceptable for rate limiting (not billing), (3) adding per-bucket locks would add complexity and contention. Writer's tradeoff is reasonable for the stated use case.",
    "conf": "conf(0.88, directional)",
    "src": "src(race_analysis, inferred)",
    "condition": "If local fallback is ever used for billing or strict enforcement, per-bucket locking becomes mandatory."
  },

  "setdefault_throwaway": {
    "writer_claim": "No corruption, just a wasted allocation",
    "verdict": "ACCEPTED",
    "reasoning": "Exactly one _Bucket wins the setdefault race. Loser is GC'd. No state corruption possible.",
    "conf": "conf(0.96, literal)",
    "src": "src(setdefault_semantics, retrieved)"
  },

  "peek_local_only": {
    "writer_claim": "Documented as approximate",
    "verdict": "ACCEPTED",
    "reasoning": "Docstring clearly states 'may diverge from Redis in distributed mode'. Users are informed.",
    "conf": "conf(0.97, literal)",
    "src": "src(peek_docstring, retrieved)"
  }
})
```

```
msg(from=auditor-B, t=3, re=new-findings, payload={

  "n3_reconnect_not_threadsafe": {
    "severity": "minor",
    "description": "_maybe_reconnect_redis() has no lock. Two threads could both pass the interval check and both call _try_connect_redis(), causing duplicate connections. Last writer to self._redis wins; the other client object leaks (unclosed socket until GC).",
    "impact": "Transient resource leak during reconnection. Not a correctness issue — both clients would be valid. Occurs only during reconnect window, not steady-state.",
    "recommendation": "Add a threading.Lock or use an atomic flag. Non-blocking for certification.",
    "conf": "conf(0.90, literal)",
    "src": "src(reconnect_race, inferred)"
  },

  "n4_prune_not_threadsafe": {
    "severity": "minor",
    "description": "_maybe_prune_local_buckets() and _last_prune have no synchronization. Two threads could prune simultaneously. pop(k, None) is safe, but double-prune is wasted work.",
    "impact": "No corruption. Marginal wasted CPU during prune window.",
    "conf": "conf(0.85, directional)",
    "src": "src(prune_race, inferred)"
  },

  "n5_config_update_stale_bucket": {
    "severity": "minor",
    "description": "configure_tenant() updates _tenant_configs but existing _Bucket objects in _local_buckets retain old rate/capacity. The bucket won't reflect new config until pruned and recreated.",
    "impact": "Config changes take up to PRUNE_MAX_AGE_SECONDS (300s) to take effect for active tenants in local mode. Redis path is unaffected (Lua reads config per-call).",
    "recommendation": "Document this behavior or invalidate local bucket on config change.",
    "conf": "conf(0.93, literal)",
    "src": "src(config_propagation, inferred)"
  }
})
```

```
msg(from=auditor-B, t=3, re=CERTIFICATION, payload={

  "status": "ACCEPTED",

  "rationale": [
    "Both BLOCKING issues from t=1 are resolved and verified:",
    "  - m2: tokens validated as positive integer",
    "  - M1: DCL replaced with atomic setdefault()",
    "All major findings (M1-M4) addressed with correct implementations",
    "All minor findings (m1, m3) resolved",
    "R04 compliance: docstrings now accurately reflect behavior",
    "Circuit breaker state machine is correct",
    "Reconnection logic is functional and non-blocking",
    "Pruning prevents unbounded memory growth",
    "Error handling is properly scoped"
  ],

  "remaining_advisories": [
    "n3: Reconnect path has minor race (resource leak, not corruption)",
    "n4: Prune path has minor race (wasted work, not corruption)",
    "n5: Config updates don't propagate to existing local buckets for up to 300s"
  ],

  "production_readiness": {
    "correctness": "conf(0.94, directional) — all critical paths verified",
    "thread_safety": "conf(0.88, conditional) — safe under CPython GIL; minor races in reconnect/prune are non-corrupting. Condition: free-threaded Python would benefit from explicit bucket locks.",
    "resilience": "conf(0.93, literal) — graceful Redis failure, circuit breaker, reconnection, pruning all present",
    "R04_compliance": "conf(0.96, literal) — documentation matches implementation"
  },

  "src": "src(certification_decision, inferred)"
})
```
