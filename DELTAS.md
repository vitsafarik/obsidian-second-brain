# DELTAS - this fork vs upstream obsidian-second-brain

Branch: `cs-adaptace`. Purpose: adapt the upstream skill to Vit Safarik's
Czech-language vault and wire the "living vault" automation to his always-on
mac mini + Claude Code. Keep this file current so future upstream merges do
not silently clobber the customizations below.

Upstream remote: `upstream` = eugeniughelbur/obsidian-second-brain; `origin` =
vitsafarik/obsidian-second-brain (own fork).

## 0. Re-apply history

Each upstream release is absorbed by re-applying the Czech deltas onto a fresh
`upstream/main` (never a rebase of old commits). The previous branch state is
kept as a fallback tag before each re-apply.

- **2026-07-31: re-applied onto 0.14 "The Harvest"** (93 commits ahead of our
  0.12 base, absorbing 0.13 "The Open Standard" and 0.14). Fallback tag:
  `cs-adaptace-pre-0.14`. Verified after re-apply: triggers_cs 46/46 (the two new
  upstream commands, `/obsidian-brainstorm` and `/obsidian-reindex`, got freshly
  authored Czech phrases), `uv run pytest` 559/559, `bash scripts/build.sh` all 7
  platforms (0.14 added the agent-skills build) with the Czech section present
  in the dispatchers, `uvx ruff check`
  clean (upstream cleared the 17-error debt), vault_health on the real vault
  393 notes / 38 issues under 0.14's checks (wanted 23, template leftovers 5 -
  the Eta-syntax false positives the nightly audit already flagged, orphans 5,
  missing frontmatter 4, duplicates 1). The 0.12 "26 issues" figure is obsolete.
  Three deltas had to be re-expressed rather than re-applied, because 0.13/0.14
  refactored what they patched - see sections 4 and 5.
- **2026-07-16: re-applied onto 0.12 "The Stress Test"** (67 commits ahead of
  our 0.11 base, including unreleased OKM freshness work, note-safety fixes,
  and the plugin-marketplace distribution). Fallback tag: `cs-adaptace-pre-0.12`.
  Verified after re-apply: triggers_cs 44/44, `uv run pytest` 164/164,
  `bash scripts/build.sh` all 6 platforms, `config/install.sh` reconcile clean,
  vault_health on the real vault reports 26 issues under the far stricter 0.12
  checks (root/docs by-design noise + real `wanted_note` findings; the old
  "63 -> 9" baseline was measured by the 0.11 checker and is obsolete).
- 2026-06-29: re-applied onto 0.11 "The Retriever" (52 commits). Fallback tag:
  `cs-adaptace-pre-0.11`.

## 1. Czech localization (commands)

- Every command in `commands/*.md` carries a `triggers_cs:` array (Czech trigger
  phrases) next to `triggers_en:` and upstream's `triggers_es`/`triggers_pt`/
  `triggers_zh`. All 46/46 commands localized (0.14 added `/obsidian-brainstorm`
  and `/obsidian-reindex`); `adapters/lib.sh` `_lang_label` knows `cs`, and the
  built dispatchers carry a `### Cestina (cs)` section.
- Trigger phrases are ASCII (no diacritics), matching the existing convention
  (`uloz`, `nacti`), so they survive the no-substitution-unicode validator.
- **0.12 note:** the Czech lines were re-inserted into the UPSTREAM command
  bodies (which 0.12 swept heavily: folder-map resolution #117, logic sweep
  #120, SKILL_ROOT anchoring). Never carry over old cs-adaptace command bodies
  wholesale - `tests/test_install_portability.py` fails on the old maintainer
  path and missing `--directory "SKILL_ROOT"`, and
  `tests/test_folder_map_compliance.py` fails on pre-sweep hardcoded folders.
- Command bodies/descriptions stay English (discovery is Czech, instructions are
  not translated). Note: `create-command` does not yet emit `triggers_cs` for
  newly authored commands - candidate follow-up.

## 2. Validator (hooks/validate-ai-first.sh)

- Accepts the Czech preamble `## Pro budoucí Claude` / `## Pro budouci Claude`
  alongside the English `## For future Claude` (prefix match on `Pro budouc`).
- Banned-character set drops em/en-dash and curly double quotes (correct Czech
  typography), keeps single curly quotes, math symbols, ellipsis, nbsp.
  Upstream's `tests/test_no_banned_chars_in_instructions.py` is unaffected: it
  carries its own char list and scans only commands/, references/, SKILL.md.
- **Check 6 (added in this fork):** notes of `type: project|person|wiki` get a
  non-blocking warning if they lack a `timeline:` field (bi-temporal rule #4).
- Skip list += `sablony/`, `log/` (upstream's new `*/Logs/*` is case-sensitive
  and misses the Czech lowercase tree), `nastenky/` (Czech kanban boards - the
  same phantom-column exception upstream added for `boards/`), plus basename
  skips for `CLAUDE.md`/`README.md` (upstream now skips `_CLAUDE.md` by path).

## 3. Autonomous agents (hooks/obsidian-bg-agent.sh)

- The PostCompact background agent prompt is localized: it writes ONLY to Czech
  folders (`lide/`, `projekty/`, `denik/`, `napady/`, `nastenky/`, `log/prace/`)
  and carries a hard "NEVER create English folders" guard, because it runs
  unattended with `--dangerously-skip-permissions`. Czech preamble enforced.
  Upstream 0.12's genericized folder-map wording in prompt items 4-5 was
  dropped as superseded by this stricter explicit map.
- Armed via `~/.claude/settings.json` (local, not in any repo):
  `OBSIDIAN_BG_AGENT_ENABLED=1` + a `PostCompact` hook entry.
- **Hardening (2026-06-29, carried forward):** stable `claude` binary
  resolution (`$HOME/.local/bin/claude`, override via `OBSIDIAN_CLAUDE_BIN`),
  detached `--bg-worker` re-invocation via `nohup` (survives async-hook
  cleanup), portable mkdir mutex `/tmp/secondbrain-vault.write.lock` shared
  with the living-loop vault-sync (overridable via `OBSIDIAN_BG_LOCK` for
  tests), `--ff-only` pull when the tree is clean, START/END logging.
- **0.14 merge (re-expressed, not re-applied):** 0.13/0.14 rewrote this hook -
  it gained a JSONL run log under `$VAULT/.claude-runs/`, a 120s burst-dedup lock
  at `$VAULT/.claude-lock`, the prompt fed via stdin from a temp file (Windows
  argv limit), `--strict-mcp-config` and `--allowedTools "Read,Write,Edit,Glob,Grep"`.
  All of that is kept verbatim. Our hardening now sits on top as a `--bg-worker`
  branch placed AFTER upstream's helper definitions (so the worker can call
  `log_run` and correlate via `BG_RUN_ID`): it takes the shared mkdir mutex
  `/tmp/secondbrain-vault.write.lock`, does the clean-tree `--ff-only` pull, runs
  `$BG_CLAUDE` with upstream's own flags, and records `completed` (plus a new
  `write_lock_timeout` / `no_claude_binary` status). Upstream's burst lock only
  drops duplicate hook fires and deliberately does not serialize the run, which
  is exactly what the vault-sync publisher needs, so both locks coexist.
- **0.12 merge:** upstream's new `hooks/hooks.json` (plugin auto-load:
  SessionStart + PostCompact) adopted verbatim - inert for the symlink-skill
  install; live wiring stays in `~/.claude/settings.json`. If the engine is
  ever ALSO installed as a plugin, remove the settings.json entries or
  PostCompact/SessionStart fire twice. Upstream's `tests/test_bg_agent_hook.py`
  adopted with one patch: `_run_hook` pins `OBSIDIAN_CLAUDE_BIN` to the stub
  (our resolution would otherwise find the real `~/.local/bin/claude` and
  launch a real unattended agent per test run) and sets `OBSIDIAN_BG_LOCK` to
  a per-test path.

## 4. MCP connector (integrations/obsidian-mcp-server/)

- Based on the upstream 0.12 server (search-quality overhaul: type-aware
  weighting, freshness re-ranking, bge-m3 default embedding, atomic rewrites).
- Localized for the Czech vault: `vault_ops.py` writes to `vstupy/` (controlled
  inbox), not `Inbox/`, with the `## Pro budoucí Claude` preamble;
  `validate_note` accepts the Czech preamble; `_SKIP_DIRS` excludes `sablony/`
  (the canonical skip set for the whole search stack, so sablony/ is also out of
  the semantic index and eval universe - intended).
- **0.14 note:** the exclude policy moved to `scripts/vault_scan.py`
  (`BASE_EXCLUDE_DIRS`), and `tests/test_exclude_policy.py` now pins
  `vault_ops._SKIP_DIRS` to that base. `sablony` is therefore declared in BOTH
  places (the base, next to upstream's `templates`, and the MCP server's
  standalone literal) - dropping either one fails that test. 0.14 also added
  `_PROTECTED_WRITE_DIRS = _SKIP_DIRS | {"raw"}`, which inherits `sablony`
  automatically: no write tool can touch the Czech templates.
- The `get_skill` path-traversal guard is NO LONGER a delta: upstream merged it
  as #84 (a156522) with identical code and added its own regression test. The
  old local branch `fix/get-skill-path-traversal` is redundant.
- 4 smoke-test localizations in `tests/test_smoke.py` (vstupy/ paths + Czech
  preamble assertions); upstream's English-preamble FIXTURES elsewhere stay
  untouched (validate_note dual-accepts, vault_health is not localized).
- **Wired into Claude Code** (user scope, `~/.claude.json` mcpServers, stdio
  `uv run --with 'mcp<2' python .../obsidian-mcp-server/server.py`) since ~2026-07.
  Not wired into any other client. The `mcp<2` pin is a **temporary local delta**
  (2026-07-31): `mcp` 2.0.0 dropped `mcp.server.fastmcp`, so the unpinned launch
  crashed the server on both machines. Sent upstream as PR #185 (issue #183) -
  drop this delta once it merges and lands here in the next re-apply.

## 5. Health/stats folder-spec localization (scripts/)

Upstream recognizes English folders (Daily, Dev Logs, Boards, Templates). The
Czech vault uses denik/, log/, nastenky/, sablony/, so the folder sets were
localized for parity:

**0.14 re-expression:** upstream centralized every tool's exclude set into
`scripts/vault_scan.BASE_EXCLUDE_DIRS`. The Czech additions are no longer pasted
into each tool's literal; `sablony` goes into the shared base (so health, stats,
link_graph, export_okf and freshness_lint all inherit it at once) and only the
genuinely per-tool ones stay local:

- `vault_scan.py` `BASE_EXCLUDE_DIRS` += `sablony` (Czech templates; upstream's
  case-insensitive `templates` match does not catch the Czech name).
- `vault_stats.py` `EXCLUDED_FOLDERS` = base + upstream's `STATS_ONLY_EXCLUDES`
  + `log` (stats-only: the append-only op-log tree is machine output and
  inflates note counts). `sablony` arrives through the base. CLI is canonically
  `--path` (upstream #105; `--vault` kept as alias).
- `vault_health.py`: `FILE_INDEX_EXCLUDE_DIRS` subtracts `sablony` alongside
  `templates` so sablony/ files stay resolvable as wikilink targets while
  excluded from health checks; `DATED_SERIES_FOLDERS` += `denik`, `log`; orphan
  `skip_folders` += `denik`, `log`, `nastenky`; and `check_missing_frontmatter`
  skips the `log/` TOP folder via `skip_top` exact-match (append-only, AI-first
  exempt per the vault _CLAUDE.md). **`log/` stays loaded** so the frontmattered
  devlogs in `log/prace/` still resolve as `[[wikilink]]` targets - do NOT add
  `log` to `EXCLUDE_DIRS`.
- Real-vault baseline on 0.14 checks (2026-07-31): 393 notes / 38 issues -
  wanted 23, template leftovers 5, orphans 5, missing frontmatter 4,
  duplicates 1. The template-leftover findings are known FALSE POSITIVES:
  `TEMPLATE_RE = re.compile(r"<%.*?%>")` matches Eta template syntax quoted
  verbatim in the generator devlogs (diagnosed by the nightly audit 2026-07-30).
  The 0.12-era "26 issues" and 0.11-era "63 -> 9" figures are obsolete.

## 6. Living-loop automation (NOT in this repo)

**Hermes cron retired for the second brain (2026-07-16).** The living loop now
runs via launchd on the always-on mac mini, defined in the `config/` repo
(`vitsafarik/claude-config`):

- `config/scripts/living-loop/` - `vault-sync.sh` (deterministic allowlist
  commit+push publisher, 4x daily), `ranni-agent.sh` (08:03 daily note +
  Telegram brief), `vecerni-audit.sh` (22:35 vault_health + stale scan ->
  audit note in `log/agenti/audity/`), `synthesis.sh` (Sun 22:00 proposals ->
  `log/agenti/synthesis/`), all via headless `claude -p`.
- `config/launchd/cz.safarikdev.secondbrain.*.plist` + `install-loop.sh`
  (mini only).
- Serialization: the same mkdir mutex `/tmp/secondbrain-vault.write.lock`
  shared with the PostCompact bg-agent (section 3).

See `config/RUNBOOK-second-brain.md` for the operational map.

## 7. Installer command reconcile (install.sh + update.sh)

Fixed 2026-06-29, still a delta in 0.12 (upstream never absorbed it; update.sh
is byte-identical to 0.11 upstream). Both installers symlink `commands/*.md`
into `~/.claude/commands/` but upstream only ever ADDS links (skip-if-exists)
and never removes them, so a version bump that deletes/adds commands leaves
dangling + missing links `git pull` cannot fix.

- `update.sh` rewritten to fully reconcile: prune stale links, link new
  commands, refresh copied ones (Windows).
- `install.sh` gained the same prune step after its link loop; upstream 0.12's
  new `setup_settings_hook.py` registration block coexists after it untouched.

Prune is scoped by `readlink` target prefix (`$SKILL_DIR/commands/*`): only this
skill's own broken links are removed, never other skills'/plugins' commands.
Upstream candidate (not Czech-specific) - a PR back upstream would need to sit
on 0.12's reworked install flow.

**Machine note (config/install.sh symlink method, NOT plugin marketplace):**
0.12's `hooks/hooks.json` auto-load applies only to plugin installs, so the
manual settings.json wiring stays necessary and sufficient. If
`engine/install.sh` is ever run here, `setup_settings_hook.py` rewrites the
SessionStart hook command to the canonical `~/.claude/skills/...` path -
functionally identical (it symlinks to engine/) but drifts from
`config/settings.template.json`. 0.12's `load_vault_context.py` now also
injects a "Skill root" block into EVERY session, not just vault sessions.

## 8. Misc

- **Czech retrieval-freshness signals** (added 2026-07-16): upstream 0.12's
  status fade and recency band are hardcoded English, so they never fired on a
  Czech vault. `vault_ops.py` `_STALE_STATUSES` += Czech project statuses
  (`pozastaveny`, `hotovy/hotovo`, `zruseny/zruseno`, `archivovany`,
  `odlozeny`, `uzavreny`, `neaktivni`) and `_CURRENT_INTENT` += Czech
  present-intent markers in both diacritic and bare-ASCII spellings (ASCII
  `stale` deliberately excluded - collides with the English word).
  `tests/test_multilingual_model.py::test_default_model_is_multilingual`
  patched to clear the machine's `OBSIDIAN_EMBED_MODEL` override before
  asserting the shipped default.
- `hooks/load_vault_context.py`: key-files block points to `log/` (one file
  per day) instead of upstream's `log.md`.
- `uv.lock`: no delta since 0.12 (upstream lockfile now carries the dev/pytest
  group our fork used to add).
- `uvx ruff check .` is clean on 0.14 - the 17-error upstream debt noted at 0.12
  is gone, so lint failures from here on are ours.

## Not adopted (deliberately)

- Plugin-marketplace install path: our machines install via `config/install.sh`
  symlinks; `.claude-plugin/` + `hooks/hooks.json` ship unchanged but unused.
- `hermes-memory-provider` branch: v0 scaffold, untested live. Hermes itself is
  retired from the loop (2026-07-16), so this stays parked.
- 0.11's optional local-Ollama semantic search layer: keep default-off
  (`OBSIDIAN_SEARCH_SEMANTIC` kill-switch); 0.12's bge-m3 default applies only
  when semantic search is enabled. Per-runtime Ollama availability is undecided.
