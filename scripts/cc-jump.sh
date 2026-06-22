#!/usr/bin/env bash
# Saute vers la prochaine window où une session Claude attend ta réponse (waiting).
# Presse répétée -> cycle entre toutes les sessions en attente. Aucune -> message.
# Bindé sur prefix + a ("answer/attention") dans ~/.tmux.conf.
#
# POSIX-friendly (bash 3.2 macOS) : pas de mapfile, on passe par les paramètres
# positionnels.

set -u

# États frais avant de décider (au cas où le rafraîchissement status 5s soit en retard).
"$(dirname "$0")/cc-states.sh" >/dev/null 2>&1

cur="$(tmux display-message -p '#{session_name}:#{window_index}')"

# Collecte ordonnée des windows en attente.
waiting=""
while IFS= read -r w; do
  waiting="$waiting $w"
done < <(tmux list-windows -a -F '#{session_name}:#{window_index} #{@cc_state}' | awk '$2=="waiting"{print $1}')

# shellcheck disable=SC2086
set -- $waiting
if [ "$#" -eq 0 ]; then
  tmux display-message "Aucune session Claude en attente ✓"
  exit 0
fi

# Prochaine window après la courante (avec wrap). Si la courante n'est pas
# dans la liste, on prend la première.
next="$1"
found=0
for w in "$@"; do
  if [ "$found" = 1 ]; then next="$w"; break; fi
  [ "$w" = "$cur" ] && found=1
done

sess="${next%:*}"
tmux switch-client -t "$sess"
tmux select-window -t "$next"
