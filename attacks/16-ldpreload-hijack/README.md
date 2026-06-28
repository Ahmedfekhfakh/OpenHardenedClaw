# Attack 16 — LD_PRELOAD Hijack & PATH Shadowing

## Attack Description

Tests two related attacks exploiting the **missing `noexec`** on the `project/`
mount:

1. **LD_PRELOAD**: A shared library placed in `project/` can be loaded via
   `LD_PRELOAD` to hook all libc functions (open, read, write, connect) in
   subsequent processes. `/tmp` has `noexec` but `project/` does not.

2. **PATH hijacking**: Shadow system commands (curl, git, etc.) with trojaned
   versions in `project/bin/`, then prepend to `$PATH`.

## Expected Result — Hardened

- `/tmp` noexec: **BLOCKED** for direct exec, but interpreter bypass works
- `project/` noexec: **NOT SET** — .so files can be loaded, scripts can execute
- PATH hijack: **WORKS** if PATH includes project/ directory

## Mitigation Recommendation

- Add `noexec` to the `project/` mount if feasible
- Set PATH explicitly in Dockerfile (no writable dirs)
- Set `LD_PRELOAD=` (empty) in container environment
