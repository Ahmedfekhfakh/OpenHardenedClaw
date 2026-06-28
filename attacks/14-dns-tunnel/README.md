# Attack 14 — DNS Tunneling (internal:true Bypass Test)

## Attack Description

Tests a **real potential gap**: Docker's `internal: true` blocks IP routing
but Docker's embedded DNS server (127.0.0.11) may still forward queries to
the host's DNS resolver, which has internet access. Data encoded in DNS
subdomain labels (e.g., `secret-data.attacker.com`) could leak to an
attacker-controlled authoritative DNS server.

## Expected Result — Hardened

**DEPENDS.** Internal hostname resolution (llamacpp-server) should work.
External DNS resolution should fail if `internal: true` properly isolates
DNS. If external DNS resolves, this is a **real gap** requiring mitigation.

## Mitigation Recommendation

- Add `dns: ["127.0.0.1"]` with no forwarder in compose
- Or use iptables on host to block DNS forwarding from internal network
- Or use `network_mode: none` with Unix socket for llama.cpp
