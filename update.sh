#!/bin/bash

set -e

SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMMANDS_DIR="$HOME/.claude/commands"
SRC_COMMANDS="$SKILL_DIR/commands"

# Pull latest
if [ -d "$SKILL_DIR/.git" ]; then
  echo "Pulling latest changes..."
  git -C "$SKILL_DIR" pull
else
  echo "Not a git repo - skipping pull. Update the files in $SKILL_DIR manually."
fi

mkdir -p "$COMMANDS_DIR"

# Reconcile ~/.claude/commands/ to mirror commands/ exactly. A plain git pull
# refreshes the contents behind existing symlinks, but it cannot add links for
# brand-new commands nor remove links for commands upstream deleted - so without
# this step a version bump leaves dangling symlinks (deleted commands) and
# missing links (new commands) behind. See DELTAS.md section 7.

# 1. Prune stale links. Only touch symlinks that point INTO this skill's
#    commands/ dir and whose target file is gone (command removed upstream).
#    Scoping by the readlink target keeps other skills'/plugins' commands safe.
echo "Pruning removed commands..."
pruned=0
for dest in "$COMMANDS_DIR"/*.md; do
  [ -L "$dest" ] || continue
  case "$(readlink "$dest")" in
    "$SRC_COMMANDS"/*)
      if [ ! -e "$dest" ]; then   # broken: target file no longer exists
        rm "$dest"
        echo "  removed $(basename "$dest") (no longer in skill)"
        pruned=$((pruned + 1))
      fi
      ;;
  esac
done
[ "$pruned" -gt 0 ] && echo "  $pruned stale command(s) removed"

# 2. Sync current commands: ensure every source command is present. Symlinks
#    pick up the git pull for free; new commands get a fresh link; copied
#    commands (Windows without Developer Mode) get their contents refreshed.
echo "Updating slash commands..."
case "$(uname -s)" in
  MINGW*|MSYS*|CYGWIN*) IS_WINDOWS=1 ;;
  *) IS_WINDOWS=0 ;;
esac
linked=0
updated=0
for file in "$SRC_COMMANDS"/*.md; do
  name=$(basename "$file")
  dest="$COMMANDS_DIR/$name"
  if [ -L "$dest" ]; then
    : # symlink - already current after git pull
  elif [ -e "$dest" ]; then
    cp "$file" "$dest"            # non-symlink copy (Windows) - refresh contents
    echo "  updated $name"
    updated=$((updated + 1))
  elif [ "$IS_WINDOWS" -eq 0 ]; then
    ln -s "$file" "$dest"         # new command - create link
    echo "  linked $name"
    linked=$((linked + 1))
  elif MSYS=winsymlinks:nativestrict ln -s "$file" "$dest" 2>/dev/null; then
    echo "  linked $name"
    linked=$((linked + 1))
  else
    cp "$file" "$dest"
    echo "  installed $name"
    updated=$((updated + 1))
  fi
done
[ "$linked" -gt 0 ] && echo "  $linked new command(s) linked"
[ "$updated" -gt 0 ] && echo "  $updated command(s) refreshed (copied, not symlinked)"

echo ""
echo "Done. Restart Claude Code to pick up the changes."
