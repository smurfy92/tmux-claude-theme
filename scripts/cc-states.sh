#!/usr/bin/env bash
# Classe chaque window tmux selon l'état de la session Claude Code qu'elle contient,
# stocke le résultat dans l'option window @cc_state (lue par choose-tree),
# ET imprime sur stdout un badge récapitulatif pour la status bar.
#
# États :
#   waiting -> Claude attend une réponse de TA part (menu / confirmation à l'écran)
#   work    -> Claude travaille (spinner braille animé dans le titre)
#   idle    -> Claude a fini / au repos (✳ mais pas de prompt en attente)
#   shell   -> pas de session Claude (shell zsh/bash)
#
# Le titre seul ne distingue pas waiting d'idle (les deux montrent ✳),
# donc pour les panes ✳ on capture le bas de l'écran et on cherche la
# signature d'un prompt interactif Claude Code.
#
# Double usage :
#   - bind w/s : run-shell "...cc-states.sh >/dev/null"  -> pose @cc_state avant choose-tree
#   - status-right : #(...cc-states.sh)                  -> rafraîchit + affiche le badge (toutes les 5s)

set -u

waiting=0
work=0

# IMPORTANT : process substitution (et non un pipe) pour que les compteurs
# survivent — un « ... | while » exécuterait la boucle dans un sous-shell.
while IFS='|' read -r sess idx cmd title; do
  case "$title" in
    "✳"*)
      # ✳ = Claude au repos OU en attente d'input -> on regarde le contenu.
      content="$(tmux capture-pane -t "${sess}:${idx}" -p -S -25 2>/dev/null)"
      if printf '%s' "$content" | grep -qE 'Esc to cancel|Enter to select|Do you want|❯ [0-9]'; then
        state="waiting"; waiting=$((waiting + 1))
      else
        state="idle"
      fi
      ;;
    "")
      state="shell"
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
done < <(tmux list-windows -a -F '#{session_name}|#{window_index}|#{pane_current_command}|#{pane_title}')

# Badge status bar : rien quand il n'y a personne en attente / au travail.
# - waiting : pastille rouge pleine + clignotement (impossible à louper)
# - work    : compteur pêche discret
out=""
[ "$waiting" -gt 0 ] && out="#[fg=#1e1e2e]#[bg=#f38ba8]#[bold]#[blink] ◆ ${waiting} #[default] "
[ "$work"    -gt 0 ] && out="${out}#[fg=#fab387]◐ ${work}#[default] "
printf '%s' "$out"
