#!/bin/bash
input=$(cat)
cwd=$(echo "$input" | jq -r '.workspace.current_dir')
dir_path=$(echo "$cwd" | sed "s|^/Users/hllvc|~|")
repo_root=$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null)
repo_name=$(basename "$repo_root" 2>/dev/null)

# Robust worktree detection (matching p10k approach)
is_worktree=false
dir="$cwd"
while [ "$dir" != "/" ]; do
  git_path="${dir}/.git"
  if [ -f "$git_path" ]; then
    read -r git_link <"$git_path"
    git_link="${git_link#gitdir: }"
    # Resolve relative paths
    [[ "$git_link" != /* ]] && git_link="${dir}/${git_link}"
    # Resolve symlinks and canonicalize
    git_link=$(cd "$git_link" 2>/dev/null && pwd -P)
    if [[ "$git_link" == */worktrees/* ]]; then
      bare_root="${git_link%/worktrees/*}"
      bare_root="${bare_root%/.bare}"
      repo_name=$(basename "$bare_root")
      rel_path="${cwd#$dir}"
      dir_path=$(echo "${bare_root}${rel_path}" | sed "s|^/Users/hllvc|~|")
      is_worktree=true
    fi
    break
  elif [ -d "$git_path" ]; then
    break
  fi
  dir=$(dirname "$dir")
done

# Branch / detached HEAD detection
branch=$(git -C "$cwd" branch --show-current 2>/dev/null)
commit=$(git -C "$cwd" rev-parse --short=8 HEAD 2>/dev/null)

if [ -z "$branch" ] && [ -n "$repo_root" -o "$is_worktree" = true ]; then
  tag=$(git -C "$cwd" describe --tags --exact-match HEAD 2>/dev/null)
  if [ -n "$tag" ]; then
    branch="#${tag}"
  elif [ -n "$commit" ]; then
    branch="@${commit}"
    commit="" # already shown as branch
  fi
fi

# Truncate long branch names (matching p10k: first12…last12)
if [ -n "$branch" ] && [ ${#branch} -gt 32 ]; then
  branch="${branch:0:12}…${branch: -12}"
fi

# Append commit hash after branch name (when on a branch, not detached)
if [ -n "$branch" ] && [ -n "$commit" ]; then
  branch="${branch} \033[38;2;88;88;88m@${commit}"
fi

# --- p10k-style path shortening ---
anchor_markers=(
  .bzr .citc .git .hg
  .node-version .python-version .go-version .ruby-version
  .lua-version .java-version .perl-version .php-version
  .tool-versions .mise.toml .shorten_folder_marker .svn .terraform
  CVS Cargo.toml composer.json go.mod package.json stack.yaml
)

# Split dir_path into segments
IFS='/' read -ra parts <<<"$dir_path"

# Build real paths and detect anchors
anchors=()
check_path=""
for i in "${!parts[@]}"; do
  seg="${parts[$i]}"
  if [ "$i" -eq 0 ] && [ "$seg" = "~" ]; then
    check_path="$HOME"
  elif [ -z "$seg" ]; then
    continue
  else
    check_path="${check_path}/${seg}"
  fi
  for marker in "${anchor_markers[@]}"; do
    if [ -e "${check_path}/${marker}" ]; then
      anchors+=("$i")
      break
    fi
  done
done

# Find first real (non-empty) segment index
first_real=-1
for i in "${!parts[@]}"; do
  if [ -n "${parts[$i]}" ]; then
    first_real=$i
    break
  fi
done

last_idx=$((${#parts[@]} - 1))
path_len=${#dir_path}
max_len=80

# Mark segments to shorten left-to-right until path fits
shorten=()
if ((path_len > max_len)); then
  for i in "${!parts[@]}"; do
    seg="${parts[$i]}"
    [ -z "$seg" ] && continue
    # Never shorten first real, last, or anchor segments
    [ "$i" -eq "$first_real" ] && continue
    [ "$i" -eq "$last_idx" ] && continue

    is_anchor=0
    for a in "${anchors[@]}"; do
      [ "$a" -eq "$i" ] && is_anchor=1 && break
    done
    [ "$is_anchor" -eq 1 ] && continue

    saved=$((${#seg} - 2))
    ((saved > 0)) || continue
    shorten+=("$i")
    ((path_len -= saved))
    ((path_len <= max_len)) && break
  done
fi

# Build display path with ANSI bold for anchors and last segment
result=""
for i in "${!parts[@]}"; do
  seg="${parts[$i]}"
  [ -z "$seg" ] && continue

  [ -n "$result" ] && result="${result}/"

  # Check if this segment should be shortened
  do_shorten=0
  for s in "${shorten[@]}"; do
    [ "$s" -eq "$i" ] && do_shorten=1 && break
  done

  # Check if anchor
  is_anchor=0
  for a in "${anchors[@]}"; do
    [ "$a" -eq "$i" ] && is_anchor=1 && break
  done

  if [ "$do_shorten" -eq 1 ]; then
    result="${result}${seg:0:2}"
  elif [ "$is_anchor" -eq 1 ] || [ "$i" -eq "$last_idx" ]; then
    result="${result}\033[1m${seg}\033[22m"
  else
    result="${result}${seg}"
  fi
done

# Restore leading / for absolute paths
[[ "$dir_path" == /* ]] && result="/${result}"

if [ -n "$branch" ]; then
  printf '\033[34m%b \033[37mon \033[32m%b\033[0m\n' "$result" "$branch"
else
  printf '\033[34m%b\033[0m\n' "$result"
fi
