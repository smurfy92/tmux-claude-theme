# Affichage du périmètre intersession (côté thème) — plan d'implémentation

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** afficher dans tmux le périmètre intersession de chaque session Claude vivante, sur l'onglet courant, dans `choose-tree` et dans le badge de droite, sans jamais montrer un périmètre périmé.

**Architecture:** le plugin intersession pose sur chaque pane deux options utilisateur (`@cc_perimeter`, `@cc_perimeter_pid`). `cc-states.sh`, déjà relancé toutes les 5 s, lit ces options pour tous les panes en un `list-panes -a`, ne retient un périmètre que si son PID est vivant (`kill -0`), écrit l'option de **fenêtre** dérivée `@cc_perimeter_ok` (vide sinon) et compte les sessions par périmètre pour le badge. Les formats de `tmux.conf` ne lisent que `@cc_perimeter_ok`. Le thème ne lit jamais le registre du plugin.

**Tech Stack:** bash, tmux ≥ 3.0, `shellcheck` en CI, harnais `test.sh` + faux `tmux` sur fixtures.

**Spec:** `~/jules/intersession-plugin/docs/superpowers/specs/2026-10-16-affichage-perimetre-design.md` (R6, R7, CA7, CA8). Plan jumeau côté plugin : `~/jules/intersession-plugin/docs/superpowers/plans/2026-10-16-affichage-perimetre.md`.

## Global Constraints

- `shellcheck scripts/*.sh hooks/*.sh install.sh setup-hooks.sh test.sh tests/bin/tmux` sans avertissement (CI).
- `./test.sh` vert, les 12 fixtures existantes inchangées dans leur résultat (`expected.txt` ne bouge que si le format d'enregistrement du faux `tmux` change, voir Task 1).
- Un seul `tmux list-panes -a` ajouté par passage de `cc-states.sh` ; aucun `capture-pane` supplémentaire.
- Couleur du périmètre : lavande `#b4befe` ; texte sur fond : `#1e1e2e`. Pas de couleur par nom.
- Glyphes : `⟨nom⟩` ; séparateur du badge ` · `.
- Commits terminés par `Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>`.

## Contrat lu (posé par le plugin, ne pas interpréter autrement)

| Option | Portée | Valeur |
|---|---|---|
| `@cc_perimeter` | pane | nom `^[a-z0-9][a-z0-9-]{0,31}$`, vide si aucun |
| `@cc_perimeter_pid` | pane | PID décimal de la session, vide si aucun |

Lecture : `tmux list-panes -a -F '#{session_name}:#{window_index}|#{pane_id}|#{@cc_perimeter}|#{@cc_perimeter_pid}'`.

## Review Focus

1. **Valeur de `@cc_perimeter` hors format** (espace, majuscule, caractère de format tmux `#`) posée par un tiers : ignorée, jamais injectée dans un format. Test : Task 2, fixture `15-perimeter-bad-name`.
2. **`@cc_perimeter_pid` non numérique ou vide avec un périmètre présent** : traité comme mort (rien affiché). Test : Task 2, fixture `14-perimeter-dead-pid`.
3. **Fenêtre dont le pane actif est un shell et un autre pane porte une session vivante** : le périmètre s'affiche (R6). Test : Task 2, fixture `16-perimeter-split-window`.
4. **Deux périmètres dans une même fenêtre** (deux panes, deux sessions) : afficher les deux séparés par ` ` dans `@cc_perimeter_ok`, compter deux sessions. Test : Task 2, fixture `16`.
5. **Changement de périmètre entre deux passages** : `@cc_perimeter_ok` est réécrite à chaque passage, y compris vidée (`set -wu`) quand plus aucun pane n'est valide ; jamais laissée à l'ancienne valeur. Test : Task 2, fixture `17-perimeter-cleared`.

---

## Structure des fichiers

```
scripts/cc-states.sh        ← MODIFIÉ : lecture des options, kill -0, @cc_perimeter_ok, badge
tmux.conf                   ← MODIFIÉ : onglet courant, choose-tree -w et -s
tests/bin/tmux              ← MODIFIÉ : list-panes avec -F → panes.txt ; enregistrement des set hors @cc_state
tests/fixtures/13-perimeter-alive/      ← CRÉÉ (windows.txt, panes.txt, expected.txt)
tests/fixtures/14-perimeter-dead-pid/   ← CRÉÉ
tests/fixtures/15-perimeter-bad-name/   ← CRÉÉ
tests/fixtures/16-perimeter-split-window/ ← CRÉÉ
tests/fixtures/17-perimeter-cleared/    ← CRÉÉ
test.sh                     ← MODIFIÉ : substitution ALIVE / DEAD dans panes.txt
README.md                   ← MODIFIÉ : section « Périmètre intersession »
```

---

### Task 1 : harnais — faux `tmux` et substitution des PID

**Files:**
- Modify: `tests/bin/tmux`
- Modify: `test.sh`

**Interfaces:**
- Produces, dans le faux `tmux` :
  - `list-panes -a -F <format>` → contenu de `$CC_FIXTURE_PANES` si défini (fichier `panes.txt` préparé par `test.sh`), sinon colonne `pane_id` de `windows.txt` (comportement actuel, conservé pour la purge des orphelins).
  - `set -w -t S:I @cc_state X` → inchangé : `S:I=X` dans `$CC_RESULT`.
  - `set -w -t S:I <autre-option> X` → `S:I <autre-option>=X` ; `set -wu -t S:I <option>` → `S:I <option>=` (valeur vide).
- Produces, dans `test.sh` : si `<cas>/panes.txt` existe, copie vers `$tmp/panes.txt` en remplaçant le mot `ALIVE` par `$$` (PID du test, vivant) et `DEAD` par `2147483000` (hors plage usuelle, jamais vivant), puis `export CC_FIXTURE_PANES=$tmp/panes.txt`.

Format de `panes.txt` : `session:index|pane_id|perimeter|pid`, une ligne par pane, champs vides autorisés.

- [ ] **Step 1 : fixture 13 qui échoue** — `tests/fixtures/13-perimeter-alive/` : `windows.txt` = `a|1|%2|claude|✳ Done`, `state/%2` = `idle\nNOW-5`, `panes.txt` = `a:1|%2|jules|ALIVE`, `expected.txt` =

```
#[fg=#1e1e2e]#[bg=#b4befe] jules 1 #[default] 
a:1 @cc_perimeter_ok=⟨jules⟩
a:1=idle
```

- [ ] **Step 2 : vérifier l'échec** — `./test.sh` → `FAIL 13-perimeter-alive` (badge vide, pas de ligne `@cc_perimeter_ok`).

- [ ] **Step 3 : implémenter** les changements du faux `tmux` et de `test.sh` décrits ci-dessus (sans toucher à `cc-states.sh`).

- [ ] **Step 4 : vérifier** — `./test.sh` → les 12 cas existants toujours `ok`, le 13 toujours `FAIL` (il attend Task 2) ; `shellcheck tests/bin/tmux test.sh` propre.

- [ ] **Step 5 : commit** — `git add tests test.sh && git commit -m "test: le faux tmux sert les options de pane et enregistre les set d'options"`.

---

### Task 2 : `cc-states.sh` lit, vérifie et dérive le périmètre

**Files:**
- Modify: `scripts/cc-states.sh` (après la boucle `list-windows`, avant le badge)
- Create: `tests/fixtures/14-perimeter-dead-pid/`, `15-perimeter-bad-name/`, `16-perimeter-split-window/`, `17-perimeter-cleared/`

**Interfaces:**
- Produces : option de fenêtre `@cc_perimeter_ok` = concaténation des `⟨nom⟩` valides de la fenêtre séparés par un espace, dans l'ordre des panes ; `set -wu` si aucun. Variables du badge : liste `nom compteur` triée par nom.
- Validité d'un pane : `perimeter` non vide **et** conforme à `^[a-z0-9][a-z0-9-]{0,31}$` **et** `pid` conforme à `^[0-9]+$` **et** `kill -0 "$pid" 2>/dev/null` vrai (ou erreur « Operation not permitted », qui prouve que le processus existe : tester `kill -0` puis, en cas d'échec, `ps -p "$pid" >/dev/null`).
- Badge : pour chaque périmètre valide, `#[fg=#1e1e2e]#[bg=#b4befe] jules 1 #[default] ` ; plusieurs périmètres → `#[fg=#1e1e2e]#[bg=#b4befe] janus 1 · jules 2 #[default] ` ; placé **avant** `◆`/`◐`.

- [ ] **Step 1 : fixtures qui échouent**

  - `14-perimeter-dead-pid` : `panes.txt` = `a:1|%2|jules|DEAD` et une 2ᵉ ligne `a:2|%3|dpl|` (pid vide) ; `windows.txt` avec les deux fenêtres `✳ Done` + `state` idle ; attendu : badge vide, `a:1 @cc_perimeter_ok=` et `a:2 @cc_perimeter_ok=`, états `idle`.
  - `15-perimeter-bad-name` : `panes.txt` = `a:1|%2|Jules #[fg=red]|ALIVE` ; attendu : badge vide, `a:1 @cc_perimeter_ok=`.
  - `16-perimeter-split-window` : `windows.txt` = `a|1|%1|zsh|` (pane actif shell) ; `panes.txt` = `a:1|%1||` + `a:1|%5|jules|ALIVE` + `a:1|%6|janus|ALIVE` ; attendu : badge `#[fg=#1e1e2e]#[bg=#b4befe] janus 1 · jules 1 #[default] `, `a:1 @cc_perimeter_ok=⟨jules⟩ ⟨janus⟩`, `a:1=shell`.
  - `17-perimeter-cleared` : `windows.txt` deux fenêtres ; `panes.txt` = `a:1|%2|jules|ALIVE` et `a:2|%3||` ; attendu : `a:1 @cc_perimeter_ok=⟨jules⟩`, `a:2 @cc_perimeter_ok=` (le `set -wu` est émis même sans option antérieure : un passage = un état complet).

- [ ] **Step 2 : vérifier l'échec** — `./test.sh` → 13 à 17 en `FAIL`.

- [ ] **Step 3 : implémenter** dans `cc-states.sh` : une boucle `while IFS='|' read -r win pane per pid; do …; done < <(tmux list-panes -a -F '#{session_name}:#{window_index}|#{pane_id}|#{@cc_perimeter}|#{@cc_perimeter_pid}')` qui accumule par fenêtre et par périmètre **sans tableau associatif** (la machine a bash 3.2, `declare -A` indisponible) : deux chaînes multi-lignes `clé|valeur` consultées avec `awk` ou `case`, ou un fichier temporaire trié et par périmètre (`count_by_per`), puis pour **chaque fenêtre vue dans la boucle `list-windows`** : `tmux set -w -t "$win" @cc_perimeter_ok "…"` ou `tmux set -wu -t "$win" @cc_perimeter_ok`. Badge construit à partir de `count_by_per` trié (`sort`), inséré en tête de `out`.

- [ ] **Step 4 : vérifier** — `./test.sh` → `17/17 cas OK` ; `shellcheck scripts/cc-states.sh` propre ; temps d'un passage sur la machine réelle : `time ~/.tmux/scripts/cc-states.sh >/dev/null` reste sous 300 ms.

- [ ] **Step 5 : commit** — `git commit -am "feat: périmètre intersession vérifié par PID et dérivé en @cc_perimeter_ok, badge par périmètre"`.

---

### Task 3 : formats `tmux.conf`

**Files:**
- Modify: `tmux.conf` lignes 64 (`window-status-current-format`), 83 et 84 (`choose-tree`)

**Interfaces:**
- Consumes : `@cc_perimeter_ok` (Task 2), déjà formatée `⟨jules⟩`.

- [ ] **Step 1 : essai préalable (question ouverte de la spec)** — dans une session tmux réelle : `tmux set -w @cc_perimeter_ok '⟨essai⟩'` sur la fenêtre courante, puis `tmux display -p '#{@cc_perimeter_ok}'` et `tmux choose-tree -s -F '#{@cc_perimeter_ok} #{window_name}'` → vérifier que la valeur apparaît en mode fenêtres **et** en mode sessions (pour `-s`, tmux évalue le format sur la fenêtre courante de chaque session : attendu visible). Noter le résultat dans le commit. Si `-s` ne résout pas : afficher le périmètre seulement en `-w` et sur l'onglet, et le dire dans le README. Retirer l'option d'essai : `tmux set -wu @cc_perimeter_ok`.

- [ ] **Step 2 : modifier les trois formats**

  - onglet courant : `"#[fg=#1e1e2e]#[bg=#cba6f7]#[bold] #I:#W #[default]#{?#{@cc_perimeter_ok},#[fg=#1e1e2e]#[bg=#b4befe] #{@cc_perimeter_ok} #[default],}"`
  - `choose-tree -w` et `-s` : insérer, juste après le bloc d'état (`}}}`) et avant `#[fg=#cdd6f4]#[bold]#{window_name}`, le fragment `#{?#{@cc_perimeter_ok},#[fg=#b4befe]#{@cc_perimeter_ok}#[default] ,}`. Attention : pas de virgule littérale à l'intérieur (le glyphe `⟨` et l'espace conviennent), sinon le `#{?…}` se casse comme le commentaire de la ligne 82 le rappelle.

- [ ] **Step 3 : vérifier** — `tmux source-file ~/.tmux.conf` sans erreur ; dans une session Claude avec périmètre `jules` : onglet `3:intersession ⟨jules⟩`, `prefix + w` montre `⟨jules⟩` sur la ligne, `prefix + s` idem si l'essai du Step 1 l'a confirmé, badge `jules 1` à droite. Tuer la session (`kill -9`) → au plus 5 s après, onglet et badge sans périmètre (CA8, CA7 en réel). Capture d'écran pour la PR.

- [ ] **Step 4 : commit** — `git commit -am "feat: périmètre intersession sur l'onglet, choose-tree et le badge"`.

---

### Task 4 : README et PR

**Files:**
- Modify: `README.md` (nouvelle section après « Badge compteur »)

- [ ] **Step 1 : écrire la section** « Périmètre intersession » : d'où viennent les options (plugin intersession, lien vers son README), la règle d'affichage (PID vivant, recalcul toutes les 5 s, jamais de valeur poussée affichée sans vérification), ce que montre chaque surface, et le fait que le thème fonctionne sans le plugin (rien ne s'affiche).

- [ ] **Step 2 : `./test.sh` et `shellcheck` une dernière fois, commit** — `git commit -am "docs: périmètre intersession dans le README"`.

- [ ] **Step 3 : PR** — branche `feat/perimetre-intersession` depuis `main`, PR citant la spec et les deux plans, capture d'écran, corps terminé par `🤖 Generated with [Claude Code](https://claude.com/claude-code)`.

---

## Auto-revue (faite à l'écriture)

- **Couverture** : R6 (Task 2 : `kill -0`, `@cc_perimeter_ok`, fenêtre scindée, badge par pane), R7 (Task 3 : trois surfaces, couleur unique), CA7 (fixtures 14, 16), CA8 (Task 3 Step 3, manuel). La question ouverte de la spec sur `choose-tree -s` est tranchée en Task 3 Step 1 avec repli défini.
- **Noms** : `@cc_perimeter_ok`, `panes.txt`, `CC_FIXTURE_PANES`, `ALIVE`/`DEAD`, format d'enregistrement `S:I option=valeur` cohérents entre Task 1 et Task 2.
- **Proportion** : le plan fixe les fixtures et les formats tmux (valeurs exactes nécessaires), pas le corps du script.
