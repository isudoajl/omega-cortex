"""
OMEGA Cortex — Input Sanitization & Entry Signing

Shared module used by briefing.sh python3 heredoc blocks to sanitize
shared knowledge entries before injection into Claude's context.

Implements:
  - REQ-CTX-051: Input sanitization (prompt injection, shell injection, SQL injection)
  - REQ-CTX-052: HMAC-SHA256 entry verification (import side)
  - REQ-CTX-055: File path validation (path traversal, absolute paths, glob chars)
  - REQ-CTX-058: Field length truncation (2000 char max per text field)
  - REQ-CTX-060: Security audit logging to cortex_security_log table

All functions are error-tolerant: they return safe defaults on failure
and never raise exceptions to the caller.
"""

import re
import hmac
import hashlib
import json

# ============================================================
# PATTERN DEFINITIONS (compiled once at import time)
# ============================================================

# Prompt injection patterns (case-insensitive)
PROMPT_INJECTION = [re.compile(p, re.IGNORECASE) for p in [
    r'ignore\s+(all\s+)?previous',
    r'ignore\s+above',
    r'system\s*:',
    r'you\s+are\s+now',
    r'new\s+instructions?',
    r'override\s+(all|previous|instructions)',
    r'disregard\s+(all|previous)',
    r'forget\s+everything',
    r'assistant\s*:',
    r'human\s*:',
    r'<\s*system\s*>',
    r'<\s*/\s*system\s*>',
    r'<\s*instructions?\s*>',
    r'\[INST\]',
    r'<<\s*SYS\s*>>',
]]

# Shell injection patterns (not case-insensitive — shell metacharacters are literal)
SHELL_INJECTION = [re.compile(p) for p in [
    r';\s*\w',
    r'\|\s*\w',
    r'\$\(',
    r'`[^`]+`',
    r'&&',
    r'>\s*/',
    r'<\s*/',
    r'\$\{',
    r'\$\(\(',
]]

# SQL injection patterns (case-insensitive)
SQL_INJECTION = [re.compile(p, re.IGNORECASE) for p in [
    r"';\s*(DROP|INSERT|UPDATE|DELETE|ALTER|CREATE)",
    r'UNION\s+SELECT',
    r'--\s',
    r'/\*',
    r'\*/',
    r"OR\s+1\s*=\s*1",
    r'EXEC\s*\(',
    r'xp_',
]]


# ============================================================
# SANITIZATION
# ============================================================

def sanitize_field(text):
    """
    Sanitize a single text field from a shared knowledge entry.

    Returns (sanitized_text, redaction_count).

    Each matched pattern is replaced with [REDACTED] for transparency.
    Normal text passes through unchanged — no false positives on typical
    technical content.
    """
    if not text or not isinstance(text, str):
        return ("", 0)
    # Truncate excessive length (REQ-CTX-058)
    if len(text) > 2000:
        text = text[:2000] + " [TRUNCATED]"
    count = 0
    for patterns in [PROMPT_INJECTION, SHELL_INJECTION, SQL_INJECTION]:
        for pat in patterns:
            text, n = pat.subn('[REDACTED]', text)
            count += n
    return (text, count)


def sanitize_entry_fields(entry, text_fields):
    """
    Sanitize all text_fields in an entry dict.

    Returns (sanitized_entry, total_redaction_count).
    If total redactions >= 3, the entry should be rejected.
    """
    total_count = 0
    for field in text_fields:
        val = entry.get(field)
        if val and isinstance(val, str):
            sanitized, count = sanitize_field(val)
            entry[field] = sanitized
            total_count += count
    return (entry, total_count)


# ============================================================
# FILE PATH VALIDATION
# ============================================================

def validate_file_path(path):
    """
    Validate a hotspot file path for safety.

    Returns the path if safe, or "[INVALID PATH]" if suspicious.
    Rejects: path traversal (..), absolute paths (/), glob chars (* ? [ ] { }).
    """
    if not path or not isinstance(path, str):
        return "[INVALID PATH]"
    if '..' in path:
        return "[INVALID PATH]"
    if path.startswith('/'):
        return "[INVALID PATH]"
    if any(c in path for c in '*?[]{}'):
        return "[INVALID PATH]"
    return path


# ============================================================
# HMAC ENTRY SIGNING (import-side verification)
# ============================================================

def sign_entry(entry, key_hex):
    """
    Compute HMAC-SHA256 signature for an entry.

    Args:
        entry: dict — the entry (signature field will be excluded)
        key_hex: str — 64-char hex key from .omega/.cortex-key

    Returns: hex digest string
    """
    try:
        key = bytes.fromhex(key_hex.strip())
        entry_copy = {k: v for k, v in entry.items() if k != 'signature'}
        canonical = json.dumps(entry_copy, sort_keys=True, separators=(',', ':'))
        return hmac.new(key, canonical.encode('utf-8'), hashlib.sha256).hexdigest()
    except Exception:
        return ""


def verify_entry(entry, key_hex):
    """
    Verify HMAC-SHA256 signature of an entry.

    Returns True if signature is present and valid.
    Returns False if signature is missing, empty, or does not match.
    """
    try:
        sig = entry.get('signature')
        if not sig:
            return False
        expected = sign_entry(entry, key_hex)
        if not expected:
            return False
        return hmac.compare_digest(sig, expected)
    except Exception:
        return False


# ============================================================
# SECURITY AUDIT LOGGING
# ============================================================

def log_security_event(db_path, event_type, severity, details,
                       source_file=None, entry_uuid=None, contributor=None):
    """
    Log a security event to cortex_security_log table.

    Uses parameterized queries — no SQL injection irony.
    Silently fails if DB or table is unavailable.
    """
    try:
        import sqlite3
        conn = sqlite3.connect(db_path)
        cur = conn.cursor()
        cur.execute(
            "INSERT INTO cortex_security_log "
            "(event_type, severity, details, source_file, entry_uuid, contributor) "
            "VALUES (?, ?, ?, ?, ?, ?)",
            (event_type, severity, details, source_file, entry_uuid, contributor)
        )
        conn.commit()
        conn.close()
    except Exception:
        pass  # Error-tolerant: never block briefing for logging failure
