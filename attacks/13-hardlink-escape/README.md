# Attack 13 — Hardlink Escape (Cross-Device Link Test)

## Attack Description

Unlike symlinks (attack 07), hardlinks share the same inode as the target.
Writes to a hardlink modify the original file directly, potentially bypassing
symlink-specific path validation. However, hardlinks cannot cross filesystem
(device) boundaries — `link()` returns `EXDEV`.

## Expected Result — Hardened

**BLOCKED.** The `:ro` bind mounts and project/ `:rw` mount are separate mount
points. `link()` fails with either EXDEV (cross-device) or EROFS (read-only
source). This validates a different code path than the symlink attack.
