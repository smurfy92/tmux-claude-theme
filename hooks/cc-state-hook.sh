#!/usr/bin/env bash
# Hook Claude Code -> écrit l'état de la session dans ~/.claude/state/<pane>.
#
# Arguments (depuis settings.json) :
#   $1 = état voulu : work | waiting | idle | end
#   $2 = "refresh" (optionnel) -> force la status bar tmux à se rafraîchir TOUT DE
#        SUITE (mode push), au lieu d'attendre le cycle de 5 s. À ne mettre que sur
#        les transitions qui changent le badge (pas sur PreToolUse, trop fréquent).
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
#   SessionStart (startup/resume/clear/compact) -> idle (reset après /clear)
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

# Mode push : rafraîchit la status bar de tous les clients attachés immédiatement.
# (refresh-client -S re-exécute le #() de la status bar -> cc-states.sh tourne.)
if [ "${2:-}" = "refresh" ]; then
  tmux list-clients -F '#{client_name}' 2>/dev/null | while IFS= read -r c; do
    tmux refresh-client -S -t "$c" 2>/dev/null || true
  done
fi

exit 0
