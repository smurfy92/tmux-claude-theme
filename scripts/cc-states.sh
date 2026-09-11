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
HOOK_DST="$HOME/.claude/hooks/cc-state-hook.sh"
STALE_AFTER=3600   # secondes avant de ne plus faire confiance à un hook work/waiting
now="$(date +%s)"
waiting=0
work=0

# Garde-fou : si le lien du hook est cassé (ex. dépôt déplacé), les hooks Claude
# Code échouent en silence et les états se figent sans qu'on s'en aperçoive.
# On l'affiche dans la barre plutôt que de laisser dériver (-x suit le symlink).
hook_broken=0
[ -L "$HOOK_DST" ] && [ ! -x "$HOOK_DST" ] && hook_broken=1

# Purge des fichiers d'état orphelins : le hook `end` les supprime à la fin propre
# d'une session, mais un crash ou un pane tué laisse des restes. On retire ceux
# dont le pane n'existe plus dans le serveur tmux.
if [ -d "$STATE_DIR" ]; then
  live_panes=" $(tmux list-panes -a -F '#{pane_id}' 2>/dev/null | tr '\n' ' ') "
  for f in "$STATE_DIR"/%*; do
    [ -e "$f" ] || continue
    case "$live_panes" in
      *" ${f##*/} "*) ;;
      *) rm -f "$f" ;;
    esac
  done
fi

# Heuristique « tour fini par une question » sur le contenu d'un pane.
# Renvoie 0 (vrai) si la dernière prose de Claude contient un « ? ».
ended_is_question() {
  printf '%s\n' "$1" \
    | grep -vE '^[[:space:]]*[─❯✻※✔◼◻☐•]' \
    | grep -vE '🤖|💰|Model:|cwd:|Context:|Ctx\(u\)|Weekly:|auto mode|[0-9]+ tasks|/goal|Session:|Cost:|for shortcuts|to navigate|to select|to cancel|How is Claude doing|Tips for getting started|Whats new|release-notes' \
    | grep -vE '^[[:space:]]*$' \
    | tail -3 | grep -q '?'
}

# IMPORTANT : process substitution (et non un pipe) pour que les compteurs survivent.
while IFS='|' read -r sess idx pane cmd title; do
  # État éventuel posé par les hooks Claude Code pour ce pane.
  hookstate=""
  if [ -r "$STATE_DIR/$pane" ]; then
    { read -r hookstate; read -r hookts; } < "$STATE_DIR/$pane"
    # Péremption : un `work`/`waiting` sans hook depuis plus de STALE_AFTER s est
    # presque sûrement un événement manqué (Stop perdu, session figée…). On l'ignore
    # et on retombe sur l'heuristique. `idle` reste fiable quel que soit son âge.
    case "$hookstate" in
      work|waiting)
        if [ $((now - ${hookts:-0})) -gt "$STALE_AFTER" ]; then hookstate=""; fi ;;
    esac
  fi

  case "$title" in
    "")
      # Titre vide -> shell (on ignore un éventuel fichier d'état périmé).
      state="shell"
      ;;
    "✳"*)
      # Tour terminé. Ordre de confiance :
      #   1. hook waiting/work  -> fiable, on prend tel quel.
      #   2. MENU interactif à l'écran (Esc to cancel / ❯ 1. …) -> vraie attente
      #      bloquante, prime même sur un hook `idle` (un menu est réellement ouvert).
      #   3. hook idle  -> Stop/SessionStart fiable : idle. On NE se fie PLUS au simple
      #      « ? » (faux positifs : « ? for shortcuts », question déjà répondue…).
      #   4. aucun hook (session hors périmètre) -> fallback : prose finissant par
      #      « ? » = attente probable.
      if [ "$hookstate" = "waiting" ]; then
        state="waiting"; waiting=$((waiting + 1))
      elif [ "$hookstate" = "work" ]; then
        state="work"; work=$((work + 1))
      else
        content="$(tmux capture-pane -t "${sess}:${idx}" -p 2>/dev/null)"
        if printf '%s' "$content" | grep -qE 'Esc to cancel|Enter to select|Do you want|❯ [0-9]'; then
          state="waiting"; waiting=$((waiting + 1))
        elif [ "$hookstate" = "idle" ]; then
          state="idle"
        elif ended_is_question "$content"; then
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
[ "$hook_broken" -eq 1 ] && out="${out}#[fg=#f9e2af]#[bold]⚠ hook#[nobold]#[default] "
printf '%s' "$out"
