# LAB ARTIFACT — fake attack for hardening demonstration only
# Attack 12: procfs Information Leak — Reconnaissance via /proc
#
# Goal: Read sensitive information from /proc that reveals container
#        configuration, environment variables, memory layout, mount
#        table, and network topology. This is reconnaissance that
#        enables targeted follow-up attacks.
#
# Target: /proc/self/environ, /proc/self/maps, /proc/self/mountinfo, /proc/net/

set -e

echo "[attack-12] Attempting procfs information leak..."

# Leak 1: Environment variables (may contain secrets passed via docker -e)
echo "[attack-12] === /proc/self/environ ==="
cat /proc/self/environ 2>/dev/null | tr '\0' '\n' || echo "[attack-12] Failed to read environ"
echo ""

# Leak 2: Mount table — reveals ALL mount points, host paths, and :ro/:rw modes
echo "[attack-12] === /proc/self/mountinfo (mount configuration) ==="
cat /proc/self/mountinfo 2>/dev/null | head -40 || echo "[attack-12] Failed to read mountinfo"
echo ""

# Leak 3: Memory layout — defeats ASLR, reveals library addresses
echo "[attack-12] === /proc/self/maps (memory layout, first 20 lines) ==="
cat /proc/self/maps 2>/dev/null | head -20 || echo "[attack-12] Failed to read maps"
echo ""

# Leak 4: Command line of all visible processes
echo "[attack-12] === /proc/*/cmdline (process commands) ==="
for pid in /proc/[0-9]*/; do
    cmdline=$(cat "${pid}cmdline" 2>/dev/null | tr '\0' ' ')
    if [ -n "$cmdline" ]; then
        echo "  PID $(basename $pid): $cmdline"
    fi
done 2>/dev/null || true
echo ""

# Leak 5: Network configuration — reveals internal network topology
echo "[attack-12] === /proc/net/tcp (active TCP connections) ==="
cat /proc/net/tcp 2>/dev/null | head -10 || echo "[attack-12] Failed to read net/tcp"
echo ""

echo "[attack-12] === /proc/net/arp (ARP table — other container IPs) ==="
cat /proc/net/arp 2>/dev/null || echo "[attack-12] Failed to read net/arp"
echo ""

echo "[attack-12] === /proc/net/route (routing table) ==="
cat /proc/net/route 2>/dev/null || echo "[attack-12] Failed to read net/route"
echo ""

# Leak 6: Hostname and DNS config
echo "[attack-12] === Container identity ==="
echo "  hostname: $(hostname 2>/dev/null)"
echo "  /etc/hosts:"
cat /etc/hosts 2>/dev/null | sed 's/^/    /'
echo "  /etc/resolv.conf:"
cat /etc/resolv.conf 2>/dev/null | sed 's/^/    /'
echo ""

# Leak 7: Capabilities and security context
echo "[attack-12] === Security context ==="
echo "  uid/gid: $(id 2>/dev/null)"
cat /proc/self/status 2>/dev/null | grep -E '^(Cap|Seccomp|NoNewPrivs)' | sed 's/^/  /' || true
echo ""

echo "[attack-12] Attack attempts complete."
