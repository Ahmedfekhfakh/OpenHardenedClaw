# 1. Environment Description

## Host Platform

The deployment runs on **Linux under WSL2** (Windows Subsystem for Linux, kernel 6.6.87.2-microsoft-standard-WSL2). WSL2 provides a genuine Linux kernel with full container support, making it a suitable development and lab environment for Docker-based hardening work. The host acts as the operator workstation; all agent execution takes place inside containers.

## OpenClaw Agent

**Agent:** OpenClaw (official image `ghcr.io/openclaw/openclaw:latest`)
**Version:** OpenClaw **2026.6.10**
**Runtime:** Node.js **v24.16.0**
**PID 1 process:** `tini -s -- node openclaw.mjs gateway --bind lan --port 18789`
**Container image:** `docker-openclaw-gateway` (extends `ghcr.io/openclaw/openclaw:latest`)

OpenClaw is an agentic coding assistant that reads and writes source code on behalf of the user. For this lab, the **real** OpenClaw agent is deployed -- the container image extends the official OpenClaw image (`ghcr.io/openclaw/openclaw:latest`) which provides the full directory structure (`/home/node/.openclaw/`, `/home/node/.openclaw/workspace/`, skills directories, session storage) and runs the real OpenClaw gateway process (`node openclaw.mjs gateway`) that boots the workspace, connects to the llama.cpp model server, and accepts tasks. The Dockerfile extends the official image, adding only the project directory structure needed for bind mounts.

### Gateway Startup Evidence (2026-06-29T21:25Z)

The following log output was captured from the real OpenClaw gateway process at startup, confirming the agent's identity and runtime state:

```
[gateway] loading configuration...
[gateway] resolving authentication...
[gateway] starting...
[gateway] starting HTTP server...
[gateway] agent model: llamacpp-local/local-model (thinking=off, fast=off)
[gateway] http server listening (7 plugins: browser, canvas, device-pair,
          file-transfer, memory-core, phone-control, talk-voice; 0.4s)
[gateway] ready
[heartbeat] started
[gateway] failed to promote config last-known-good backup: Error: EROFS:
          read-only file system, open '/home/node/.openclaw/openclaw.json.last-good'
[gateway] provider auth state pre-warmed in 1135ms
```

This log reveals several significant details. First, the gateway loaded its configuration, resolved authentication, and started the HTTP server with 7 plugins, confirming it is the real, full-featured OpenClaw agent -- not a stub or mock. Second, the agent model is `llamacpp-local/local-model`, confirming the connection to the local llama.cpp server. Third, and most importantly, the gateway itself attempted to write `openclaw.json.last-good` as part of its normal startup routine and received `EROFS: read-only file system`. This is the ultimate proof that the `:ro` mount works against the real agent binary: OpenClaw's own internal write path was blocked by the kernel.

### Functional Agent Demonstration

Two demo scripts prove the agent performs real work within the hardened container:

- **`demo/agent-coding-task.sh`** -- The agent receives a coding task ("write an is_prime function"), sends it to the llama.cpp model via `/v1/chat/completions`, and writes the generated code to `project/prime.py`. The llama.cpp model produced actual `is_prime()` code that was written to the `:rw` mount. Protected paths were confirmed read-only.

- **`demo/indirect-injection-demo.sh`** -- The agent reads `project/README.md` (which contains a hidden prompt-injection payload in HTML comments) and sends it to the model as project context. The model responded to the injected instructions. Actions 1--3 succeeded (read `/proc`, write to `project/`). Actions 4--6 (rewrite `SOUL.md`, `openclaw.json`, `MEMORY.md`) were all **BLOCKED** with `Read-only file system`. This satisfies the "injection de prompt directe ou indirecte" requirement.

## Local Model Serving -- llama.cpp

Instead of calling a remote LLM provider API, the deployment serves a model **locally** using `llama.cpp`. A `.gguf` quantized model file is placed in the `models/` directory on the host and bind-mounted read-only into the `llamacpp-server` container. The server exposes an OpenAI-compatible `/v1` endpoint on the internal Docker network. OpenClaw's configuration (`openclaw.json`) references this endpoint at `http://llamacpp-server:8080/v1` with a placeholder API key (`sk-local`). This design eliminates any need for a real provider API key to enter the sandbox, closing the "egress through approved domain" exfiltration class entirely.

The server is launched with the `--jinja` flag to support chat-template-based tool calling, and `--host 0.0.0.0 --port 8080` to serve on the internal network. GPU offloading is enabled with `-ngl 99` for CUDA acceleration. Streaming is disabled in the agent config (`params.streaming: false`) and tool choice is set to `required` to work around flaky tool-call parsing on smaller quantized models.

## Three-Container Topology

The deployment consists of three containers on a single Docker network:

| Container | Role | Key Properties |
|-----------|------|----------------|
| `openclaw-gateway` | Agent loop -- reads instructions, calls the model, executes tool results | Config/instructions/skills mounted `:ro`; project directory mounted `:rw`; credentials **not mounted**; read-only root filesystem |
| `llamacpp-server` | Model inference -- serves the `.gguf` over `/v1` | Model weights mounted `:ro`; read-only root filesystem; CUDA GPU passthrough; no config or project mounts |
| `openclaw-sandbox` | Per-session tool execution (defined under `sandbox` profile, spawned on demand) | `network_mode: none`; read-only root; no config, project, or credential mounts; `tmpfs` scratch only |

Both `openclaw-gateway` and `llamacpp-server` were confirmed healthy during the live run on 2026-06-29.

## Network

All three containers sit on a single Docker network named `openclaw-internal`, configured with `internal: true`. This means the network has **no default gateway to the host** and therefore **no internet route**. Container-to-container communication (gateway to llamacpp-server) works normally over DNS, but no container can reach any external endpoint. The sandbox container goes further: it uses `network_mode: none`, giving it no network interfaces at all.

## Docker and Orchestration

Containers are defined in `docker/docker-compose.yml` and built with `docker compose up -d --build`. The compose file enforces all security invariants declaratively: read-only root filesystems, non-root user (`1000:1000`), capability dropping (`cap_drop: ALL`), `no-new-privileges`, seccomp profiles, resource limits (PIDs, memory, CPU), and volume mount modes. No manual `docker run` flags are needed.
