#!/usr/bin/env bash
# Câble les hooks Claude Code qui alimentent l'état des sessions (~/.claude/state/<pane>).
# Idempotent : sauvegarde settings.json, n'ajoute QUE si absent, préserve les hooks
# existants (ex: peon-ping). Relançable sans risque.
#
# Usage : ./setup-hooks.sh

set -eu

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
SETTINGS="$HOME/.claude/settings.json"
HOOK_SRC="$REPO_DIR/hooks/cc-state-hook.sh"
HOOK_DST="$HOME/.claude/hooks/cc-state-hook.sh"

command -v jq >/dev/null 2>&1 || { echo "✗ jq requis (brew install jq)"; exit 1; }

# 1. Lien symbolique du hook script.
mkdir -p "$HOME/.claude/hooks"
chmod +x "$HOOK_SRC"
ln -sfn "$HOOK_SRC" "$HOOK_DST"
echo "→ lien hook : $HOOK_DST -> $HOOK_SRC"

# 2. settings.json : créer si absent, toujours sauvegarder.
[ -f "$SETTINGS" ] || echo '{}' > "$SETTINGS"
cp "$SETTINGS" "$SETTINGS.bak.$(date +%Y%m%d-%H%M%S)"

# 3. Merge idempotent, un (événement -> état) à la fois.
add_hook() {
  event="$1"; state="$2"
  tmp="$(mktemp)"
  jq --arg ev "$event" --arg cmd "$HOOK_DST $state" '
    .hooks //= {} | .hooks[$ev] //= [] |
    ([ .hooks[$ev][].hooks[]?.command? // empty ] | any(test("cc-state-hook.sh"))) as $exists |
    if $exists then .
    else .hooks[$ev] += [ { matcher: "", hooks: [ { type: "command", command: $cmd, timeout: 5, async: true } ] } ]
    end
  ' "$SETTINGS" > "$tmp" && mv "$tmp" "$SETTINGS"
  echo "  $event -> $state"
}

echo "→ merge hooks dans $SETTINGS"
add_hook UserPromptSubmit work
add_hook PreToolUse        work
add_hook PermissionRequest waiting
add_hook Stop              idle
add_hook SessionEnd        end

# 4. Valider le JSON résultant.
if jq empty "$SETTINGS" 2>/dev/null; then
  echo "✓ settings.json valide"
else
  echo "✗ settings.json invalide — restaure la dernière sauvegarde .bak.*"
  exit 1
fi

echo ""
echo "ℹ Claude Code recharge sa config à chaud : les hooks s'activent immédiatement,"
echo "  y compris pour les sessions déjà ouvertes (à défaut, l'heuristique prend le relais)."
