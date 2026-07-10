#!/usr/bin/env bash
# `codex` with good defaults for the aisolation container.
#
# The interactive session runs without approval prompts or sandboxing — the
# container itself is the isolation boundary (see README, "not a security
# barrier"). Management sub-commands (login, exec, mcp, ...) are passed through
# untouched; they pick up the same non-interactive defaults from
# ~/.codex/config.toml, and would reject the bypass flag anyway.
set -euo pipefail

# codex sub-commands + aliases (anything else is a positional prompt to the TUI)
subcommands=" exec e review login logout mcp plugin mcp-server app-server remote-control completion update doctor sandbox debug apply a resume archive delete unarchive fork cloud exec-server features help "

first="${1:-}"
if [[ -n "$first" && "$first" != -* && "$subcommands" == *" $first "* ]]; then
    exec /usr/bin/codex2 "$@"
fi
exec /usr/bin/codex2 --dangerously-bypass-approvals-and-sandbox "$@"
