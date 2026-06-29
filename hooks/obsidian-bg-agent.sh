#!/usr/bin/env bash
# obsidian-bg-agent.sh - PostCompact vault propagation hook
#
# Fires after Claude compacts the conversation context. Reads the session
# summary from stdin (JSON), then runs a headless Claude agent to propagate
# everything worth preserving to the vault.
#
# TRUST CAVEAT: this agent writes to the vault UNATTENDED using
# --dangerously-skip-permissions. For that reason it is OPT-IN and ships INERT.
# It requires BOTH of the following before it does anything:
#   - OBSIDIAN_VAULT_PATH set (where to write), AND
#   - OBSIDIAN_BG_AGENT_ENABLED=1 (a second, deliberate enable flag)
# setup.sh sets the first but never the second, so the agent stays inert after a
# normal install. See hooks/postcompact.hook.example.json for the opt-in steps.
#
# Setup:
#   1. Set OBSIDIAN_VAULT_PATH in the env section of ~/.claude/settings.json
#   2. Set OBSIDIAN_BG_AGENT_ENABLED=1 in the same env section to enable
#   3. Register this script as a PostCompact hook (see postcompact.hook.example.json)
#   4. Make executable: chmod +x hooks/obsidian-bg-agent.sh
# To disable again: clear OBSIDIAN_BG_AGENT_ENABLED (the gate below makes that enough).
#
# Optional env:
#   OBSIDIAN_CLAUDE_BIN  absolute path to a stable `claude` binary (auto-detected
#                        otherwise). The interactive `claude` on PATH is often a
#                        temporary per-session shim that does not exist headless.
#
# Logs: /tmp/obsidian-bg-agent.log

LOG=/tmp/obsidian-bg-agent.log
# A machine-local mkdir mutex (portable: macOS has no flock). Shared with the
# Hermes vault-sync so an unattended write never races a commit/push. Lives
# outside the repo so it never shows up in `git status`.
LOCK=/tmp/secondbrain-vault.write.lock

# ---------------------------------------------------------------------------
# Detached worker: re-invoked via `nohup "$0" --bg-worker` so the async-hook
# cleanup cannot kill the multi-minute agent run. Reads BG_* from the env.
# ---------------------------------------------------------------------------
if [[ "${1:-}" == "--bg-worker" ]]; then
  tries=0
  while ! mkdir "$LOCK" 2>/dev/null; do
    # stale-lock breaker: reclaim if the recorded holder is gone
    if [[ -f "$LOCK/pid" ]] && ! kill -0 "$(cat "$LOCK/pid" 2>/dev/null)" 2>/dev/null; then
      rm -rf "$LOCK" 2>/dev/null; continue
    fi
    tries=$((tries + 1))
    if [[ "$tries" -gt 600 ]]; then
      printf '%s bg-agent could not acquire lock in 600s, skipping\n' "$(date '+%F %T')" >> "$LOG"
      exit 0
    fi
    sleep 1
  done
  echo $$ > "$LOCK/pid"
  trap 'rm -rf "$LOCK"' EXIT

  cd "$BG_VAULT" || exit 0
  # current with the remote only when the tree is clean (during an active session
  # it is usually dirty, so this is a no-op and never clobbers in-progress work)
  if git diff --quiet 2>/dev/null && git diff --cached --quiet 2>/dev/null; then
    git pull --ff-only --quiet 2>/dev/null || true
  fi
  printf '%s START bg-agent write (claude=%s)\n' "$(date '+%F %T')" "$BG_CLAUDE" >> "$LOG"
  "$BG_CLAUDE" --dangerously-skip-permissions -p "$BG_PROMPT" >> "$LOG" 2>&1
  printf '%s END bg-agent write rc=%s\n' "$(date '+%F %T')" "$?" >> "$LOG"
  exit 0
fi

# ---------------------------------------------------------------------------
# Hook entry point
# ---------------------------------------------------------------------------
VAULT="${OBSIDIAN_VAULT_PATH:-}"
[[ -z "$VAULT" ]] && exit 0

# Opt-in gate: no-op unless the user deliberately enabled the agent. This is the
# second of the two flags; without it the hook does nothing even when registered.
[[ "${OBSIDIAN_BG_AGENT_ENABLED:-0}" != "1" ]] && exit 0

# PostCompact stdin includes `transcript_path`; the compaction summary itself
# is written into the transcript JSONL as entries with `isCompactSummary: true`.
# We read the most recent one here.
INPUT=$(cat)
TRANSCRIPT=$(printf '%s' "$INPUT" | jq -r '.transcript_path // ""' 2>/dev/null || true)
[[ -z "$TRANSCRIPT" || ! -f "$TRANSCRIPT" ]] && exit 0

# Stream the JSONL (transcripts can be 100MB+). base64-encode each match so the
# multi-line content stays on one line, then decode the most recent one.
SUMMARY=$(jq -rc 'select(.isCompactSummary == true) | .message.content // "" | @base64' "$TRANSCRIPT" 2>/dev/null | tail -n 1 | base64 -d 2>/dev/null || true)
[[ -z "$SUMMARY" ]] && exit 0

TODAY=$(date +%Y-%m-%d)

# Build prompt in a temp file to handle special characters in the summary safely
PROMPT_FILE=$(mktemp /tmp/obsidian-bg-XXXXXX.txt)

cat > "$PROMPT_FILE" << HEADER
You are an autonomous Obsidian vault agent. The Claude session was just compacted.
Propagate everything worth preserving from the summary to the vault. Run silently.

VAULT: $VAULT
TODAY: $TODAY

SESSION SUMMARY:
HEADER

printf '%s\n\n' "$SUMMARY" >> "$PROMPT_FILE"

cat >> "$PROMPT_FILE" << 'INSTRUCTIONS'
INSTRUCTIONS:
1. Read _CLAUDE.md at the vault root first - follow its rules exactly. Where silent, use defaults.
   This vault is CZECH. Use ONLY the Czech folder names below. NEVER create English
   folders (no People/, Projects/, Daily/, Ideas/, Boards/, Dev Logs/). Folder map:
   People -> lide/, Projects -> projekty/, Daily -> denik/ (YYYY-MM-DD.md),
   Ideas -> napady/, Boards -> nastenky/ (Obsidian Kanban), Dev Logs -> log/prace/,
   operational log -> log/YYYY-MM-DD.md (append-only). Write note bodies in Czech,
   including the "## Pro budouci Claude" preamble (not "## For future Claude").
2. Identify all vault-worthy items in the summary:
   - Decisions made or confirmed
   - Tasks created, assigned, or completed
   - People mentioned (new interactions, context added)
   - Projects worked on or updated
   - Dev work done (code written, bugs fixed, features shipped)
   - Ideas, learnings, or insights
   - Shoutouts or mentions worth logging
3. Before creating any note, search for an existing one. Never duplicate.
4. Update or create notes as appropriate:
   - People: update lide/jmeno.md interaction log; create a stub if missing
   - Projects: update status, recent activity, key decisions sections in projekty/
   - Dev work: create or update log/prace/YYYY-MM-DD-projekt.md; link from project note
   - Tasks: add to the right column of the existing board nastenky/ukoly.md (use TODAY date)
   - Ideas: save to napady/
   - Decisions: append to the relevant projekty/ note's decisions section
5. Update today's daily note (denik/[TODAY].md using the TODAY value above):
   - Create it from the daily template in sablony/ if it does not exist
   - Link everything you touched - people, projects, dev logs, decisions
6. Propagate everywhere:
   - Nothing is saved in isolation
   - Every write ripples to the daily note, boards, and linked notes per the write rules

CONSTRAINTS:
- Use filesystem tools only (Read, Write, Edit, Glob, Grep) - MCP is not available in this subprocess.
- Run completely silently. No output to the user. No questions.
- If the summary contains nothing vault-worthy, exit without making any changes.
- Match the vault's existing writing style, frontmatter schemas, and naming conventions exactly.
- Do not archive, delete, or merge anything - only add or update.
INSTRUCTIONS

PROMPT=$(cat "$PROMPT_FILE")
rm -f "$PROMPT_FILE"

# Resolve a STABLE claude binary (the interactive PATH `claude` is often a
# temporary session shim that is absent in a headless hook).
CLAUDE_BIN="${OBSIDIAN_CLAUDE_BIN:-}"
if [[ -z "$CLAUDE_BIN" || ! -x "$CLAUDE_BIN" ]]; then
  for c in "$HOME/.local/bin/claude" "$HOME/.claude/local/claude" /opt/homebrew/bin/claude /usr/local/bin/claude; do
    [[ -x "$c" ]] && { CLAUDE_BIN="$c"; break; }
  done
fi
if [[ -z "$CLAUDE_BIN" || ! -x "$CLAUDE_BIN" ]]; then
  printf '%s no stable claude binary found (set OBSIDIAN_CLAUDE_BIN)\n' "$(date '+%F %T')" >> "$LOG"
  exit 0
fi

# Hand off to the detached worker (survives async-hook cleanup; takes the mutex).
export BG_PROMPT="$PROMPT" BG_VAULT="$VAULT" BG_CLAUDE="$CLAUDE_BIN"
nohup "$0" --bg-worker >/dev/null 2>&1 &
disown 2>/dev/null || true

exit 0
