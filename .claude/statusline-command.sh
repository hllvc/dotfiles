#!/bin/bash
input=$(cat)

# Snapshot rate limits for the modelusage client (~/.modelusage-client)
if echo "$input" | jq -e '.rate_limits' >/dev/null 2>&1; then
  tracker_dir="$HOME/.claude_usage_tracker"
  mkdir -p "$tracker_dir"
  tmp_status=$(mktemp "$tracker_dir/.last_status.XXXXXX" 2>/dev/null) &&
    printf '%s\n' "$input" >"$tmp_status" &&
    mv -f "$tmp_status" "$tracker_dir/last_status.json"
fi

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

# --- Extract session fields for right side ---
model_name=$(echo "$input" | jq -r '.model.display_name // empty' 2>/dev/null)
effort_level=$(echo "$input" | jq -r '.effort.level // empty' 2>/dev/null)
ctx_pct=$(echo "$input" | jq -r 'if .context_window.used_percentage then (.context_window.used_percentage | round | tostring) else empty end' 2>/dev/null)
fh_pct=$(echo "$input" | jq -r 'if .rate_limits.five_hour.used_percentage then (.rate_limits.five_hour.used_percentage | round | tostring) else empty end' 2>/dev/null)
fh_reset_epoch=$(echo "$input" | jq -r '.rate_limits.five_hour.resets_at // empty' 2>/dev/null)

# --- Build right-side string ---
# Sections are visually separated by a dim │; model and effort joined by ·

DIM='\033[2m'
RESET='\033[0m'
SEP="${DIM} │ ${RESET}"

pct_color() {
  local pct="$1"
  if (( pct < 60 )); then printf '\033[32m'
  elif (( pct < 85 )); then printf '\033[33m'
  else printf '\033[31m'; fi
}

sections=()

# Section 1: model · effort
if [[ -n "$model_name" ]]; then
  sec="\033[37m${model_name}${RESET}"
  if [[ -n "$effort_level" ]]; then
    case "$effort_level" in
      low)       effort_clr="${DIM}" ;;
      medium)    effort_clr="\033[37m" ;;
      high)      effort_clr="\033[33m" ;;
      max|xhigh) effort_clr="\033[31m" ;;
      *)         effort_clr="\033[37m" ;;
    esac
    sec+=" ${DIM}·${RESET} ${effort_clr}${effort_level}${RESET}"
  fi
  sections+=("$sec")
fi

# Section 2: ctx %
if [[ -n "$ctx_pct" ]] && [[ "$ctx_pct" =~ ^[0-9]+$ ]]; then
  ctx_clr=$(pct_color "$ctx_pct")
  sections+=("${DIM}ctx${RESET} ${ctx_clr}${ctx_pct}%${RESET}")
fi

# Section 3: 5h % → HH:MM
if [[ -n "$fh_pct" ]] && [[ "$fh_pct" =~ ^[0-9]+$ ]]; then
  fh_clr=$(pct_color "$fh_pct")
  sec="${DIM}5h${RESET} ${fh_clr}${fh_pct}%${RESET}"
  if [[ -n "$fh_reset_epoch" ]] && [[ "$fh_reset_epoch" =~ ^[0-9]+$ ]]; then
    now=$(date +%s)
    secs_left=$(( fh_reset_epoch - now ))
    if (( secs_left > 0 )); then
      if (( secs_left >= 3600 )); then
        h=$(( secs_left / 3600 ))
        m=$(( (secs_left % 3600) / 60 ))
        countdown="${h}h${m}m"
      else
        m=$(( secs_left / 60 ))
        countdown="${m}m"
      fi
      sec+=" ${DIM}→ ${countdown}${RESET}"
    fi
  fi
  sections+=("$sec")
fi

# Join sections with separator
right=""
for sec in "${sections[@]}"; do
  [[ -n "$right" ]] && right+="$SEP"
  right+="$sec"
done

# --- Build left string and pad to terminal width ---
if [ -n "$branch" ]; then
  left_str=$(printf '\033[34m%b \033[37mon \033[32m%b\033[0m' "$result" "$branch")
else
  left_str=$(printf '\033[34m%b\033[0m' "$result")
fi

if [[ -n "$right" ]]; then
  term_width=""
  { term_width=$(stty size </dev/tty 2>/dev/null | awk '{print $2}'); } 2>/dev/null
  [[ -z "$term_width" ]] && term_width=${COLUMNS:-$(tput cols 2>/dev/null || echo 100)}
  left_visible=$(printf '%b' "$left_str" | sed $'s/\033\[[0-9;:]*m//g')
  right_visible=$(printf '%b' "$right" | sed $'s/\033\[[0-9;:]*m//g')
  pad=$(( term_width - ${#left_visible} - ${#right_visible} - 6 ))
  (( pad < 2 )) && pad=2
  printf '%b%*s%b\n' "$left_str" "$pad" "" "$right"
else
  printf '%b\n' "$left_str"
fi
