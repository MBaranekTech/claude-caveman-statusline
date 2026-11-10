#!/usr/bin/env bash
# claude-caveman-statusline
# Compact Claude Code status line: caveman badge, model, project, git worktree,
# context usage, session cost, remaining 5-hour / weekly usage with reset
# countdowns, and a clickable link to the session's scratchpad folder.
# Requires: jq, Claude Code >= 2.1.80 (usage bars need Pro/Max login)

input=$(cat)
j() { echo "$input" | jq -r "$1 // empty"; }

model=$(j '.model.display_name')
cur=$(j '.workspace.current_dir')
proj=$(j '.workspace.project_dir')
wt=$(j '.worktree.name // .workspace.git_worktree')
sid=$(j '.session_id')
ctx=$(j '.context_window.used_percentage')
cost=$(j '.cost.total_cost_usd')
h5=$(j '.rate_limits.five_hour.used_percentage')
d7=$(j '.rate_limits.seven_day.used_percentage')
r5=$(j '.rate_limits.five_hour.resets_at')
r7=$(j '.rate_limits.seven_day.resets_at')

# Color by remaining %: green > 50, yellow > 20, red otherwise
col() { local l=$1; ((l > 50)) && echo 32 || { ((l > 20)) && echo 33 || echo 31; }; }

# Thin 5-segment bar of REMAINING usage
bar() {
  local left=$((100 - ${1%.*})) w=5 s="" i; ((left < 0)) && left=0
  local fill=$(( (left * w + 50) / 100 ))
  for ((i=0; i<w; i++)); do ((i < fill)) && s+="▰" || s+="▱"; done
  printf '\e[%sm%s %d%%\e[0m' "$(col $left)" "$s" "$left"
}

# Dim countdown until a limit window resets: " (2h10)" or " (3d04h)"
# Accepts epoch seconds or an ISO timestamp.
until_reset() {
  local r=$1 ts m
  [ -z "$r" ] && return
  [[ $r =~ ^[0-9]+$ ]] && ts=$r || ts=$(date -d "$r" +%s 2>/dev/null)
  [ -z "$ts" ] && return
  m=$(( (ts - $(date +%s)) / 60 )); ((m < 0)) && m=0
  if ((m >= 1440)); then
    printf ' \e[2m(%dd%02dh)\e[0m' $((m / 1440)) $((m % 1440 / 60))
  else
    printf ' \e[2m(%dh%02d)\e[0m' $((m / 60)) $((m % 60))
  fi
}

# Caveman badge (plain for default mode, level shown otherwise)
cave=""
f=${CLAUDE_CONFIG_DIR:-$HOME/.claude}/.caveman-active
if [ -f "$f" ]; then
  mode=$(tr -d '[:space:]' < "$f" | tr '[:upper:]' '[:lower:]')
  case "$mode" in ""|full|caveman|on) tag="🪨" ;; *) tag="🪨${mode^^}" ;; esac
  cave="$tag "
fi

# Project name (launch dir); add the current subfolder when Claude moved away from it
[ -z "$proj" ] && proj=$cur
where="\e[1;34m$(basename "$proj")\e[0m"
[ -n "$cur" ] && [ "$cur" != "$proj" ] && where+="\e[2m/\e[0m$(basename "$cur")"

# Session scratchpad (Claude's working files): shown only when it holds files,
# as an OSC 8 link (Ctrl+click / Cmd+click opens the folder)
scratch=""
if [ -n "$sid" ]; then
  for base in "${CLAUDE_CODE_TMPDIR:-}" "${TMPDIR:-}" /tmp; do
    [ -z "$base" ] && continue
    for d in "${base%/}/claude-$(id -u)"/*/"$sid"/scratchpad; do
      [ -d "$d" ] || continue
      n=$(find "$d" -type f 2>/dev/null | wc -l)
      ((n > 0)) && scratch="\e]8;;file://${d// /%20}\a📂 ${n}\e]8;;\a"
      break 2
    done
  done
fi

# One line: where you work, then what you use. Dim labels and separators.
# Separators and labels are plain ASCII: box-drawing and symbol glyphs have
# ambiguous widths in tmux/VTE and can overlap neighbouring characters.
D='\e[2m' R='\e[0m' sep=" \e[2m|\e[0m "
join() { local o="" x; for x in "$@"; do [ -n "$x" ] && o+="${o:+$sep}$x"; done; printf '%s' "$o"; }

l1=("${cave}\e[1m${model}\e[0m" "${where}")
[ -n "$wt" ]      && l1+=("${D}wt${R} \e[35m${wt}\e[0m")
[ -n "$scratch" ] && l1+=("$scratch")

l2=()
[ -n "$ctx" ]  && l2+=("${D}ctx${R} ${ctx%.*}%")
# Session cost in USD (LC_NUMERIC=C so locales with a decimal comma still parse "0.42")
[ -n "$cost" ] && l2+=("\$$(LC_NUMERIC=C printf '%.2f' "$cost")")
[ -n "$h5" ]   && l2+=("${D}5h${R} $(bar "$h5")$(until_reset "$r5")")
if [ -n "$d7" ]; then
  wl=$((100 - ${d7%.*})); ((wl < 0)) && wl=0
  l2+=("${D}wk${R} \e[$(col $wl)m${wl}%\e[0m$(until_reset "$r7")")
fi

# Visible width: drop ANSI colors and OSC 8 links, count each emoji as 2 columns
width() {
  local t; t=$(printf '%b' "$1" | sed -E $'s/\e\\[[0-9;]*m//g; s/\e]8;;[^\a]*\a//g')
  local e=${t//[^🪨📂]/}
  echo $(( ${#t} + ${#e} ))
}

line=$(join "${l1[@]}" "${l2[@]}")
# Too wide for the terminal (Claude Code sets COLUMNS)? Split into two rows.
if [ -n "$COLUMNS" ] && ((COLUMNS > 0)) && (($(width "$line") > COLUMNS)); then
  printf '%b\n' "$(join "${l1[@]}")"
  ((${#l2[@]})) && printf '%b\n' "$(join "${l2[@]}")"
else
  printf '%b\n' "$line"
fi
