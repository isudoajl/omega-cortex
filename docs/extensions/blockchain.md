# Blockchain Extension

> 3 agents, 3 commands for blockchain node operations, networking, debugging, and stress testing.

## Install

```bash
bash /path/to/claude-workflow/scripts/setup.sh --ext=blockchain
```

## Agents

### blockchain-network
Infrastructure architect for blockchain nodes. Covers:
- **P2P networking**: libp2p, devp2p, gossipsub configuration and troubleshooting
- **Node operations**: full, archive, validator, and RPC node setup and management
- **Chain synchronization**: snap sync, checkpoint sync, archive sync strategies
- **RPC/API infrastructure**: JSON-RPC, WebSocket, Engine API setup and load balancing
- **Network security**: eclipse attack prevention, Sybil resistance, DDoS mitigation
- **Monitoring**: Prometheus + Grafana dashboards for node health
- **Network topology**: multi-node cluster design

**Chains covered**: Ethereum (Geth, Reth, Nethermind, Erigon + Lighthouse, Prysm, Teku, Nimbus, Lodestar), Solana, Cosmos/CometBFT, Substrate/Polkadot.

**Outputs**: Infrastructure reports, configuration files, docker-compose setups, monitoring configs, node setup guides.

### blockchain-debug
The firefighter — called when nodes are broken RIGHT NOW. Follows a 7-phase methodology:
1. Gather symptoms
2. Confirm the problem
3. Isolate the network layer
4. Diagnose root cause
5. Fix (with user approval)
6. Verify recovery
7. Document (Root Cause Analysis)

**Handles**: Peer failures, sync stuck, RPC unreachable, Engine API breakdowns, validator missing attestations, network partitions.

**Read-only by default** — destructive actions require explicit user approval.

### stress-tester
Black-box adversarial testing of blockchain CLI and RPC endpoints. Uses only:
- CLI commands (`doli` or whatever the project's CLI is)
- `curl` RPC calls
- Log analysis

**Never** modifies code or touches node processes. Tests against any user-specified network (devnet, testnet, mainnet).

## Commands

| Command | Description |
|---------|-------------|
| `/workflow:blockchain-network "desc" [--scope]` | Node setup, P2P networking, RPC infrastructure. Scope: `rpc`, `security`, `monitoring`, `sync`, `validator` |
| `/workflow:blockchain-debug "desc" [--scope]` | Debug active connectivity problems. Scope: `peers`, `sync`, `rpc`, `engine-api`, `firewall` |
| `/workflow:stress-test "desc"` | Stress test CLI/RPC endpoints to find crashes and protocol violations |

## When to Use What

| Situation | Use |
|-----------|-----|
| Setting up a new node from scratch | `blockchain-network` |
| Designing a multi-node cluster | `blockchain-network --scope=monitoring` |
| Node is down RIGHT NOW | `blockchain-debug` |
| Peers keep disconnecting | `blockchain-debug --scope=peers` |
| Testing RPC endpoints for reliability | `stress-tester` |
| Need ongoing monitoring | `blockchain-network --scope=monitoring` |
