# 3. Installation and Deployment Process

## Prerequisites

- A Linux host or WSL2 environment
- Docker Engine (with compose v2 plugin)
- A `.gguf` quantized model file compatible with llama.cpp

## Step-by-Step Deployment

### 1. Clone the Repository

```bash
git clone <repo-url> Projet_707
cd Projet_707
```

### 2. Place Model Weights

Copy a `.gguf` model file into the `models/` directory. This directory is git-ignored (model files are large binaries that should not enter version control).

```bash
mkdir -p models
cp /path/to/your-model.gguf models/model.gguf
```

The filename must match the `--model` argument in `docker-compose.yml` (default: `/models/model.gguf`).

### 3. Verify Configuration Files Exist

The workspace instruction files and config must be present for the read-only bind mounts to succeed:

```bash
ls config/openclaw.json
ls config/workspace/SOUL.md config/workspace/MEMORY.md \
   config/workspace/AGENTS.md config/workspace/BOOT.md \
   config/workspace/HEARTBEAT.md config/workspace/IDENTITY.md \
   config/workspace/USER.md config/workspace/TOOLS.md
ls config/workspace/memory/ config/workspace/skills/ config/skills/
```

If any are missing, create them as empty files or with default content. The bind mounts in `docker-compose.yml` require these paths to exist on the host.

### 4. Build and Start Containers

```bash
cd docker
docker compose up -d --build
```

This builds the `openclaw-gateway` and `openclaw-sandbox` images from `Dockerfile.openclaw` and pulls the `ghcr.io/ggerganov/llama.cpp:server` image for the model server. Only `openclaw-gateway` and `llamacpp-server` start by default; the sandbox is under a `sandbox` profile and is spawned on demand.

### 5. Verify Containers Are Running

```bash
docker compose ps
```

Expected output: two services (`openclaw-gateway`, `llamacpp-server`) in `Up` state.

### 6. Check Model Server Health

```bash
docker compose logs llamacpp-server | head -20
```

Look for the model loading confirmation and the `/v1` endpoint binding on port 8080. The health check (`curl -sf http://localhost:8080/v1/models`) runs every 15 seconds with a 30-second start period.

### 7. Verify Read-Only Mounts (Optional Sanity Check)

From the gateway container, confirm that protected paths reject writes:

```bash
docker exec openclaw-gateway sh -c \
  'echo "test" >> /home/agent/.openclaw/openclaw.json 2>&1 || true'
```

Expected output: `Read-only file system`.

### 8. Start the Sandbox (When Needed)

To bring up the sandbox service explicitly:

```bash
docker compose --profile sandbox up -d openclaw-sandbox
```

### 9. Run Functional Agent Demos

Demonstrate the agent performing a coding task and the indirect prompt injection demo:

```bash
# Coding task: agent calls llama.cpp and writes code to project/
docker exec openclaw-gateway sh /home/agent/demo/agent-coding-task.sh

# Indirect injection: poisoned README.md reaches model loop,
# environment blocks writes to protected paths
docker exec openclaw-gateway sh /home/agent/demo/indirect-injection-demo.sh
```

### 10. Run Attack Harness

Execute all 20 attacks and capture evidence:

```bash
docker exec openclaw-gateway sh /home/agent/attacks/harness.sh
```

Evidence is written to `evidence/<attack-id>/result.txt` for each attack.

## Tear-Down

```bash
cd docker
docker compose down
```

This stops and removes all containers and the `openclaw-internal` network. Model weights in `models/` and configuration in `config/` are unaffected (they are bind-mounted, not Docker volumes).
