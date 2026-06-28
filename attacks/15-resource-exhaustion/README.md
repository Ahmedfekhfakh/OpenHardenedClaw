# Attack 15 — Resource Exhaustion (DoS)

## Attack Description

Tests container resource limits:
1. **Fork bomb** — attempts to exceed `pids_limit: 256`
2. **tmpfs fill** — attempts to exceed `/tmp` 256MB size cap
3. **Disk fill via project/** — no quota, potential host-level DoS
4. **File descriptor exhaustion** — tests ulimit

## Expected Result — Hardened

- Fork bomb: **CONTAINED** by `pids_limit: 256`
- tmpfs fill: **CONTAINED** by `size=256m`
- Disk fill via project/: **NOT CONTAINED** — no quota on `:rw` mount
- FD exhaustion: **PARTIALLY CONTAINED** by default ulimits

## Mitigation Recommendation

- Add disk quota on project/ mount (dedicated partition or `--storage-opt`)
- Set explicit `ulimits: nofile: 4096:8192` in compose
