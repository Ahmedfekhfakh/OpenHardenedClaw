# Hardened OpenClaw in Docker -- Project Report

**Telecom Paris -- Defensive Security Lab (Projet 707)**
**Live run: 2026-06-29 -- OpenClaw 2026.6.10 on Node.js v24.16.0**

---

## Table of Contents

| # | File | Section |
|---|------|---------|
| 1 | [01-environment.md](01-environment.md) | Environment description: host platform, OpenClaw 2026.6.10, llama.cpp, three-container topology, gateway startup evidence |
| 2 | [02-threat-model.md](02-threat-model.md) | Threat model: three risk categories (external/supply-chain, model misbehavior, user misuse), protected assets, blast radius |
| 3 | [03-install-process.md](03-install-process.md) | Installation and deployment: step-by-step bash commands to clone, configure, build, and verify |
| 4 | [04-hardening-design.md](04-hardening-design.md) | Hardening design (centerpiece): filesystem partition table with per-row justification, plus non-FS controls (seccomp, capabilities, network, resource limits) |
| 5 | [05-before-after.md](05-before-after.md) | Before/after attack matrix: 20 attacks with SHA-256 evidence, gateway self-proof, functional demos |
| 6 | [06-diagrams.md](06-diagrams.md) | Architecture and workflow diagrams: agentic tool-call loop with read-only boundary, before vs. after deployment comparison |
| 7 | [07-bonus.md](07-bonus.md) | Bonus: egress-through-approved-domain attack class, local llama.cpp fix, and MITM proxy fallback |
| -- | [full-report.md](full-report.md) | Complete report (all sections combined in one file) |

---

## How to Read This Report

Each section is a standalone Markdown file. They can be read individually or as the combined `full-report.md`. For PDF conversion:

```bash
# The full-report.md is already a complete, self-contained document.
# Convert with pandoc, grip, or any Markdown-to-PDF tool:
pandoc docs/report/full-report.md -o report.pdf
```

## Source Artifacts

This report synthesizes from the following project files:

- `docs/partition-table.md` -- configuration surface map with mount modes
- `docs/threat-model.md` -- threat model with risk categories and mapping table
- `docker/docker-compose.yml` -- hardened Docker Compose deployment
- `docker/Dockerfile.openclaw` -- container image definition (extends `ghcr.io/openclaw/openclaw:latest`)
- `docker/seccomp/openclaw-seccomp.json` -- custom seccomp profile
- `config/openclaw.json` -- OpenClaw runtime configuration
- `demo/agent-coding-task.sh` -- functional agent coding task demo
- `demo/indirect-injection-demo.sh` -- indirect prompt injection demo
- `attacks/harness.sh` -- 20-attack evidence capture harness
- Official OpenClaw image (`ghcr.io/openclaw/openclaw:latest`, version 2026.6.10)

## Key Evidence Summary

- **11 attacks BLOCKED** (EROFS, EXDEV, network unreachable)
- **1 attack CONTAINED** (pids_limit enforced)
- **1 INFO LEAK** (procfs readable, no secrets by design)
- **7 attacks PLANTED** (residual risk in `:rw` project/ directory)
- **9/9 protected files** verified unchanged by SHA-256 after all 20 attacks
- **Gateway self-proof**: OpenClaw's own startup code received `EROFS` on `openclaw.json.last-good`
