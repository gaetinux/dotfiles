# dotfiles

Mon environnement de dev terminal, géré comme de l'infra reproductible :
**tmux + Neovim (LazyVim) + Claude Code**, déployable sur un serveur neuf en
une seule commande.

Pas d'outil magique : un **bare git repo** pour les dotfiles + un **`install.sh`
idempotent** pour les binaires. Du texte et du git — ça se recrée à l'identique
et ça ne casse pas dans le temps.

## Ce qu'il y a dedans

| Outil | Rôle |
|-------|------|
| **tmux** | Sessions persistantes en SSH (la connexion saute, le travail continue) + multiplexage — config 100 % native, sans plugins |
| **Neovim / LazyVim** | Éditeur dans le terminal, config versionnée, plugins figés via `lazy-lock.json` |
| **Claude Code** | Assistant de code dans le terminal (installeur natif, auto-update) |

## Arborescence

```
~/.tmux.conf                    # config tmux (true-color, TPM, persistance)
~/.config/nvim/                 # config LazyVim (+ lazy-lock.json committé)
~/.config/dotfiles/install.sh   # provisioner idempotent
~/.config/dotfiles/uninstall.sh # désinstalle proprement (flags --purge-data / --purge-packages)
~/bootstrap.sh                  # entrée one-shot pour serveur neuf
```

---

## Installation sur un serveur neuf

Prérequis : un Ubuntu/Debian frais avec `curl` et `git`.

Version simple (suit `main`) :

```bash
REPO=https://github.com/gaetinux/dotfiles.git \
  bash <(curl -fsSL https://raw.githubusercontent.com/gaetinux/dotfiles/main/bootstrap.sh)
```

Version durcie (recommandée) — on récupère `bootstrap.sh` figé sur un commit
précis, et on déploie ce même commit (un SHA git est un hash de contenu :
l'état déployé est immuable et vérifié) :

```bash
COMMIT=<sha-du-commit>
REPO=https://github.com/gaetinux/dotfiles.git \
REF=$COMMIT \
  bash <(curl -fsSL "https://raw.githubusercontent.com/gaetinux/dotfiles/$COMMIT/bootstrap.sh")
```

Si tu signes tes commits/tags en GPG, ajoute `VERIFY_GPG=1` pour exiger une
signature valide avant tout déploiement.

Le script clone le repo, pose les dotfiles dans `$HOME` (en sauvegardant ce
qui gênerait dans `~/.dotfiles-backup/`), puis lance `install.sh`.

Ensuite :

```bash
tmux        # session persistante
nvim        # LazyVim installe ses plugins au 1er lancement
claude      # login navigateur au 1er run
```

---

## Premier setup du repo (référence)

Pour mémoire, voici comment ce repo a été créé — bare repo monté sur `$HOME` :

```bash
git init --bare $HOME/.dotfiles
alias config='git --git-dir=$HOME/.dotfiles/ --work-tree=$HOME'
config config status.showUntrackedFiles no
echo "alias config='git --git-dir=\$HOME/.dotfiles/ --work-tree=\$HOME'" >> ~/.bashrc

# Seed LazyVim (sans git imbriqué dans le bare repo)
git clone https://github.com/LazyVim/starter ~/.config/nvim
rm -rf ~/.config/nvim/.git
nvim   # génère lazy-lock.json, puis :q

# Tracker
config add ~/.tmux.conf ~/.config/dotfiles/install.sh ~/bootstrap.sh ~/.config/nvim
config commit -m "init: dev box terminal reproductible"
config remote add origin https://github.com/gaetinux/dotfiles.git
config branch -M main
config push -u origin main
```

---

## Modifier la config

Avec le bare repo, le fichier édité **est** le fichier tracké (pas de
source/cible séparées) :

```bash
nvim ~/.tmux.conf
config add ~/.tmux.conf
config commit -m "tmux: ..."
config push
```

Mettre à jour un serveur déjà déployé : `config pull` (puis relancer
`install.sh` si des paquets ont changé — il est idempotent).

> **`lazy-lock.json`** fige la version exacte de chaque plugin Neovim : un
> serveur neuf reconstruit l'environnement au plugin près. Le recommiter après
> chaque `:Lazy update` validé.

---

## Désinstallation

```bash
bash ~/.config/dotfiles/uninstall.sh                 # retire les outils, garde tes données
bash ~/.config/dotfiles/uninstall.sh --purge-data    # + config/credentials Claude & données nvim
bash ~/.config/dotfiles/uninstall.sh --all           # + paquets apt (partagés, prudence)
```

Par défaut le script ne touche ni à tes paquets système partagés, ni à ton
bare repo de dotfiles, ni à tes configs trackées. Il l'indique en fin
d'exécution avec les commandes manuelles si tu veux aller plus loin.

## Tester sur un conteneur jetable

```bash
docker run -it --rm ubuntu:24.04 bash

# dans le conteneur (le script gère le cas root sans sudo) :
apt-get update && apt-get install -y curl git
REPO=https://github.com/gaetinux/dotfiles.git \
  bash <(curl -fsSL https://raw.githubusercontent.com/gaetinux/dotfiles/main/bootstrap.sh)
```

---

## Sécurité

- **Aucun secret dans ce repo.** Le bare repo track des fichiers de `$HOME` —
  là où vivent les secrets. On ajoute les fichiers **un par un** (jamais de
  `config add .`), et `status.showUntrackedFiles no` évite les ajouts
  accidentels. À ne jamais committer : `~/.ssh/`, `~/.claude/`, `~/.aws/`,
  `~/.netrc`, `~/.bash_history`, tout token/clé.
- **Téléchargement Neovim vérifié** par checksum SHA256 (`install.sh` refuse
  d'installer si ça ne matche pas).
- **Déploiement pinnable** sur un commit/tag précis (`REF=`) + signature GPG
  optionnelle (`VERIFY_GPG=1`).
- `curl | bash` : seulement pour l'installeur natif first-party de Claude Code
  et pour ce `bootstrap.sh` (lis-le avant de le lancer ; préfère la version
  pinnée).
- Scripts en `set -euo pipefail`, vérifiables avec `shellcheck`.

## Notes

- **Nerd Font** : à installer **côté client** (ton terminal local), pas sur le
  serveur — c'est lui qui rend les glyphes de LazyVim.
- **Neovim ARM64** : `install.sh` cible `x86_64` par défaut ; vérifier le nom
  de l'asset pour une machine ARM.
- **Claude Code** : installé via l'installeur natif officiel (auto-update). La
  fonction `install_claude_code()` de `install.sh` est le seul point à toucher
  si la méthode d'install évolue.
