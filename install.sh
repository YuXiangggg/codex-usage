#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WAYBAR_DIR="${WAYBAR_CONFIG_DIR:-$HOME/.config/waybar}"
SCRIPT_SRC="$ROOT_DIR/codex-usage.sh"
CSS_SRC="$ROOT_DIR/codex-waybar.css"
SCRIPT_DST="$WAYBAR_DIR/codex-usage.sh"
CSS_DST="$WAYBAR_DIR/codex-usage.css"

mkdir -p "$WAYBAR_DIR"

install -m 755 "$SCRIPT_SRC" "$SCRIPT_DST"
install -m 644 "$CSS_SRC" "$CSS_DST"

if [[ -f "$WAYBAR_DIR/style.css" ]]; then
  cp "$WAYBAR_DIR/style.css" "$WAYBAR_DIR/style.css.bak"
fi
if [[ -f "$WAYBAR_DIR/modules.json" ]]; then
  cp "$WAYBAR_DIR/modules.json" "$WAYBAR_DIR/modules.json.bak"
fi
if [[ -f "$WAYBAR_DIR/config.jsonc" ]]; then
  cp "$WAYBAR_DIR/config.jsonc" "$WAYBAR_DIR/config.jsonc.bak"
fi

python3 - <<'PY'
from pathlib import Path

style_path = Path.home() / '.config/waybar/style.css'
import_line = '@import "./codex-usage.css";'

if style_path.exists():
    text = style_path.read_text(encoding='utf-8')
    if import_line not in text:
        lines = text.splitlines()
        insert_at = 0
        for idx, line in enumerate(lines):
            if line.strip().startswith('@import'):
                insert_at = idx + 1
        lines.insert(insert_at, import_line)
        style_path.write_text('\n'.join(lines) + '\n', encoding='utf-8')
else:
    style_path.write_text(import_line + '\n', encoding='utf-8')
PY

python3 - <<'PY'
import json
import os
import re
from pathlib import Path

def load_jsonc(path):
    text = path.read_text(encoding='utf-8')
    text = re.sub(r'/\*.*?\*/', '', text, flags=re.S)
    text = re.sub(r'//.*', '', text)
    return json.loads(text or '{}')

def dump_json(path, data):
    path.write_text(json.dumps(data, indent=2) + '\n', encoding='utf-8')

waybar_dir = Path.home() / '.config/waybar'
modules_path = waybar_dir / 'modules.json'
config_path = waybar_dir / 'config.jsonc'
script_path = waybar_dir / 'codex-usage.sh'

modules_data = load_jsonc(modules_path) if modules_path.exists() else {}
group = modules_data.get('group/codex', {})
group['orientation'] = 'horizontal'
group['modules'] = [
    'custom/codex-week-time',
    'custom/codex-week-usage',
    'custom/codex-5h-time',
    'custom/codex-5h-usage',
]
modules_data['group/codex'] = group

def module_entry(mode):
    return {
        'exec': f"{script_path} --mode {mode}",
        'return-type': 'json',
        'interval': 60,
        'format': '{text}',
        'tooltip': True,
    }

modules_data['custom/codex-week-time'] = module_entry('week-time')
modules_data['custom/codex-week-usage'] = module_entry('week-usage')
modules_data['custom/codex-5h-time'] = module_entry('5h-time')
modules_data['custom/codex-5h-usage'] = module_entry('5h-usage')

dump_json(modules_path, modules_data)

config_data = load_jsonc(config_path) if config_path.exists() else {}
modules_right = config_data.get('modules-right', [])
if 'group/codex' not in modules_right:
    if 'group/extras' in modules_right:
        index = modules_right.index('group/extras') + 1
        modules_right.insert(index, 'group/codex')
    else:
        modules_right.append('group/codex')
config_data['modules-right'] = modules_right

dump_json(config_path, config_data)
PY

printf '%s\n' "Installed codex-waybar module." "Restart Waybar to apply changes."
