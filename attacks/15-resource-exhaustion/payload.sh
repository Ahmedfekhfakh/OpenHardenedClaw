# LAB ARTIFACT — fake attack for hardening demonstration only
# Attack 15: Resource Exhaustion — Fork Bomb, tmpfs Fill, Disk Bomb
#
# Goal: Test resource limits by attempting:
#        1. Fork bomb (PID exhaustion) — should hit pids_limit: 256
#        2. tmpfs filling (memory exhaustion via tmpfs) — capped at 256MB
#        3. Disk filling via project/ (no quota!) — potential host DoS
#        4. File descriptor exhaustion
#
# CAUTION: These are contained by resource limits, but the disk fill
#          via project/ has NO quota and could impact the host.

set +e

echo "[attack-15] Attempting resource exhaustion attacks..."

# Test 1: Fork bomb (CAREFUL — limited by pids_limit: 256)
echo "[attack-15] Test 1: Fork bomb (pids_limit test)"
echo "[attack-15]   Current PID count before:"
ls /proc/[0-9]* -d 2>/dev/null | wc -l || true

# Controlled fork bomb — spawn 300 short-lived sleeps to exceed pids_limit: 256
# Using sleep 3 (not 60) so PIDs are reclaimed quickly after the test.
FORK_FAIL=0
for i in $(seq 1 300); do
    sleep 3 & 2>/dev/null || FORK_FAIL=$((FORK_FAIL + 1))
done 2>/dev/null
echo "[attack-15]   Fork failures: $FORK_FAIL"
echo "[attack-15]   PID count at peak:"
ls /proc/[0-9]* -d 2>/dev/null | wc -l || true

# Wait for short-lived sleeps to finish naturally (3s), then clean up stragglers
echo "[attack-15]   Waiting for background processes to exit..."
sleep 4
wait 2>/dev/null || true
echo "[attack-15]   PID count after cleanup:"
ls /proc/[0-9]* -d 2>/dev/null | wc -l || true

# Test 2: tmpfs filling (/tmp has 256MB limit)
echo "[attack-15] Test 2: tmpfs fill (/tmp, 256MB limit)"
dd if=/dev/zero of=/tmp/fill-test bs=1M count=300 2>&1 || true
echo "[attack-15]   /tmp usage:"
df -h /tmp 2>/dev/null || true
rm -f /tmp/fill-test 2>/dev/null || true

# Test 3: Disk fill via project/ (NO QUOTA — real gap)
echo "[attack-15] Test 3: Disk fill via project/ (50MB test — limited for safety)"
dd if=/dev/zero of=/home/node/project/fill-test bs=1M count=50 2>&1 || true
echo "[attack-15]   project/ usage:"
du -sh /home/node/project/ 2>/dev/null || true
rm -f /home/node/project/fill-test 2>/dev/null || true
echo "[attack-15]   NOTE: No disk quota on project/ mount — a real attacker"
echo "[attack-15]   could write gigabytes, filling the host filesystem."

# Test 4: File descriptor exhaustion
echo "[attack-15] Test 4: File descriptor exhaustion"
echo "[attack-15]   Current ulimit -n: $(ulimit -n 2>/dev/null || echo 'unknown')"
FD_COUNT=0
for i in $(seq 1 2000); do
    exec 3>/dev/null 2>/dev/null && FD_COUNT=$((FD_COUNT + 1)) || break
done
echo "[attack-15]   Opened $FD_COUNT file descriptors before limit"

echo "[attack-15] Attack attempts complete."
