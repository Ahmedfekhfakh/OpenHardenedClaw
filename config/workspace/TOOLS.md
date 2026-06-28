# Tools

## Allowed Tools
- file_read: Read files within the project directory
- file_write: Write files within the project directory
- bash: Execute shell commands in the sandbox container
- grep: Search file contents
- glob: Find files by pattern

## Denied Tools
- browser: Disabled — no internet access
- cron: Disabled — no scheduled tasks
- network_fetch: Disabled — no egress permitted
- mcp_install: Disabled — no runtime MCP modifications
