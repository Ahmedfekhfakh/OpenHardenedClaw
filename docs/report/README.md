# Hardened OpenClaw in Docker -- Project Report

**Telecom Paris -- Defensive Security Lab (Projet 707)**

---

## Table of Contents

| # | File | Section |
|---|------|---------|
| 1 | [01-environment.md](01-environment.md) | Environment description: host platform, OpenClaw, llama.cpp, three-container topology, internal network |
| 2 | [02-threat-model.md](02-threat-model.md) | Threat model: three risk categories (external/supply-chain, model misbehavior, user misuse), protected assets, blast radius |
| 3 | [03-install-process.md](03-install-process.md) | Installation and deployment: step-by-step bash commands to clone, configure, build, and verify |
| 4 | [04-hardening-design.md](04-hardening-design.md) | Hardening design (centerpiece): filesystem partition table with per-row justification, plus non-FS controls (seccomp, capabilities, network, resource limits) |
| 5 | [05-before-after.md](05-before-after.md) | Functional agent demos (coding task + indirect injection) and before/after attack matrix (20 attacks with evidence) |
| 6 | [06-diagrams.md](06-diagrams.md) | Architecture and workflow diagrams: agentic tool-call loop with read-only boundary, before vs. after deployment comparison |
| 7 | [07-bonus.md](07-bonus.md) | Bonus: egress-through-approved-domain attack class, local llama.cpp fix, and MITM proxy fallback |

---

## How to Read This Report

Each section is a standalone Markdown file. They can be read individually or concatenated for PDF conversion:

```bash
cat docs/report/0*.md > docs/report/full-report.md
# Then convert with pandoc, grip, or any Markdown-to-PDF tool
```

## Source Artifacts

This report synthesizes from the following project files:

- `docs/partition-table.md` -- configuration surface map with mount modes
- `docs/threat-model.md` -- threat model with risk categories and mapping table
- `docker/docker-compose.yml` -- hardened Docker Compose deployment
- `docker/Dockerfile.openclaw` -- container image definition
- `docker/seccomp/openclaw-seccomp.json` -- custom seccomp profile
- `config/openclaw.json` -- OpenClaw runtime configuration
- `demo/agent-coding-task.sh` -- functional agent coding task demo
- `demo/indirect-injection-demo.sh` -- indirect prompt injection demo
- `docker/agent-loop.sh` -- simulated agent loop (container CMD)
