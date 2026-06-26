#!/usr/bin/env bash
#
# uninstall.sh — retire ce que install.sh a posé. Idempotent et prudent.
#
# Par défaut : retire les OUTILS (Neovim, lien fd, Claude Code binaire,
# ligne PATH ajoutée à ~/.bashrc, vieux dossiers de plugins tmux).
# Ne touche PAS à tes données ni aux paquets apt partagés.
#
# Flags :
#   --purge-data       supprime aussi les données : config/credentials Claude
#                      (~/.claude, ~/.claude.json, ~/.local/state/claude) et
#                      les données Neovim (~/.local/share|state|cache/nvim).
#   --purge-packages   désinstalle aussi les paquets apt posés par install.sh
#                      (⚠️ partagés avec le reste du système — à tes risques).
#   --all              = --purge-data --purge-packages
#
# NB : ce script NE supprime PAS ton bare repo de dotfiles ni tes fichiers de
#      config trackés (~/.tmux.conf, ~/.config/nvim). Pour ça, voir la fin.
#
set -euo pipefail

PURGE_DATA=0
PURGE_PACKAGES=0
for arg in "$@"; do
  case "$arg" in
    --purge-data)     PURGE_DATA=1 ;;
    --purge-packages) PURGE_PACKAGES=1 ;;
    --all)            PURGE_DATA=1; PURGE_PACKAGES=1 ;;
    -h|--help)
      grep '^#' "$0" | grep -v '^#!' | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "Option inconnue : $arg (voir --help)" >&2; exit 1 ;;
  esac
done

if [ "$(id -u)" -eq 0 ]; then SUDO=""; else SUDO="sudo"; fi
log()  { printf '\033[1;34m::\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m!!\033[0m %s\n' "$*" >&2; }

# ── Neovim ───────────────────────────────────────────────────────
remove_neovim() {
  # ne retire le lien que si c'est bien le nôtre (un symlink), pas un vrai binaire
  if [ -L /usr/local/bin/nvim ]; then
    $SUDO rm -f /usr/local/bin/nvim && log "Lien nvim retiré."
  fi
  if [ -d /opt/nvim ]; then
    $SUDO rm -rf /opt/nvim && log "/opt/nvim supprimé."
  fi
}

# ── Lien fd -> fdfind ────────────────────────────────────────────
remove_fd_link() {
  if [ -L /usr/local/bin/fd ]; then
    $SUDO rm -f /usr/local/bin/fd && log "Lien fd retiré."
  fi
}

# ── Claude Code (méthode officielle, installeur natif) ───────────
remove_claude() {
  rm -f  "$HOME/.local/bin/claude"      2>/dev/null && log "Binaire claude retiré." || true
  rm -rf "$HOME/.local/share/claude"    2>/dev/null || true
  if [ "$PURGE_DATA" = "1" ]; then
    rm -rf "$HOME/.claude" "$HOME/.local/state/claude" 2>/dev/null || true
    rm -f  "$HOME/.claude.json"                        2>/dev/null || true
    log "Données/credentials Claude supprimés."
  else
    log "Config Claude conservée (~/.claude). Utilise --purge-data pour l'effacer."
  fi
}

# ── Ligne PATH ajoutée à ~/.bashrc par install.sh ────────────────
clean_bashrc() {
  local rc="$HOME/.bashrc"
  [ -f "$rc" ] || return 0
  if grep -qF '# Ajouté par install.sh' "$rc"; then
    cp "$rc" "$rc.bak.$(date +%s)"
    # supprime la ligne marqueur + la ligne export qui suit
    sed -i '/# Ajouté par install.sh/{N;d;}' "$rc"
    log "Ligne PATH retirée de ~/.bashrc (backup créé)."
  fi
}

# ── Vieux dossiers de plugins tmux (TPM/resurrect), si présents ──
remove_tmux_leftovers() {
  if [ -d "$HOME/.tmux/plugins" ]; then
    rm -rf "$HOME/.tmux/plugins" && log "Anciens plugins tmux supprimés."
  fi
  if [ -d "$HOME/.local/share/tmux/resurrect" ]; then
    rm -rf "$HOME/.local/share/tmux/resurrect" && log "Sauvegardes tmux-resurrect supprimées."
  fi
}

# ── Données Neovim (plugins téléchargés, cache, état) ────────────
purge_nvim_data() {
  rm -rf "$HOME/.local/share/nvim" "$HOME/.local/state/nvim" "$HOME/.cache/nvim" 2>/dev/null || true
  log "Données Neovim (plugins/cache/état) supprimées."
  log "  (ta config ~/.config/nvim et lazy-lock.json sont conservés.)"
}

# ── Paquets apt posés par install.sh ─────────────────────────────
remove_packages() {
  warn "Désinstallation de paquets PARTAGÉS (tmux jq ripgrep fd-find unzip)."
  warn "On NE retire pas git/curl/build-essential (trop centraux)."
  $SUDO apt-get remove -y tmux jq ripgrep fd-find unzip || true
  $SUDO apt-get autoremove -y || true
  log "Paquets retirés."
}

main() {
  log "Désinstallation…"
  remove_neovim
  remove_fd_link
  remove_claude
  clean_bashrc
  remove_tmux_leftovers
  [ "$PURGE_DATA" = "1" ]     && purge_nvim_data
  [ "$PURGE_PACKAGES" = "1" ] && remove_packages

  log "Terminé ✓"
  echo
  echo "Non touché (volontairement) :"
  echo "  • Ton bare repo de dotfiles      -> rm -rf ~/.dotfiles"
  echo "  • Tes configs trackées           -> rm -f ~/.tmux.conf ; rm -rf ~/.config/nvim"
  echo "  • L'alias 'config' dans ~/.bashrc -> à retirer à la main si besoin"
  echo "Ouvre un nouveau terminal pour que le PATH se rafraîchisse."
}

main
