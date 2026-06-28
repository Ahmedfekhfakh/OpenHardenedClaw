# Attack 17 — TOCTOU Race Condition (Defense-in-Depth Validation)

## Attack Description

Rapidly alternates a path in `project/` between a regular file and a symlink
to a `:ro`-mounted target. If an application checks the path (sees safe file)
but the write hits the symlink (targeting SOUL.md), the race is won.

## Expected Result — Hardened

**BLOCKED by kernel backstop.** Even when the TOCTOU race wins and the
write goes through the symlink, the `:ro` mount on the target rejects
the write with `EROFS`. This validates defense-in-depth: the kernel
does not trust application-layer path validation.
