# Cortex Bridge Extension

> Self-hosted sync bridge for OMEGA Cortex collective intelligence.

## Overview

The Cortex Bridge is a lightweight Rust HTTP server that enables real-time OMEGA Cortex knowledge sync between team members. It replaces the default git push/pull cycle with instant HTTP-based sync for teams that want lower latency.

## Technology

- **Language**: Rust (edition 2024, MSRV 1.85)
- **HTTP framework**: axum 0.8
- **Async runtime**: tokio (multi-thread)
- **TLS**: rustls via axum-server (pure Rust, no OpenSSL)
- **Storage**: SQLite via rusqlite (bundled)
- **Auth**: HMAC-SHA256 via ring + Bearer token
- **Serialization**: serde + serde_json

## What It Does

| Endpoint | Auth | Purpose |
|----------|------|---------|
| `GET /api/health` | None | Health check |
| `GET /api/status` | Bearer | Entry counts + last sync time |
| `POST /api/export` | Bearer + HMAC | Receive entries from curator |
| `GET /api/import?since=` | Bearer | Return entries since timestamp |

## Authentication

Dual authentication:
1. **Bearer token** -- constant-time comparison
2. **HMAC-SHA256** (export only) -- signature over `<timestamp>.<body>` with shared key; 5-minute replay window

## Deployment

Three deployment options:
- **Docker** (recommended): `docker compose up -d`
- **Bare metal**: `cargo build --release && ./target/release/cortex-bridge`
- **systemd service**: See `extensions/cortex-bridge/README.md`

Rate limited at 100 requests/minute globally.

## Configuration

All via environment variables:

| Variable | Required | Default |
|----------|----------|---------|
| `CORTEX_BRIDGE_TOKEN` | Yes | -- |
| `CORTEX_BRIDGE_HMAC_KEY` | Yes | -- |
| `CORTEX_BRIDGE_HOST` | No | `0.0.0.0` |
| `CORTEX_BRIDGE_PORT` | No | `8443` |
| `CORTEX_BRIDGE_DB_PATH` | No | `./cortex-bridge.db` |
| `CORTEX_BRIDGE_TLS_CERT` | No | -- |
| `CORTEX_BRIDGE_TLS_KEY` | No | -- |

## Client Configuration

In the target project's `.omega/cortex-config.json`, set backend to `self-hosted` and provide the endpoint URL and auth token env var. Use `/omega:cortex-config` to configure interactively.

## Related

- [Cortex Protocol](../../core/protocols/cortex-protocol.md) -- JSONL format, curation rules
- [Sync Adapters](../../core/protocols/sync-adapters.md) -- Adapter interface specification
- [Cortex Architecture Spec](../../specs/cortex-architecture.md) -- Full architecture design
