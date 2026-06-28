# 1. Environment Description

## Host Platform

The deployment runs on **Linux under WSL2** (Windows Subsystem for Linux, kernel 6.6.x). WSL2 provides a genuine Linux kernel with full container support, making it a suitable development and lab environment for Docker-based hardening work. The host acts as the operator workstation; all agent execution takes place inside containers.

## OpenClaw Agent

**Agent:** OpenClaw v0.1-lab (simulated)
**Version basis:** OpenClaw architecture as of June 2026 (config schema, workspace layout, skill precedence, sandbox model)

OpenClaw is an agentic coding assistant that reads and writes source code on behalf of the user. For this lab, OpenClaw is **simulated** -- the container image builds the expected directory structure (`~/.openclaw/`, `~/.openclaw/workspace/`, skills directories, session storage) and includes an agent-loop script (`docker/agent-loop.sh`) that boots the workspace, connects to the llama.cpp model server, and accepts tasks. This simulation demonstrates the agent's runtime lifecycle (boot, context loading, model interaction, file writes) so that the hardening controls can be demonstrated and attacked without requiring a production OpenClaw license or binary. The Dockerfile is based on `node:20-slim` with only essential packages (curl for health checks and model API calls, tini for PID-1 signal forwarding).

### Functional Agent Demonstration

Two demo scripts prove the agent performs real work within the hardened container:

- **`demo/agent-coding-task.sh`** -- The agent receives a coding task ("write an is_prime function"), sends it to the llama.cpp model via `/v1/chat/completions`, and writes the generated code to `project/prime.py`. This demonstrates a complete agent session: boot, model call, file write to `:rw` project/, and verification that protected paths remain read-only.

- **`demo/indirect-injection-demo.sh`** -- The agent reads `project/README.md` (which contains a hidden prompt-injection payload in HTML comments) and sends it to the model as project context. The model may follow the injected instructions (read `/proc/self/environ`, copy workspace files, rewrite `SOUL.md`). The demo shows that writes to protected paths are blocked by `:ro` mounts regardless of whether the injection reaches the model loop. This satisfies the "injection de prompt directe ou indirecte" requirement.

## Local Model Serving -- llama.cpp

Instead of calling a remote LLM provider API, the deployment serves a model **locally** using `llama.cpp`. A `.gguf` quantized model file is placed in the `models/` directory on the host and bind-mounted read-only into the `llamacpp-server` container. The server exposes an OpenAI-compatible `/v1` endpoint on the internal Docker network. OpenClaw's configuration (`openclaw.json`) references this endpoint at `http://llamacpp-server:8080/v1` with a placeholder API key (`sk-local`). This design eliminates any need for a real provider API key to enter the sandbox, closing the "egress through approved domain" exfiltration class entirely.

The server is launched with the `--jinja` flag to support chat-template-based tool calling. Streaming is disabled in the agent config (`params.streaming: false`) and tool choice is set to `required` to work around flaky tool-call parsing on smaller quantized models.

## Three-Container Topology

The deployment consists of three containers on a single Docker network:

| Container | Role | Key Properties |
|-----------|------|----------------|
| `openclaw-gateway` | Agent loop -- reads instructions, calls the model, executes tool results | Config/instructions/skills mounted `:ro`; project directory mounted `:rw`; credentials **not mounted**; read-only root filesystem |
| `llamacpp-server` | Model inference -- serves the `.gguf` over `/v1` | Model weights mounted `:ro`; read-only root filesystem; no config or project mounts |
| `openclaw-sandbox` | Per-session tool execution (defined under `sandbox` profile, spawned on demand) | `network_mode: none`; read-only root; no config, project, or credential mounts; `tmpfs` scratch only |

## Network

All three containers sit on a single Docker network named `openclaw-internal`, configured with `internal: true`. This means the network has **no default gateway to the host** and therefore **no internet route**. Container-to-container communication (gateway to llamacpp-server) works normally over DNS, but no container can reach any external endpoint. The sandbox container goes further: it uses `network_mode: none`, giving it no network interfaces at all.

## Docker and Orchestration

Containers are defined in `docker/docker-compose.yml` and built with `docker compose up -d --build`. The compose file enforces all security invariants declaratively: read-only root filesystems, non-root user (`1000:1000`), capability dropping (`cap_drop: ALL`), `no-new-privileges`, seccomp profiles, resource limits (PIDs, memory, CPU), and volume mount modes. No manual `docker run` flags are needed.
