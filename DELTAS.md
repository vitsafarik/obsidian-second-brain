# DELTAS - this fork vs upstream obsidian-second-brain

Branch: `cs-adaptace-0.11`. Purpose: adapt the upstream skill to Vit Safarik's
Czech-language vault and wire the "living vault" automation to his always-on
mac mini (Hermes) + Claude Code. Keep this file current so future upstream
merges do not silently clobber the customizations below.

Upstream remote: `upstream` = eugeniughelbur/obsidian-second-brain; `origin` =
vitsafarik/obsidian-second-brain (own fork).

## 0. Re-apply onto upstream 0.11 "The Retriever" (2026-06-29)

The original `cs-adaptace` branched from an old base (1b335b6) and fell 52
commits behind upstream, missing release 0.11: the MCP server with guarded
curator-write tools, the native Hermes adapter + Pi platform, and hybrid/
semantic search. Rather than rebase 4 commits over commands upstream had since
deleted/merged, the Czech deltas were **re-applied onto a fresh `upstream/main`**
(this branch). The old `cs-adaptace` is kept as a fallback. Verified after
re-apply: triggers_cs 44/44, `uv run pytest` 27/27, `bash scripts/build.sh` all
6 platforms, vault_health on the real vault down to 9 (by-design) issues.

## 1. Czech localization (commands)

- Every command in `commands/*.md` carries a `triggers_cs:` array (Czech trigger
  phrases) next to `triggers_en:`. All 44/44 commands localized.
- Trigger phrases are ASCII (no diacritics), matching the existing convention
  (`uloz`, `nacti`), so they survive the no-substitution-unicode validator.
- 0.11 consolidation handled: the 4 commands upstream deleted (obsidian-adr,
  -agenda, -meeting, -schedule) had their Czech triggers **folded into the
  surviving targets** - adr -> `obsidian-decide`; agenda+meeting+schedule ->
  `obsidian-calendar`. The 4 commands upstream added (obsidian-board-hygiene,
  -catchup, -distill, -retrieval-eval) got freshly authored `triggers_cs`.
- Command bodies/descriptions stay English (discovery is Czech, instructions are
  not translated). Note: `create-command` does not yet emit `triggers_cs` for
  newly authored commands - candidate follow-up.

## 2. Validator (hooks/validate-ai-first.sh)

- Accepts the Czech preamble `## Pro budoucí Claude` / `## Pro budouci Claude`
  alongside the English `## For future Claude` (prefix match on `Pro budouc`).
- Banned-character set drops em/en-dash and curly double quotes (correct Czech
  typography), keeps single curly quotes, math symbols, ellipsis, nbsp.
- **Check 6 (added in this fork):** notes of `type: project|person|wiki` get a
  non-blocking warning if they lack a `timeline:` field (bi-temporal rule #4).
- Upstream did not touch this file, so it carries over unchanged.

## 3. Autonomous agents (hooks/obsidian-bg-agent.sh)

- The PostCompact background agent prompt is localized: it writes ONLY to Czech
  folders (`lide/`, `projekty/`, `denik/`, `napady/`, `nastenky/`, `log/prace/`)
  and carries a hard "NEVER create English folders" guard, because it runs
  unattended with `--dangerously-skip-permissions`. Czech preamble enforced.
- Armed via `~/.claude/settings.json` (local, not in any repo):
  `OBSIDIAN_BG_AGENT_ENABLED=1` + a `PostCompact` hook entry.
- **Hardened 2026-06-29** (the hook had never actually fired end-to-end):
  - Resolves a STABLE `claude` binary (`$HOME/.local/bin/claude`, override via
    `OBSIDIAN_CLAUDE_BIN`) instead of the bare PATH `claude`, which is often a
    temporary per-session shim absent in a headless hook - the likely reason it
    silently no-opped.
  - Re-invokes itself as a detached `--bg-worker` via `nohup` so the async-hook
    cleanup cannot kill the multi-minute agent run.
  - Takes a portable mkdir mutex `/tmp/secondbrain-vault.write.lock` (macOS has no
    flock) shared with the Hermes vault-sync, so an unattended write never races a
    commit/push. Pulls `--ff-only` first when the tree is clean. Logs START/END.
  - Verified end-to-end: hook->worker handoff, detach survival, lock contention,
    and the real `claude` binary running headless (stub + real smoke test).

## 4. MCP connector (integrations/obsidian-mcp-server/)

- Now based on the **upstream 0.11 server** (9 tools incl. the guarded curator
  set: `obsidian_update_note`, `obsidian_validate_note`, `obsidian_backlinks`,
  `obsidian_vault_health`) - a strict superset of the old fork snapshot. The
  `mcp` dependency now ships in upstream's lockfile and is covered by smoke tests.
- Localized for the Czech vault: `vault_ops.py` writes to `vstupy/` (controlled
  inbox), not `Inbox/`, with the `## Pro budoucí Claude` preamble; `validate_note`
  accepts the Czech preamble; `_SKIP_DIRS` excludes `sablony/`.
- **Security fix re-applied:** `get_skill(name)` has a path-traversal guard
  (flat-slug allowlist) - upstream's `get_skill` is still unguarded, so this is a
  real delta, not redundant. Worth a PR back upstream. (`read_note`/`validate`
  already carry upstream's own resolve()-based escape guard.)
- The upstream MCP smoke tests in `tests/test_smoke.py` were localized to assert
  the `vstupy/` path and Czech preamble (3 assertions).
- Not yet wired into any client; wiring is a per-client config entry (see
  integrations/obsidian-mcp-server/README.md, which still says `Inbox/` - cosmetic
  follow-up).

## 5. Health/stats folder-spec localization (scripts/)

Upstream recognizes English folders (Daily, Dev Logs, Boards, Templates). The
Czech vault uses denik/, log/, nastenky/, sablony/, so the folder sets were
localized for parity:

- `vault_stats.py` `EXCLUDED_FOLDERS` += `sablony`, `log` (upstream did not touch
  this file).
- `vault_health.py`: `EXCLUDE_DIRS` += `sablony` (templates); `DATED_SERIES_FOLDERS`
  += `denik`, `log`; orphan `skip_folders` += `denik`, `log`, `nastenky`; and
  `check_missing_frontmatter` skips the `log/` top folder (append-only, AI-first
  exempt per the vault _CLAUDE.md). **`log/` stays loaded** so the frontmattered
  devlogs in `log/prace/` still resolve as `[[wikilink]]` targets - do NOT add
  `log` to `EXCLUDE_DIRS`. This cut real-vault noise from 63 to 9 (the 9 are root
  README/CLAUDE, docs/ imports, and the `[[_CLAUDE.md]]` .md-link quirk).
- Note: the 0.11 CLI is `vault_health.py --path <vault>` (was positional).

## 6. Scheduled / living-vault automation (NOT in this repo)

Runs on the always-on mac mini (`Vit--Mac-mini.local`), via Hermes cron
(`~/.hermes/cron/jobs.json`, managed with `hermes cron ...`):

- `secondbrain-ranni-agent-telegram` - daily 08:03, creates the daily note,
  delivers a Telegram brief. Pulls --ff-only before writing.
- `hermes-vecerni-audit-pameti` - daily 22:35, vault health + stale audit
  (runs `secondbrain_stale_scan.py`), report to `log/hermes/vystupy/audity/`.
- `secondbrain-synthesis-tydenni-telegram` - Sunday 22:00, report-only synthesis
  proposals to `log/hermes/vystupy/synthesis/`. Added 2026-06-29; first run
  2026-07-05 (unproven end-to-end until then).

Delivery uses the verified target `telegram:Detoxa`, not bare `telegram`
(runtime-reload pitfall). NOTE: `hermes-vecerni-audit-pameti` still uses bare
`telegram` - pending fix.

Multi-runtime sync (was a gap, FIXED 2026-06-29): a deterministic `--no-agent`
Hermes cron `secondbrain-git-sync` (07:30/12:30/18:30/23:30) runs
`~/.hermes/scripts/secondbrain_vault_sync.sh`, which commits+pushes ONLY the
Hermes-owned allowlist (`log denik index.md`, never `git add -A`), pulls
`--rebase --autostash` before push, never force-pushes, and skips its cycle if the
bg-agent holds the shared mkdir mutex. The morning agent's write-block guard was
loosened to treat `log/`, today's `denik/`, and `index.md` as expected Hermes
churn (it previously deadlocked on 2026-06-26 and -28). Evening + synthesis prompts
gained `git pull --ff-only`; evening delivery fixed to `telegram:Detoxa`.

## 7. Installer command reconcile (install.sh + update.sh)

Fixed 2026-06-29. Both installers symlink `commands/*.md` into
`~/.claude/commands/` but only ever ADDED links (skip-if-exists) and never
removed them. After the 0.11 re-apply deleted 4 commands (`obsidian-adr`,
`-agenda`, `-meeting`, `-schedule`, folded into `obsidian-decide` /
`obsidian-calendar`) and added 4 (`obsidian-board-hygiene`, `-catchup`,
`-distill`, `-retrieval-eval`), a synced machine was left with 4 dangling
symlinks (targets gone) + 4 missing new commands - `git pull` alone cannot fix
either, since it only refreshes contents behind existing links.

- `update.sh` rewritten to fully reconcile: prune stale links, link new
  commands, refresh copied ones (Windows).
- `install.sh` gained the same prune step after its link loop, so re-running it
  post-upgrade self-heals too.

Prune is scoped by `readlink` target prefix (`$SKILL_DIR/commands/*`): only this
skill's own broken links are removed, never other skills'/plugins' commands.
Upstream candidate (not Czech-specific) - offer it back if a clean PR is wanted.

## Not adopted (deliberately)

- `hermes-memory-provider` branch: v0 scaffold, untested live; Hermes already
  uses the vault via its `safarikdev-secondbrain` skill. Left unmerged.
- launchd-based maintenance agents: superseded by Hermes cron on the mini.
- 0.11's optional local-Ollama semantic search layer: keep default-off
  (`OBSIDIAN_SEARCH_SEMANTIC` kill-switch); the keyword-ranking fix is free and
  on by default. Per-runtime Ollama availability is undecided.
