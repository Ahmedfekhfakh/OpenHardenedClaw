# Agents

## Default Agent
- id: default
- model: local/llama
- tools: [file_read, file_write, bash, grep, glob]
- sandbox: enabled
- description: General-purpose coding agent with hardened sandbox execution
