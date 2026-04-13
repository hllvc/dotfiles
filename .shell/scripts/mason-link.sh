#!/usr/bin/env bash

MASON_BIN="$HOME/.local/share/nvim/mason/bin"
LOCAL_BIN="$HOME/.local/bin"

if [[ ! -d "$MASON_BIN" ]]; then
  echo "Mason bin not found: $MASON_BIN"
  exit 1
fi

mkdir -p "$LOCAL_BIN"

created=0
updated=0
skipped=0

for bin in "$MASON_BIN"/*; do
  name="$(basename "$bin")"
  target="$LOCAL_BIN/$name"

  if [[ -L "$target" ]]; then
    existing="$(readlink "$target")"
    if [[ "$existing" == "$bin" ]]; then
      ((skipped++))
      continue
    fi
    ln -sf "$bin" "$target"
    echo "updated: $name ($existing -> $bin)"
    ((updated++))
  elif [[ -e "$target" ]]; then
    echo "skipped: $name (non-symlink file exists)"
    ((skipped++))
  else
    ln -s "$bin" "$target"
    echo "created: $name"
    ((created++))
  fi
done

echo "done: $created created, $updated updated, $skipped skipped"
