#!/usr/bin/env bash
# Installe la conf tmux + les scripts d'état Claude.
# Idempotent : sauvegarde toute conf existante, puis crée des liens symboliques
# vers ce repo (les futures éditions dans le repo sont donc prises en compte).
#
# Usage : ./install.sh

set -eu

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
STAMP="$(date +%Y%m%d-%H%M%S)"

link() {
  # link <source-dans-repo> <destination>
  src="$1"; dst="$2"
  mkdir -p "$(dirname "$dst")"
  if [ -e "$dst" ] && [ ! -L "$dst" ]; then
    echo "  sauvegarde de $dst -> $dst.bak.$STAMP"
    mv "$dst" "$dst.bak.$STAMP"
  fi
  ln -sfn "$src" "$dst"
  echo "  lien : $dst -> $src"
}

echo "→ Liens de configuration"
link "$REPO_DIR/tmux.conf"          "$HOME/.tmux.conf"
link "$REPO_DIR/scripts/cc-states.sh" "$HOME/.tmux/scripts/cc-states.sh"
link "$REPO_DIR/scripts/cc-jump.sh"   "$HOME/.tmux/scripts/cc-jump.sh"
chmod +x "$REPO_DIR/scripts/"*.sh

# tmux Plugin Manager (tpm) — requis pour les plugins (resurrect/continuum/sensible).
TPM_DIR="$HOME/.tmux/plugins/tpm"
if [ ! -d "$TPM_DIR" ]; then
  echo "→ Installation de tpm"
  git clone --depth 1 https://github.com/tmux-plugins/tpm "$TPM_DIR"
else
  echo "→ tpm déjà présent"
fi

# Hooks Claude Code (signal d'état fiable). Optionnel : nécessite jq et modifie
# ~/.claude/settings.json (avec backup). Non bloquant si ça échoue — l'heuristique
# titre/contenu prend le relais.
echo "→ Hooks Claude Code (état des sessions)"
if "$REPO_DIR/setup-hooks.sh"; then
  :
else
  echo "  ⚠ hooks non configurés (jq manquant ?) — la détection de base fonctionne quand même"
fi

echo ""
echo "✓ Installé. Étapes finales :"
echo "  1) Ouvre tmux (ou recharge :  tmux source-file ~/.tmux.conf )"
echo "  2) Installe les plugins :     prefix + I   (prefix = backtick \` par défaut)"
echo ""
echo "  Raccourcis clés :"
echo "    prefix + w  -> choose-tree coloré par état Claude"
echo "    prefix + a  -> saute à la prochaine session Claude en attente"
