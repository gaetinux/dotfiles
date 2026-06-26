#!/usr/bin/env bash
#
# bootstrap.sh — déploie les dotfiles sur un serveur NEUF, en une commande.
#
# Clone le repo (bare), pose les fichiers dans $HOME en sauvegardant ce qui
# gênerait, vérifie l'état déployé, puis lance install.sh.
#
# Variables :
#   REPO       (requis)   URL du repo dotfiles
#   REF        (optionnel) commit SHA, tag ou branche à déployer. Défaut: main.
#                         -> Pinner sur un SHA complet = état immuable et vérifié
#                            (un SHA git EST un hash de contenu : tu obtiens
#                             exactement cet arbre, rien d'autre).
#   VERIFY_GPG (optionnel) "1" pour exiger une signature GPG valide sur le REF
#                          (nécessite que tu signes tes commits/tags).
#
# Usage typique (pinné sur un commit précis, recommandé) :
#   REPO=https://github.com/gaetinux/dotfiles.git \
#   REF=<commit-sha> \
#     bash bootstrap.sh
#
set -euo pipefail

REPO="${REPO:?Définis REPO=<url-de-ton-repo-dotfiles>}"
REF="${REF:-main}"
VERIFY_GPG="${VERIFY_GPG:-0}"
DOTGIT="$HOME/.dotfiles"
BACKUP="$HOME/.dotfiles-backup"

if [ "$(id -u)" -eq 0 ]; then SUDO=""; else SUDO="sudo"; fi

config() { git --git-dir="$DOTGIT" --work-tree="$HOME" "$@"; }

# git = seul prérequis pour démarrer
command -v git >/dev/null 2>&1 || { $SUDO apt-get update -qq && $SUDO apt-get install -y git; }

# Clone en bare (on récupère tout l'historique pour pouvoir checkout un REF précis)
if [ ! -d "$DOTGIT" ]; then
  echo ":: Clone du repo dotfiles…"
  git clone --bare "$REPO" "$DOTGIT"
else
  echo ":: Repo déjà cloné, fetch des dernières réfs…"
  config fetch --all --tags --prune
fi

# Vérification GPG optionnelle du REF avant de poser quoi que ce soit
if [ "$VERIFY_GPG" = "1" ]; then
  echo ":: Vérification de la signature GPG de '$REF'…"
  if config verify-commit "$REF" 2>/dev/null || config verify-tag "$REF" 2>/dev/null; then
    echo ":: Signature GPG valide ✓"
  else
    echo "!! Signature GPG absente ou invalide pour '$REF'. Abandon." >&2
    exit 1
  fi
fi

config config status.showUntrackedFiles no

# Checkout du REF demandé. Sauvegarde des fichiers existants qui gêneraient.
echo ":: Déploiement de '$REF' dans \$HOME…"
if ! config checkout "$REF" 2>/dev/null; then
  echo ":: Conflits détectés -> sauvegarde dans $BACKUP/"
  config checkout "$REF" 2>&1 | grep -E "^\s+\." | awk '{print $1}' | while read -r f; do
    mkdir -p "$BACKUP/$(dirname "$f")"
    mv "$HOME/$f" "$BACKUP/$f"
  done
  config checkout "$REF"
fi

echo ":: Dotfiles en place ✓ (réf: $(config rev-parse --short HEAD))"

# Lance le provisioning
INSTALL="$HOME/.config/dotfiles/install.sh"
if [ -f "$INSTALL" ]; then
  echo ":: Lancement de install.sh…"
  bash "$INSTALL"
else
  echo "!! $INSTALL introuvable — vérifie le chemin de install.sh dans ton repo." >&2
  exit 1
fi
