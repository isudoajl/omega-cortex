"""
Token-bucket rate limiter with per-client tracking, configurable rate/burst,
and thread-safety guarantees.

msg(from=writer-A, t=2, re=IMPLEMENTATION,
    conf(0.92, literal),
    src("implementation follows standard token-bucket algorithm", shared))
"""

import threading
import time
from typing import Dict


class TokenBucket:
    """A single token bucket for one client.

    Tokens refill at `rate` tokens per second up to a maximum of `burst` tokens.
    Calls to `consume` are O(1) — refill is computed lazily on each access.
    """

    __slots__ = ("rate", "burst", "tokens", "last_refill")

    def __init__(self, rate: float, burst: int) -> None:
        if rate <= 0:
            raise ValueError("rate must be positive")
        if burst <= 0:
            raise ValueError("burst must be a positive integer")
        self.rate: float = rate
        self.burst: int = burst
        self.tokens: float = float(burst)  # start full
        self.last_refill: float = time.monotonic()

    def _refill(self) -> None:
        now = time.monotonic()
        elapsed = now - self.last_refill
        self.tokens = min(self.burst, self.tokens + elapsed * self.rate)
        self.last_refill = now

    def try_consume(self, n: int = 1) -> bool:
        self._refill()
        if self.tokens >= n:
            self.tokens -= n
            return True
        return False


class RateLimiter:
    """Per-client token-bucket rate limiter.

    Parameters
    ----------
    rate : float
        Sustained token refill rate (tokens per second).
    burst : int
        Maximum number of tokens a bucket can hold (peak burst size).

    Thread Safety
    -------------
    A single `threading.Lock` serialises all bucket mutations.  This is
    correct and simple.  Under extreme contention (>10 000 concurrent
    clients on a single process) a sharded-lock or per-bucket lock design
    would reduce contention — see self-assessment at t=4.

    Usage
    -----
    >>> limiter = RateLimiter(rate=10.0, burst=20)
    >>> limiter.consume("client-42")          # True  (first call, bucket is full)
    >>> limiter.consume("client-42", tokens=25)  # False (exceeds burst)
    """

    def __init__(self, rate: float, burst: int) -> None:
        self._rate = rate
        self._burst = burst
        self._buckets: Dict[str, TokenBucket] = {}
        self._lock = threading.Lock()

    # -- public API ----------------------------------------------------------

    def consume(self, client_id: str, tokens: int = 1) -> bool:
        """Attempt to consume *tokens* from the bucket for *client_id*.

        Returns ``True`` if the tokens were available and have been removed,
        ``False`` otherwise (the request should be rejected / throttled).
        """
        with self._lock:
            bucket = self._buckets.get(client_id)
            if bucket is None:
                bucket = TokenBucket(self._rate, self._burst)
                self._buckets[client_id] = bucket
            return bucket.try_consume(tokens)

    def peek(self, client_id: str) -> float:
        """Return the current token count for *client_id* without consuming."""
        with self._lock:
            bucket = self._buckets.get(client_id)
            if bucket is None:
                return float(self._burst)
            bucket._refill()
            return bucket.tokens

    def reset(self, client_id: str) -> None:
        """Remove the bucket for *client_id*, effectively resetting it."""
        with self._lock:
            self._buckets.pop(client_id, None)

    def active_clients(self) -> int:
        """Return the number of tracked client buckets."""
        with self._lock:
            return len(self._buckets)
