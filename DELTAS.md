# DELTAS - this fork vs upstream obsidian-second-brain

Branch: `cs-adaptace`. Purpose: adapt the upstream skill to Vit Safarik's
Czech-language vault and wire the "living vault" automation to his always-on
mac mini (Hermes) + Claude Code. Keep this file current so future upstream
merges do not silently clobber the customizations below.

Upstream remote: `origin` = vitsafarik/obsidian-second-brain (own fork of
eugeniughelbur/obsidian-second-brain). `cs-adaptace` = `main` + the deltas here.

## 1. Czech localization (commands)

- Every command in `commands/*.md` carries a `triggers_cs:` array (Czech trigger
  phrases) next to `triggers_en:`. All 44/44 commands localized.
- Trigger phrases are ASCII (no diacritics), matching the existing convention
  (`uloz`, `nacti`), so they survive the no-substitution-unicode validator.
- Command bodies/descriptions stay English (discovery is Czech, instructions are
  not translated). If full body translation is ever done, note it here.

## 2. Validator (hooks/validate-ai-first.sh)

- Accepts the Czech preamble `## Pro budouci Claude` / `## Pro budouci Claude`
  alongside the English `## For future Claude`.
- Banned-character set drops em/en-dash and curly double quotes (correct Czech
  typography), keeps single curly quotes, math symbols, ellipsis, nbsp.
- **Check 6 (added in this fork):** notes of `type: project|person|wiki` get a
  non-blocking warning if they lack a `timeline:` field (bi-temporal rule #4).

## 3. Autonomous agents (hooks/obsidian-bg-agent.sh)

- The PostCompact background agent prompt is localized: it writes ONLY to Czech
  folders (`lide/`, `projekty/`, `denik/`, `napady/`, `nastenky/`, `log/prace/`)
  and carries a hard "NEVER create English folders" guard, because it runs
  unattended with `--dangerously-skip-permissions`. Czech preamble enforced.
- Armed via `~/.claude/settings.json` (local, not in any repo):
  `OBSIDIAN_BG_AGENT_ENABLED=1` + a `PostCompact` hook entry.

## 4. MCP connector (integrations/obsidian-mcp-server/)

- Brought in from the `obsidian-mcp-server` branch (the `integrations/` dir only,
  not a full branch merge, to avoid dragging pre-cs-adaptace versions of shared
  files).
- Localized for the Czech vault: `vault_ops.py` writes to `vstupy/` (controlled
  inbox), not an English `Inbox/`, and uses the `## Pro budouci Claude` preamble.
- Verified working end-to-end against the real vault via `live_test.py`
  (read-only: handshake + search + read). Not yet wired into any client; wiring
  is a per-client config entry (see integrations/obsidian-mcp-server/README.md).

## 5. Scheduled / living-vault automation (NOT in this repo)

Runs on the always-on mac mini (`Vit--Mac-mini.local`), via Hermes cron
(`~/.hermes/cron/jobs.json`, managed with `hermes cron ...`):

- `secondbrain-ranni-agent-telegram` - daily 08:03, creates the daily note,
  delivers a Telegram brief.
- `hermes-vecerni-audit-pameti` - daily 22:35, vault health + stale audit
  (runs `secondbrain_stale_scan.py`), report to `log/hermes/vystupy/audity/`.
- `secondbrain-synthesis-tydenni-telegram` - Sunday 22:00, report-only synthesis
  proposals to `log/hermes/vystupy/synthesis/`. Added 2026-06-29.

Delivery uses the verified target `telegram:Detoxa`, not bare `telegram`
(runtime-reload pitfall documented in the Hermes morning-agent reference).

## Not adopted (deliberately)

- `hermes-memory-provider` branch: v0 scaffold, untested live; Hermes already
  uses the vault via its `safarikdev-secondbrain` skill. Left unmerged.
- launchd-based maintenance agents: superseded by Hermes cron on the mini.
