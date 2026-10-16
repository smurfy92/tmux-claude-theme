#!/usr/bin/env bash
# Tests de cc-states.sh sur fixtures, sans serveur tmux : un faux `tmux`
# (tests/bin/tmux) est placé en tête du PATH et lit tests/fixtures/<cas>/.
#
# Un cas = un dossier avec :
#   windows.txt      lignes session|index|pane_id|commande|titre
#   screens/<pane>.txt   contenu affiché du pane (optionnel)
#   state/<pane>     fichiers de hook, « NOW-<n> » remplacé par l'epoch courant - n
#   hook-broken      (marqueur) simule un lien de hook cassé
#   panes.txt        lignes session:index|pane_id|périmètre|pid (optionnel) ;
#                    « ALIVE » devient le PID de ce script (vivant), « DEAD » un PID
#                    hors plage usuelle (jamais vivant)
#   expected.txt     badge attendu (ligne 1) puis « S:I=état » et, pour un cas avec
#                    panes.txt, « S:I option=valeur », triés
#
# Usage : ./test.sh            (exit 1 si un cas échoue)

set -u
cd "$(dirname "$0")" || exit 1
ROOT="$PWD"
export PATH="$ROOT/tests/bin:$PATH"
now="$(date +%s)"
fail=0; total=0

for dir in "$ROOT"/tests/fixtures/*/; do
  name="$(basename "$dir")"
  total=$((total + 1))
  tmp="$(mktemp -d)"
  export HOME="$tmp" CC_FIXTURE="$dir" CC_RESULT="$tmp/result"
  mkdir -p "$HOME/.claude/state" "$HOME/.claude/hooks"
  : > "$CC_RESULT"

  if [ -d "$dir/state" ]; then
    for f in "$dir"/state/*; do
      [ -e "$f" ] || continue
      awk -v now="$now" '/^NOW-[0-9]+$/ { print now - substr($0, 5); next } { print }' "$f" \
        > "$HOME/.claude/state/$(basename "$f")"
    done
  fi
  [ -e "$dir/hook-broken" ] && ln -s /nonexistent "$HOME/.claude/hooks/cc-state-hook.sh"

  # Options de pane du cas : le faux tmux les sert à `list-panes`.
  unset CC_FIXTURE_PANES
  if [ -e "$dir/panes.txt" ]; then
    awk -F'|' -v OFS='|' -v alive="$$" -v dead=2147483000 \
      '$4 == "ALIVE" { $4 = alive } $4 == "DEAD" { $4 = dead } { print }' \
      "$dir/panes.txt" > "$tmp/panes.txt"
    export CC_FIXTURE_PANES="$tmp/panes.txt"
  fi

  badge="$("$ROOT/scripts/cc-states.sh")"
  { printf '%s\n' "$badge"; sort "$CC_RESULT"; } > "$tmp/actual"
  if diff -u "$dir/expected.txt" "$tmp/actual" > "$tmp/diff"; then
    echo "ok   $name"
  else
    echo "FAIL $name"; sed 's/^/     /' "$tmp/diff"; fail=$((fail + 1))
  fi
  # Effet de bord vérifiable : fichiers d'état restants après purge.
  if [ -e "$dir/expected-state.txt" ]; then
    (cd "$HOME/.claude/state" && find . -mindepth 1 | sed "s|^\./||" | sort) > "$tmp/state-actual"
    if ! diff -u "$dir/expected-state.txt" "$tmp/state-actual" > "$tmp/diff2"; then
      echo "FAIL $name (fichiers d'état)"; sed 's/^/     /' "$tmp/diff2"; fail=$((fail + 1))
    fi
  fi
  rm -rf "$tmp"
done

echo "$((total - fail))/$total cas OK"
[ "$fail" -eq 0 ]
