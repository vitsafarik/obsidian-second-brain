"""Writes AI-first research notes to the Obsidian vault.

Each note follows the AI-first vault rule:
1. Self-contained context
2. "For future Claude" preamble
3. Rich frontmatter
4. Recency markers per claim
5. Sources preserved verbatim
6. Mandatory wikilinks
7. Confidence levels (where applicable)
"""

import re
from datetime import datetime
from pathlib import Path
from typing import Any
from urllib.parse import quote

from .config import VAULT_PATH

# Subfolder routing per command (relative to vault root, under Research/).
# Ceske vaulty maji zakaz anglickych slozek (_CLAUDE.md), proto se koren hleda:
# existuje-li vstupy/ (rizeny inbox), vysledky researche padaji tam bez podslozek.
_RESEARCH_ROOT = Path("Research")
SUBFOLDERS = {
    "x-read":      _RESEARCH_ROOT / "X-reads",
    "x-pulse":     _RESEARCH_ROOT / "X-pulse",
    "research":    _RESEARCH_ROOT / "Web",
    "research-deep": _RESEARCH_ROOT / "Deep",
    "youtube":     _RESEARCH_ROOT / "YouTube",
    "podcast":     _RESEARCH_ROOT / "Podcasts",
}
# Vaulty s vlastnim inboxem (prvni existujici vyhrava, jinak Research/ jako driv).
INBOX_DIRS = ("vstupy", "Inputs", "Inbox")


def subfolder_for(command: str) -> Path:
    """Kam ulozit vystup daneho commandu, s ohledem na layout vaultu."""
    for name in INBOX_DIRS:
        if (VAULT_PATH / name).is_dir():
            return Path(name)
    return SUBFOLDERS.get(command, _RESEARCH_ROOT)


def slugify(text: str, max_len: int = 80) -> str:
    text = text.strip().lower()
    text = re.sub(r"[^\w\s-]", "", text)
    text = re.sub(r"[\s_]+", " ", text).strip()
    text = re.sub(r"\s+", " ", text)
    return text[:max_len].strip().rstrip(" -")


def filename_for(command: str, topic: str) -> str:
    date = datetime.now().strftime("%Y-%m-%d")
    slug = slugify(topic) or "untitled"
    return f"{date} - {slug}.md"


def write_note(command: str, topic: str, frontmatter: dict[str, Any], body: str) -> Path:
    """Write a research note to the vault. Returns the absolute path."""
    if command not in SUBFOLDERS:
        raise ValueError(f"Unknown command: {command}")
    folder = VAULT_PATH / subfolder_for(command)
    folder.mkdir(parents=True, exist_ok=True)
    path = folder / filename_for(command, topic)

    fm_lines = ["---"]
    for k, v in frontmatter.items():
        fm_lines.append(_yaml_kv(k, v))
    fm_lines.append("---")
    fm_text = "\n".join(fm_lines)

    full = f"{fm_text}\n\n{body.strip()}\n"
    path.write_text(full)
    return path


def _yaml_kv(key: str, value: Any) -> str:
    if isinstance(value, list):
        if not value:
            return f"{key}: []"
        items = "\n".join(f"  - {_yaml_scalar(v)}" for v in value)
        return f"{key}:\n{items}"
    if isinstance(value, dict):
        items = "\n".join(f"  {k}: {_yaml_scalar(v)}" for k, v in value.items())
        return f"{key}:\n{items}"
    return f"{key}: {_yaml_scalar(value)}"


def _yaml_scalar(v: Any) -> str:
    if v is None:
        return ""
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, (int, float)):
        return str(v)
    s = str(v)
    if any(c in s for c in [":", "#", "\n", '"', "'", "[", "]", "{", "}"]) or s.strip() != s:
        s = s.replace('"', '\\"')
        return f'"{s}"'
    return s


def obsidian_uri(note_path: Path) -> str:
    """Build an obsidian://open?... URI that opens this note directly in Obsidian."""
    vault_name = VAULT_PATH.name
    rel = note_path.relative_to(VAULT_PATH)
    file_no_ext = str(rel).removesuffix(".md")
    return f"obsidian://open?vault={quote(vault_name)}&file={quote(file_no_ext)}"


def print_save_links(note_path: Path, file=None) -> None:
    """Print save confirmation with clickable Obsidian + VS Code links to the saved note.

    Also auto-opens the note in Obsidian unless disabled via RESEARCH_AUTOOPEN=0.
    """
    import os
    import subprocess
    import sys
    out = file or sys.stderr
    rel = note_path.relative_to(VAULT_PATH)
    uri = obsidian_uri(note_path)
    print(f"\n💾 Saved: {rel}", file=out)
    print(f"   📖 Open in Obsidian: {uri}", file=out)
    print(f"   ✏️  Open in VS Code:  code \"{note_path}\"", file=out)

    # Auto-open in Obsidian by default. Disable with RESEARCH_AUTOOPEN=0.
    if os.environ.get("RESEARCH_AUTOOPEN", "1") != "0":
        try:
            import platform
            # Platform-aware open: `open` on macOS, `xdg-open` on Linux,
            # `cmd /c start "" <uri>` on Windows (the empty "" is the window title).
            open_cmd = {
                "Darwin": ["open", uri],
                "Linux": ["xdg-open", uri],
                "Windows": ["cmd", "/c", "start", "", uri],
            }.get(platform.system(), ["open", uri])
            subprocess.run(open_cmd, check=False, timeout=5)
        except Exception:
            pass  # auto-open is a nice-to-have, never block the save flow


# Layout vaultu se lisi podle jazyka a verze bootstrapu, cesty se proto HLEDAJI
# a nehardcoduji (stejna trida chyby jako VAULT_SCAN_DIRS, opraveno 2026-08-06).
LOG_DIRS = ("log", "Logs")                       # per-den operační log
DAILY_DIRS = ("denik", "Daily", "daily", "wiki/daily")


def _log_target() -> tuple[Path, bool]:
    """Vrátí (cesta, per_day). Per-den log má přednost před root log.md."""
    date = datetime.now().strftime("%Y-%m-%d")
    for name in LOG_DIRS:
        d = VAULT_PATH / name
        if d.is_dir():
            return d / f"{date}.md", True
    return VAULT_PATH / "log.md", False


def append_to_log(operation_summary: str) -> None:
    """Append to the vault's operation log (per-day file when the vault has one)."""
    log_path, per_day = _log_target()
    now = datetime.now()
    stamp = now.strftime("%H:%M") if per_day else now.strftime("%Y-%m-%d")
    entry = f"\n## [{stamp}] research-toolkit | {operation_summary}\n"
    if per_day and not log_path.exists():
        log_path.write_text(f"# Log {now.strftime('%Y-%m-%d')}\n")
    with log_path.open("a") as f:
        f.write(entry)


def _daily_path() -> Path | None:
    date = datetime.now().strftime("%Y-%m-%d")
    for name in DAILY_DIRS:
        p = VAULT_PATH / name / f"{date}.md"
        if p.exists():
            return p
    return None


def append_to_daily(summary_md: str) -> bool:
    """Append a research summary to today's daily note. Returns True if appended."""
    daily_path = _daily_path()
    if daily_path is None:
        return False
    current = daily_path.read_text()
    block = f"\n### Research - {datetime.now().strftime('%H:%M')}\n\n{summary_md.strip()}\n"
    if "## 🌙 Evening Review" in current:
        new = current.replace("## 🌙 Evening Review", f"{block}\n---\n\n## 🌙 Evening Review", 1)
    else:
        new = current + block
    daily_path.write_text(new)
    return True
