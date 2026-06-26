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
| **tmux** | Sessions persistantes en SSH (la connexion saute, le travail continue) + multiplexage |
| **Neovim / LazyVim** | Éditeur dans le terminal, config versionnée, plugins figés via `lazy-lock.json` |
| **Claude Code** | Assistant de code dans le terminal (installeur natif, auto-update) |

## Arborescence

```
~/.tmux.conf                    # config tmux (true-color, TPM, persistance)
~/.config/nvim/                 # config LazyVim (+ lazy-lock.json committé)
~/.config/dotfiles/install.sh   # provisioner idempotent
~/bootstrap.sh                  # entrée one-shot pour serveur neuf
```

---

## Installation sur un serveur neuf

Prérequis : un Ubuntu/Debian frais avec `curl` et `git`.

```bash
REPO=https://github.com/gaetinux/dotfiles.git \
  bash <(curl -fsSL https://raw.githubusercontent.com/gaetinux/dotfiles/main/bootstrap.sh)
```

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

## Tester sur un conteneur jetable

```bash
docker run -it --rm ubuntu:24.04 bash

# dans le conteneur (le script gère le cas root sans sudo) :
apt-get update && apt-get install -y curl git
REPO=https://github.com/gaetinux/dotfiles.git \
  bash <(curl -fsSL https://raw.githubusercontent.com/gaetinux/dotfiles/main/bootstrap.sh)
```

---

## Notes

- **Nerd Font** : à installer **côté client** (ton terminal local), pas sur le
  serveur — c'est lui qui rend les glyphes de LazyVim.
- **Neovim ARM64** : `install.sh` cible `x86_64` par défaut ; vérifier le nom
  de l'asset pour une machine ARM.
- **Claude Code** : installé via l'installeur natif officiel (auto-update). La
  fonction `install_claude_code()` de `install.sh` est le seul point à toucher
  si la méthode d'install évolue.
- Scripts en `set -euo pipefail` + vérifiables avec `shellcheck`.
