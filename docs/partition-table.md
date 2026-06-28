# OpenClaw Configuration Surface Map — Partition-Ready Table

**Project:** Hardened OpenClaw in Docker (Télécom Paris defensive-security lab)
**Agent:** `config-surface-mapper` — READ-ONLY output
**Date:** 2026-06-27

---

## 1. Scope and Terminology

OpenClaw splits its state into two trees that are fundamentally different in character:

- **`~/.openclaw/`** — the installation root: runtime config (`openclaw.json`), credentials, session history, and managed/bundled skills (lower precedence).
- **`~/.openclaw/workspace/`** — the agent's brain: identity, personality, memory, hook files, and workspace skills (highest precedence, can shadow managed skills).

In the Docker deployment, those two trees are sourced from **`./config/`** inside the repo (bind-mounted into the container). The code the agent edits lives in **`./project/`** — an entirely separate `:rw` mount. This split is the central architectural insight.

---

## 2. Partition-Ready Table

| # | Path (host → container) | Loads When | Executes? | Proposed Mode | Threat Covered |
|---|--------------------------|------------|-----------|---------------|----------------|
| 1 | `config/openclaw.json` → `~/.openclaw/openclaw.json` | Gateway start + **hot-reload on change** | No (data) | **`:ro`** | Prevents agent from rewriting model provider, adding MCP grants, or relaxing tool allow-lists mid-session via hot-reload |
| 2 | `config/credentials/` → `~/.openclaw/credentials/` | On demand (first auth call) | No | **`unmounted`** | Credentials cannot be read or exfiltrated if the path does not exist inside the container; model is local (llama.cpp) so no API key needed |
| 3 | `config/agents/<id>/sessions/` → `~/.openclaw/agents/<id>/sessions/` | Written continuously | No | **`tmpfs`** | Session history is ephemeral per run; tmpfs prevents cross-session persistence from a compromised run |
| 4 | `config/skills/` (managed) → `~/.openclaw/skills/` | Session start (index) + on-demand invocation | **Yes** | **`:ro`** | Prevents agent from writing a new managed skill or overwriting an existing one to inject persistent arbitrary code |
| 5 | `config/workspace/AGENTS.md` → `~/.openclaw/workspace/AGENTS.md` | Session start | No (instruction text) | **`:ro`** | Prevents redefinition of agent roles, permission scopes, or sub-agent delegation rules |
| 6 | `config/workspace/SOUL.md` → `~/.openclaw/workspace/SOUL.md` | Session start | No (instruction text) | **`:ro`** | Blocks cross-session personality/rule poisoning — rewriting SOUL.md permanently overrides safety rules for all future sessions |
| 7 | `config/workspace/MEMORY.md` → `~/.openclaw/workspace/MEMORY.md` | Session start + written during operation | No (trusted text) | **`:ro`** | Blocks persistent memory poisoning — injected facts survive session boundaries and steer future sessions |
| 8 | `config/workspace/USER.md` → `~/.openclaw/workspace/USER.md` | Session start | No (instruction text) | **`:ro`** | Prevents modification of user preference profiles to lower safety thresholds |
| 9 | `config/workspace/IDENTITY.md` → `~/.openclaw/workspace/IDENTITY.md` | Session start | No (instruction text) | **`:ro`** | Blocks identity substitution attacks |
| 10 | `config/workspace/TOOLS.md` → `~/.openclaw/workspace/TOOLS.md` | Session start | No (tool schema) | **`:ro`** | Prevents silent addition of tool definitions or widening tool scopes |
| 11 | `config/workspace/BOOT.md` → `~/.openclaw/workspace/BOOT.md` | **Session start, BEFORE user interaction** | **Yes — pre-consent** | **`:ro`** | BOOT.md executes before user can observe or consent; writable BOOT.md = unconditional code-execution every session start |
| 12 | `config/workspace/HEARTBEAT.md` → `~/.openclaw/workspace/HEARTBEAT.md` | **Periodic, at runtime intervals** | **Yes — timer-driven** | **`:ro`** | Writable HEARTBEAT.md gives a recurring, timer-driven execution channel; combined with network = persistent beaconing/exfil |
| 13 | `config/workspace/memory/` → `~/.openclaw/workspace/memory/` | On demand (extended memory) | No (trusted text) | **`:ro`** | Extended memory files loaded as authoritative; writable = inject facts/instructions that persist across sessions |
| 14 | `config/workspace/skills/` → `~/.openclaw/workspace/skills/` | Session start (index) + on-demand | **Yes — highest precedence, name-shadowing** | **`:ro`** | Most dangerous surface: one write = code execution + skill hijack via name-shadowing of managed/bundled skills |
| 15 | `./project/` → `~/project/` | On demand (agent edits) | No (source code) | **`:rw`** | **Only legitimately writable mount** — isolated from all config/memory/skill paths |
| 16 | Container root filesystem | Container start | N/A | **`read_only: true` + `tmpfs /tmp, /run`** | Prevents writes to anything not covered by a named mount |
| 17 | `models/*.gguf` → `/models/` (llamacpp only) | llamacpp start | No (binary weights) | **`:ro`** (gateway doesn't mount) | Model weights are static; only llamacpp-server needs them |
| 18 | `/var/run/docker.sock` | N/A | **Yes — daemon takeover** | **`unmounted`** | Docker socket = full daemon control = host escape |
| 19 | `~/.aws/`, `~/.ssh/`, `.env` | N/A | No (secrets) | **`unmounted`** | Host secret stores must never appear inside any container |

---

## 3. Key Findings

### Finding 1 — Workspace ≠ Code Repo (Critical Split)
The "workspace" (`~/.openclaw/workspace/`) is the agent's **memory/identity**, not the code repo. These require opposite mount modes:
- `~/.openclaw/workspace/` → **`:ro`** (immutable agent brain)
- `./project/` → **`:rw`** (editable code)

They must be separate bind mounts at separate container paths.

### Finding 2 — `openclaw.json` Hot-Reload Is Mid-Session Attack Surface
Hot-reload means a single write to this file can add MCP grants, relax tool allow-lists, redirect the inference endpoint, or disable sandboxing — all mid-session without restart. `:ro` eliminates this class entirely.

### Finding 3 — Workspace Skills: Execution + Name-Shadowing
`workspace/skills/` combines execution (arbitrary code) with override precedence (shadows managed/bundled skills by name). One file write = persistent arbitrary code at highest precedence. `:ro` breaks this completely.

### Finding 4 — BOOT.md & HEARTBEAT.md Are Pre-Consent Execution Primitives
Both execute outside the user-interaction loop with no consent gate. A writable BOOT.md is a fully unconditional, session-persistent, user-invisible code execution channel. `:ro` is non-negotiable for both.

### Finding 5 — Credentials Must Be Unmounted, Not Read-Protected
`:ro` still allows reads and exfiltration. `unmounted` removes the data from the container's namespace entirely. Same applies to `~/.aws/`, `~/.ssh/`, `.env`.

### Finding 6 — MEMORY.md Write-Back Design Decision
MEMORY.md tension: `:ro` blocks legitimate writes. **Recommended for this lab: stateless sessions** (`:ro`, no write-back). Alternative: separate `tmpfs` scratch with post-session human-reviewed promotion.

### Finding 7 — Symlink Resolution Before Path Validation
A symlink in `./project/` could point to `~/.openclaw/workspace/`. Path validation must resolve symlinks to real paths before checking the `:rw` perimeter. The `:ro` mounts on target paths provide the OS-level backstop.

---

## 4. Docker Mount Map Summary

```
Service: openclaw-gateway
────────────────────────────────────────────────────────────────────
MOUNT SOURCE                        CONTAINER PATH                  MODE
config/openclaw.json             → ~/.openclaw/openclaw.json        :ro
config/workspace/AGENTS.md       → ~/.openclaw/workspace/AGENTS.md  :ro
config/workspace/SOUL.md         → ~/.openclaw/workspace/SOUL.md    :ro
config/workspace/MEMORY.md       → ~/.openclaw/workspace/MEMORY.md  :ro
config/workspace/USER.md         → ~/.openclaw/workspace/USER.md    :ro
config/workspace/IDENTITY.md     → ~/.openclaw/workspace/IDENTITY.md :ro
config/workspace/TOOLS.md        → ~/.openclaw/workspace/TOOLS.md   :ro
config/workspace/BOOT.md         → ~/.openclaw/workspace/BOOT.md    :ro  ← pre-consent exec
config/workspace/HEARTBEAT.md    → ~/.openclaw/workspace/HEARTBEAT.md :ro ← timer exec
config/workspace/memory/         → ~/.openclaw/workspace/memory/    :ro
config/workspace/skills/         → ~/.openclaw/workspace/skills/    :ro  ← exec + shadow
config/skills/                   → ~/.openclaw/skills/              :ro  ← exec
./project/                       → ~/project/                       :rw  ← ONLY writable
[sessions]                       → ~/.openclaw/agents/sessions/     tmpfs
[/tmp, /run]                     → /tmp, /run                       tmpfs
[root]                           → /                                read_only: true

NOT MOUNTED: credentials/, ~/.aws/, ~/.ssh/, .env, docker.sock, models/

Service: llamacpp-server
────────────────────────────────────────────────────────────────────
models/                          → /models/                         :ro
[root]                           → /                                read_only: true
[/tmp]                           → /tmp                             tmpfs

Service: openclaw-sandbox
────────────────────────────────────────────────────────────────────
[no config mounts — sandbox sees only what gateway passes]
[root]                           → /                                read_only: true
[/tmp]                           → /tmp                             tmpfs
network: none
```

---

## 5. Threat-to-Control Cross-Reference

| Attack | Abused File/Dir | Control |
|---|---|---|
| Self-privilege: add MCP/tool mid-session | `openclaw.json` (hot-reload) | `:ro` → kernel rejects write |
| Pre-consent hook injection | `BOOT.md`, `HEARTBEAT.md` | `:ro` → kernel rejects write |
| Cross-session personality poisoning | `SOUL.md` | `:ro` → kernel rejects write |
| Cross-session memory poisoning | `MEMORY.md`, `memory/` | `:ro` → kernel rejects write |
| Agent identity substitution | `IDENTITY.md`, `AGENTS.md` | `:ro` → kernel rejects write |
| Skill hijack via name-shadowing | `workspace/skills/` | `:ro` → kernel rejects write |
| Managed skill replacement | `skills/` (managed) | `:ro` → kernel rejects write |
| Credential exfiltration | `credentials/`, `~/.aws/`, `~/.ssh/` | `unmounted` → path absent |
| Host daemon takeover | `/var/run/docker.sock` | `unmounted` → path absent |
| Symlink escape from project/ | `project/<symlink> → config` | `:ro` on target → kernel backstop |
| Destruction outside work area | Any config/skill/memory path | `:ro` → kernel rejects write |
| Session history persistence | `sessions/` | `tmpfs` → wiped at container stop |
