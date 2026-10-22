#!/usr/bin/env bash
#
# git clean filter for .claude/settings.json (wired in .gitattributes,
# registered by `./dotctl stow`). ~/.claude/settings.json is a symlink into this
# repo, and Claude Code saves the /model picker's model and effort there, so a
# temporary switch in one session would show up as a repo change. This puts
# the session-written keys back to their committed values before git sees the
# file. Claude Code also reorders top-level keys when it rewrites the file, so
# they're put back in committed order (new keys last). Values otherwise pass
# through.
#
# Changing a default on purpose bypasses the filter:
#   git -c filter.claude-settings.clean=cat add .claude/settings.json

set -u

path="${1:-.claude/settings.json}"
input="$(cat)"

# Pass through untouched when there's nothing to compare against (no HEAD, file
# not committed yet, no jq) or the working copy isn't valid JSON.
committed="$(git cat-file blob "HEAD:$path" 2>/dev/null)" &&
  command -v jq >/dev/null &&
  out="$(jq --argjson head "$committed" '
    reduce ("model", "effortLevel", "modelSettings") as $k (.;
      if $head | has($k) then .[$k] = $head[$k] else del(.[$k]) end)
    | . as $cur
    | reduce (($head | keys_unsorted[] | select(. as $k | $cur | has($k))),
              ($cur | keys_unsorted[] | select(. as $k | $head | has($k) | not)))
        as $k ({}; .[$k] = $cur[$k])
  ' <<<"$input" 2>/dev/null)" ||
  out="$input"

printf '%s\n' "$out"
