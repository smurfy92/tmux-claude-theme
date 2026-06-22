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

### 3. Saut direct vers une session en attente (`prefix + a`)
Te téléporte sur la prochaine window où Claude attend. Presse répétée → cycle entre
toutes. Aucune en attente → message « tout est traité ✓ ».

### 4. Thème Catppuccin Mocha cohérent
Status bar, onglets, bordures de panes, menus, sélections, horloge — le tout en
Catppuccin Mocha, **sans plugin de thème** (réglages manuels, donc aucune dépendance
fragile). Les fenêtres inactives sont masquées de la status bar (navigation via
`choose-tree`).

---

## 🧠 Comment marche la détection d'état

Claude Code écrit l'état dans le **titre du pane** :
- `✳ …`  → Claude au repos **ou** en attente d'input (le titre ne distingue pas les deux !)
- `⠐ ⠂ ⠄ …` (braille animé) → spinner = Claude travaille
- titre vide / hostname → simple shell

Comme `✳` est ambigu, le script [`scripts/cc-states.sh`](scripts/cc-states.sh)
**capture le bas du pane** pour les sessions `✳` et cherche la signature d'un prompt
interactif (`Esc to cancel`, `Enter to select`, `❯ 1.`, `Do you want`). Si trouvé →
`waiting`, sinon → `idle`.

Le résultat est stocké dans l'option window `@cc_state`, lue par le format de
`choose-tree`. Le script tourne :
- **toutes les 5 s** via la status bar (`#(...)`), ce qui garde `@cc_state` à jour ;
- **juste avant** chaque `choose-tree` (pour une fraîcheur immédiate).

Pas de daemon, pas de polling permanent au-delà du rafraîchissement status.

---

## 📦 Installation

### Prérequis
- **tmux ≥ 3.2** (testé sur 3.5a) — nécessaire pour `#{?}`, `#{m:}`, options `@user`.
- **git**, **bash**, **awk** (présents par défaut sur macOS / Linux).
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
3. installe **tpm** (tmux Plugin Manager) si absent.

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
│   ├── cc-states.sh     # classifie les windows + imprime le badge status bar
│   └── cc-jump.sh       # prefix + a : saute à la prochaine session en attente
├── install.sh           # liens symboliques + tpm
└── README.md
```

---

## Licence

MIT — fais-en ce que tu veux.
