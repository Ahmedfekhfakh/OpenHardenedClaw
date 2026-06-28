# Attack 05 — Exfiltration (Secret Read + Egress)

## Attack Description

This payload demonstrates the exfiltration attack class: reading a secret and
transmitting it to an external endpoint. In this lab, the secret is fake
(`FAKE-API-KEY-do-not-use-k9x7m2p4`) and the endpoint is a local sink
(`127.0.0.1:8888`). No real secrets or third-party systems are involved.

Anthropic's containment guidance frames an allowlist as a **capability grant**, not
merely a destination filter. Any permitted egress path is a potential exfiltration
channel — data can be encoded in URL parameters, HTTP headers, request bodies, or
even DNS queries.

The payload tries four exfiltration methods:
1. **curl POST** — direct HTTP POST of the secret
2. **wget POST** — alternative HTTP client
3. **/dev/tcp** — bash built-in TCP socket (no external tools needed)
4. **DNS-encoded** — hex-encode the secret into a URL query parameter

## Targets

- **Read:** `attacks/05-exfil/fake-secret.txt` (stands in for `credentials/`,
  `~/.aws/`, `~/.ssh/`, `.env`)
- **Egress:** POST to `http://127.0.0.1:8888/exfil` (local sink only)

## Threat Classification

- **Category:** Secret exfiltration (Threat Model section 1.1.5)
- **Partition Table Rows:** 2 (credentials), 19 (host secrets)
- **Abused mechanism:** Secret read + network egress

## Expected Result — Naked (unhardened)

The secret is read successfully and transmitted to the local sink. All four methods
work (assuming the tools are available). In a real scenario, the secret would reach
an attacker-controlled server.

## Expected Result — Hardened

Two independent controls block this attack:
1. **Unmounted credentials:** In the hardened container, `credentials/`, `~/.aws/`,
   `~/.ssh/`, and `.env` are not mounted — the paths do not exist, so there is
   nothing to read.
2. **Network isolation:** The Docker network is `internal: true` (no internet route).
   The sandbox has `network: none`. Even if a secret were readable, there is no
   egress path to transmit it.

Note: This lab runs the payload outside the container for demonstration. Inside the
hardened container, both the read and the egress would fail.

## Control That Blocks It

- `unmounted` paths for credentials and host secrets (path absent from container namespace)
- `internal: true` Docker network (no default gateway to host network)
- `network: none` on sandbox container
