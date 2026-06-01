#!/usr/bin/env bash

# Compact statusline: ⬢ Sonnet 4.6 · ↑15k ↓5k ($0.04) · ⣿⣿⣿⣀⣀⣀⣀⣀⣀⣀ 42% · ⏱ 2h14m ⣿⣿⣿⣿⣀⣀ 62% · 📆 6d14h ⣿⣀⣀⣀ 7% · 💳 $0.12/$5
input=$(cat)

CACHE_FILE="/tmp/claude-statusline-usage-cache.json"
CACHE_TTL=60

# Linux/Windows credential store used by Claude Code as a fallback to macOS Keychain.
CRED_FILE="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/.credentials.json"

# ANSI color helpers
COLOR_CYAN="\033[36m"
COLOR_GREEN="\033[32m"
COLOR_YELLOW="\033[33m"
COLOR_RED="\033[31m"
COLOR_RESET="\033[0m"

# Builds a braille-block bar; color by usage % (green<50, yellow<80, red>=80).
# $1=percentage, $2=total_blocks (default 8)
build_bar() {
  local pct=$1
  local total=${2:-8}
  local filled=$(( (pct * total + 50) / 100 ))
  local bar=""
  for ((i=0; i<filled; i++));     do bar="${bar}⣿"; done
  for ((i=filled; i<total; i++)); do bar="${bar}⣀"; done

  local color
  if   (( pct < 50 )); then color="$COLOR_GREEN"
  elif (( pct < 80 )); then color="$COLOR_YELLOW"
  else                       color="$COLOR_RED"
  fi

  printf '%b%s%b' "$color" "$bar" "$COLOR_RESET"
}

# Builds a braille-block bar colored by time/budget remaining % (inverse logic).
# green when >50% remaining, yellow when 20-50% remaining, red when <20% remaining.
# $1=used_percentage, $2=total_blocks (default 8)
build_bar_remaining() {
  local pct=$1
  local total=${2:-8}
  local filled=$(( (pct * total + 50) / 100 ))
  local bar=""
  for ((i=0; i<filled; i++));     do bar="${bar}⣿"; done
  for ((i=filled; i<total; i++)); do bar="${bar}⣀"; done

  local remaining=$(( 100 - pct ))
  local color
  if   (( remaining > 50 )); then color="$COLOR_GREEN"
  elif (( remaining > 20 )); then color="$COLOR_YELLOW"
  else                             color="$COLOR_RED"
  fi

  printf '%b%s%b' "$color" "$bar" "$COLOR_RESET"
}

format_duration() {
  local secs=$1
  local d=$(( secs / 86400 ))
  local h=$(( (secs % 86400) / 3600 ))
  local m=$(( (secs % 3600) / 60 ))
  if (( d > 0 )); then
    printf '%dd%dh' "$d" "$h"
  elif (( h > 0 )); then
    printf '%dh%dm' "$h" "$m"
  else
    printf '%dm' "$m"
  fi
}

parse_iso8601() {
  python3 -c "
from datetime import datetime
import sys
try:
    dt = datetime.fromisoformat(sys.argv[1])
    print(int(dt.timestamp()))
except Exception:
    pass
" "$1" 2>/dev/null
}

# Reads the raw credentials JSON from the macOS Keychain, falling back to the
# Linux/Windows file store (~/.claude/.credentials.json).
read_credentials() {
  local creds
  creds=$(security find-generic-password -s "Claude Code-credentials" -w 2>/dev/null)
  if [ -n "$creds" ]; then
    printf '%s' "$creds"
    return 0
  fi
  [ -f "$CRED_FILE" ] && cat "$CRED_FILE" 2>/dev/null
}

# Persists updated credentials back to whichever store is in use.
write_credentials() {
  local creds="$1"
  if security find-generic-password -s "Claude Code-credentials" -w >/dev/null 2>&1; then
    security add-generic-password -U -s "Claude Code-credentials" -w "$creds" 2>/dev/null
  elif [ -f "$CRED_FILE" ]; then
    printf '%s' "$creds" > "$CRED_FILE" 2>/dev/null
  fi
}

get_access_token() {
  read_credentials \
    | python3 -c "import sys,json; d=json.loads(sys.stdin.read())['claudeAiOauth']; print(d['accessToken'])" 2>/dev/null
}

get_refresh_token() {
  read_credentials \
    | python3 -c "import sys,json; d=json.loads(sys.stdin.read())['claudeAiOauth']; print(d['refreshToken'])" 2>/dev/null
}

refresh_access_token() {
  local refresh_token
  refresh_token=$(get_refresh_token)
  [ -z "$refresh_token" ] && return 1

  local response
  response=$(curl -s --max-time 3 \
    -X POST "https://api.anthropic.com/api/oauth/token" \
    -H "Content-Type: application/x-www-form-urlencoded" \
    -d "grant_type=refresh_token&refresh_token=${refresh_token}&client_id=claude-code" 2>/dev/null)

  local new_access_token
  new_access_token=$(echo "$response" | jq -r '.access_token // empty' 2>/dev/null)
  [ -z "$new_access_token" ] && return 1

  local new_refresh_token
  new_refresh_token=$(echo "$response" | jq -r '.refresh_token // empty' 2>/dev/null)

  local existing_creds
  existing_creds=$(read_credentials)
  if [ -n "$existing_creds" ] && [ -n "$new_refresh_token" ]; then
    local updated_creds
    updated_creds=$(echo "$existing_creds" | python3 -c "
import sys, json
d = json.loads(sys.stdin.read())
d['claudeAiOauth']['accessToken'] = '${new_access_token}'
d['claudeAiOauth']['refreshToken'] = '${new_refresh_token}'
print(json.dumps(d))
" 2>/dev/null)
    if [ -n "$updated_creds" ]; then
      write_credentials "$updated_creds"
    fi
  fi

  printf '%s' "$new_access_token"
}

call_usage_api() {
  local token="$1"
  curl -s --max-time 3 \
    -H "Authorization: Bearer ${token}" \
    -H "anthropic-beta: oauth-2025-04-20" \
    -H "User-Agent: claude-code/2.1.45" \
    -H "Accept: application/json" \
    "https://api.anthropic.com/api/oauth/usage" 2>/dev/null
}

get_cached_usage() {
  [ -f "$CACHE_FILE" ] || return 1
  local now cache_ts age
  now=$(date +%s)
  cache_ts=$(jq -r '._cached_at // 0' "$CACHE_FILE" 2>/dev/null)
  age=$(( now - cache_ts ))
  (( age < CACHE_TTL )) || return 1
  cat "$CACHE_FILE"
}

fetch_usage() {
  local token
  token=$(get_access_token)
  [ -z "$token" ] && return 1

  local response
  response=$(call_usage_api "$token")

  local err_type
  err_type=$(echo "$response" | jq -r '.error.type // empty' 2>/dev/null)
  if [ "$err_type" = "authentication_error" ]; then
    token=$(refresh_access_token)
    [ -z "$token" ] && return 1
    response=$(call_usage_api "$token")
    err_type=$(echo "$response" | jq -r '.error.type // empty' 2>/dev/null)
    [ -n "$err_type" ] && return 1
  fi

  local has_data
  has_data=$(echo "$response" | jq -r '.five_hour // empty' 2>/dev/null)
  [ -z "$has_data" ] && return 1

  local now
  now=$(date +%s)
  echo "$response" | jq --argjson t "$now" '. + {_cached_at: $t}' > "$CACHE_FILE" 2>/dev/null
  printf '%s' "$response"
}

# Abbreviates token counts: 15200 → 15k, 1200000 → 1.2M
fmt_tokens() {
  local t=$1
  if (( t >= 1000000 )); then
    python3 -c "print(f'{$t/1000000:.1f}M')" 2>/dev/null
  elif (( t >= 1000 )); then
    python3 -c "print(f'{round($t/1000)}k')" 2>/dev/null
  else
    printf '%s' "$t"
  fi
}

# --- Read stdin JSON ---
model=$(echo "$input" | jq -r '.model.display_name // empty')
# Shorten "Claude Sonnet 4.6" → "Sonnet 4.6"
model="${model#Claude }"

parts=()

# --- Section 1: cyan ⬢ model name ---
parts+=("\033[36m⬢ ${model}\033[0m")

# --- Section 2: ↑ in green, ↓ in red, cost in default color ---
input_tokens=$(echo "$input" | jq -r '.context_window.total_input_tokens // empty')
output_tokens=$(echo "$input" | jq -r '.context_window.total_output_tokens // empty')
cache_read_tokens=$(echo "$input" | jq -r '.context_window.current_usage.cache_read_input_tokens // empty')
cost_usd=$(echo "$input" | jq -r '.cost.total_cost_usd // empty')
if [ -n "$input_tokens" ] && [ -n "$output_tokens" ]; then
  in_fmt=$(fmt_tokens "$input_tokens")
  out_fmt=$(fmt_tokens "$output_tokens")
  tok_part="\033[32m↑\033[0m${in_fmt} \033[31m↓\033[0m${out_fmt}"
  if [ -n "$cache_read_tokens" ] && (( cache_read_tokens > 0 )); then
    cache_fmt=$(fmt_tokens "$cache_read_tokens")
    tok_part="${tok_part} 🧠${cache_fmt}"
  fi
  if [ -n "$cost_usd" ]; then
    cost_fmt=$(python3 -c "print(f'\${$cost_usd:.2f}')" 2>/dev/null)
    cost_color="\033[32m"
    (( $(python3 -c "print(1 if $cost_usd >= 3.00 else 0)") )) && cost_color="\033[33m"
    (( $(python3 -c "print(1 if $cost_usd > 12.00 else 0)") )) && cost_color="\033[31m"
    tok_part="${tok_part}  💰${cost_color}${cost_fmt}\033[0m"
  fi
  parts+=("$tok_part")
fi

# --- Section 3: context bar (braille blocks, colored by usage %) ---
ctx_pct=$(echo "$input" | jq -r '.context_window.used_percentage // empty')
ctx_used=$(echo "$input" | jq -r '.context_window.total_input_tokens // empty')
if [ -n "$ctx_pct" ] && [ -n "$ctx_used" ]; then
  printf -v ctx_int "%.0f" "$ctx_pct" 2>/dev/null
  ctx_bar=$(build_bar "$ctx_int" 10)
  ctx_used_fmt=$(fmt_tokens "$ctx_used")
  # Derive total context size from used tokens and percentage
  ctx_total=$(python3 -c "print(round($ctx_used * 100 / $ctx_pct / 1000) * 1000)" 2>/dev/null)
  ctx_total_fmt=$(fmt_tokens "$ctx_total")
  parts+=("${ctx_bar} ${ctx_used_fmt}/${ctx_total_fmt}")
elif [ -n "$ctx_pct" ]; then
  printf -v ctx_int "%.0f" "$ctx_pct" 2>/dev/null
  ctx_bar=$(build_bar "$ctx_int" 10)
  parts+=("${ctx_bar} ${ctx_int}%")
fi

# --- Fetch usage data ---
usage=$(get_cached_usage 2>/dev/null || fetch_usage 2>/dev/null)

# --- Section 4: ⏱ 5-hour session — usage %, time remaining, mini bar ---
if [ -n "$usage" ]; then
  session_pct=$(echo "$usage" | jq -r '.five_hour.utilization // empty' 2>/dev/null)
  session_resets_at=$(echo "$usage" | jq -r '.five_hour.resets_at // empty' 2>/dev/null)
  if [ -n "$session_pct" ]; then
    printf -v session_int "%.0f" "$session_pct" 2>/dev/null
    session_bar=$(build_bar_remaining "$session_int" 6)
    session_part="⏱"
    if [ -n "$session_resets_at" ]; then
      reset_ts=$(parse_iso8601 "$session_resets_at")
      now=$(date +%s)
      if [ -n "$reset_ts" ] && (( reset_ts > now )); then
        remaining=$(( reset_ts - now ))
        session_part="${session_part} $(format_duration "$remaining")"
      fi
    fi
    session_part="${session_part} ${session_bar} ${session_int}%"
    parts+=("$session_part")
  fi
fi

# --- Section 5: 📆 7-day weekly — usage %, time remaining, mini bar ---
if [ -n "$usage" ]; then
  weekly_pct=$(echo "$usage" | jq -r '.seven_day.utilization // empty' 2>/dev/null)
  weekly_resets_at=$(echo "$usage" | jq -r '.seven_day.resets_at // empty' 2>/dev/null)
  if [ -n "$weekly_pct" ]; then
    printf -v weekly_int "%.0f" "$weekly_pct" 2>/dev/null
    weekly_bar=$(build_bar_remaining "$weekly_int" 4)
    weekly_part="📆"
    if [ -n "$weekly_resets_at" ]; then
      weekly_reset_ts=$(parse_iso8601 "$weekly_resets_at")
      now=$(date +%s)
      if [ -n "$weekly_reset_ts" ] && (( weekly_reset_ts > now )); then
        weekly_remaining=$(( weekly_reset_ts - now ))
        weekly_part="${weekly_part} $(format_duration "$weekly_remaining")"
      fi
    fi
    weekly_part="${weekly_part} ${weekly_bar} ${weekly_int}%"
    parts+=("$weekly_part")
  fi
fi

# --- Section 6: 💳 extra usage — spend/budget, color by % of budget used ---
if [ -n "$usage" ]; then
  extra_enabled=$(echo "$usage" | jq -r '.extra_usage.is_enabled // false' 2>/dev/null)
  if [ "$extra_enabled" = "true" ]; then
    extra_used=$(echo "$usage" | jq -r '.extra_usage.used_credits // 0' 2>/dev/null)
    extra_limit=$(echo "$usage" | jq -r '.extra_usage.monthly_limit // 0' 2>/dev/null)
    extra_used_fmt=$(python3 -c "print(f'\${${extra_used}/100:.2f}')" 2>/dev/null)
    extra_limit_fmt=$(python3 -c "
v = ${extra_limit}/100
print(f'\${v:.0f}' if v == int(v) else f'\${v:.2f}')" 2>/dev/null)
    # Compute % of budget used for color selection
    if [ -n "$extra_limit" ] && (( extra_limit > 0 )); then
      extra_pct=$(python3 -c "print(int(${extra_used}/${extra_limit}*100))" 2>/dev/null)
    else
      extra_pct=0
    fi
    printf -v extra_int "%.0f" "${extra_pct:-0}" 2>/dev/null
    local_color="$COLOR_GREEN"
    (( extra_int >= 50 )) && local_color="$COLOR_YELLOW"
    (( extra_int >= 80 )) && local_color="$COLOR_RED"
    parts+=("💳 ${local_color}${extra_used_fmt}/${extra_limit_fmt}\033[0m")
  fi
fi

# --- Assemble with · separator ---
# First part (model) already included; join remaining with separator
line="${parts[0]}"
for part in "${parts[@]:1}"; do
  line="${line} · ${part}"
done

printf '%b\n' "$line"
