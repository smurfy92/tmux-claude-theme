#!/usr/bin/env bash
# Classe chaque window tmux selon l'état de la session Claude Code qu'elle contient,
# stocke le résultat dans l'option window @cc_state (lue par choose-tree),
# ET imprime sur stdout un badge récapitulatif pour la status bar.
#
# États : waiting | work | idle | shell
#
# Deux sources, combinées (la plus fiable d'abord) :
#  A) HOOKS Claude Code -> fichier ~/.claude/state/<pane_id> (voir hooks/cc-state-hook.sh
#     + setup-hooks.sh). Donne un signal `waiting` fiable et instantané sur les
#     demandes de PERMISSION. Présent seulement pour les sessions démarrées après
#     l'installation des hooks.
#  B) HEURISTIQUE titre/contenu (fallback universel, marche sans hooks) :
#     - titre braille animé        -> work
#     - titre vide / shell zsh      -> shell
#     - titre ✳ -> tour terminé : on regarde le contenu pour distinguer
#         * menu interactif (Esc to cancel / ❯ 1.)         -> waiting
#         * dernière prose finissant par une question « ? » -> waiting (probable)
#         * sinon                                            -> idle
#
# Le cas « tour fini par une question libre » n'est PAS distinguable par les hooks
# (Stop se déclenche pareil que la session soit finie ou en attente d'une réponse) :
# c'est la lacune signalée à Anthropic, couverte ici par l'heuristique (B).
#
# Double usage :
#   - bind w/s : run-shell "...cc-states.sh >/dev/null"  -> pose @cc_state avant choose-tree
#   - status-right : #(...cc-states.sh)                  -> rafraîchit + badge (toutes les 5s)

set -u

STATE_DIR="$HOME/.claude/state"
waiting=0
work=0

# Heuristique « tour fini par une question » sur le contenu d'un pane.
# Renvoie 0 (vrai) si la dernière prose de Claude contient un « ? ».
ended_is_question() {
  printf '%s\n' "$1" \
    | grep -vE '^[[:space:]]*[─❯✻※✔◼◻☐•]' \
    | grep -vE '🤖|💰|Model:|cwd:|Context:|Ctx\(u\)|Weekly:|auto mode|[0-9]+ tasks|/goal|Session:|Cost:' \
    | grep -vE '^[[:space:]]*$' \
    | tail -3 | grep -q '?'
}

# IMPORTANT : process substitution (et non un pipe) pour que les compteurs survivent.
while IFS='|' read -r sess idx pane cmd title; do
  # État éventuel posé par les hooks Claude Code pour ce pane.
  hookstate=""
  [ -r "$STATE_DIR/$pane" ] && hookstate="$(head -1 "$STATE_DIR/$pane" 2>/dev/null)"

  case "$title" in
    "")
      # Titre vide -> shell (on ignore un éventuel fichier d'état périmé).
      state="shell"
      ;;
    "✳"*)
      # Tour terminé (idle OU en attente). Hook `waiting` (permission) = fiable.
      if [ "$hookstate" = "waiting" ]; then
        state="waiting"; waiting=$((waiting + 1))
      elif [ "$hookstate" = "work" ]; then
        state="work"; work=$((work + 1))
      else
        content="$(tmux capture-pane -t "${sess}:${idx}" -p 2>/dev/null)"
        if printf '%s' "$content" | grep -qE 'Esc to cancel|Enter to select|Do you want|❯ [0-9]' \
           || ended_is_question "$content"; then
          state="waiting"; waiting=$((waiting + 1))
        else
          state="idle"
        fi
      fi
      ;;
    *)
      # Titre non vide ne commençant pas par ✳.
      # Shell pur -> shell ; sinon session Claude avec spinner braille -> work.
      case "$cmd" in
        zsh|bash|fish|sh|-zsh|-bash) state="shell" ;;
        *)                           state="work"; work=$((work + 1)) ;;
      esac
      ;;
  esac

  tmux set -w -t "${sess}:${idx}" @cc_state "$state"
done < <(tmux list-windows -a -F '#{session_name}|#{window_index}|#{pane_id}|#{pane_current_command}|#{pane_title}')

# Badge status bar : rien quand il n'y a personne en attente / au travail.
# - waiting : pastille rouge pleine + clignotement (impossible à louper)
# - work    : compteur pêche discret
out=""
[ "$waiting" -gt 0 ] && out="#[fg=#1e1e2e]#[bg=#f38ba8]#[bold]#[blink] ◆ ${waiting} #[default] "
[ "$work"    -gt 0 ] && out="${out}#[fg=#fab387]◐ ${work}#[default] "
printf '%s' "$out"
