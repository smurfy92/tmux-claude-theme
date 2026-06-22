#!/usr/bin/env bash
# Hook Claude Code -> écrit l'état de la session dans ~/.claude/state/<pane>.
#
# L'état voulu est passé en argument ($1) par la config settings.json :
#   work | waiting | idle | end
# Le pane tmux est identifié via $TMUX_PANE (hérité de l'environnement du
# terminal où tourne Claude Code). Hors tmux -> on ne fait rien.
#
# Le JSON du hook arrive sur stdin (session_id, cwd, hook_event_name…) ; on ne
# l'exploite pas ici (l'état est déjà déterminé par l'argument), mais on draine
# stdin pour ne pas bloquer l'émetteur.
#
# Mappage des événements (voir settings.json / setup-hooks.sh) :
#   UserPromptSubmit, PreToolUse -> work
#   PermissionRequest            -> waiting
#   Stop                         -> idle
#   SessionEnd                   -> end (supprime le fichier)

set -u

state="${1:-}"
cat >/dev/null 2>&1 || true   # draine stdin

pane="${TMUX_PANE:-}"
[ -z "$pane" ] && exit 0       # pas dans un pane tmux -> rien à signaler

dir="$HOME/.claude/state"
mkdir -p "$dir"
file="$dir/${pane}"

case "$state" in
  work|waiting|idle)
    # ligne 1 = état, ligne 2 = epoch (pour une éventuelle gestion de péremption)
    { printf '%s\n' "$state"; date +%s; } > "$file"
    ;;
  end)
    rm -f "$file"
    ;;
  *)
    : # argument inconnu -> no-op
    ;;
esac

exit 0
