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

- **2026-08-26: merged `upstream/main`** (3 unreleased commits since the 2026-08-19
  merge; still no release after v0.14.0). Plain `git merge` again, so the other
  machine pulls `--ff-only`. Fallback tag: `cs-adaptace-pre-upstream-20260826`.
  One conflict, `integrations/obsidian-mcp-server/README.md` (our `vstupy/` wording
  vs upstream's new flag - kept both). What arrived: the MCP server launches with
  `uv run --no-project` everywhere (#226 - without it `uv` adopted whatever
  pyproject.toml sat in the user's cwd and wrote a `.venv`/`uv.lock` there on every
  session start), a `grok-bot` adapter (8th platform build), Grok Bot SEO wording.
  `test_no_documented_command_adopts_the_users_project` now also sweeps this file,
  so section 4 below spells the launch with the flag. Verified after the merge:
  `uv run pytest` 627/627 (with the machine env stripped - see the fork's memory
  note: `OBSIDIAN_EMBED_MODEL`, `OBSIDIAN_BG_AGENT_ENABLED` and a local
  `GEMINI_SUMMARY_MODEL` each break one upstream test when exported), `uvx ruff
  check` clean, `bash scripts/build.sh` all platforms, vault_health on the real
  vault 779 notes.
- **2026-08-19: merged `upstream/main`** (26 unreleased commits since the 0.14
  re-apply; no new upstream release - v0.14.0 is still the newest tag). This one
  was absorbed as a real `git merge`, NOT a re-apply: the delta was small enough
  that a merge keeps history linear for the other machine (`git pull --ff-only`
  instead of `reset --hard` after a force-push). Fallback tag:
  `cs-adaptace-pre-upstream-20260819`. The next RELEASE still gets the re-apply
  treatment - that protocol is unchanged. 25 conflicts, all in known delta
  surfaces: 19 commands (upstream rewrote `triggers_es`; kept both, ours + theirs),
  `validate-ai-first.sh`, the MCP server trio, `test_plugin_manifest.py` (taken
  from upstream wholesale) and `test_smoke.py`. Verified after the merge:
  `uv run pytest` 608/608, `uvx ruff check` clean, `bash scripts/build.sh` all 7
  platforms with the Czech block present in the dispatcher builds (pi, gemini-cli,
  opencode - claude-code has no monolithic dispatcher), triggers_cs 46/46,
  vault_health on the real vault 634 notes / 32 issues. What upstream brought that
  matters here: wikilink extraction now strips code blocks (#207, the source of
  part of the nightly "no match" noise), the research toolkit's silent-empty
  defaults are fixed, JSON transcripts read Whisper-style `segments[].text` (#193),
  and the `mcp<2` pin landed upstream (see section 4).
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
  alongside the English headings (prefix match on `Pro budouc`). **0.14+/2026-08-19:**
  upstream renamed the vocabulary to `## For future agent` and now anchors the
  whole heading (`^## For future (agent|AI|Claude|Codex)$`); the Czech arm rides
  alongside that exact set as a prefix match, so both pass.
- **Severity split (added 2026-08-19):** upstream escalated every finding to
  `decision: "block"`, which makes the PostToolUse host hand the warning back to
  the agent as a correction task. Structural defects and secrets keep that
  verdict. The banned-character check does NOT: **537 of 632 notes in this vault
  already carry one** (mostly U+2026 in imported prose), so blocking on it would
  bounce every edit of an old note and push the agent to rewrite lines it never
  touched. When typography is the ONLY finding, the hook advises instead
  (`systemMessage` + `additionalContext`, no `decision`). Revisit if the corpus
  is ever swept.
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
- **Preamble heading (re-expressed 2026-08-19):** upstream centralized the
  heading into `_PREAMBLE_HEADING` / `_PREAMBLE_RE` and made `_prepare_note_content`
  the single place that emits it (collapsing duplicate legacy headings). The fork
  keeps the Czech label by pointing `_PREAMBLE_HEADING` at `Pro budoucí Claude`
  and widening `_PREAMBLE_RE` with a Czech arm - upstream's English labels stay
  ACCEPTED (legacy notes, notes written by another agent), only the Czech one is
  EMITTED. Do not re-add a hand-built preamble in `save_note`: the body is now
  `f"{note_body}"` and building it twice is exactly the duplicate-heading bug
  upstream fixed. Pinned by `tests/test_smoke.py` and by one localized assertion
  in upstream's new `tests/test_mcp_codex_parity.py` (save emits the Czech label;
  the collapse-to-one behaviour it tests is untouched).
- **The `mcp<2` pin is NO LONGER a delta (2026-08-19).** PR #185 merged upstream
  and arrived with this merge: the manifest, `scripts/setup.sh`, `SKILL.md`,
  `README.md` and the integration docs all carry `--no-project --with 'mcp<2'`
  (the `--no-project` half arrived with upstream #226 on 2026-08-26), and
  `tests/test_plugin_manifest.py` sweeps every tracked file to keep it that way.
  Reinstalling via `setup.sh` no longer resurrects the unpinned launch.
- 4 smoke-test localizations in `tests/test_smoke.py` (vstupy/ paths + Czech
  preamble assertions); upstream's English-preamble FIXTURES elsewhere stay
  untouched (validate_note dual-accepts, vault_health is not localized).
- **Wired into Claude Code** (user scope, `~/.claude.json` mcpServers, stdio
  `uv run --no-project --with 'mcp<2' python .../obsidian-mcp-server/server.py`) since ~2026-07.
  Not wired into any other client. The `mcp<2` pin was a temporary local delta
  (2026-07-31, after `mcp` 2.0.0 dropped `mcp.server.fastmcp` and crashed the
  server on both machines); it was sent upstream as PR #185 (issue #183) and
  merged back here on 2026-08-19, so it is now upstream behaviour, not a delta.

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
