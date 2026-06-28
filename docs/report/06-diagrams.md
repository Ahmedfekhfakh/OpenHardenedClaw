# 6. Diagrams

## Diagram 1 -- Agentic Workflow (Tool Call Loop with Read-Only Boundary)

This diagram shows the agent's execution loop and where the read-only filesystem boundary intercepts write attempts.

```
+-------------------+      prompt       +------------------+
|                   | ----------------> |                  |
|   User / Prompt   |                   |   LLM (llama.cpp |
|   (or indirect    | <---------------- |   on internal    |
|    injection via   |    completion     |   network)       |
|    project/ file)  |                   |                  |
+-------------------+                   +------------------+
                                               |
                                          tool call
                                               |
                                               v
                                     +-------------------+
                                     |  OpenClaw Gateway  |
                                     |  (agent loop)      |
                                     +-------------------+
                                               |
                              +----------------+----------------+
                              |                                 |
                         file_write                        file_read
                         bash (write)                       grep, glob
                              |                                 |
                              v                                 v
                   +---------------------+           +---------------------+
                   | Path in ./project/? |           | Any readable path   |
                   +---------------------+           | (config files are   |
                       |             |               |  readable via :ro)  |
                      YES            NO              +---------------------+
                       |             |
                       v             v
              +--------------+  +---------------------------+
              | WRITE SUCCEEDS|  | Target is :ro mount?      |
              | (only writable|  +---------------------------+
              |  location)    |      |                  |
              +--------------+      YES                 NO
                                    |                  |
                                    v                  v
                          +------------------+  +------------------+
                          | WRITE BLOCKED    |  | read_only root?  |
                          | "Read-only file  |  +------------------+
                          |  system" (EROFS) |       |          |
                          +------------------+      YES         NO
                                                    |      (impossible
                                                    v       in this
                                              +----------+  config)
                                              | BLOCKED  |
                                              | (EROFS)  |
                                              +----------+
```

**Key insight:** Every write attempt that does not target `./project/` (or the tmpfs scratch areas `/tmp`, `/run`, sessions) hits either a `:ro` bind mount or the `read_only: true` root filesystem. The kernel rejects the write regardless of what the agent intends.

---

## Diagram 2 -- Architecture: Before vs. After Hardening

### BEFORE (Unhardened / Naive Deployment)

```
+============================================================+
|                        HOST                                  |
|                                                              |
|  +------------------------------------------------------+   |
|  |             Single Container (or bare host)           |   |
|  |                                                       |   |
|  |  openclaw process (root)                              |   |
|  |    |                                                  |   |
|  |    +-- ~/.openclaw/openclaw.json    [WRITABLE]        |   |
|  |    +-- ~/.openclaw/workspace/                         |   |
|  |    |     SOUL.md, MEMORY.md,        [WRITABLE]        |   |
|  |    |     BOOT.md, skills/           [WRITABLE]        |   |
|  |    +-- ~/.openclaw/credentials/     [READABLE]        |   |
|  |    +-- ./project/                   [WRITABLE]        |   |
|  |    +-- /var/run/docker.sock         [MOUNTED]         |   |
|  |                                                       |   |
|  |  Network: host / bridge with internet access          |   |
|  |  Capabilities: default set (14+ caps)                 |   |
|  |  Seccomp: default (300+ syscalls)                     |   |
|  |  Root filesystem: writable                            |   |
|  +------------------------------------------------------+   |
|                         |                                    |
|                    INTERNET (egress open)                     |
+==============================================================+

Blast radius: TOTAL
  - Config rewrite      -> succeeds (hot-reload escalation)
  - SOUL/MEMORY poison  -> succeeds (persistent across sessions)
  - Skill injection     -> succeeds (code exec + shadowing)
  - Credential theft    -> succeeds (read + exfil)
  - Docker escape       -> succeeds (socket mounted)
  - Destruction         -> succeeds (everything writable)
```

### AFTER (Hardened Deployment)

```
+============================================================+
|                        HOST (WSL2)                           |
|                                                              |
|  openclaw-internal network [internal: true, NO INTERNET]     |
|  +----------------------------------------------------------+|
|  |                                                          ||
|  |  +--------------------+     +------------------------+   ||
|  |  | openclaw-gateway   |     | llamacpp-server        |   ||
|  |  | (agent loop)       |     | (model inference)      |   ||
|  |  |                    | DNS | /v1 on :8080           |   ||
|  |  |  user: 1000:1000   |---->| user: 1000:1000        |   ||
|  |  |  cap_drop: ALL     |     | cap_drop: ALL          |   ||
|  |  |  no-new-privileges |     | no-new-privileges      |   ||
|  |  |  read_only root    |     | read_only root         |   ||
|  |  |  seccomp: custom   |     | models/ :ro            |   ||
|  |  |                    |     | pids: 64, mem: 4g      |   ||
|  |  |  MOUNTS:           |     +------------------------+   ||
|  |  |  openclaw.json :ro |                                  ||
|  |  |  SOUL.md       :ro |     +------------------------+   ||
|  |  |  MEMORY.md     :ro |     | openclaw-sandbox       |   ||
|  |  |  BOOT.md       :ro |     | (tool execution)       |   ||
|  |  |  HEARTBEAT.md  :ro |     |                        |   ||
|  |  |  skills/       :ro |     | network_mode: none     |   ||
|  |  |  memory/       :ro |     | read_only root         |   ||
|  |  |  [all others]  :ro |     | tmpfs /tmp only        |   ||
|  |  |                    |     | cap_drop: ALL          |   ||
|  |  |  project/      :rw |     | no-new-privileges      |   ||
|  |  |  sessions/   tmpfs |     | seccomp: custom        |   ||
|  |  |  /tmp, /run  tmpfs |     | pids: 64, mem: 512m    |   ||
|  |  |                    |     +------------------------+   ||
|  |  |  NOT MOUNTED:      |                                  ||
|  |  |  credentials/      |                                  ||
|  |  |  docker.sock       |                                  ||
|  |  |  ~/.aws, ~/.ssh    |                                  ||
|  |  |  .env              |                                  ||
|  |  |  models/           |                                  ||
|  |  +--------------------+                                  ||
|  +----------------------------------------------------------+|
|                         |                                    |
|                    NO INTERNET (internal: true)               |
+==============================================================+

Blast radius: CAPPED to ./project/ only
  - Config rewrite      -> EROFS (read-only file system)
  - SOUL/MEMORY poison  -> EROFS
  - Skill injection     -> EROFS
  - Credential theft    -> path absent (unmounted)
  - Docker escape       -> socket absent (unmounted)
  - Exfiltration        -> network unreachable
  - Destruction         -> EROFS on all protected paths
```

**Key contrasts:**
- Flat, writable filesystem becomes partitioned read-only mounts with a single writable path
- Host/bridge network with internet becomes `internal: true` with no internet route
- Root user with default capabilities becomes non-root with zero capabilities
- Default seccomp (300+ syscalls) becomes custom allowlist with dangerous syscalls removed
- Credentials readable and exfiltrable becomes credentials absent from container namespace
- Docker socket mounted becomes socket absent
