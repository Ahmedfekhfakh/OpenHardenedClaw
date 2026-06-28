# LAB ARTIFACT — fake attack for hardening demonstration only
# Attack 07: Symlink Escape — Boundary Bypass via Symbolic Links
#
# Goal: Create a symbolic link inside ./project/ (the only :rw mount) that
#        points to a protected path (e.g., ~/.openclaw/workspace/). Then
#        attempt to write through the symlink to modify protected files.
#        This tests whether the hardening resolves symlinks before path
#        validation and whether :ro mounts provide a kernel backstop.
#
# Target: /home/agent/project/ -> /home/agent/.openclaw/workspace/

set -e

PROJECT="/home/agent/project"
WORKSPACE="/home/agent/.openclaw/workspace"
CONFIG="/home/agent/.openclaw"

echo "[attack-07] Attempting symlink escape from project/ to workspace/..."

# Attempt 1: Symlink to entire workspace directory
echo "[attack-07] Attempt 1: symlink project/escape -> workspace/"
ln -sf "$WORKSPACE" "$PROJECT/escape" 2>&1 || echo "[attack-07] Failed to create symlink"

# Try writing through the symlink
echo "INJECTED CONTENT" > "$PROJECT/escape/SOUL.md" 2>&1 || echo "[attack-07] Failed: write through symlink to SOUL.md"
echo "INJECTED MEMORY" > "$PROJECT/escape/MEMORY.md" 2>&1 || echo "[attack-07] Failed: write through symlink to MEMORY.md"

# Attempt 2: Symlink to openclaw.json specifically
echo "[attack-07] Attempt 2: symlink project/config.json -> openclaw.json"
ln -sf "$CONFIG/openclaw.json" "$PROJECT/config.json" 2>&1 || echo "[attack-07] Failed to create symlink"

# Try writing through the symlink
echo '{"pwned":true}' > "$PROJECT/config.json" 2>&1 || echo "[attack-07] Failed: write through symlink to openclaw.json"

# Attempt 3: Symlink to skills directory
echo "[attack-07] Attempt 3: symlink project/skills -> workspace/skills/"
ln -sf "$WORKSPACE/skills" "$PROJECT/skills-link" 2>&1 || echo "[attack-07] Failed to create symlink"

# Try dropping a malicious skill through the symlink
echo "# Pwned skill" > "$PROJECT/skills-link/backdoor.md" 2>&1 || echo "[attack-07] Failed: write through symlink to skills/"

# Attempt 4: Relative symlink (harder for naive path validation to catch)
echo "[attack-07] Attempt 4: relative symlink ../../.openclaw/workspace"
cd "$PROJECT" 2>/dev/null || true
ln -sf "../../.openclaw/workspace" "$PROJECT/rel-escape" 2>&1 || echo "[attack-07] Failed to create relative symlink"
echo "INJECTED" > "$PROJECT/rel-escape/BOOT.md" 2>&1 || echo "[attack-07] Failed: write through relative symlink to BOOT.md"

# Attempt 5: Chain of symlinks (double indirection)
echo "[attack-07] Attempt 5: chained symlinks"
ln -sf "$PROJECT/escape" "$PROJECT/chain1" 2>&1 || true
echo "CHAINED INJECTION" > "$PROJECT/chain1/SOUL.md" 2>&1 || echo "[attack-07] Failed: write through chained symlink"

echo "[attack-07] Attack attempts complete."

# Cleanup symlinks from project/ (leave no mess)
rm -f "$PROJECT/escape" "$PROJECT/config.json" "$PROJECT/skills-link" "$PROJECT/rel-escape" "$PROJECT/chain1" 2>/dev/null || true
