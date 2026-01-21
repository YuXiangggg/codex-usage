# codex-waybar

Waybar module that renders four slim bars for Codex rate limits:

- Week time elapsed (secondary window progress)
- Week usage (secondary window used %)
- 5h time elapsed (primary window progress)
- 5h usage (primary window used %)

The module works for both vertical and horizontal Waybar layouts.

## Requirements

- Waybar
- Python 3
- A valid Codex auth file (default: `~/.codex/auth.json`)

## Install (automatic)

```sh
./install.sh
```

What the installer does:

- Copies `codex-usage.sh` to `~/.config/waybar/codex-usage.sh`
- Copies `codex-waybar.css` to `~/.config/waybar/codex-usage.css`
- Adds an `@import "./codex-usage.css";` line to `~/.config/waybar/style.css`
- Adds the `group/codex` module and four custom modules to `~/.config/waybar/modules.json`
- Adds `group/codex` to `modules-right` in `~/.config/waybar/config.jsonc`
- Creates backups of the touched files with `.bak` suffix

Restart Waybar after installing.

## Install (manual)

1. Copy `codex-usage.sh` to `~/.config/waybar/codex-usage.sh` and make it executable.
2. Copy `codex-waybar.css` to `~/.config/waybar/codex-usage.css` and import it from your `style.css`.
3. Add the module group and module definitions to your Waybar config:

```json
// config.jsonc
"modules-right": [
  "group/extras",
  "group/codex",
  "network"
]
```

```json
// modules.json
"group/codex": {
  "orientation": "horizontal",
  "modules": [
    "custom/codex-week-time",
    "custom/codex-week-usage",
    "custom/codex-5h-time",
    "custom/codex-5h-usage"
  ]
},
"custom/codex-week-time": {
  "exec": "~/.config/waybar/codex-usage.sh --mode week-time",
  "return-type": "json",
  "interval": 60,
  "format": "{text}",
  "tooltip": true
},
"custom/codex-week-usage": {
  "exec": "~/.config/waybar/codex-usage.sh --mode week-usage",
  "return-type": "json",
  "interval": 60,
  "format": "{text}",
  "tooltip": true
},
"custom/codex-5h-time": {
  "exec": "~/.config/waybar/codex-usage.sh --mode 5h-time",
  "return-type": "json",
  "interval": 60,
  "format": "{text}",
  "tooltip": true
},
"custom/codex-5h-usage": {
  "exec": "~/.config/waybar/codex-usage.sh --mode 5h-usage",
  "return-type": "json",
  "interval": 60,
  "format": "{text}",
  "tooltip": true
}
```

Restart Waybar after updating the config.

## Configuration

Environment variables:

- `CODEX_AUTH_FILE`: path to the auth file (default: `~/.codex/auth.json`)
- `CODEX_CHATGPT_BASE`: override API base URL (default: `https://chatgpt.com`)

## Notes

- The bars are color-coded using your Waybar theme colors: week time uses `@color6`, week usage uses `@color3`, 5h time uses `@color4`, 5h usage uses `@color2`, and limit states use `@color1`.
- For horizontal Waybar, the bars automatically switch to horizontal fills.

## License

MIT
