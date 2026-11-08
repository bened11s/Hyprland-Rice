#!/usr/bin/env bash
# Nur installierte Agenten starten; niemals etwas automatisch installieren.
set -eu
export PATH="$HOME/.local/bin:$HOME/.claude/local:$HOME/.npm-global/bin:$HOME/.bun/bin:$PATH"
names=()
commands=()
for agent in opencode claude; do
    if executable=$(command -v "$agent"); then
        case "$agent" in
            opencode) names+=("OpenCode") ;;
            claude) names+=("Claude Code") ;;
        esac
        commands+=("$executable")
    fi
done
if [[ "${1:-}" == --list ]]; then
    if ((${#names[@]})); then printf '%s\n' "${names[@]}"; fi
    exit 0
fi
if ((${#names[@]} == 0)); then
    notify-send 'KI-Agent' 'Weder OpenCode noch Claude Code ist installiert.' || true
    exit 1
fi
index=0
if ((${#names[@]} > 1)); then
    # Abbrechen startet keinen Agenten.
    selection=$(printf '%s\n' "${names[@]}" | fuzzel --dmenu --prompt 'KI-Agent: ') || exit 0
    case "$selection" in
        "${names[0]}") index=0 ;;
        "${names[1]}") index=1 ;;
        *) exit 0 ;;
    esac
fi
cd "$HOME"
if command -v kitty >/dev/null; then
    exec kitty --title "${names[index]}" "${commands[index]}"
elif command -v konsole >/dev/null; then
    exec konsole -e "${commands[index]}"
elif command -v xterm >/dev/null; then
    exec xterm -e "${commands[index]}"
fi
notify-send 'KI-Agent' 'Kein unterstütztes Terminal gefunden (Kitty, Konsole, Xterm).' || true
exit 1
