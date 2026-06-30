#!/bin/sh
# LAB ARTIFACT — fake attack for hardening demonstration only
# ============================================================================
# harness.sh — Evidence-Capture Harness for Attack Demonstrations
# ============================================================================
#
# Runs each attack payload and captures output to evidence/<attack-name>/.
# Records: command attempted, stdout/stderr, file hashes before/after, mtimes.
#
# Usage: bash attacks/harness.sh
#        (run from the repository root, or the script will cd there)
# ============================================================================

set -u

# ---------------------------------------------------------------------------
# Resolve paths
# ---------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
ATTACKS_DIR="$SCRIPT_DIR"
EVIDENCE_DIR="$REPO_ROOT/evidence"

echo "========================================"
echo "  Attack Harness — Evidence Capture"
echo "========================================"
echo "Repo root:   $REPO_ROOT"
echo "Attacks dir: $ATTACKS_DIR"
echo "Evidence dir: $EVIDENCE_DIR"
echo ""

# ---------------------------------------------------------------------------
# Target files to monitor (container paths for in-container runs,
# or config/ paths for host-side simulation)
# ---------------------------------------------------------------------------
# When running inside the hardened container, targets are at /home/node/...
# When running on the host for development, we monitor the config/ source files.
if [ -f "/home/node/.openclaw/openclaw.json" ]; then
    # Running inside the container
    TARGETS="
/home/node/.openclaw/openclaw.json
/home/node/.openclaw/workspace/BOOT.md
/home/node/.openclaw/workspace/SOUL.md
/home/node/.openclaw/workspace/MEMORY.md
/home/node/.openclaw/workspace/HEARTBEAT.md
/home/node/.openclaw/workspace/AGENTS.md
/home/node/.openclaw/workspace/IDENTITY.md
/home/node/.openclaw/workspace/USER.md
/home/node/.openclaw/workspace/TOOLS.md
"
else
    # Running on the host — monitor config/ source files
    TARGETS="
$REPO_ROOT/config/openclaw.json
$REPO_ROOT/config/workspace/BOOT.md
$REPO_ROOT/config/workspace/SOUL.md
$REPO_ROOT/config/workspace/MEMORY.md
$REPO_ROOT/config/workspace/HEARTBEAT.md
$REPO_ROOT/config/workspace/AGENTS.md
$REPO_ROOT/config/workspace/IDENTITY.md
$REPO_ROOT/config/workspace/USER.md
$REPO_ROOT/config/workspace/TOOLS.md
"
fi

# ---------------------------------------------------------------------------
# Helper: record hashes and mtimes for all target files
# ---------------------------------------------------------------------------
snapshot() {
    local label="$1"
    local outfile="$2"
    echo "=== $label ===" >> "$outfile"
    for f in $TARGETS; do
        if [ -f "$f" ]; then
            hash=$(sha256sum "$f" 2>/dev/null | awk '{print $1}')
            mtime=$(stat -c '%Y %y' "$f" 2>/dev/null || stat -f '%m' "$f" 2>/dev/null || echo "N/A")
            echo "  $f" >> "$outfile"
            echo "    sha256: $hash" >> "$outfile"
            echo "    mtime:  $mtime" >> "$outfile"
        else
            echo "  $f  [NOT FOUND]" >> "$outfile"
        fi
    done
    echo "" >> "$outfile"
}

# ---------------------------------------------------------------------------
# Helper: run one attack and capture evidence
# ---------------------------------------------------------------------------
run_attack() {
    local name="$1"
    local payload="$2"
    local evidence_subdir="$EVIDENCE_DIR/$name"

    echo "----------------------------------------"
    echo "  Running: $name"
    echo "  Payload: $payload"
    echo "----------------------------------------"

    # Create evidence directory
    mkdir -p "$evidence_subdir"

    local result_file="$evidence_subdir/result.txt"

    # Header
    echo "============================================" > "$result_file"
    echo "  Attack: $name" >> "$result_file"
    echo "  Payload: $payload" >> "$result_file"
    echo "  Date: $(date -u '+%Y-%m-%dT%H:%M:%SZ')" >> "$result_file"
    echo "============================================" >> "$result_file"
    echo "" >> "$result_file"

    # Record the command
    echo "--- Command ---" >> "$result_file"
    echo "sh $payload" >> "$result_file"
    echo "" >> "$result_file"

    # Snapshot BEFORE
    snapshot "BEFORE (hashes + mtimes)" "$result_file"

    # Run the payload, capture stdout+stderr
    echo "--- Output (stdout + stderr) ---" >> "$result_file"
    sh "$payload" >> "$result_file" 2>&1 || true
    echo "" >> "$result_file"

    # Snapshot AFTER
    snapshot "AFTER (hashes + mtimes)" "$result_file"

    # Compare before/after
    echo "--- Comparison ---" >> "$result_file"
    local changed=0
    for f in $TARGETS; do
        if [ -f "$f" ]; then
            # Re-compute hash to compare
            hash_now=$(sha256sum "$f" 2>/dev/null | awk '{print $1}')
            # Extract the BEFORE hash from the result file
            hash_before=$(grep -A2 "^  $f\$" "$result_file" | head -1 | grep "sha256:" | awk '{print $2}' | head -1)
            if [ -n "$hash_before" ] && [ "$hash_now" != "$hash_before" ]; then
                echo "  CHANGED: $f" >> "$result_file"
                echo "    before: $hash_before" >> "$result_file"
                echo "    after:  $hash_now" >> "$result_file"
                changed=1
            fi
        fi
    done
    if [ "$changed" -eq 0 ]; then
        echo "  No target files were modified. Hardening held." >> "$result_file"
    else
        echo "  WARNING: Some target files were modified!" >> "$result_file"
    fi
    echo "" >> "$result_file"

    # Verdict
    echo "--- Verdict ---" >> "$result_file"
    if grep -q "Read-only file system" "$result_file" 2>/dev/null; then
        echo "  BLOCKED: Write attempts rejected with 'Read-only file system'" >> "$result_file"
    elif grep -q "Permission denied" "$result_file" 2>/dev/null; then
        echo "  BLOCKED: Write attempts rejected with 'Permission denied'" >> "$result_file"
    elif [ "$changed" -eq 0 ]; then
        echo "  BLOCKED: No files modified (may be running outside container)" >> "$result_file"
    else
        echo "  VULNERABLE: Attack succeeded — files were modified" >> "$result_file"
    fi

    echo "  Evidence saved to: $result_file"
    echo ""
}

# ---------------------------------------------------------------------------
# Run all attacks
# ---------------------------------------------------------------------------

# Attack 01 — Config Rewrite
if [ -f "$ATTACKS_DIR/01-config-rewrite/payload.sh" ]; then
    run_attack "01-config-rewrite" "$ATTACKS_DIR/01-config-rewrite/payload.sh"
fi

# Attack 02 — Boot Hook
if [ -f "$ATTACKS_DIR/02-boot-hook/payload.sh" ]; then
    run_attack "02-boot-hook" "$ATTACKS_DIR/02-boot-hook/payload.sh"
fi

# Attack 03 — Soul Poison
if [ -f "$ATTACKS_DIR/03-soul-poison/payload.sh" ]; then
    run_attack "03-soul-poison" "$ATTACKS_DIR/03-soul-poison/payload.sh"
fi

# Attack 04 — Skill Shadow
if [ -f "$ATTACKS_DIR/04-skill-shadow/payload.sh" ]; then
    run_attack "04-skill-shadow" "$ATTACKS_DIR/04-skill-shadow/payload.sh"
fi

# Attack 05 — Exfiltration
if [ -f "$ATTACKS_DIR/05-exfil/payload.sh" ]; then
    run_attack "05-exfil" "$ATTACKS_DIR/05-exfil/payload.sh"
fi

# Attack 06 — Destruction
if [ -f "$ATTACKS_DIR/06-destruction/payload.sh" ]; then
    run_attack "06-destruction" "$ATTACKS_DIR/06-destruction/payload.sh"
fi

# Attack 07 — Symlink Escape
if [ -f "$ATTACKS_DIR/07-symlink-escape/payload.sh" ]; then
    run_attack "07-symlink-escape" "$ATTACKS_DIR/07-symlink-escape/payload.sh"
fi

# Attack 08 — Git Hook Time Bomb
if [ -f "$ATTACKS_DIR/08-git-hook-bomb/payload.sh" ]; then
    run_attack "08-git-hook-bomb" "$ATTACKS_DIR/08-git-hook-bomb/payload.sh"
fi

# Attack 09 — CI/CD Config Injection
if [ -f "$ATTACKS_DIR/09-cicd-injection/payload.sh" ]; then
    run_attack "09-cicd-injection" "$ATTACKS_DIR/09-cicd-injection/payload.sh"
fi

# Attack 10 — Makefile Weaponization
if [ -f "$ATTACKS_DIR/10-makefile-trap/payload.sh" ]; then
    run_attack "10-makefile-trap" "$ATTACKS_DIR/10-makefile-trap/payload.sh"
fi

# Attack 11 — Cross-Session Poisoning
if [ -f "$ATTACKS_DIR/11-cross-session-poison/payload.sh" ]; then
    run_attack "11-cross-session-poison" "$ATTACKS_DIR/11-cross-session-poison/payload.sh"
fi

# Attack 12 — procfs Information Leak
if [ -f "$ATTACKS_DIR/12-procfs-leak/payload.sh" ]; then
    run_attack "12-procfs-leak" "$ATTACKS_DIR/12-procfs-leak/payload.sh"
fi

# Attack 13 — Hardlink Escape
if [ -f "$ATTACKS_DIR/13-hardlink-escape/payload.sh" ]; then
    run_attack "13-hardlink-escape" "$ATTACKS_DIR/13-hardlink-escape/payload.sh"
fi

# Attack 14 — DNS Tunneling
if [ -f "$ATTACKS_DIR/14-dns-tunnel/payload.sh" ]; then
    run_attack "14-dns-tunnel" "$ATTACKS_DIR/14-dns-tunnel/payload.sh"
fi

# Attack 15 — Resource Exhaustion
if [ -f "$ATTACKS_DIR/15-resource-exhaustion/payload.sh" ]; then
    run_attack "15-resource-exhaustion" "$ATTACKS_DIR/15-resource-exhaustion/payload.sh"
fi

# ---------------------------------------------------------------------------
# Cleanup after attack 15 (resource exhaustion)
# The fork bomb spawns short-lived (3s) sleep processes. Wait for them to
# exit naturally so subsequent attacks get a clean process table.
# ---------------------------------------------------------------------------
echo "  [harness] Waiting for attack 15 residual processes to exit..."
sleep 5
wait 2>/dev/null || true
echo "  [harness] PID count after cleanup: $(ls /proc/[0-9]* -d 2>/dev/null | wc -l)"
echo ""

# Attack 16 — LD_PRELOAD Hijack
if [ -f "$ATTACKS_DIR/16-ldpreload-hijack/payload.sh" ]; then
    run_attack "16-ldpreload-hijack" "$ATTACKS_DIR/16-ldpreload-hijack/payload.sh"
fi

# Attack 17 — TOCTOU Race Condition
if [ -f "$ATTACKS_DIR/17-toctou-race/payload.sh" ]; then
    run_attack "17-toctou-race" "$ATTACKS_DIR/17-toctou-race/payload.sh"
fi

# Attack 18 — Chat Template Injection
if [ -f "$ATTACKS_DIR/18-chat-template-inject/payload.sh" ]; then
    run_attack "18-chat-template-inject" "$ATTACKS_DIR/18-chat-template-inject/payload.sh"
fi

# Attack 19 — File-Name Exfiltration
if [ -f "$ATTACKS_DIR/19-filename-exfil/payload.sh" ]; then
    run_attack "19-filename-exfil" "$ATTACKS_DIR/19-filename-exfil/payload.sh"
fi

# Attack 20 — IDE Weaponization
if [ -f "$ATTACKS_DIR/20-ide-weaponize/payload.sh" ]; then
    run_attack "20-ide-weaponize" "$ATTACKS_DIR/20-ide-weaponize/payload.sh"
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo "========================================"
echo "  Harness Complete"
echo "========================================"
echo "Evidence saved to: $EVIDENCE_DIR/"
echo ""
echo "Per-attack results:"
for d in "$EVIDENCE_DIR"/*/; do
    if [ -f "$d/result.txt" ]; then
        name=$(basename "$d")
        verdict=$(grep -A1 "Verdict" "$d/result.txt" | tail -1 | sed 's/^  //')
        echo "  $name: $verdict"
    fi
done
echo ""
