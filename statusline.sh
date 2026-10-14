#!/usr/bin/env bash
# claude-caveman-statusline
# Compact Claude Code status line: caveman badge, model, folder,
# context usage, session cost, and remaining 5-hour / weekly usage.
# Requires: jq, Claude Code >= 2.1.80 (usage bars need Pro/Max login)

input=$(cat)
j() { echo "$input" | jq -r "$1 // empty"; }

model=$(j '.model.display_name')
dir=$(basename "$(j '.workspace.current_dir')")
ctx=$(j '.context_window.used_percentage')
cost=$(j '.cost.total_cost_usd')
h5=$(j '.rate_limits.five_hour.used_percentage')
d7=$(j '.rate_limits.seven_day.used_percentage')
r5=$(j '.rate_limits.five_hour.resets_at')

# Color by remaining %: green > 50, yellow > 20, red otherwise
col() { local l=$1; ((l > 50)) && echo 32 || { ((l > 20)) && echo 33 || echo 31; }; }

# Thin 5-segment bar of REMAINING usage
bar() {
  local left=$((100 - ${1%.*})) w=5 s="" i; ((left < 0)) && left=0
  local fill=$(( (left * w + 50) / 100 ))
  for ((i=0; i<w; i++)); do ((i < fill)) && s+="▰" || s+="▱"; done
  printf '\e[%sm%s %d%%\e[0m' "$(col $left)" "$s" "$left"
}

# Caveman badge (plain for default mode, level shown otherwise)
cave=""
f=${CLAUDE_CONFIG_DIR:-$HOME/.claude}/.caveman-active
if [ -f "$f" ]; then
  mode=$(tr -d '[:space:]' < "$f" | tr '[:upper:]' '[:lower:]')
  case "$mode" in ""|full|caveman|on) tag="🪨" ;; *) tag="🪨${mode^^}" ;; esac
  cave="$tag "
fi

# Time until the 5-hour window resets (epoch or ISO timestamp)
reset=""
if [ -n "$r5" ]; then
  [[ $r5 =~ ^[0-9]+$ ]] && ts=$r5 || ts=$(date -d "$r5" +%s 2>/dev/null)
  [ -n "$ts" ] && { m=$(( (ts - $(date +%s)) / 60 )); ((m < 0)) && m=0; reset=" \e[2m$((m/60))h$(printf %02d $((m%60)))\e[0m"; }
fi

out="${cave}${model} · ${dir}"
[ -n "$ctx" ] && out+=" · ctx ${ctx%.*}%"
# Session cost in USD (LC_NUMERIC=C so locales with a decimal comma still parse "0.42")
[ -n "$cost" ] && out+=" · \$$(LC_NUMERIC=C printf '%.2f' "$cost")"
[ -n "$h5" ]  && out+=" · 5h $(bar "$h5")${reset}"
if [ -n "$d7" ]; then
  wl=$((100 - ${d7%.*}))
  out+=" · wk \e[$(col $wl)m${wl}%\e[0m"
fi
printf '%b\n' "$out"
