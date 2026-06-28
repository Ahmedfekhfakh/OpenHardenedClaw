# Attack 12 — procfs Information Leak (Reconnaissance)

## Attack Description

Reads sensitive information from `/proc` to map the container's configuration:
- `/proc/self/environ` — environment variables (may contain secrets)
- `/proc/self/mountinfo` — complete mount table with `:ro`/`:rw` modes and host paths
- `/proc/self/maps` — memory layout (defeats ASLR)
- `/proc/net/tcp`, `/proc/net/arp` — network topology, other container IPs
- `/proc/self/status` — capability set, seccomp status

## Expected Result — Hardened

**INFORMATION LEAK — readable but low impact by design.** No secrets are
passed via environment variables (model is local). Mount info reveals the
hardening configuration but does not enable bypass. Network info shows only
the internal network.

## Mitigation Recommendation

- Verify no secrets leak via environ (this attack validates that)
- Consider masking additional /proc paths if feasible
