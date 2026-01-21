#!/usr/bin/env bash
set -euo pipefail

# Waybar module: show Codex 5h + weekly usage/time
# Data source: https://chatgpt.com/backend-api/codex/usage

AUTH_FILE="${CODEX_AUTH_FILE:-$HOME/.codex/auth.json}"
API_BASE="${CODEX_CHATGPT_BASE:-https://chatgpt.com}"
URL="$API_BASE/backend-api/codex/usage"

MODE="5h-usage"
if [[ "${1:-}" == "--mode" && -n "${2:-}" ]]; then
  MODE="$2"
  shift 2
fi
export CODEX_USAGE_MODE="$MODE"

python3 - <<'PY'
import base64
import json
import os
import ssl
import sys
import time
import urllib.parse
import urllib.request
from datetime import datetime, timezone

auth_file = os.environ.get('CODEX_AUTH_FILE') or os.path.expanduser('~/.codex/auth.json')
base = os.environ.get('CODEX_CHATGPT_BASE') or 'https://chatgpt.com'
url = base.rstrip('/') + '/backend-api/codex/usage'
token_url = 'https://auth.openai.com/oauth/token'
client_id = 'app_EMoamEEZ73f0CkXaXp7hrann'

try:
    auth = json.loads(open(auth_file, 'r', encoding='utf-8').read())
    token = auth['tokens']['access_token']
except Exception as e:
    print(json.dumps({"text":" ","tooltip":f"Failed to read {auth_file}: {e}"}))
    sys.exit(0)


def decode_jwt(token_value):
    try:
        parts = token_value.split('.')
        if len(parts) != 3:
            return None
        payload = parts[1]
        padding = '=' * (-len(payload) % 4)
        decoded = base64.urlsafe_b64decode(payload + padding).decode('utf-8')
        return json.loads(decoded)
    except Exception:
        return None


def token_expired(token_value, leeway_seconds=60):
    payload = decode_jwt(token_value)
    if not payload:
        return False
    exp = payload.get('exp')
    if not exp:
        return False
    return int(exp) <= int(datetime.now(timezone.utc).timestamp()) + leeway_seconds


def refresh_access_token(auth_state):
    refresh_token = auth_state.get('tokens', {}).get('refresh_token')
    if not refresh_token:
        return None, 'Missing refresh token'
    body = urllib.parse.urlencode({
        'grant_type': 'refresh_token',
        'refresh_token': refresh_token,
        'client_id': client_id,
    }).encode('utf-8')
    request = urllib.request.Request(
        token_url,
        data=body,
        headers={'Content-Type': 'application/x-www-form-urlencoded'},
    )
    try:
        with urllib.request.urlopen(request, context=ctx, timeout=10) as resp:
            data = json.loads(resp.read())
    except Exception as e:
        return None, f'Token refresh failed: {e}'
    access = data.get('access_token')
    if not access:
        return None, f'Token refresh failed: {data}'
    auth_state.setdefault('tokens', {})['access_token'] = access
    if data.get('refresh_token'):
        auth_state['tokens']['refresh_token'] = data['refresh_token']
    if data.get('id_token'):
        auth_state['tokens']['id_token'] = data['id_token']
    auth_state['last_refresh'] = datetime.now(timezone.utc).isoformat()
    try:
        with open(auth_file, 'w', encoding='utf-8') as handle:
            json.dump(auth_state, handle, indent=2, sort_keys=True)
            handle.write('\n')
    except Exception as e:
        return None, f'Failed to write {auth_file}: {e}'
    return access, None


headers = {
    'Authorization': f'Bearer {token}',
    'Accept': 'application/json',
    'User-Agent': 'waybar-codex-usage/0.2',
}
ctx = ssl.create_default_context()

if token_expired(token):
    refreshed, error = refresh_access_token(auth)
    if refreshed:
        token = refreshed
        headers['Authorization'] = f'Bearer {token}'
    elif error:
        print(json.dumps({"text":" ","tooltip":error}))
        sys.exit(0)

try:
    req = urllib.request.Request(url, headers=headers)
    with urllib.request.urlopen(req, context=ctx, timeout=10) as resp:
        data = json.loads(resp.read())
except Exception as e:
    if 'HTTP Error 401' in str(e):
        refreshed, error = refresh_access_token(auth)
        if refreshed:
            headers['Authorization'] = f'Bearer {refreshed}'
            try:
                req = urllib.request.Request(url, headers=headers)
                with urllib.request.urlopen(req, context=ctx, timeout=10) as resp:
                    data = json.loads(resp.read())
            except Exception as retry_error:
                print(json.dumps({"text":" ","tooltip":f"Failed to fetch {url}: {retry_error}"}))
                sys.exit(0)
        else:
            print(json.dumps({"text":" ","tooltip":error or f"Failed to fetch {url}: {e}"}))
            sys.exit(0)
    else:
        print(json.dumps({"text":" ","tooltip":f"Failed to fetch {url}: {e}"}))
        sys.exit(0)

rate = data.get('rate_limit') or {}
primary = rate.get('primary_window') or {}
secondary = rate.get('secondary_window') or {}

# Remaining % is (100 - used_percent)
prim_used = int(primary.get('used_percent') or 0)
sec_used = int(secondary.get('used_percent') or 0)
prim_left = max(0, 100 - prim_used)
sec_left = max(0, 100 - sec_used)


def fmt_reset(ts):
    if not ts:
        return 'unknown'
    try:
        dt = datetime.fromtimestamp(int(ts), tz=timezone.utc).astimezone()
        return dt.strftime('%a %H:%M')
    except Exception:
        return 'unknown'


prim_reset = fmt_reset(primary.get('reset_at'))
sec_reset = fmt_reset(secondary.get('reset_at'))


def time_elapsed_percent(window, fallback_seconds):
    now = int(time.time())
    window_seconds = window.get('window_seconds') or window.get('window') or fallback_seconds
    reset_at = window.get('reset_at')
    if not reset_at or not window_seconds:
        return 0
    try:
        start_at = int(reset_at) - int(window_seconds)
        if start_at <= now <= int(reset_at):
            return int(round(((now - start_at) / int(window_seconds)) * 100))
        if now > int(reset_at):
            return 100
    except Exception:
        return 0
    return 0


def step_percent(value):
    step = int(round(value / 10.0) * 10)
    return max(0, min(100, step))


primary_time_used = time_elapsed_percent(primary, 5 * 60 * 60)
secondary_time_used = time_elapsed_percent(secondary, 7 * 24 * 60 * 60)

usage_step = step_percent(prim_used)
week_usage_step = step_percent(sec_used)
time_step = step_percent(primary_time_used)
week_time_step = step_percent(secondary_time_used)
text = " "

tooltip = (
    f"Codex rate limits\n"
    f"5h window: {prim_left}% left (used {prim_used}%)\n"
    f"Resets: {prim_reset}\n\n"
    f"Weekly window: {sec_left}% left (used {sec_used}%)\n"
    f"Resets: {sec_reset}\n"
)

mode = os.environ.get('CODEX_USAGE_MODE', '5h-usage').lower()
is_limited = not rate.get('allowed', True) or rate.get('limit_reached', False)
if mode in ('5h-time', 'primary-time'):
    class_name = f"t{time_step}"
    percent_value = primary_time_used
elif mode in ('week-time', 'weekly-time', 'secondary-time'):
    class_name = f"t{week_time_step}"
    percent_value = secondary_time_used
elif mode in ('week-usage', 'weekly-usage', 'secondary-usage'):
    class_name = f"p{week_usage_step}"
    percent_value = sec_used
else:
    class_name = f"p{usage_step}"
    percent_value = prim_used

if mode.endswith('usage') and is_limited:
    class_name = f"limit {class_name}"

out = {
    "text": text,
    "alt": text,
    "tooltip": tooltip,
    "class": class_name,
    "percentage": percent_value,
}
print(json.dumps(out))
PY
