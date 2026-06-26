#!/usr/bin/env bash
#
# install.sh — provisionne un environnement de dev terminal reproductible.
#
# Idempotent : tu peux le relancer autant de fois que tu veux, il ne fait
# que ce qui manque. Sûr sur un serveur Ubuntu blanc comme sur une machine
# déjà configurée.
#
# Usage : bash install.sh
#
set -euo pipefail

# ─────────────────────────────────────────────────────────────────
#  Variables ajustables (le seul endroit que tu touches normalement)
# ─────────────────────────────────────────────────────────────────
NVIM_VERSION="stable"     # "stable", "nightly", ou un tag précis ex: "v0.10.4"

# ─────────────────────────────────────────────────────────────────
#  Plomberie
# ─────────────────────────────────────────────────────────────────
# sudo = rien quand on est root (utile pour tester dans un conteneur)
if [ "$(id -u)" -eq 0 ]; then SUDO=""; else SUDO="sudo"; fi

log()  { printf '\033[1;34m::\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m!!\033[0m %s\n' "$*" >&2; }

ARCH="$(uname -m)"   # x86_64 ou aarch64

# ─────────────────────────────────────────────────────────────────
#  1. Paquets système (stable, ne bouge pas)
# ─────────────────────────────────────────────────────────────────
install_system_packages() {
  log "Paquets système (apt)…"
  # ripgrep + fd = requis par Telescope (LazyVim) ; build-essential pour les
  # plugins qui compilent (treesitter, etc.)
  local pkgs=(tmux git curl unzip build-essential ripgrep fd-find)
  local missing=()
  for p in "${pkgs[@]}"; do
    dpkg -s "$p" >/dev/null 2>&1 || missing+=("$p")
  done
  if [ "${#missing[@]}" -gt 0 ]; then
    log "À installer : ${missing[*]}"
    $SUDO apt-get update -qq
    $SUDO apt-get install -y "${missing[@]}"
  else
    log "Tous les paquets apt sont déjà là."
  fi
}

# Le binaire `claude` (installeur natif) atterrit dans ~/.local/bin, qui n'est
# pas toujours dans le PATH sur un shell non-login. On l'ajoute à ~/.bashrc.
ensure_local_bin_path() {
  local rc="$HOME/.bashrc"
  mkdir -p "$HOME/.local/bin"
  # idempotent : on n'ajoute la ligne que si ~/.local/bin n'y est pas déjà
  if ! grep -qsF '.local/bin' "$rc"; then
    printf '\n# Ajouté par install.sh\nexport PATH="$HOME/.local/bin:$PATH"\n' >> "$rc"
    log "~/.local/bin ajouté au PATH dans ~/.bashrc."
  else
    log "~/.local/bin déjà dans le PATH (~/.bashrc)."
  fi
  # rend aussi dispo dans le shell courant (pour le 'command -v claude' qui suit)
  case ":$PATH:" in
    *":$HOME/.local/bin:"*) ;;
    *) export PATH="$HOME/.local/bin:$PATH" ;;
  esac
}

# Ubuntu fournit le binaire `fdfind`, mais Telescope cherche `fd`.
link_fd() {
  if ! command -v fd >/dev/null 2>&1 && command -v fdfind >/dev/null 2>&1; then
    $SUDO ln -sf "$(command -v fdfind)" /usr/local/bin/fd
    log "Lien fd -> fdfind créé."
  fi
}

# ─────────────────────────────────────────────────────────────────
#  2. Neovim (la version apt est souvent trop vieille pour LazyVim,
#     donc on prend la release officielle)
# ─────────────────────────────────────────────────────────────────
install_neovim() {
  if command -v nvim >/dev/null 2>&1; then
    log "Neovim déjà installé ($(nvim --version | head -n1))."
    return
  fi
  log "Installation de Neovim ($NVIM_VERSION)…"
  local asset
  case "$ARCH" in
    x86_64)  asset="nvim-linux-x86_64" ;;
    aarch64) asset="nvim-linux-arm64"  ;;  # ⚠️ vérifie le nom de l'asset si arm
    *) warn "Arch '$ARCH' non gérée, installe nvim à la main."; return 1 ;;
  esac
  local url="https://github.com/neovim/neovim/releases/download/${NVIM_VERSION}/${asset}.tar.gz"
  curl -fsSL "$url" -o /tmp/nvim.tar.gz

  # Vérification d'intégrité du tarball (refuse d'installer si ça ne matche pas).
  # Neovim publie un asset .sha256sum à côté de chaque archive.
  log "Vérification du checksum…"
  local expected actual
  expected="$(curl -fsSL "${url}.sha256sum" 2>/dev/null | awk '{print $1}')"
  if [ -z "$expected" ]; then
    warn "Checksum introuvable pour cet asset — vérifie le nom de l'asset/URL."
    warn "Abandon par sécurité (pas d'install non vérifiée)."
    rm -f /tmp/nvim.tar.gz
    exit 1
  fi
  actual="$(sha256sum /tmp/nvim.tar.gz | awk '{print $1}')"
  if [ "$expected" != "$actual" ]; then
    warn "Checksum Neovim INVALIDE — fichier corrompu ou altéré. Abandon."
    warn "  attendu : $expected"
    warn "  obtenu  : $actual"
    rm -f /tmp/nvim.tar.gz
    exit 1
  fi
  log "Checksum OK ✓"

  $SUDO rm -rf /opt/nvim
  $SUDO mkdir -p /opt/nvim
  $SUDO tar -xzf /tmp/nvim.tar.gz -C /opt/nvim --strip-components=1
  $SUDO ln -sf /opt/nvim/bin/nvim /usr/local/bin/nvim
  rm -f /tmp/nvim.tar.gz
  log "Neovim installé ($(nvim --version | head -n1))."
}

# ─────────────────────────────────────────────────────────────────
#  3. TPM (tmux plugin manager) + install des plugins sans ouvrir tmux
# ─────────────────────────────────────────────────────────────────
install_tpm() {
  local tpm_dir="$HOME/.tmux/plugins/tpm"
  if [ -d "$tpm_dir" ]; then
    log "TPM déjà présent."
  else
    log "Clone de TPM…"
    git clone --depth 1 https://github.com/tmux-plugins/tpm "$tpm_dir"
  fi
  # installe les plugins listés dans ~/.tmux.conf
  if [ -f "$HOME/.tmux.conf" ]; then
    "$tpm_dir/bin/install_plugins" >/dev/null 2>&1 \
      || warn "install_plugins a renvoyé une erreur (souvent normal au tout 1er run)."
  fi
}

# ─────────────────────────────────────────────────────────────────
#  4. Claude Code — LA partie qui bouge dans le temps, isolée exprès.
#     Installeur natif officiel : pas de Node, auto-update en arrière-plan.
#     -> Le jour où ça change, c'est ici et nulle part ailleurs.
# ─────────────────────────────────────────────────────────────────
install_claude_code() {
  if command -v claude >/dev/null 2>&1; then
    log "Claude Code déjà installé."
    return
  fi
  log "Installation de Claude Code (installeur natif)…"
  curl -fsSL https://claude.ai/install.sh | bash
  # Alternative si tu préfères des MAJ via apt :
  #   curl -fsSL https://claude.ai/install.sh | bash -s -- --apt   # (vérifie le flag courant)
}

# ─────────────────────────────────────────────────────────────────
#  Orchestration
# ─────────────────────────────────────────────────────────────────
main() {
  install_system_packages
  ensure_local_bin_path
  link_fd
  install_neovim
  install_tpm
  install_claude_code

  log "Terminé ✓"
  log "Lance 'tmux', puis 'nvim' (LazyVim installera ses plugins au 1er lancement)."
  log "Puis 'claude' pour t'authentifier (login navigateur au 1er run)."
}

main "$@"
