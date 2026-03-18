# Architecture: OMEGA CLI (`omg`)

> Rewriting the OMEGA workflow toolkit as a distributable Rust binary.

## Scope

This architecture covers the complete replacement of `scripts/setup.sh`, `scripts/db-init.sh`, and the deployment model with a single Rust binary (`omg`) that users install globally and run in target projects. The binary embeds all assets (agents, commands, hooks, SQL schema, workflow rules, extensions) and provides subcommands for initialization, updates, health checks, and self-updates.

## Overview

```
                        omg binary (single file, ~5-10MB)
                        ================================
                        |  Embedded Assets               |
                        |  - 14 core agents (.md)        |
                        |  - 14 core commands (.md)      |
                        |  - 5 hooks (.sh)               |
                        |  - SQL schema + queries         |
                        |  - CLAUDE.md workflow rules     |
                        |  - Extension packs (blockchain, |
                        |    c2c-protocol, future ones)   |
                        |  - Default settings.json        |
                        |  - Default scaffold templates   |
                        |                                 |
                        |  Rust Modules                   |
                        |  - CLI parser (clap)            |
                        |  - Asset registry               |
                        |  - Deploy engine                |
                        |  - SQLite manager (rusqlite)    |
                        |  - CLAUDE.md injector           |
                        |  - Settings.json merger         |
                        |  - Version tracker              |
                        |  - Self-updater                 |
                        |  - Doctor / diagnostics         |
                        =================================

User runs:
  $ omg init                    # Deploy to current project
  $ omg init --ext=blockchain   # Deploy with extension
  $ omg update                  # Update deployed files
  $ omg doctor                  # Health check
  $ omg self-update             # Update the binary itself
```

## Modules

### Module 1: `cli` (Command Line Interface)

- **Responsibility**: Parse arguments, dispatch to subcommands, manage global flags, produce colored terminal output.
- **Public interface**:
  - `fn main()` -- entry point, delegates to `clap` subcommand dispatch
  - `struct Cli` -- top-level clap derive struct
  - `enum Commands` -- `Init`, `Update`, `Doctor`, `SelfUpdate`, `ListExt`, `Version`, `Completions`
- **Dependencies**: `clap` (v4, derive), `console`/`indicatif` (terminal formatting), all other modules
- **Implementation order**: 1 (skeleton first, flesh out as other modules land)

#### CLI Command Design

```
omg init [OPTIONS]
    --ext=<name1,name2|all>    Install extensions alongside core
    --no-db                    Skip SQLite initialization
    --verbose                  Show unchanged files individually
    --dry-run                  Show what would be deployed without writing
    --force                    Overwrite even if checksums match

omg update [OPTIONS]
    --ext=<name1,name2|all>    Also update/add extensions
    --no-db                    Skip SQLite migration
    --verbose                  Show unchanged files individually
    --dry-run                  Show what would change

omg doctor
    (no flags -- diagnoses the current project installation)

omg self-update
    --check                    Only check if update is available, don't install

omg list-ext
    (no flags -- lists all embedded extensions with agent/command counts)

omg version
    --json                     Output version info as JSON

omg completions <shell>
    shell: bash | zsh | fish | powershell
```

**Rationale**: `omg init` replaces `bash setup.sh`. `omg update` is semantically identical to `omg init` but communicates intent (updating vs first-time). Internally they share the deploy engine with a flag for whether to report "new" or "updated". `--dry-run` is new and valuable for CI/scripted environments.

#### Failure Modes

| Failure | Cause | Detection | Recovery | Impact |
|---------|-------|-----------|----------|--------|
| Invalid subcommand | Typo | clap error | Show help with suggestion | None |
| Missing permissions | Read-only filesystem | IO error on first write | Report clearly, exit 1 | No deployment |
| Not in a git repo | User forgot `git init` | `git rev-parse` check | Offer to run `git init` or `--force` | Blocked |

#### Security Considerations

- **Trust boundary**: The binary runs with the user's filesystem permissions. No network access except `self-update`.
- **Sensitive data**: None. All assets are public markdown/SQL.
- **Attack surface**: The `self-update` command downloads from a remote URL. Must verify checksums.
- **Mitigations**: Pin TLS, verify SHA-256 checksums, validate downloaded binary before replacing.

#### Performance Budget

- **Startup time**: < 50ms to parse args and begin dispatch
- **Binary size**: < 15MB (target: ~8MB with embedded assets)
- **Memory**: < 20MB RSS during any operation

---

### Module 2: `assets` (Embedded Asset Registry)

- **Responsibility**: Embed all deployable files into the binary at compile time. Provide an API to query, list, and extract assets by category (core agents, core commands, hooks, schema, queries, workflow rules, extensions).
- **Public interface**:
  ```rust
  pub struct AssetRegistry { /* built at compile time */ }

  impl AssetRegistry {
      pub fn core_agents() -> &'static [Asset];
      pub fn core_commands() -> &'static [Asset];
      pub fn core_hooks() -> &'static [Asset];
      pub fn schema_sql() -> &'static str;
      pub fn query_files() -> &'static [Asset];
      pub fn workflow_rules() -> &'static str;
      pub fn scaffold_specs_md() -> &'static str;
      pub fn scaffold_docs_md() -> &'static str;
      pub fn extensions() -> &'static [Extension];
      pub fn extension_by_name(name: &str) -> Option<&'static Extension>;
  }

  pub struct Asset {
      pub name: &'static str,        // e.g., "analyst.md"
      pub content: &'static str,     // file contents
      pub category: AssetCategory,
  }

  pub enum AssetCategory {
      Agent,
      Command,
      Hook,
      Schema,
      Query,
      WorkflowRules,
      Scaffold,
  }

  pub struct Extension {
      pub name: &'static str,        // e.g., "blockchain"
      pub agents: &'static [Asset],
      pub commands: &'static [Asset],
  }
  ```
- **Dependencies**: None at runtime. Uses `include_str!()` at compile time.
- **Implementation order**: 2 (foundational -- every other module reads from this)

#### Embedding Strategy

Use Rust's `include_str!()` macro to embed each file at compile time. This is the simplest approach and has zero runtime overhead. The alternative (`rust-embed` or `include_dir!`) adds unnecessary abstraction for our case since we know every file path at compile time.

```rust
// In assets/mod.rs or a build.rs-generated file
pub const AGENT_ANALYST: &str = include_str!("../../core/agents/analyst.md");
pub const AGENT_ARCHITECT: &str = include_str!("../../core/agents/architect.md");
// ... one const per file

pub const SCHEMA_SQL: &str = include_str!("../../core/db/schema.sql");
pub const WORKFLOW_RULES: &str = include_str!("../../core/CLAUDE_WORKFLOW_RULES.md");
// The workflow rules are extracted from CLAUDE.md at build time (see Build section)
```

**Why `include_str!` over `rust-embed`**: We have a fixed, known set of files (approximately 50 total). `include_str!` is zero-dependency, zero-abstraction, and gives us compile-time errors if a file is missing. `rust-embed` is designed for dynamic/large asset directories (hundreds of files, images, etc.) -- overkill here.

**Why not a compressed archive**: The total text content of all assets is approximately 250-400KB uncompressed. Compression would save maybe 150KB while adding decompression complexity and latency. Not worth it for a CLI that runs in milliseconds.

#### Size Estimate

| Category | Files | Est. Lines | Est. Size |
|----------|-------|-----------|-----------|
| Core agents | 14 | ~3,650 | ~180KB |
| Core commands | 14 | ~1,430 | ~70KB |
| Core hooks | 5 | ~250 | ~12KB |
| SQL schema | 1 | ~320 | ~15KB |
| SQL queries | 3 | ~200 | ~10KB |
| Workflow rules | 1 | ~420 | ~20KB |
| Scaffolds | 2 | ~20 | ~1KB |
| Blockchain ext | 6 | ~600 | ~30KB |
| C2C ext | 5 | ~500 | ~25KB |
| **Total** | **~51** | **~7,390** | **~363KB** |

The embedded assets add approximately 350-400KB to the binary. Negligible.

#### Build-Time Asset Extraction

The workflow rules section needs to be extracted from `CLAUDE.md` (everything from `# OMEGA` to EOF). This is done at build time:

**Option A (chosen)**: Store the workflow rules as a separate file (`core/WORKFLOW_RULES.md`) that is the single source of truth. The `CLAUDE.md` in the repo includes it via a build step or manual sync. This avoids runtime parsing and makes the embedded content explicit.

**Option B (rejected)**: Parse `CLAUDE.md` at build time in `build.rs` to extract the section. This is fragile -- depends on marker text remaining stable and adds build complexity.

**Decision**: Create `core/WORKFLOW_RULES.md` as the canonical source. Update `CLAUDE.md` to be assembled from the toolkit preamble + workflow rules during the release process. This is cleaner and makes the embedded asset explicit.

#### Failure Modes

| Failure | Cause | Detection | Recovery | Impact |
|---------|-------|-----------|----------|--------|
| Asset missing at compile time | File deleted/moved | Compile error (include_str!) | Fix path, rebuild | Build fails (good) |
| Asset content stale | Forgot to rebuild | Manual -- version mismatch | Rebuild from latest source | Users get old assets |

---

### Module 3: `deploy` (Deploy Engine)

- **Responsibility**: Write embedded assets to the target project's filesystem. Handle change detection, directory creation, file permissions, and reporting.
- **Public interface**:
  ```rust
  pub struct DeployEngine {
      target_dir: PathBuf,
      options: DeployOptions,
  }

  pub struct DeployOptions {
      pub extensions: Vec<String>,  // empty = core only, ["all"] = everything
      pub skip_db: bool,
      pub verbose: bool,
      pub dry_run: bool,
      pub force: bool,
  }

  pub struct DeployReport {
      pub new_files: Vec<String>,
      pub updated_files: Vec<String>,
      pub unchanged_files: Vec<String>,
      pub errors: Vec<DeployError>,
  }

  impl DeployEngine {
      pub fn new(target_dir: PathBuf, options: DeployOptions) -> Self;
      pub fn deploy(&self) -> Result<DeployReport, DeployError>;
      // Internally calls:
      fn deploy_agents(&self, report: &mut DeployReport) -> Result<(), DeployError>;
      fn deploy_commands(&self, report: &mut DeployReport) -> Result<(), DeployError>;
      fn deploy_hooks(&self, report: &mut DeployReport) -> Result<(), DeployError>;
      fn deploy_scaffolding(&self, report: &mut DeployReport) -> Result<(), DeployError>;
      fn configure_hooks_settings(&self, report: &mut DeployReport) -> Result<(), DeployError>;
      fn inject_workflow_rules(&self, report: &mut DeployReport) -> Result<(), DeployError>;
      fn initialize_db(&self, report: &mut DeployReport) -> Result<(), DeployError>;
  }
  ```
- **Dependencies**: `assets`, `claude_md`, `settings`, `db`
- **Implementation order**: 4 (after assets, claude_md, db)

#### Change Detection

The current `setup.sh` uses `cmp -s` (byte comparison) to detect changes. The Rust equivalent:

1. Read existing file content (if file exists)
2. Compare with embedded asset content using `==` on string slices
3. Report as `new`, `updated`, or `unchanged`

This is simpler than checksumming and equally correct for text files.

#### Failure Modes

| Failure | Cause | Detection | Recovery | Impact |
|---------|-------|-----------|----------|--------|
| Permission denied | Read-only dir, wrong user | `io::Error` | Report which file failed, continue others | Partial deploy |
| Disk full | No space | `io::Error` on write | Report, abort remaining | Partial deploy |
| CLAUDE.md locked | Editor has it open | `io::Error` | Retry once, then report | Workflow rules not injected |
| Conflicting agent names | Extension has same name as core | Compile-time check + runtime validation | Warn user, core wins | Extension agent skipped |

#### Security Considerations

- **Trust boundary**: Writes only to the target project directory. Never writes outside it.
- **File permissions**: Hooks get `chmod +x` (0o755). All other files get default permissions.
- **Overwrite safety**: Never overwrites `specs/SPECS.md` or `docs/DOCS.md` if they exist (matches current behavior). CLAUDE.md preserves user content above the separator.

#### Performance Budget

- **Full init (cold)**: < 500ms for all file writes + DB init
- **Update (warm, no changes)**: < 200ms (read + compare + skip)
- **Memory**: < 5MB RSS (all assets are static strings, not heap-allocated)

---

### Module 4: `claude_md` (CLAUDE.md Injector)

- **Responsibility**: Handle the append/update/create logic for the target project's CLAUDE.md. Preserve user content above the separator, replace workflow rules below it.
- **Public interface**:
  ```rust
  pub enum ClaudeMdResult {
      Created,
      Appended,
      Updated,
      Unchanged,
  }

  pub fn inject_workflow_rules(
      target_dir: &Path,
      workflow_rules: &str,
  ) -> Result<ClaudeMdResult, io::Error>;
  ```
- **Dependencies**: `assets` (for workflow rules content)
- **Implementation order**: 3

#### Logic

This module replicates the exact behavior of the current `setup.sh` CLAUDE.md section:

1. **No CLAUDE.md exists**: Create one with header + placeholder + separator + workflow rules. Return `Created`.
2. **CLAUDE.md exists, no marker**: Append separator + workflow rules. Return `Appended`.
3. **CLAUDE.md exists, has `# OMEGA` marker**:
   a. Extract everything above the separator (user content)
   b. Compare existing workflow rules with new ones
   c. If identical: Return `Unchanged`
   d. If different: Replace from separator onwards. Return `Updated`
4. **CLAUDE.md exists, has legacy marker** (`# Claude Code Quality Workflow`): Same as 3, but upgrade the marker.

**Marker constants**:
- Primary: `# OMEGA` (with the omega symbol being part of the full line `# OMEGA Ω`)
- Legacy: `# Claude Code Quality Workflow`
- Separator: `---`

#### Edge Cases

- Blank lines before/after separator are handled (strip trailing whitespace from user section, add clean separator)
- UTF-8 handling: The omega symbol (Ω, U+03A9) is standard UTF-8. Rust handles this natively.
- Multiple separators in user content: Only the last `---` before the marker is treated as the OMEGA separator. This is identified by proximity to the marker, not by position.

#### Failure Modes

| Failure | Cause | Detection | Recovery | Impact |
|---------|-------|-----------|----------|--------|
| CLAUDE.md is not UTF-8 | Unusual encoding | `std::fs::read_to_string` error | Report error, skip injection | No workflow rules |
| CLAUDE.md is huge (>1MB) | Generated/binary content accidentally | Size check | Warn but proceed | Slow but functional |
| Concurrent write | Another process editing | Not detected (no locking) | Last writer wins | Acceptable for CLI |

---

### Module 5: `settings` (Settings.json Merger)

- **Responsibility**: Create or merge `.claude/settings.json` to register hooks. Preserve non-hook settings.
- **Public interface**:
  ```rust
  pub fn configure_hooks(
      target_dir: &Path,
      project_abs_path: &Path,
  ) -> Result<SettingsResult, SettingsError>;

  pub enum SettingsResult {
      Created,
      Updated,
      Unchanged,
  }
  ```
- **Dependencies**: `serde_json`
- **Implementation order**: 3 (parallel with claude_md)

#### Logic

1. Generate the hooks JSON structure with absolute paths to `.claude/hooks/*.sh`
2. If `settings.json` does not exist: write the full hooks JSON. Return `Created`.
3. If `settings.json` exists:
   a. Parse it as JSON
   b. Compare `.hooks` key with generated hooks
   c. If identical: Return `Unchanged`
   d. If different: Replace `.hooks` key, preserve everything else. Return `Updated`.
4. If `settings.json` exists but is malformed: overwrite entirely. Return `Created`.

**Key improvement over setup.sh**: The current script uses Python 3 for JSON merging. The Rust binary handles this natively with `serde_json`, eliminating the Python dependency entirely.

#### Failure Modes

| Failure | Cause | Detection | Recovery | Impact |
|---------|-------|-----------|----------|--------|
| Malformed JSON | Manual edit broke syntax | `serde_json::from_str` error | Overwrite with hooks-only | Other settings lost (warn user) |
| Missing .claude/ dir | Race condition | `io::Error` | Create dir first | Self-healing |

---

### Module 6: `db` (SQLite Manager)

- **Responsibility**: Initialize and migrate the institutional memory database. Deploy query reference files.
- **Public interface**:
  ```rust
  pub fn initialize_db(target_dir: &Path) -> Result<DbResult, DbError>;
  pub fn deploy_query_files(target_dir: &Path) -> Result<(), io::Error>;

  pub enum DbResult {
      Created { tables: usize, views: usize },
      Migrated { tables: usize, views: usize },
      AlreadyCurrent { tables: usize, views: usize },
  }
  ```
- **Dependencies**: `rusqlite` (with bundled SQLite feature), `assets` (for schema SQL)
- **Implementation order**: 3 (parallel with claude_md and settings)

#### SQLite Strategy: Bundled via `rusqlite`

**Decision**: Use `rusqlite` with the `bundled` feature flag. This compiles SQLite directly into the binary.

| Option | Verdict | Reason |
|--------|---------|--------|
| System `sqlite3` CLI | Rejected | External dependency. User might not have it. Version differences cause subtle bugs. The #1 support issue with current setup.sh. |
| `rusqlite` with system SQLite | Rejected | Still requires SQLite dev libraries at compile time and shared lib at runtime. |
| `rusqlite` with `bundled` | **Chosen** | Zero external dependencies. Consistent SQLite version across all platforms. Adds ~1.5MB to binary (acceptable). |
| `libsql` | Rejected | Overkill -- we don't need replication or HTTP. |

**Impact**: This eliminates the `sqlite3` CLI prerequisite entirely. Users no longer need `sqlite3` installed. The binary handles all database operations internally.

**Important nuance**: The agents themselves still use `sqlite3` CLI commands (they run shell commands via Claude Code's Bash tool). This is unavoidable because the agents are markdown instructions executed by an LLM, not compiled code. However, the `omg doctor` command will check for `sqlite3` availability and warn if it's missing, since agents need it at runtime even though `omg init` does not.

#### Schema Migration Strategy

The schema uses `CREATE TABLE IF NOT EXISTS` and `CREATE INDEX IF NOT EXISTS` throughout, making it safe to re-run on an existing database. The migration strategy is:

1. Open (or create) the database file
2. Execute the full schema SQL (all `IF NOT EXISTS` statements are safe)
3. Enable WAL mode and foreign keys
4. Count tables and views for reporting
5. Copy query reference files to `.claude/db-queries/`

For future schema changes (adding columns, altering tables), we will need a migration system. This is deferred to v0.2 -- the current schema is v1.1.0 and stable.

#### Failure Modes

| Failure | Cause | Detection | Recovery | Impact |
|---------|-------|-----------|----------|--------|
| DB file locked | Another process (Claude Code session) has it open | rusqlite error | Retry with timeout (5s), then warn | DB not migrated |
| DB corrupted | Disk error, incomplete write | `PRAGMA integrity_check` | Report corruption, offer `--force` to recreate | Data loss if recreated |
| Schema conflict | Manual edits to schema | SQL execution error | Report error, suggest `--force` to recreate | DB not migrated |

#### Performance Budget

- **DB creation**: < 100ms
- **Schema migration (no changes)**: < 50ms
- **DB file size (empty)**: < 100KB

---

### Module 7: `doctor` (Health Diagnostics)

- **Responsibility**: Verify the OMEGA installation in the current project. Check for missing files, stale versions, DB health, prerequisite availability.
- **Public interface**:
  ```rust
  pub fn run_diagnostics(target_dir: &Path) -> DiagnosticReport;

  pub struct DiagnosticReport {
      pub checks: Vec<Check>,
      pub overall: OverallHealth,  // Healthy, Degraded, Broken
  }

  pub struct Check {
      pub name: String,
      pub status: CheckStatus,  // Pass, Warn, Fail
      pub detail: String,
  }
  ```
- **Dependencies**: `assets` (for comparing deployed vs embedded), `db` (for DB health)
- **Implementation order**: 6 (after core deploy works)

#### Checks

| # | Check | Pass | Warn | Fail |
|---|-------|------|------|------|
| 1 | Git repository | Inside git repo | -- | Not a git repo |
| 2 | `.claude/` directory | Exists | -- | Missing |
| 3 | Core agents deployed | All 14 present and current | Some outdated | Missing agents |
| 4 | Core commands deployed | All 14 present and current | Some outdated | Missing commands |
| 5 | Hooks deployed | All 5 present, executable | Some outdated | Missing hooks |
| 6 | settings.json | Hooks configured | Partial hooks | Missing |
| 7 | memory.db | Exists, all tables present | Missing views | Missing or corrupt |
| 8 | CLAUDE.md | Workflow rules present and current | Rules outdated | No workflow rules |
| 9 | specs/SPECS.md | Exists | -- | Missing |
| 10 | docs/DOCS.md | Exists | -- | Missing |
| 11 | sqlite3 CLI | In PATH | -- | Missing (agents need it) |
| 12 | Version tracking | `.claude/.omg-version` matches binary | Version mismatch | Missing version file |
| 13 | Extension integrity | Deployed extensions match embedded | Outdated extensions | Corrupt/partial |

#### Failure Modes

| Failure | Cause | Detection | Recovery | Impact |
|---------|-------|-----------|----------|--------|
| Not in a project dir | No .claude/ | Directory check | Report "run omg init first" | Doctor exits cleanly |
| DB unreadable | Permissions | rusqlite error | Report specific error | Degraded report |

---

### Module 8: `self_update` (Binary Self-Update)

- **Responsibility**: Check for new versions, download the appropriate platform binary, verify checksum, replace the running binary.
- **Public interface**:
  ```rust
  pub fn check_for_update() -> Result<Option<UpdateInfo>, UpdateError>;
  pub fn perform_update(info: &UpdateInfo) -> Result<(), UpdateError>;

  pub struct UpdateInfo {
      pub current_version: String,
      pub latest_version: String,
      pub download_url: String,
      pub checksum_sha256: String,
      pub release_notes: String,
  }
  ```
- **Dependencies**: `reqwest` (HTTP client), `sha2` (checksum), `self_replace` or `self-update` crate
- **Implementation order**: 7 (last -- needs release infrastructure first)

#### Update Flow

1. `omg self-update --check`: Fetch `https://omgagi.ai/releases/latest.json` (or GitHub API)
2. Compare `latest_version` with compiled-in `env!("CARGO_PKG_VERSION")`
3. If newer: download platform-specific binary from `download_url`
4. Verify SHA-256 checksum
5. Replace running binary using `self_replace` (handles platform differences)
6. Print "Updated from vX.Y.Z to vA.B.C"

#### Version Manifest Format (`latest.json`)

```json
{
  "version": "0.2.0",
  "released": "2026-04-15",
  "release_notes": "Added extension hot-loading and DB migration framework",
  "binaries": {
    "x86_64-apple-darwin": {
      "url": "https://omgagi.ai/releases/v0.2.0/omg-x86_64-apple-darwin",
      "sha256": "abc123..."
    },
    "aarch64-apple-darwin": {
      "url": "https://omgagi.ai/releases/v0.2.0/omg-aarch64-apple-darwin",
      "sha256": "def456..."
    },
    "x86_64-unknown-linux-gnu": {
      "url": "https://omgagi.ai/releases/v0.2.0/omg-x86_64-unknown-linux-gnu",
      "sha256": "ghi789..."
    },
    "aarch64-unknown-linux-gnu": {
      "url": "https://omgagi.ai/releases/v0.2.0/omg-aarch64-unknown-linux-gnu",
      "sha256": "jkl012..."
    }
  }
}
```

#### Security Considerations

- **Trust boundary**: Downloads execute on the user's machine as the user. The binary replaces itself.
- **Attack surface**: Man-in-the-middle on download URL. Compromised release server.
- **Mitigations**:
  - HTTPS only (TLS 1.2+)
  - SHA-256 checksum verification (checksum fetched over same HTTPS channel -- TODO: consider separate signing)
  - Future: Ed25519 signature verification (v0.2+)
- **No auto-update**: The binary never updates itself without explicit `omg self-update`. No background checks, no telemetry.

#### Failure Modes

| Failure | Cause | Detection | Recovery | Impact |
|---------|-------|-----------|----------|--------|
| Network unreachable | No internet, DNS failure | reqwest timeout | Report "cannot check for updates" | Self-update unavailable |
| Checksum mismatch | Corrupted download, MITM | SHA-256 comparison | Abort, report error, do not replace | Binary unchanged |
| Permission denied | Binary in protected location | IO error on replace | Suggest `sudo omg self-update` | Binary unchanged |
| Manifest parse error | Server issue | serde_json error | Report "update server returned invalid data" | Self-update unavailable |

#### Performance Budget

- **Check**: < 2s (single HTTPS request)
- **Download + verify + replace**: < 30s (depends on connection speed)

---

### Module 9: `version` (Version Tracker)

- **Responsibility**: Track which version of `omg` deployed assets to a project. Enable version comparison for doctor and update.
- **Public interface**:
  ```rust
  pub fn binary_version() -> &'static str;  // compiled-in from Cargo.toml
  pub fn deployed_version(target_dir: &Path) -> Option<String>;  // from .claude/.omg-version
  pub fn write_version_stamp(target_dir: &Path) -> Result<(), io::Error>;

  // .claude/.omg-version content:
  // {
  //   "version": "0.1.0",
  //   "deployed_at": "2026-03-17T14:30:00Z",
  //   "extensions": ["blockchain"],
  //   "asset_checksum": "sha256:abc123"
  // }
  ```
- **Dependencies**: `serde_json`, `chrono` (or `time`)
- **Implementation order**: 5

#### Version Stamp

After every successful `omg init` or `omg update`, write `.claude/.omg-version` with:

- `version`: The binary's version at deploy time
- `deployed_at`: ISO 8601 timestamp
- `extensions`: Which extensions were installed
- `asset_checksum`: SHA-256 of all embedded asset contents concatenated (detects rebuilds with same version but different content during development)

This enables:
- `omg doctor` to compare deployed vs current binary version
- `omg update` to skip work if already current
- Debugging "which version deployed this?" questions

---

## Project Structure (Rust Crate Layout)

```
omega-cli/                          # New repo or subdirectory
├── Cargo.toml                      # Workspace root (single crate for v0.1)
├── Cargo.lock
├── src/
│   ├── main.rs                     # Entry point, clap setup
│   ├── cli.rs                      # Command definitions, argument parsing
│   ├── assets/
│   │   ├── mod.rs                  # AssetRegistry, include_str! for all files
│   │   └── extensions.rs           # Extension asset definitions
│   ├── deploy.rs                   # DeployEngine -- orchestrates all deployment
│   ├── claude_md.rs                # CLAUDE.md injection logic
│   ├── settings.rs                 # settings.json merger
│   ├── db.rs                       # SQLite initialization via rusqlite
│   ├── doctor.rs                   # Health diagnostics
│   ├── self_update.rs              # Binary self-update
│   └── version.rs                  # Version tracking
├── assets/                         # Symlink or copy of omega repo assets
│   ├── core/
│   │   ├── agents/*.md
│   │   ├── commands/*.md
│   │   ├── hooks/*.sh
│   │   ├── db/schema.sql
│   │   ├── db/queries/*.sql
│   │   └── WORKFLOW_RULES.md       # Extracted workflow rules (new file)
│   └── extensions/
│       ├── blockchain/
│       └── c2c-protocol/
├── build.rs                        # Optional: generate asset checksums, validate assets exist
├── tests/
│   ├── init_test.rs                # Integration: init in temp dir, verify all files
│   ├── update_test.rs              # Integration: init then update, verify idempotency
│   ├── claude_md_test.rs           # Unit: all CLAUDE.md injection scenarios
│   ├── settings_test.rs            # Unit: settings.json merge scenarios
│   ├── db_test.rs                  # Integration: DB creation and migration
│   └── doctor_test.rs              # Integration: doctor on good/broken installs
├── dist/                           # Release artifacts (gitignored)
├── install.sh                      # Install script (lives in repo, hosted at omgagi.ai/install.sh)
└── .github/
    └── workflows/
        ├── ci.yml                  # Build + test on all platforms
        └── release.yml             # Build release binaries, publish, update latest.json
```

### Mono-Crate vs Workspace

**Decision**: Single crate for v0.1. The codebase is small enough (estimated 2,000-3,000 lines of Rust) that splitting into multiple crates adds configuration overhead without benefit. If the project grows significantly (e.g., adding a server mode, plugin system), split into a workspace then.

### Asset Organization

The `assets/` directory in the Rust project mirrors the `core/` and `extensions/` structure from the OMEGA repo. Two options for keeping them in sync:

**Option A (chosen for v0.1)**: The Rust CLI project lives in a new repo (`omega-cli`). Assets are copied from the main `omega` repo during the release process. A CI step validates that the embedded assets match the latest `omega` repo.

**Option B (future consideration)**: The Rust CLI project is a subdirectory of the main `omega` repo. The `include_str!` paths reference `../../core/agents/...` directly. This keeps everything in one repo but mixes Rust build artifacts with the markdown-only toolkit.

**Rationale for Option A**: The OMEGA repo is currently a pure markdown/shell toolkit. Adding Rust build infrastructure (Cargo.toml, target/, CI for cross-compilation) would confuse contributors who only work on agent definitions. Separate repos with a sync mechanism is cleaner.

---

## Cross-Platform Build Strategy

### Target Platforms

| Target Triple | OS | Arch | Priority | Notes |
|---------------|-----|------|----------|-------|
| `aarch64-apple-darwin` | macOS | ARM (M1/M2/M3/M4) | P0 | Primary dev platform |
| `x86_64-apple-darwin` | macOS | Intel | P1 | Legacy Macs |
| `x86_64-unknown-linux-gnu` | Linux | x86_64 | P0 | Servers, CI, WSL |
| `aarch64-unknown-linux-gnu` | Linux | ARM | P2 | ARM servers, Raspberry Pi |

Windows is explicitly excluded from v0.1. Claude Code runs on macOS and Linux. Windows users use WSL, which is covered by the Linux binaries.

### Build Toolchain

**Decision**: Use GitHub Actions with `cross` for cross-compilation. `cargo-dist` is considered but rejected for v0.1 due to its opinionated release flow.

| Option | Verdict | Reason |
|--------|---------|--------|
| `cargo-dist` | Deferred to v0.2 | Automates installers, Homebrew taps, and release infrastructure. Excellent for mature projects. Adds complexity for a first release -- we want to understand the build before automating it. |
| `cross` + manual CI | **Chosen for v0.1** | Direct control over build targets. Simple Dockerfile-based cross-compilation. We write the CI workflow ourselves. |
| Native builds per platform | Rejected | Requires macOS, Linux ARM, and Linux x86 runners. Expensive and fragile. |

### CI Workflow (`.github/workflows/release.yml`)

```yaml
# Triggered by tag push: v0.1.0, v0.2.0, etc.
jobs:
  build:
    strategy:
      matrix:
        target:
          - aarch64-apple-darwin
          - x86_64-apple-darwin
          - x86_64-unknown-linux-gnu
          - aarch64-unknown-linux-gnu
    steps:
      - Checkout omega-cli repo
      - Sync assets from omega repo (or verify embedded assets)
      - Install cross (for Linux targets) or use native (for macOS)
      - cargo build --release --target ${{ matrix.target }}
      - Strip binary (reduce size)
      - Generate SHA-256 checksum
      - Upload artifact

  release:
    needs: build
    steps:
      - Create GitHub release
      - Upload all binaries
      - Generate and upload latest.json manifest
      - Deploy install.sh to omgagi.ai
```

**macOS builds**: GitHub Actions provides macOS ARM runners (`macos-14`). Both macOS targets build natively -- no cross-compilation needed.

**Linux builds**: Use `cross` with appropriate Docker images for x86_64 and aarch64.

### Binary Size Budget

| Component | Est. Size |
|-----------|-----------|
| Rust runtime | ~500KB |
| clap | ~200KB |
| rusqlite (bundled SQLite) | ~1.5MB |
| reqwest + TLS | ~2MB |
| serde_json | ~200KB |
| Embedded assets | ~400KB |
| Application code | ~200KB |
| **Total (stripped, release)** | **~5MB** |

Target: < 10MB. Stretch goal: < 8MB.

---

## Install Script Design (`install.sh`)

The install script is a shell script hosted at `https://omgagi.ai/install.sh`. Users run:

```bash
curl -fsSL https://omgagi.ai/install.sh | bash
```

### Behavior

```bash
#!/bin/bash
set -e

# 1. Detect platform
OS=$(uname -s)     # Darwin, Linux
ARCH=$(uname -m)   # arm64, x86_64, aarch64

# 2. Map to Rust target triple
case "${OS}-${ARCH}" in
    Darwin-arm64)    TARGET="aarch64-apple-darwin" ;;
    Darwin-x86_64)   TARGET="x86_64-apple-darwin" ;;
    Linux-x86_64)    TARGET="x86_64-unknown-linux-gnu" ;;
    Linux-aarch64)   TARGET="aarch64-unknown-linux-gnu" ;;
    *)               echo "Unsupported platform: ${OS}-${ARCH}"; exit 1 ;;
esac

# 3. Determine install location
INSTALL_DIR="${OMG_INSTALL_DIR:-$HOME/.local/bin}"
mkdir -p "$INSTALL_DIR"

# 4. Fetch latest version
LATEST=$(curl -fsSL https://omgagi.ai/releases/latest.json)
VERSION=$(echo "$LATEST" | grep -o '"version":"[^"]*"' | cut -d'"' -f4)
URL=$(echo "$LATEST" | python3 -c "import sys,json; print(json.load(sys.stdin)['binaries']['$TARGET']['url'])" 2>/dev/null || \
      echo "$LATEST" | jq -r ".binaries.\"$TARGET\".url" 2>/dev/null)
CHECKSUM=$(echo "$LATEST" | python3 -c "import sys,json; print(json.load(sys.stdin)['binaries']['$TARGET']['sha256'])" 2>/dev/null || \
           echo "$LATEST" | jq -r ".binaries.\"$TARGET\".sha256" 2>/dev/null)

# 5. Download binary
echo "Downloading omg v${VERSION} for ${TARGET}..."
curl -fsSL -o "${INSTALL_DIR}/omg" "$URL"
chmod +x "${INSTALL_DIR}/omg"

# 6. Verify checksum
ACTUAL=$(shasum -a 256 "${INSTALL_DIR}/omg" | cut -d' ' -f1)
if [ "$ACTUAL" != "$CHECKSUM" ]; then
    echo "ERROR: Checksum mismatch. Expected $CHECKSUM, got $ACTUAL"
    rm -f "${INSTALL_DIR}/omg"
    exit 1
fi

# 7. Verify it runs
"${INSTALL_DIR}/omg" version

# 8. PATH guidance
if ! echo "$PATH" | grep -q "$INSTALL_DIR"; then
    echo ""
    echo "Add to your PATH:"
    echo "  export PATH=\"$INSTALL_DIR:\$PATH\""
    echo ""
    echo "Add this to your ~/.zshrc or ~/.bashrc to make it permanent."
fi

echo ""
echo "Installed omg v${VERSION} to ${INSTALL_DIR}/omg"
echo "Run 'omg init' in any project to deploy OMEGA."
```

### Design Decisions

| Decision | Rationale |
|----------|-----------|
| Install to `~/.local/bin` by default | Standard user-local bin directory on both macOS and Linux. Does not require `sudo`. |
| `OMG_INSTALL_DIR` override | Corporate environments may have restricted PATHs. |
| JSON parsing with Python3 fallback to jq | Most macOS systems have Python3. Most Linux systems have jq or Python3. Cover both without hard dependency on either. |
| No `sudo` by default | Avoid privilege escalation. If user wants `/usr/local/bin`, they can set `OMG_INSTALL_DIR`. |
| Checksum verification | Mandatory. Failed checksum = deleted binary + error. |

### Failure Modes

| Failure | Cause | Detection | Recovery |
|---------|-------|-----------|----------|
| Unsupported platform | Windows, FreeBSD, etc. | uname check | Error message with platform info |
| Download fails | Network, 404 | curl exit code | Error message with URL |
| Checksum mismatch | Corrupted download, MITM | shasum comparison | Delete binary, exit 1 |
| No Python3 or jq | Minimal container | Command check | Fallback to grep/sed parsing |
| INSTALL_DIR not writable | Permissions | mkdir failure | Suggest different directory |

---

## Version Management

### Compile-Time Version

The binary's version comes from `Cargo.toml` via `env!("CARGO_PKG_VERSION")`. This is the single source of truth for the binary version.

### Project-Level Version Tracking

Each deployed project gets `.claude/.omg-version` (see Module 9). This file answers:

- "When was OMEGA last deployed here?"
- "Which version deployed it?"
- "Which extensions are installed?"
- "Are my assets current?"

### Version Comparison Logic

```
omg update:
  1. Read .claude/.omg-version → deployed_version
  2. Compare with binary_version()
  3. If deployed_version < binary_version → proceed with update
  4. If deployed_version == binary_version → check asset_checksum
     a. If checksum matches → "already up to date" (unless --force)
     b. If checksum differs → "assets changed, updating..." (dev builds)
  5. If deployed_version > binary_version → warn "project was deployed with newer version"
```

### Versioning Scheme

Semantic versioning: `MAJOR.MINOR.PATCH`

- **MAJOR**: Breaking changes to deployed file structure (e.g., moving agents out of `.claude/agents/`)
- **MINOR**: New features, new agents/commands, schema migrations
- **PATCH**: Bug fixes, agent content updates

---

## Extension Discovery and Selection

### Compile-Time Registry

All extensions are embedded at compile time. There is no runtime extension loading in v0.1. The `AssetRegistry` knows about every extension.

```rust
pub fn extensions() -> &'static [Extension] {
    &[
        Extension {
            name: "blockchain",
            agents: &[
                Asset { name: "blockchain-network.md", content: include_str!("..."), .. },
                Asset { name: "blockchain-debug.md", content: include_str!("..."), .. },
                Asset { name: "stress-tester.md", content: include_str!("..."), .. },
            ],
            commands: &[
                Asset { name: "omega-blockchain-network.md", content: include_str!("..."), .. },
                Asset { name: "omega-blockchain-debug.md", content: include_str!("..."), .. },
                Asset { name: "omega-stress-test.md", content: include_str!("..."), .. },
            ],
        },
        Extension {
            name: "c2c-protocol",
            // ...
        },
    ]
}
```

### `omg list-ext` Output

```
Available extensions:

  blockchain (3 agents, 3 commands)
    Agents:  blockchain-network, blockchain-debug, stress-tester
    Commands: omega-blockchain-network, omega-blockchain-debug, omega-stress-test

  c2c-protocol (2 agents, 3 commands)
    Agents:  proto-auditor, proto-architect
    Commands: omega-c2c, omega-proto-audit, omega-proto-improve
```

### Future: External Extension Packs (v0.3+)

A future version could support extensions loaded from external sources:

```
omg ext add https://github.com/user/omg-ext-kubernetes
omg init --ext=kubernetes
```

This is explicitly out of scope for v0.1. All extensions must be compiled into the binary.

---

## Dependency Elimination

A key benefit of the Rust binary is eliminating runtime dependencies that the current shell-based setup requires:

| Dependency | Current (setup.sh) | Future (omg binary) |
|------------|-------------------|---------------------|
| Bash | Required | Not needed |
| sqlite3 CLI | Required for DB init | Not needed (rusqlite bundled) |
| Python 3 | Required for JSON merge in settings.json | Not needed (serde_json) |
| cmp | Required for file comparison | Not needed (Rust string comparison) |
| sed | Required for CLAUDE.md marker extraction | Not needed (Rust string processing) |
| grep | Required for CLAUDE.md marker detection | Not needed |
| Git | Required (git init if not present) | Still required (for projects) |

**Post-migration prerequisites for users**:
- Git (for the target project)
- Claude Code (for running workflows)
- sqlite3 CLI (for agents at runtime -- `omg doctor` warns if missing)

**That's it.** Python 3 is no longer needed. The install script needs only `curl`, `uname`, `shasum`, and a shell -- all standard on macOS/Linux.

---

## Failure Modes (System-Level)

| Scenario | Affected Modules | Detection | Recovery Strategy | Degraded Behavior |
|----------|-----------------|-----------|-------------------|-------------------|
| Binary not in PATH | cli | User error | Install script provides PATH guidance | Manual path usage |
| Stale binary (old version) | all | `omg doctor` warns, `omg self-update --check` | `omg self-update` | Old agents deployed |
| Corrupted .claude/ dir | deploy, doctor | `omg doctor` detects missing/corrupt files | `omg init --force` | Partial OMEGA |
| DB locked by active session | db | rusqlite busy timeout | Wait + retry, then warn | DB not migrated |
| No internet (self-update) | self_update | reqwest timeout | Graceful error message | Self-update unavailable |
| CLAUDE.md manually corrupted | claude_md | Marker detection fails | Treat as "no marker", append fresh | Possible duplicate rules |
| Disk full | deploy, db | IO errors | Abort with clear message | Nothing deployed |

---

## Security Model

### Trust Boundaries

- **Binary distribution**: User trusts the install script (HTTPS) and the binary (checksum-verified). The install script is the initial trust bootstrap -- same model as Homebrew, Rustup, etc.
- **Deployed assets**: The binary writes markdown, SQL, and shell scripts to the project. These are all plaintext and auditable. No compiled or obfuscated code is deployed.
- **Hooks**: The deployed shell scripts run with the user's permissions inside Claude Code. They read/write only to `.claude/` within the project.
- **Self-update**: The binary replaces itself. This is the highest-trust operation. Checksum verification is mandatory. Signature verification is planned for v0.2.

### Data Classification

| Data | Classification | Storage | Access Control |
|------|---------------|---------|---------------|
| Agent definitions | Public | Embedded in binary, deployed to .claude/ | None needed |
| Workflow rules | Public | Embedded in binary, deployed to CLAUDE.md | None needed |
| SQL schema | Public | Embedded in binary, deployed to memory.db | None needed |
| memory.db content | Project-internal | .claude/memory.db | Project filesystem permissions |
| .omg-version | Project-internal | .claude/.omg-version | Project filesystem permissions |
| Download checksums | Public | Fetched from release server | HTTPS |
| User's CLAUDE.md content | User-owned | Target project | Never sent anywhere |

### Attack Surface

- **Install script (MITM)**: Mitigated by HTTPS. Future: host script checksum separately.
- **Binary download (MITM)**: Mitigated by HTTPS + SHA-256 checksum.
- **Compromised release server**: Future mitigation: Ed25519 signatures with public key embedded in install script.
- **Malicious extension content**: All extensions are compiled in. No user-supplied extensions in v0.1.

---

## Graceful Degradation

| Dependency | Normal Behavior | Degraded Behavior | User Impact |
|-----------|----------------|-------------------|-------------|
| Network (self-update only) | Check + download new version | Skip update, report unavailable | Binary works fine, just not updated |
| sqlite3 CLI (runtime) | Agents query memory.db | `omg doctor` warns, agents skip memory | Agents work but without institutional memory |
| Git | Deploy to git repo | Warn, deploy anyway (unless strict mode) | Project structure works |
| Existing CLAUDE.md | Preserve + append | Create fresh if missing | No user content to preserve |
| Existing memory.db | Migrate schema | Create fresh if missing | No historical data |

---

## Performance Budgets

| Operation | Latency (p50) | Latency (p99) | Memory | Notes |
|-----------|---------------|---------------|--------|-------|
| `omg init` (cold) | 200ms | 500ms | 10MB | File writes + DB creation |
| `omg init` (warm, no changes) | 50ms | 150ms | 5MB | Read + compare + skip |
| `omg update` | 100ms | 400ms | 10MB | Compare + selective write |
| `omg doctor` | 100ms | 300ms | 10MB | Read + DB check |
| `omg self-update --check` | 500ms | 2000ms | 15MB | Network request |
| `omg self-update` | 2s | 30s | 30MB | Download + verify + replace |
| `omg list-ext` | 10ms | 20ms | 2MB | Pure computation |
| `omg version` | 5ms | 10ms | 1MB | Print string |

---

## Design Decisions

| Decision | Alternatives Considered | Justification |
|----------|------------------------|---------------|
| Single binary distribution | npm package, Homebrew formula only, Docker image | Single binary has zero runtime dependencies (except OS). `curl \| bash` is the universal install pattern for CLI tools. npm requires Node.js. Docker is heavy for a CLI tool. |
| `include_str!` for assets | `rust-embed`, compressed tar, external asset dir | Fixed set of ~50 text files. `include_str!` is zero-dependency, compile-time checked, zero-overhead. See Module 2 rationale. |
| `rusqlite` with bundled SQLite | System sqlite3, libsql, standalone sqlite3 binary | Eliminates the #1 user issue (missing sqlite3). Adds ~1.5MB. Worth it for zero-dependency DB operations. |
| Separate repo (`omega-cli`) | Subdirectory of omega repo, monorepo | Keeps the markdown toolkit clean for non-Rust contributors. Sync via CI. See Project Structure rationale. |
| `cross` for CI builds (v0.1) | `cargo-dist`, native per-platform runners | Direct control for first release. Migrate to `cargo-dist` in v0.2 once the build is understood. |
| No Windows support (v0.1) | Cross-compile for Windows | Claude Code targets macOS/Linux. Windows users use WSL (Linux binary works). Saves 25% of CI complexity. |
| No plugin/external extension system (v0.1) | Dynamic loading, WASM plugins, external git repos | Premature complexity. All current extensions are known at compile time. External extensions are a v0.3+ feature. |
| JSON for version stamp (.omg-version) | TOML, plain text, SQLite table | JSON is already a dependency (serde_json for settings.json). Consistent format. Easy to parse and extend. |
| No telemetry, no auto-update | Opt-in telemetry, background update checks | Privacy-first. Users control when updates happen. Trust is earned, not assumed. |

---

## External Dependencies (Rust Crates)

| Crate | Version | Purpose | Size Impact |
|-------|---------|---------|-------------|
| `clap` | 4.x | CLI parsing with derive macros | ~200KB |
| `rusqlite` | 0.31+ | SQLite operations (with `bundled` feature) | ~1.5MB (includes SQLite C lib) |
| `serde` + `serde_json` | 1.x | JSON serialization for settings.json, .omg-version | ~200KB |
| `reqwest` | 0.12+ | HTTP client for self-update (with `rustls-tls` feature, not OpenSSL) | ~2MB |
| `sha2` | 0.10+ | SHA-256 checksums for self-update verification | ~50KB |
| `self_replace` | 1.x | Cross-platform binary self-replacement | ~10KB |
| `console` | 0.15+ | Colored terminal output, progress indicators | ~50KB |
| `thiserror` | 2.x | Error type derivation | ~10KB |
| `chrono` or `time` | latest | Timestamps for version stamp | ~100KB |

**Total estimated crate overhead**: ~4MB (compiled, stripped, release mode)

**Note on `reqwest`**: Use the `rustls-tls` feature instead of `native-tls` to avoid OpenSSL dependency on Linux. This is critical for static/portable binaries.

---

## v0.1 Scope

### In Scope (v0.1 -- First Release)

| Feature | Priority | Module |
|---------|----------|--------|
| `omg init` (core deployment) | P0 | deploy, assets, claude_md, settings, db |
| `omg init --ext=<name>` (extension deployment) | P0 | deploy, assets |
| `omg update` (idempotent re-deployment) | P0 | deploy |
| `omg doctor` (health check) | P0 | doctor |
| `omg list-ext` | P1 | assets, cli |
| `omg version` | P1 | version, cli |
| `omg completions <shell>` | P2 | cli (clap built-in) |
| `omg self-update` | P1 | self_update |
| `omg init --dry-run` | P2 | deploy |
| Cross-platform binaries (4 targets) | P0 | CI |
| Install script (`install.sh`) | P0 | CI + hosting |
| Version tracking (`.omg-version`) | P1 | version |
| Change detection (new/updated/unchanged) | P0 | deploy |
| Python 3 dependency elimination | P0 | settings (serde_json) |
| sqlite3 CLI dependency elimination (for init) | P0 | db (rusqlite) |

### Out of Scope (v0.2+)

| Feature | Target Version | Rationale |
|---------|---------------|-----------|
| `cargo-dist` integration | v0.2 | Need to understand the build first |
| Ed25519 signature verification for updates | v0.2 | Requires key management infrastructure |
| DB migration framework (ALTER TABLE) | v0.2 | Current schema is stable; migrations needed when schema evolves |
| External extension loading | v0.3 | Premature; no user demand yet |
| `omg ext add <url>` | v0.3 | Requires extension manifest format, trust model |
| Windows native builds | v0.3+ | Low demand; WSL covers Windows users |
| Homebrew tap (`brew install omg`) | v0.2 | Nice-to-have; `cargo-dist` can automate this |
| `omg status` (show deployed config) | v0.2 | Lower priority than doctor |
| `omg diff` (show what would change) | v0.2 | `--dry-run` covers most of this |
| `omg uninstall` (remove OMEGA from project) | v0.2 | Low priority; users can delete .claude/ manually |
| Auto-detection of stale deployments | v0.3 | Would require a background daemon or shell hook |
| Telemetry (opt-in) | Never (v0.1), Reconsidered (v1.0) | Privacy-first approach |

---

## Migration Path (Shell to Rust)

### Phase 1: Parallel Operation

The Rust binary and shell scripts coexist. Users can use either:

- `bash scripts/setup.sh` -- existing shell workflow (still works)
- `omg init` -- new Rust binary

Both produce identical output in `.claude/`. The Rust binary writes `.omg-version` (which setup.sh does not), but this file is harmless.

### Phase 2: Deprecation Notice

After v0.1 is stable (1-2 months), add a deprecation notice to `setup.sh`:

```bash
echo "WARNING: setup.sh is deprecated. Install the omg CLI:"
echo "  curl -fsSL https://omgagi.ai/install.sh | bash"
echo "Then run: omg init"
echo ""
echo "Continuing with legacy setup..."
```

### Phase 3: Removal

After v0.2 (3-4 months after v0.1), remove `scripts/setup.sh` and `scripts/db-init.sh` from the OMEGA repo. The CLI binary is the sole deployment mechanism.

### Backward Compatibility

- Projects deployed with `setup.sh` can be updated with `omg update` (the output format is identical)
- `omg doctor` works on projects deployed by either method
- The `.omg-version` file is new and optional; its absence just means "deployed by legacy setup.sh"

---

## Data Flow

### `omg init` Flow

```
User: omg init --ext=blockchain
  |
  +-- CLI parses args
  |     ext = ["blockchain"]
  |     skip_db = false
  |     dry_run = false
  |
  +-- Verify preconditions
  |     Is this a git repo? (warn if not)
  |     Does .claude/ exist? (create if not)
  |
  +-- DeployEngine::deploy()
  |     |
  |     +-- deploy_agents()
  |     |     For each core agent: compare + write if changed
  |     |     For "blockchain" extension: compare + write if changed
  |     |
  |     +-- deploy_commands()
  |     |     Same pattern as agents
  |     |
  |     +-- deploy_hooks()
  |     |     Write hook scripts, chmod +x
  |     |
  |     +-- deploy_scaffolding()
  |     |     Create specs/, docs/, SPECS.md, DOCS.md if missing
  |     |
  |     +-- configure_hooks_settings()
  |     |     Merge hooks into .claude/settings.json
  |     |
  |     +-- inject_workflow_rules()
  |     |     Append/update CLAUDE.md workflow rules
  |     |
  |     +-- initialize_db()
  |     |     Open .claude/memory.db with rusqlite
  |     |     Execute schema.sql
  |     |     Deploy query reference files
  |     |
  |     +-- write_version_stamp()
  |           Write .claude/.omg-version
  |
  +-- Print DeployReport
        14 agents (12 unchanged, 2 new)
        14 commands (14 unchanged)
        ...
```

---

## Milestones

| ID | Name | Scope (Modules) | Scope (Requirements) | Est. Size | Dependencies |
|----|------|-----------------|---------------------|-----------|-------------|
| M1 | Core Foundation | cli (skeleton), assets, version | P0 init basics | M | None |
| M2 | Deploy Engine | deploy, claude_md, settings | P0 file deployment | L | M1 |
| M3 | Database | db (rusqlite) | P0 DB init/migration | S | M1 |
| M4 | Diagnostics + Update | doctor, self_update | P0 doctor, P1 self-update | M | M1, M2, M3 |
| M5 | CI + Release | CI workflows, install.sh | P0 distribution | M | M1-M4 |

### Milestone Details

**M1 -- Core Foundation**: Set up the Rust project. Implement `clap` CLI skeleton with all subcommands (stubs). Implement asset embedding with `include_str!`. Implement version tracking. All compile-time work. Deliverable: binary that parses all commands and can list extensions.

**M2 -- Deploy Engine**: Implement the full deployment pipeline: file writing with change detection, CLAUDE.md injection (all 4 scenarios), settings.json merging, scaffolding creation, hook deployment with permissions. Deliverable: `omg init` and `omg update` work end-to-end.

**M3 -- Database**: Implement rusqlite-based DB initialization and migration. Deploy query reference files. Deliverable: `omg init` creates a working memory.db.

**M4 -- Diagnostics + Update**: Implement `omg doctor` with all checks. Implement `omg self-update` with version manifest, download, checksum verification, binary replacement. Deliverable: complete CLI feature set.

**M5 -- CI + Release**: Set up GitHub Actions for cross-compilation (4 targets). Create install.sh. Set up release hosting. Publish v0.1.0. Deliverable: users can install and use the binary.

---

## Requirement Traceability

| Requirement | Architecture Section | Module(s) |
|-------------|---------------------|-----------|
| Replace setup.sh with binary | Module 3: deploy | deploy.rs |
| Replace db-init.sh with binary | Module 6: db | db.rs |
| Embed all assets in binary | Module 2: assets | assets/mod.rs |
| Cross-platform distribution | Cross-Platform Build Strategy | CI workflows |
| Install via curl pipe bash | Install Script Design | install.sh |
| CLAUDE.md append/update logic | Module 4: claude_md | claude_md.rs |
| Settings.json merge (no Python) | Module 5: settings | settings.rs |
| SQLite init (no external sqlite3) | Module 6: db | db.rs |
| Extension selection at init time | Module 2: assets, Module 3: deploy | assets/extensions.rs, deploy.rs |
| Health check / diagnostics | Module 7: doctor | doctor.rs |
| Binary self-update | Module 8: self_update | self_update.rs |
| Version tracking per project | Module 9: version | version.rs |
| Dry-run mode | Module 3: deploy | deploy.rs |
| Change detection (new/updated/unchanged) | Module 3: deploy | deploy.rs |
