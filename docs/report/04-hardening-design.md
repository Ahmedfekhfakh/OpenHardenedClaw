# 4. Hardening Design

This section documents every hardening control applied to the deployment. It is organized in two parts: the filesystem partition table (the centerpiece of the defense) and the non-filesystem controls that complement it.

---

## Part A -- Filesystem Partition Table

The partition table maps every significant path to a mount mode and ties each decision to a specific threat.

| Path | Mode | Threat Covered |
|------|------|----------------|
| `config/openclaw.json` | `:ro` | Mid-session self-escalation via hot-reload |
| `config/credentials/` | unmounted | Credential read and exfiltration |
| `config/agents/<id>/sessions/` | `tmpfs` | Cross-session data persistence from a compromised run |
| `config/skills/` (managed) | `:ro` | Persistent arbitrary code injection at managed precedence |
| `config/workspace/AGENTS.md` | `:ro` | Agent role and delegation redefinition |
| `config/workspace/SOUL.md` | `:ro` | Cross-session personality and safety-rule poisoning |
| `config/workspace/MEMORY.md` | `:ro` | Persistent memory poisoning (write-once, execute-forever) |
| `config/workspace/USER.md` | `:ro` | User preference manipulation to lower safety thresholds |
| `config/workspace/IDENTITY.md` | `:ro` | Identity substitution attacks |
| `config/workspace/TOOLS.md` | `:ro` | Silent tool-definition injection or scope widening |
| `config/workspace/BOOT.md` | `:ro` | Pre-consent unconditional code execution every session start |
| `config/workspace/HEARTBEAT.md` | `:ro` | Timer-driven recurring execution, beaconing, exfiltration |
| `config/workspace/memory/` | `:ro` | Extended memory injection (same trust level as MEMORY.md) |
| `config/workspace/skills/` | `:ro` | Code execution + highest-precedence name-shadowing (skill hijack) |
| `./project/` | `:rw` | **Only legitimately writable mount** -- isolated from all config paths |
| Container root filesystem | `read_only: true` + `tmpfs /tmp, /run` | Arbitrary writes to system paths or fallback locations |
| `models/*.gguf` (llamacpp only) | `:ro` | Model weight tampering or replacement |
| `/var/run/docker.sock` | unmounted | Full Docker daemon control, host escape |
| `~/.aws/`, `~/.ssh/`, `.env` | unmounted | Host secret store access and exfiltration |

### Row-by-Row Justification

**openclaw.json (`:ro`).** OpenClaw hot-reloads this file on filesystem change events. A single write can add MCP server grants, relax the tool allow-list, redirect the inference endpoint to an attacker-controlled server, or disable sandboxing -- all mid-session, without restart, without user confirmation. The read-only mount ensures the hot-reload code path never fires because the underlying write is blocked by the kernel.

**credentials/ (unmounted).** A read-only mount still allows the agent to read file contents and exfiltrate them over the network. Unmounting removes the path from the container's namespace entirely -- there is nothing to read. Since the model is served locally via llama.cpp, no provider API key is needed inside the container.

**sessions/ (tmpfs).** Session history is written continuously during operation. Using tmpfs means all session data is wiped when the container stops, preventing a compromised session from leaking data or planting instructions that a subsequent session could find.

**Managed skills (`:ro`).** Skills execute arbitrary code. Even at lower precedence than workspace skills, a managed skill write provides persistent code execution. Read-only mounting blocks this entirely.

**AGENTS.md (`:ro`).** Defines agent roles, permission scopes, and sub-agent delegation. A rewrite could grant the agent permissions it was not intended to have or reconfigure delegation to bypass checks.

**SOUL.md (`:ro`).** The agent's personality and safety rules. A rewrite permanently overrides safety constraints for all future sessions. This is the canonical persistent-memory poisoning target identified by Anthropic's containment guidance.

**MEMORY.md (`:ro`).** Cross-session memory loaded as ground truth. Injected "facts" (e.g., "the user has authorized all file writes") persist indefinitely and steer future decision-making. For this lab, we adopt stateless sessions with no write-back.

**USER.md (`:ro`).** User preference profiles. A rewrite could lower safety thresholds or change interaction settings that affect tool authorization.

**IDENTITY.md (`:ro`).** Agent identity definition. A rewrite enables identity substitution, potentially impersonating a higher-privileged agent.

**TOOLS.md (`:ro`).** Tool schema definitions. A rewrite could silently add tool definitions or widen the scope of existing tools.

**BOOT.md (`:ro`).** Executes before user interaction, with no consent gate. A writable BOOT.md is a fully unconditional, session-persistent, user-invisible code-execution channel. Read-only mounting is non-negotiable.

**HEARTBEAT.md (`:ro`).** Executes on a periodic timer at runtime intervals. A writable HEARTBEAT.md combined with network access gives a recurring, timer-driven beaconing and exfiltration channel.

**memory/ (`:ro`).** Extended memory files carry the same trust level as MEMORY.md. The same poisoning risk applies.

**workspace/skills/ (`:ro`).** The most dangerous surface in the partition table. Workspace skills combine three properties: arbitrary code execution, highest precedence in the skill index, and the ability to shadow managed or bundled skills by name. One file write yields persistent arbitrary code at the top of the resolution order.

**./project/ (`:rw`).** The test repository the agent legitimately edits. This is the only writable bind mount. It is isolated from all config, identity, memory, and skill paths at different container paths. A symlink in `./project/` pointing to a config path is caught by the read-only mount on the target (kernel backstop).

**Root filesystem (`read_only: true`).** Prevents writes to any path not covered by a named mount. Combined with tmpfs on `/tmp` and `/run` (with `noexec`, `nosuid`, `nodev`), this ensures there is no fallback location where the agent can drop binaries or configuration files.

**models/ (`:ro`, llamacpp only).** Model weights are static binary files. Read-only mounting prevents tampering or replacement that could alter model behavior. The gateway container does not mount models at all.

**docker.sock (unmounted).** The Docker socket grants full daemon control, equivalent to root on the host. It is never mounted into any container. This is the single most important "do not do" in container security.

**Host secrets (unmounted).** `~/.aws/`, `~/.ssh/`, and `.env` are host-level secret stores. They are never mounted into any container. Even read-only mounting would be insufficient because the agent could read and exfiltrate the contents.

---

## Part B -- Non-Filesystem Controls

### Non-Root User

All containers run as `user: 1000:1000` (the `agent` user created in the Dockerfile with `/usr/sbin/nologin` as shell). Running as a non-root user means the process cannot modify system files owned by root, cannot bind to privileged ports, and reduces the attack surface for container-escape exploits that require root inside the container.

**Threat covered:** Root-inside-container enables privilege escalation and escape vectors.

### Capability Dropping (`cap_drop: ALL`)

All Linux capabilities are dropped from every container. The default Docker capability set includes `CAP_NET_RAW`, `CAP_SYS_CHROOT`, `CAP_SETUID`, `CAP_SETGID`, and others that could be leveraged for privilege escalation or network abuse. Dropping all capabilities and adding none back enforces absolute minimum privilege.

**Threat covered:** Capability-based privilege escalation (e.g., `CAP_SYS_ADMIN` for mount namespace manipulation, `CAP_NET_RAW` for raw socket abuse).

### No-New-Privileges (`no-new-privileges: true`)

This security option prevents the process from gaining new privileges through `execve` (e.g., via SUID binaries or file capabilities). Even if a SUID binary exists in the container image, executing it will not elevate privileges.

**Threat covered:** SUID binary exploitation, file-capability escalation.

### Seccomp Profile

A custom seccomp profile (`docker/seccomp/openclaw-seccomp.json`) restricts the syscalls available to gateway and sandbox containers. The profile uses a default-deny architecture (`SCMP_ACT_ERRNO`) with an explicit allowlist of **366 safe syscalls** -- this is the **full working profile** derived from Docker's default seccomp profile, not an abbreviated skeleton. It includes all syscalls required to run a Node.js agent (`socket`, `connect`, `epoll_wait`, `accept`, `getdents64`, `clone`, `execve`, etc.) while removing the dangerous syscalls listed below.

**Blocked syscalls and rationale:**

| Syscall(s) | Rationale |
|------------|-----------|
| `mount`, `umount`, `umount2` | Prevents filesystem namespace manipulation; blocks remounting read-only filesystems as read-write |
| `pivot_root` | Prevents changing the root filesystem; used in container escape techniques |
| `swapon`, `swapoff` | Prevents swap manipulation; no legitimate container use |
| `reboot` | Prevents host reboot from inside the container |
| `settimeofday`, `clock_settime`, `adjtimex` | Prevents time manipulation; blocks TOCTOU attacks and log falsification |
| `sethostname`, `setdomainname` | Prevents hostname spoofing; could confuse logging and network identity |
| `init_module`, `finit_module`, `delete_module` | Prevents loading or unloading kernel modules; blocks direct kernel code execution |
| `kexec_load`, `kexec_file_load` | Prevents loading a new kernel; complete host takeover |
| `perf_event_open` | Prevents performance counter access; blocks side-channel attacks (Spectre class) |
| `bpf` | Prevents BPF program loading; blocks kernel-level code execution and tracing |
| `userfaultfd` | Prevents user-space page-fault handling; used in use-after-free exploits |
| `ptrace` | Prevents process tracing and debugging; blocks memory inspection and code injection across processes |
| `process_vm_readv`, `process_vm_writev` | Prevents cross-process memory reads and writes; blocks credential theft and code injection |
| `kcmp` | Prevents kernel object comparison; blocks information leaks about kernel state |
| `keyctl`, `request_key`, `add_key` | Prevents kernel keyring manipulation; blocks access to or planting of credentials in the kernel keyring |

### Egress Control

**Internal network.** The Docker network `openclaw-internal` is configured with `internal: true`, which means the Docker daemon does not create a default gateway to the host network. Containers on this network can communicate with each other (e.g., gateway to llamacpp-server over DNS) but cannot reach any external IP address. There is no internet route.

**Sandbox isolation.** The sandbox container uses `network_mode: none`, which gives it no network interfaces at all -- not even loopback in the default configuration. This is the strongest possible network isolation.

**Threat covered:** Data exfiltration, C2 beaconing, supply-chain attacks at runtime, "egress through approved domain" covert channels. Because the model is local (llama.cpp on the internal network), there is no permitted external endpoint that could serve as an exfiltration channel.

### Resource Limits

| Container | PIDs Limit | Memory Limit | CPU Limit |
|-----------|-----------|--------------|-----------|
| `openclaw-gateway` | 256 | 2 GB | 2 CPUs |
| `llamacpp-server` | 64 | 4 GB | 4 CPUs |
| `openclaw-sandbox` | 64 | 512 MB | 1 CPU |

**Threat covered:** Fork-bomb denial of service, memory-exhaustion attacks, CPU-exhaustion attacks. PID limits prevent uncontrolled process spawning. Memory limits trigger OOM kills before the host is affected. CPU limits prevent a single container from starving others.

### Symlink Resolution

The `openclaw.json` configuration includes `"resolveSymlinks": true` in its security section. This instructs OpenClaw to resolve symlinks to their real paths before validating whether a path falls within an allowed perimeter. Without this, a symlink in `./project/` could point to `~/.openclaw/workspace/SOUL.md`, and a path check against `./project/` would pass while the actual write targets a protected file.

The read-only mounts on target paths provide a kernel-level backstop: even if symlink resolution fails in the application layer, the Linux VFS will reject the write because the target mount is read-only.

**Threat covered:** Symlink escape from the writable `./project/` perimeter to protected configuration paths.

### PID-1 Signal Handling (tini)

The Dockerfile uses `tini` as the entrypoint (`ENTRYPOINT ["tini", "--"]`). Tini serves as PID 1 inside the container, properly forwarding signals and reaping zombie processes. Without tini, an orphaned process tree could accumulate zombies until the PID limit is reached, causing a denial of service.

### Minimal Base Image

The Dockerfile uses `node:20-slim` and installs only `curl` (for health checks) and `tini`. No compiler toolchain, no package managers beyond apt (which has its cache removed), no development headers. This minimizes the attack surface inside the container.
