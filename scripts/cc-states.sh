#!/usr/bin/env bash
# Classe chaque window tmux selon l'état de la session Claude Code qu'elle contient,
# stocke le résultat dans l'option window @cc_state (lue par choose-tree),
# ET imprime sur stdout un badge récapitulatif pour la status bar.
#
# États :
#   waiting -> Claude attend une réponse de TA part
#   work    -> Claude travaille (spinner braille animé dans le titre)
#   idle    -> Claude a fini / au repos (✳ mais rien en attente)
#   shell   -> pas de session Claude (shell zsh/bash)
#
# Le titre seul ne distingue pas waiting d'idle (les deux montrent ✳). Pour les
# panes ✳ on capture l'écran et on cherche deux signaux d'attente :
#   1) prompt interactif explicite (menu / confirmation) -> certain
#   2) dernière prose de Claude se terminant par une question (« ? ») -> probable
# (1) couvre les sélecteurs ; (2) couvre « j'ai fait X, tu veux que je continue ? ».
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
      # ✳ = Claude au repos OU en attente d'input. On capture l'écran visible et on
      # cherche DEUX signaux d'attente (du plus sûr au plus heuristique) :
      content="$(tmux capture-pane -t "${sess}:${idx}" -p 2>/dev/null)"
      if printf '%s' "$content" | grep -qE 'Esc to cancel|Enter to select|Do you want|❯ [0-9]'; then
        # 1) Prompt interactif explicite (menu / confirmation) -> attente CERTAINE.
        state="waiting"; waiting=$((waiting + 1))
      elif printf '%s\n' "$content" \
            | grep -vE '^[[:space:]]*[─❯✻※✔◼◻☐•]' \
            | grep -vE '🤖|💰|Model:|cwd:|Context:|Ctx\(u\)|Weekly:|auto mode|[0-9]+ tasks|/goal|Session:|Cost:' \
            | grep -vE '^[[:space:]]*$' \
            | tail -3 | grep -q '?'; then
        # 2) Claude a fini son tour par une QUESTION en texte libre (prompt vide).
        #    On isole sa dernière prose (hors UI/status/tasklist) et on cherche un « ? »
        #    dans les 3 dernières lignes -> attente PROBABLE. Erreur volontairement
        #    du côté « signaler » : mieux vaut un faux waiting qu'un waiting manqué.
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
