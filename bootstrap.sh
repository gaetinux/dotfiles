#!/usr/bin/env bash
#
# bootstrap.sh — à lancer sur un serveur NEUF pour tout déployer en une commande.
#
# Il clone ton repo de dotfiles (bare repo), pose les fichiers dans $HOME en
# sauvegardant ce qui gênerait, puis lance install.sh.
#
# Usage :
#   REPO=https://github.com/TOI/dotfiles.git bash bootstrap.sh
#
# Ou directement depuis un serveur neuf (une fois bootstrap.sh poussé sur ton repo) :
#   REPO=https://github.com/TOI/dotfiles.git \
#     bash <(curl -fsSL https://raw.githubusercontent.com/TOI/dotfiles/main/bootstrap.sh)
#
set -euo pipefail

REPO="${REPO:?Définis REPO=<url-de-ton-repo-dotfiles>}"
DOTGIT="$HOME/.dotfiles"
BACKUP="$HOME/.dotfiles-backup"

if [ "$(id -u)" -eq 0 ]; then SUDO=""; else SUDO="sudo"; fi

# Raccourci git pour piloter le bare repo
config() { git --git-dir="$DOTGIT" --work-tree="$HOME" "$@"; }

# git est le seul prérequis pour démarrer
command -v git >/dev/null 2>&1 || { $SUDO apt-get update -qq && $SUDO apt-get install -y git; }

# Clone en bare si pas déjà fait
if [ ! -d "$DOTGIT" ]; then
  echo ":: Clone du repo dotfiles…"
  git clone --bare "$REPO" "$DOTGIT"
fi

config config status.showUntrackedFiles no

# Checkout. Si des fichiers existants gênent (.bashrc par ex.), on les sauvegarde.
echo ":: Déploiement des dotfiles dans \$HOME…"
if ! config checkout 2>/dev/null; then
  echo ":: Conflits détectés -> sauvegarde dans $BACKUP/"
  config checkout 2>&1 | grep -E "^\s+\." | awk '{print $1}' | while read -r f; do
    mkdir -p "$BACKUP/$(dirname "$f")"
    mv "$HOME/$f" "$BACKUP/$f"
  done
  config checkout
fi

echo ":: Dotfiles en place ✓"

# Lance le provisioning
INSTALL="$HOME/.config/dotfiles/install.sh"
if [ -f "$INSTALL" ]; then
  echo ":: Lancement de install.sh…"
  bash "$INSTALL"
else
  echo "!! $INSTALL introuvable — vérifie le chemin de install.sh dans ton repo."
  exit 1
fi
