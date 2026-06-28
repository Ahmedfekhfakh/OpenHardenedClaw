# Heartbeat

Periodic health-check hook. This file is mounted read-only to prevent injection of
timer-driven execution payloads. Any modification attempt will fail with "Read-only file system".
