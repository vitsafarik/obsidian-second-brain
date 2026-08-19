#!/usr/bin/env bash
# =============================================================================
# validate-ai-first.sh - Enforce the AI-first vault rule on Write/Edit
# =============================================================================
# Fires as a Claude Code PostToolUse hook after Write/Edit (terminal) or
# create_file (VS Code extension). Inspects the written file and warns if it
# does not follow the AI-first rule defined in references/ai-first-rules.md.
#
# This is the write-time enforcement primitive: the vault stays AI-first
# because every write is checked, not because future agent remembers all
# seven rules every time.
#
# Validation (warnings, non-blocking):
#   1. Frontmatter delimiters (--- ... ---) are well-formed
#   2. No tabs inside frontmatter (YAML requires spaces)
#   3. Required AI-first fields present: date, type, tags, ai-first: true
#   4. `## For future agent` preamble exists in the body
#   5. No banned non-ASCII substitution characters (em/en-dashes, curly
#      quotes, smart apostrophes, Unicode math). Reports codepoint +
#      suggested ASCII replacement. Explicit ban list; anything not in
#      the list passes.
#
# Scope:
#   - Only inspects files inside OBSIDIAN_VAULT_PATH (env var)
#   - Skips raw/, templates/, _export/, .obsidian/, boards/ (kanban exception:
#     an H2 preamble renders as a phantom column), vault-surface files
#     (_CLAUDE.md, Home.md, index.md, log.md, catchup.md, per-day Logs/ -
#     operating surfaces, not knowledge notes), and any path containing
#     /.git/ - those are system/template paths, not first-class notes
#   - Skips any file not ending in .md
#
# Exit codes:
#   0 = pass (silent), or warn via JSON on stdout (write is NOT reverted)
# =============================================================================

# Warn via Claude Code hook JSON (systemMessage + additionalContext). stderr
# is mirrored for logs; exit 0 so the host parses stdout.
emit_ai_first_warning() {
  local msg="$1"
  printf '%s\n' "$msg" >&2
  # cs-adaptace: severity split. Upstream escalated EVERY finding to
  # `decision: "block"`, which makes the PostToolUse host hand the warning back
  # as a correction task. For structural defects and secrets that is right. For
  # the banned-character check it is a trap on this vault: 537 of 632 notes
  # already carry a banned character (mostly U+2026 in imported prose), so any
  # edit to an old note would bounce and push the agent to rewrite lines it never
  # touched. So: typography alone advises, everything else still blocks.
  local severity="${2:-block}"
  if [[ "$severity" == "block" ]]; then
    jq -n --arg msg "$msg" '{
      systemMessage: $msg,
      decision: "block",
      reason: $msg,
      hookSpecificOutput: {
        hookEventName: "PostToolUse",
        additionalContext: $msg
      }
    }'
  else
    jq -n --arg msg "$msg" '{
      systemMessage: $msg,
      hookSpecificOutput: {
        hookEventName: "PostToolUse",
        additionalContext: $msg
      }
    }'
  fi
  exit 0
}

INPUT=$(cat)

# Write/Edit: tool_input.file_path. VS Code create_file: tool_input.filePath.
FILE=$(printf '%s' "$INPUT" | jq -r '
  .tool_input.file_path
  // .tool_input.filePath
  // .args.file_path
  // .args.filePath
  // ""
' 2>/dev/null)

# Bail silently on unparseable input or empty path
[[ -z "$FILE" ]] && exit 0
[[ "$FILE" == *.md ]] || exit 0
[[ -f "$FILE" ]] || exit 0

# Only validate inside the configured vault. Environment wins; fall back to the
# documented config .env, because a plugin-marketplace install configures the
# vault there and never exports the variable - so an env-only check made this
# hook a silent no-op for exactly the installs that need it most. Same root
# cause as #160 (MCP server) and #124 (research toolkit); this is the third code
# path, swept when the hook turned out never to have been wired at all.
VAULT="${OBSIDIAN_VAULT_PATH:-}"
if [[ -z "$VAULT" ]]; then
  ENV_FILE="${OBSIDIAN_ENV_FILE:-$HOME/.config/obsidian-second-brain/.env}"
  if [[ -r "$ENV_FILE" ]]; then
    VAULT=$(sed -n 's/^[[:space:]]*OBSIDIAN_VAULT_PATH[[:space:]]*=[[:space:]]*//p' "$ENV_FILE" \
      | tail -n 1 | sed -e 's/^"//' -e 's/"$//' -e "s/^'//" -e "s/'$//")
  fi
fi
[[ -z "$VAULT" ]] && exit 0
VAULT="${VAULT%/}"
case "$FILE" in
  "$VAULT"/*) ;;
  *) exit 0 ;;
esac

# Skip non-first-class paths
# cs-adaptace: += sablony/ (Czech templates), log/ (Czech append-only logs;
# upstream's */Logs/* is case-sensitive and misses it), nastenky/ (Czech kanban
# boards - same phantom-column exception as boards/).
case "$FILE" in
  */raw/*|*/templates/*|*/_export/*|*/.obsidian/*|*/.git/*|*/.trash/*|*/boards/*|*/Boards/*|*/Logs/*|*/sablony/*|*/log/*|*/nastenky/*|*/_CLAUDE.md|*/Home.md|*/index.md|*/log.md|*/catchup.md)
    exit 0 ;;
esac

BASENAME=$(basename "$FILE")

# Skip vault meta files that are manuals/pointers, not AI-first notes
# (vault_health.py exempts these the same way; upstream skips _CLAUDE.md by
# path above, so only CLAUDE.md/README.md remain cs-adaptace additions).
case "$BASENAME" in
  CLAUDE.md|README.md) exit 0 ;;
esac

WARNINGS=()

# ── Check 1: frontmatter delimiters ──────────────────────────────────────────
FIRST_LINE=$(head -1 "$FILE")
if [[ "$FIRST_LINE" != "---" ]]; then
  # Without frontmatter we can't run the other checks meaningfully - surface
  # this single warning and exit.
  emit_ai_first_warning "AI-first warning: $BASENAME has no frontmatter (expected --- on the first line). AI-first notes need date/type/tags/ai-first metadata."
fi

DELIMITER_COUNT=$(grep -c '^---$' "$FILE")
if [[ "$DELIMITER_COUNT" -lt 2 ]]; then
  WARNINGS+=("$BASENAME frontmatter is missing the closing --- delimiter.")
fi

# Extract frontmatter content (between the first and second --- lines)
FRONTMATTER=$(awk '/^---$/{c++; if (c==1) next; if (c==2) exit} c==1' "$FILE")

# ── Check 2: tabs in frontmatter ─────────────────────────────────────────────
TAB_CHAR=$'\t'
if printf '%s' "$FRONTMATTER" | grep -q "$TAB_CHAR"; then
  WARNINGS+=("$BASENAME frontmatter contains tab characters. YAML requires spaces only.")
fi

# ── Check 3: required AI-first frontmatter fields ────────────────────────────
has_field() {
  local key="$1"
  printf '%s\n' "$FRONTMATTER" | grep -qE "^${key}:"
}

has_field "date"  || WARNINGS+=("$BASENAME missing 'date:' in frontmatter.")
has_field "type"  || WARNINGS+=("$BASENAME missing 'type:' in frontmatter.")
has_field "tags"  || WARNINGS+=("$BASENAME missing 'tags:' in frontmatter.")

if ! printf '%s\n' "$FRONTMATTER" | grep -qE '^ai-first:[[:space:]]*true[[:space:]]*$'; then
  WARNINGS+=("$BASENAME missing 'ai-first: true' in frontmatter.")
fi

# ── Check 4: 'For future agent' preamble in body ─────────────────────────────
# Upstream renamed the vocabulary from 'For future Claude' to 'For future agent'
# and now anchors the whole heading. Czech vaults (cs-adaptace) use
# '## Pro budouci Claude' and the diacritic form '## Pro budoucí Claude', so the Czech
# arm stays a prefix match and rides alongside upstream's exact set.
BODY=$(awk '/^---$/{c++; if (c<2) next; next} c>=2' "$FILE")
if ! printf '%s\n' "$BODY" | grep -qE '^##[[:space:]]+(For future (agent|AI|Claude|Codex)[[:space:]]*$|Pro budouc)' ; then
  WARNINGS+=("$BASENAME missing '## For future agent' (or '## Pro budouci Claude') preamble (required by ai-first-rules.md rule #2).")
fi

# ── Check 6: bi-temporal timeline on stateful notes ──────────────────────────
# Project/person/wiki notes hold facts that change over time; the vault rule
# (_CLAUDE.md rule #4) wants a timeline: array so state changes leave an audit
# trail instead of being silently overwritten. Warn (non-blocking) when one of
# these note types lacks it.
NOTE_TYPE=$(printf '%s\n' "$FRONTMATTER" | sed -nE 's/^type:[[:space:]]*"?([a-zA-Z]+)"?.*/\1/p' | head -1)
case "$NOTE_TYPE" in
  project|person|wiki)
    if ! printf '%s\n' "$FRONTMATTER" | grep -qE '^timeline:'; then
      WARNINGS+=("$BASENAME (type: $NOTE_TYPE) missing 'timeline:' - bi-temporal facts keep an audit trail of state changes (see _CLAUDE.md rule #4).")
    fi ;;
esac

# ── Check 5: non-ASCII substitution characters ───────────────────────────────
if command -v python3 >/dev/null 2>&1; then
  NON_ASCII_HITS=$(python3 - "$FILE" <<'PYEOF'
import sys

# cs-adaptace: em/en-dash and curly double quotes removed from the banned set --
# they are correct Czech typography (pomlcka, uvozovky). Single curly quotes,
# Unicode math, ellipsis and nbsp stay banned.
BANNED = {
    '‘': ('U+2018 left single quote',   "'"),
    '’': ('U+2019 right single quote',  "'"),
    '≥': ('U+2265 >=',                  '>='),
    '≤': ('U+2264 <=',                  '<='),
    '≠': ('U+2260 !=',                  '!='),
    '…': ('U+2026 ellipsis',            '...'),
    ' ': ('U+00A0 non-breaking space',  ' '),
}

path = sys.argv[1]
seen = set()
try:
    with open(path, encoding='utf-8', errors='replace') as fh:
        for lineno, line in enumerate(fh, 1):
            for ch in line:
                if ch not in BANNED:
                    continue
                key = (lineno, ch)
                if key in seen:
                    continue
                seen.add(key)
                name, suggest = BANNED[ch]
                print(f"    line {lineno}: {name} -- try {suggest!r}")
except OSError:
    pass
PYEOF
  )
  if [[ -n "$NON_ASCII_HITS" ]]; then
    WARNINGS+=("$BASENAME contains banned non-ASCII substitution characters:")
    while IFS= read -r hit; do
      [[ -n "$hit" ]] && WARNINGS+=("$hit")
    done <<< "$NON_ASCII_HITS"
  fi
fi

# ── Check 6: secrets never belong in a vault note ────────────────────────────
# High-precision patterns only (a false positive here trains people to ignore
# the hook). Catches real key material, not the word "password" in prose.
if command -v python3 >/dev/null 2>&1; then
  SECRET_HITS=$(python3 - "$FILE" <<'PYEOF'
import re
import sys

PATTERNS = [
    (re.compile(r"-----BEGIN [A-Z ]*PRIVATE KEY-----"), "private key block"),
    (re.compile(r"\bAKIA[0-9A-Z]{16}\b"), "AWS access key id"),
    (re.compile(r"\bsk-[A-Za-z0-9_-]{24,}\b"), "sk- API key"),
    (re.compile(r"\bghp_[A-Za-z0-9]{36}\b"), "GitHub personal token"),
    (re.compile(r"\bgithub_pat_[A-Za-z0-9_]{22,}\b"), "GitHub fine-grained token"),
    (re.compile(r"\bxox[bpars]-[A-Za-z0-9-]{10,}\b"), "Slack token"),
    (re.compile(r"\bAIza[0-9A-Za-z_-]{35}\b"), "Google API key"),
    (re.compile(r"(?i)\b(?:password|passwd)\s*[:=]\s*['\"][^'\"\s]{8,}['\"]"), "quoted password assignment"),
]

path = sys.argv[1]
try:
    with open(path, encoding="utf-8", errors="replace") as fh:
        for lineno, line in enumerate(fh, 1):
            for pat, label in PATTERNS:
                if pat.search(line):
                    print(f"    line {lineno}: looks like a {label} - secrets never belong in vault notes; keep them in ~/.config/obsidian-second-brain/.env or a password manager and reference them by NAME only")
                    break
except OSError:
    pass
PYEOF
  )
  if [[ -n "$SECRET_HITS" ]]; then
    WARNINGS+=("$BASENAME appears to contain secret material:")
    while IFS= read -r hit; do
      [[ -n "$hit" ]] && WARNINGS+=("$hit")
    done <<< "$SECRET_HITS"
  fi
fi

# ── Emit warnings ────────────────────────────────────────────────────────────
if [[ ${#WARNINGS[@]} -gt 0 ]]; then
  MSG="AI-first warnings on ${BASENAME}:"$'\n'
  for w in "${WARNINGS[@]}"; do
    MSG+="  - ${w}"$'\n'
  done
  MSG+=$'\n'"See references/ai-first-rules.md for the full spec."
  # Count findings that are NOT the banned-character block (its header plus the
  # indented `line N:` details). Zero of them means typography is the only
  # complaint - advise instead of blocking (see emit_ai_first_warning).
  OTHER_FINDINGS=0
  IN_BANNED=0
  for w in "${WARNINGS[@]}"; do
    if [[ "$w" == *"contains banned non-ASCII substitution characters:" ]]; then
      IN_BANNED=1; continue
    fi
    if [[ $IN_BANNED -eq 1 && "$w" =~ ^[[:space:]]+line[[:space:]] ]]; then
      continue
    fi
    IN_BANNED=0
    OTHER_FINDINGS=$((OTHER_FINDINGS + 1))
  done
  if [[ $OTHER_FINDINGS -eq 0 ]]; then
    emit_ai_first_warning "$MSG" "warn"
  else
    emit_ai_first_warning "$MSG" "block"
  fi
fi

exit 0
