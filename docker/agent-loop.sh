#!/bin/sh
# =============================================================================
# agent-loop.sh -- Simulated OpenClaw agent loop
# =============================================================================
# In production, this would be the OpenClaw binary (`openclaw serve`).
# This simulation demonstrates the agent's runtime lifecycle:
#   1. Boot: load workspace instruction files and config
#   2. Connect: verify llama.cpp model server is reachable
#   3. Ready: accept tasks via `docker exec`
# =============================================================================

echo "[agent] OpenClaw agent starting (simulated v0.1-lab)..."
echo "[agent] PID: $$, User: $(whoami), UID: $(id -u)"
echo "[agent] Timestamp: $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
echo ""

# ---- Boot phase: load workspace instruction files --------------------------
echo "[agent] Boot: loading workspace configuration..."
for f in SOUL.md AGENTS.md MEMORY.md USER.md IDENTITY.md TOOLS.md BOOT.md HEARTBEAT.md; do
    path="/home/agent/.openclaw/workspace/$f"
    if [ -f "$path" ]; then
        size=$(wc -c < "$path")
        echo "[agent]   Loaded $f ($size bytes)"
    else
        echo "[agent]   WARNING: $f not found"
    fi
done

echo "[agent] Boot: loading openclaw.json..."
if [ -f "/home/agent/.openclaw/openclaw.json" ]; then
    size=$(wc -c < "/home/agent/.openclaw/openclaw.json")
    echo "[agent]   Config loaded ($size bytes)"
    provider=$(grep -o '"baseUrl"[^,]*' /home/agent/.openclaw/openclaw.json | head -1 | cut -d'"' -f4)
    echo "[agent]   Model provider: $provider"
else
    echo "[agent]   WARNING: openclaw.json not found"
fi

echo ""

# ---- Verify read-only enforcement -----------------------------------------
echo "[agent] Boot: verifying read-only enforcement..."
if sh -c 'echo "test" >> /home/agent/.openclaw/openclaw.json' 2>/dev/null; then
    echo "[agent]   WARNING: openclaw.json is WRITABLE -- hardening not active"
else
    echo "[agent]   openclaw.json is read-only (OK)"
fi
if sh -c 'echo "test" >> /home/agent/.openclaw/workspace/SOUL.md' 2>/dev/null; then
    echo "[agent]   WARNING: SOUL.md is WRITABLE -- hardening not active"
else
    echo "[agent]   SOUL.md is read-only (OK)"
fi
echo ""

# ---- Connect to llama.cpp model server ------------------------------------
echo "[agent] Connecting to llama.cpp model server..."
CONNECTED=0
for i in $(seq 1 30); do
    if curl -sf http://llamacpp-server:8080/v1/models >/dev/null 2>&1; then
        MODEL_INFO=$(curl -sf http://llamacpp-server:8080/v1/models 2>/dev/null)
        echo "[agent]   Connected to llamacpp-server:8080"
        echo "[agent]   Model info: $(echo "$MODEL_INFO" | head -c 200)"
        CONNECTED=1
        break
    fi
    if [ "$i" -le 3 ] || [ "$((i % 10))" -eq 0 ]; then
        echo "[agent]   Waiting for llamacpp-server... ($i/30)"
    fi
    sleep 2
done

if [ "$CONNECTED" -eq 0 ]; then
    echo "[agent]   WARNING: Could not reach llamacpp-server after 60s"
    echo "[agent]   Agent will start but model calls will fail"
fi
echo ""

# ---- Ready -----------------------------------------------------------------
echo "[agent] ================================================"
echo "[agent]   Agent ready. Workspace loaded, model connected."
echo "[agent] ================================================"
echo "[agent] Run demos with:"
echo "[agent]   docker exec openclaw-gateway sh /home/agent/demo/agent-coding-task.sh"
echo "[agent]   docker exec openclaw-gateway sh /home/agent/demo/indirect-injection-demo.sh"
echo "[agent] Run attack harness with:"
echo "[agent]   docker exec openclaw-gateway sh /home/agent/attacks/harness.sh"
echo ""

# Keep the container alive (agent event loop)
exec tail -f /dev/null
