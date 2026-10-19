# tmux-claude-theme

Une configuration **tmux** sous palette **Catppuccin Mocha**, avec une fonctionnalité
maison : la **détection visuelle de l'état des sessions Claude Code** dans chaque
window — savoir d'un coup d'œil qui **attend ta réponse**, qui **travaille**, qui est
**au repos**.

> Pensé pour qui jongle avec plusieurs sessions Claude Code en parallèle (une par
> window tmux) et perd le fil de « laquelle a besoin de moi ? ».

---

## ✨ Ce que ça apporte

### 1. `choose-tree` coloré par état (`prefix + w`)
Chaque window est taguée selon l'état de la session Claude qu'elle contient :

| Badge | État | Signification |
|-------|------|---------------|
| `◆ waiting` | 🔴 rouge | **Claude attend une réponse de ta part** (menu / confirmation à l'écran) |
| `◐ work`    | 🟠 pêche | Claude travaille (spinner actif) |
| `● idle`    | 🟢 vert  | Claude a fini / au repos |
| `○ shell`   | ⚪ gris  | Pas de session Claude (shell) |

### 2. Badge compteur dans la status bar
En permanence, à droite :
- **`◆ N`** (pastille rouge clignotante) — N sessions Claude **t'attendent**
- **`◐ N`** (pêche) — N sessions **au travail**
- Rien ne s'affiche quand tout est calme (zéro bruit visuel).

### 3. Périmètre intersession (si le plugin est installé)
Quand une session Claude Code déclare un **périmètre** (un groupe de sessions qui
travaillent sur le même sujet), le thème l'affiche sur trois surfaces :
- **l'onglet** de la window courante : `3:intersession ⟨jules⟩` ;
- **`prefix + w` / `prefix + s`** : `⟨jules⟩` juste après le badge d'état ;
- **la status bar**, à droite : un badge lavande `janus 1 · jules 2` (nombre de
  sessions vivantes par périmètre, triés par nom), placé avant les compteurs `◆` / `◐`.

Sans le plugin, ou si aucune session ne déclare de périmètre, rien ne s'affiche.
Détails : [Périmètre intersession](#-périmètre-intersession).

### 4. Saut direct vers une session en attente (`prefix + a`)
Te téléporte sur la prochaine window où Claude attend. Presse répétée → cycle entre
toutes. Aucune en attente → message « tout est traité ✓ ».

### 5. Thème Catppuccin Mocha cohérent
Status bar, onglets, bordures de panes, menus, sélections, horloge — le tout en
Catppuccin Mocha, **sans plugin de thème** (réglages manuels, donc aucune dépendance
fragile). Les fenêtres inactives sont masquées de la status bar (navigation via
`choose-tree`).

---

## 🧠 Comment marche la détection d'état

La détection combine **deux couches**, de la plus fiable à la plus heuristique.

### Couche A — Hooks Claude Code (événementiel, fiable)
Claude Code déclenche des *hooks* qui héritent de l'environnement du terminal (donc
`$TMUX_PANE` est connu). Le hook [`hooks/cc-state-hook.sh`](hooks/cc-state-hook.sh)
écrit l'état dans `~/.claude/state/<pane_id>` :

| Événement Claude Code | → état |
|---|---|
| `UserPromptSubmit` | `work` + **push** |
| `PreToolUse` | `work` (sans push — trop fréquent) |
| `PermissionRequest` | `waiting` + **push** (Claude bloqué sur une permission — **100 % fiable**) |
| `Stop` | `idle` + **push** |
| `SessionEnd` | supprime le fichier + **push** |

**Mode push** : sur les transitions marquées **push**, le hook appelle
`tmux refresh-client -S`, ce qui ré-exécute le `#()` de la status bar
**immédiatement** — le badge se met à jour en ~100 ms au lieu d'attendre le cycle
de 5 s. `PreToolUse` (qui se déclenche des dizaines de fois par tour) est
volontairement exclu du push pour éviter une tempête de rafraîchissements.

Configuré par [`setup-hooks.sh`](setup-hooks.sh), qui **fusionne** ces hooks dans
`~/.claude/settings.json` sans toucher aux hooks existants.

### Couche B — Heuristique titre/contenu (fallback universel, sans hooks)
Claude écrit aussi l'état dans le **titre du pane** :
- `✳ …` → tour terminé : au repos **ou** en attente (le titre ne distingue pas !) ;
- `⠐ ⠂ ⠄ …` (braille animé) → spinner = `work` ;
- titre vide / hostname → `shell`.

Pour les panes `✳`, le script [`scripts/cc-states.sh`](scripts/cc-states.sh) **capture
le contenu** et cherche deux signaux d'attente :
1. un **prompt interactif** (`Esc to cancel`, `❯ 1.`, `Do you want`) → `waiting` ;
2. la **dernière prose de Claude se terminant par une question** (`?`) → `waiting`
   (couvre « j'ai fait X, tu veux que je continue ? »).

### Pourquoi les deux ?
Le cas **« tour fini par une question libre »** n'est détectable par **aucun hook** :
`Stop` se déclenche de la même façon que Claude ait fini ou qu'il attende une réponse
à sa question. C'est une vraie lacune de l'API (→ *feature request* à Anthropic),
couverte ici par l'heuristique (B). Les hooks (A) apportent un `waiting` fiable et
instantané sur les **permissions**, et un `work`/`idle` événementiel.

> ℹ️ En pratique, Claude Code recharge sa config à chaud : les hooks s'activent
> **immédiatement**, y compris pour les sessions déjà ouvertes. Et même si un hook
> manquait, la couche B (heuristique) prend toujours le relais.

Le résultat est stocké dans l'option window `@cc_state`, lue par `choose-tree`. Le
même passage calcule le périmètre intersession, voir
[Périmètre intersession](#-périmètre-intersession). Le
script tourne **toutes les 5 s** (status bar), **juste avant** chaque `choose-tree`,
et **à la demande** quand un hook déclenche un push (voir mode push ci-dessus).
Pas de daemon ni de polling permanent au-delà du rafraîchissement status.

---

## 🧭 Périmètre intersession

Le plugin **intersession** (dépôt `~/jules/intersession-plugin`, voir son `README.md`)
coordonne plusieurs sessions Claude Code qui partagent un même **périmètre** (par
exemple `jules` ou `janus`). Il pose, **sur chaque pane** où tourne une session, deux
options tmux :

| Option de pane | Contenu |
|---|---|
| `@cc_perimeter` | nom du périmètre (`^[a-z0-9][a-z0-9-]{0,31}$`) |
| `@cc_perimeter_pid` | PID de la session Claude Code |

Le thème **ne fait que lire** ces options, à chaque passage de
[`scripts/cc-states.sh`](scripts/cc-states.sh). Elles sont **de portée pane
uniquement** (`set -p`) : posée au niveau window, session ou global, une valeur serait
héritée par chaque pane de ce niveau et le plugin ne pourrait pas la retirer en
nettoyant ses propres panes.

**Règle d'affichage : jamais de valeur poussée affichée sans vérification.** Un pane
n'est retenu que si son nom est conforme **et** si son PID est **vivant** (`kill -0`,
repli sur `ps -p` pour un processus d'un autre utilisateur). Le calcul est refait
**toutes les 5 s** (et avant chaque `choose-tree`). Une session morte cesse d'afficher
son périmètre au passage suivant, même si l'option est restée sur le pane. Un
périmètre retiré ou changé par le plugin est repris au passage suivant ; si le plugin
n'a pas pu l'écrire, sa réconciliation corrige au prochain prompt. Un nom hors charte
est ignoré, ce qui évite aussi toute injection de format dans la status bar.

Le résultat est stocké dans l'option window `@cc_perimeter_ok` (format `⟨jules⟩`, ou
`⟨jules⟩ ⟨janus⟩` si une window scindée porte plusieurs périmètres, chaque nom une
seule fois), posée ou retirée sur **chaque** window à chaque passage, en un seul appel
tmux. Un pane listé par plusieurs sessions groupées n'est compté qu'une fois dans le
badge.

| Surface | Rendu |
|---|---|
| Onglet de la window courante | `3:intersession ⟨jules⟩` |
| `prefix + w` / `prefix + s` | `⟨jules⟩` après le badge d'état, avant le nom de la window |
| Status bar (droite) | badge lavande `janus 1 · jules 2` (triés par nom), absent si aucune session n'a de périmètre |

> Dans `choose-tree -s` (vue par sessions), une ligne de session résout l'option via la
> **window courante** de la session : elle n'affiche que le périmètre de cette window.
> Les lignes de pane héritent de la valeur de leur window (vérifié sur tmux 3.5a).

**Le thème fonctionne sans le plugin** : sans option `@cc_perimeter`, aucun périmètre
n'est affiché et rien d'autre ne change.

---

## 📦 Installation

### Prérequis
- **tmux ≥ 3.2** (testé sur 3.5a) — nécessaire pour `#{?}`, `#{m:}`, options `@user`.
- **git**, **bash**, **awk** (présents par défaut sur macOS / Linux).
- **jq** — uniquement pour la couche hooks (`setup-hooks.sh`). Sans lui, l'install
  continue et la détection heuristique fonctionne quand même.
- **Claude Code** — pour la couche hooks (facultative).
- Un terminal gérant les attributs `blink` et les glyphes Unicode (iTerm2, Kitty,
  WezTerm, Alacritty…).

### En une commande
```bash
git clone <url-de-ton-repo> ~/tmux-claude-theme
cd ~/tmux-claude-theme
./install.sh
```

L'installeur :
1. sauvegarde un éventuel `~/.tmux.conf` existant (`.bak.<timestamp>`) ;
2. crée des **liens symboliques** vers ce repo (`~/.tmux.conf`,
   `~/.tmux/scripts/cc-states.sh`, `~/.tmux/scripts/cc-jump.sh`) ;
3. installe **tpm** (tmux Plugin Manager) si absent ;
4. lance `setup-hooks.sh` (couche hooks Claude Code) — non bloquant si `jq` manque.

> **Dépôt déplacé ?** Les liens (`~/.tmux/scripts/*`, `~/.claude/hooks/cc-state-hook.sh`)
> sont absolus : si tu déplaces ce dossier, relance `./install.sh`. Un lien de hook
> cassé fait échouer les hooks en silence ; la status bar affiche alors `⚠ hook`.

> La couche hooks est facultative : tu peux relancer `./setup-hooks.sh` seul à tout
> moment, et la désactiver en retirant les entrées `cc-state-hook.sh` de
> `~/.claude/settings.json` (une sauvegarde `.bak.*` est créée à chaque run).

Puis, dans tmux :
```
prefix + I      # installe les plugins (resurrect, continuum, sensible)
```
> Le **prefix** par défaut de cette conf est le **backtick** `` ` `` (et non `C-b`).

---

## ⌨️ Raccourcis principaux

| Raccourci | Action |
|-----------|--------|
| `` ` `` | prefix (remplace `C-b`) |
| `prefix + w` | `choose-tree` coloré par état Claude |
| `prefix + s` | idem, vue par sessions |
| `prefix + a` | saute à la prochaine session Claude en attente |
| `prefix + r` | recharge `~/.tmux.conf` |
| `prefix + I` | installe / met à jour les plugins (tpm) |

---

## 🎨 Personnalisation

Les couleurs sont des hex Catppuccin Mocha (`#f38ba8` rouge, `#fab387` pêche,
`#a6e3a1` vert, `#b4befe` lavande, `#cba6f7` mauve…). Cherche-les dans `tmux.conf`
pour les ajuster.

### ⚠️ Le piège à connaître (virgules dans `#[...]`)
Dans un format conditionnel `#{?cond,vrai,faux}`, **n'utilise jamais de virgule à
l'intérieur d'un bloc de style** `#[...]` : tmux découpe le `#{?}` sur les virgules et
ça casse le rendu (du texte type `bold]` fuit à l'écran).

```tmux
# ❌ casse :   #{?cond,#[fg=#f38ba8,bold]X,}
# ✅ correct : #{?cond,#[fg=#f38ba8]#[bold]X,}
```

(Hors `#{?}`, dans une option simple comme `status-left`, la virgule est tolérée.)

---

## 🧩 Dépendances de plugins (via tpm)

- [`tmux-plugins/tpm`](https://github.com/tmux-plugins/tpm)
- [`tmux-plugins/tmux-sensible`](https://github.com/tmux-plugins/tmux-sensible)
- [`tmux-plugins/tmux-resurrect`](https://github.com/tmux-plugins/tmux-resurrect)
- [`tmux-plugins/tmux-continuum`](https://github.com/tmux-plugins/tmux-continuum) (auto-save des sessions)

Aucun plugin de thème : Catppuccin est appliqué manuellement.

---

## 🗂️ Structure

```
tmux-claude-theme/
├── tmux.conf            # la configuration (-> ~/.tmux.conf)
├── scripts/
│   ├── cc-states.sh     # classifie les windows (hooks + heuristique) + badge status bar
│   └── cc-jump.sh       # prefix + a : saute à la prochaine session en attente
├── hooks/
│   └── cc-state-hook.sh # hook Claude Code -> écrit ~/.claude/state/<pane_id>
├── setup-hooks.sh       # fusionne les hooks dans ~/.claude/settings.json (idempotent)
├── install.sh           # liens symboliques + tpm + setup-hooks
├── test.sh              # tests de cc-states.sh sur fixtures (faux tmux, sans serveur)
├── tests/
│   ├── bin/tmux         # le faux tmux lu par test.sh
│   └── fixtures/<cas>/  # windows.txt, panes.txt, screens/, state/, expected.txt
├── .github/workflows/ci.yml  # shellcheck + test.sh
└── README.md
```

---

## 🧪 Tests

```bash
./test.sh          # 20 cas : les 4 états, question libre, menu, hook périmé, purge, lien cassé, périmètre (13–20)
shellcheck scripts/*.sh hooks/*.sh install.sh setup-hooks.sh test.sh tests/bin/tmux
```

`test.sh` ne touche pas au serveur tmux : un faux `tmux` (`tests/bin/tmux`) est placé
en tête du `PATH` et répond à partir de `tests/fixtures/<cas>/`. Chaque cas décrit ses
windows (`windows.txt`), le contenu affiché des panes (`screens/`), les fichiers de
hook (`state/`, `NOW-<n>` = il y a *n* secondes), les options de périmètre des panes
(`panes.txt`, optionnel : lignes `session:index|pane_id|périmètre|pid`, où `ALIVE`
devient un PID vivant et `DEAD` un PID jamais vivant) et le résultat attendu
(`expected.txt` : badge, puis les lignes triées `S:I=état` pour `@cc_state` et, pour un
cas avec `panes.txt`, `S:I option=valeur` — valeur vide pour une option retirée). La CI
GitHub rejoue les deux commandes.

## Licence

MIT — fais-en ce que tu veux.
