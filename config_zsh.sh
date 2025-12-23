#!/usr/bin/env bash
set -euo pipefail

# Installation script:
# - Install Oh My Zsh
# - Install common plugins
# - Configure ~/.zshrc to enable plugins
#
# Notes:
# - This script does NOT handle sudo or privilege escalation
# - If system-level installation is required (e.g., installing zsh),
#   run this script with sudo yourself:
#     sudo bash install-omz.sh

TIMESTAMP="$(date +%Y%m%dT%H%M%S)"
ZSH_CUSTOM="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"
BACKUP="$HOME/.zshrc.pre-omz-$TIMESTAMP"

# Plugin repositories (will be cloned into $ZSH_CUSTOM/plugins/<name>)
declare -A PLUGINS
PLUGINS["zsh-autosuggestions"]="https://github.com/zsh-users/zsh-autosuggestions.git"
PLUGINS["zsh-syntax-highlighting"]="https://github.com/zsh-users/zsh-syntax-highlighting.git"
PLUGINS["you-should-use"]="https://github.com/MichaelAquilina/zsh-you-should-use.git"
PLUGINS["zsh-bat"]="https://github.com/fdellwing/zsh-bat.git"
PLUGINS["z"]="https://github.com/rupa/z.git"

# Plugins to enable in oh-my-zsh
PLUGINS_ENABLE=(git z zsh-autosuggestions zsh-syntax-highlighting you-should-use zsh-bat)

command_exists() {
  command -v "$1" >/dev/null 2>&1
}

info() {
  printf "[INFO] %s\n" "$*"
}

warn() {
  printf "[WARN] %s\n" "$*"
}

err() {
  printf "[ERROR] %s\n" "$*"
}

# 1) Check and install zsh (system permissions are the caller's responsibility)
install_zsh_if_missing() {
  if command_exists zsh; then
    info "zsh detected: $(command -v zsh)"
    return
  fi

  info "zsh not found, attempting installation via system package manager..."

  if command_exists apt; then
    apt update
    apt install -y zsh
  elif command_exists dnf; then
    dnf install -y zsh
  elif command_exists pacman; then
    pacman -Sy --noconfirm zsh
  elif command_exists brew; then
    brew install zsh
  else
    err "No supported package manager detected (apt / dnf / pacman / brew). Cannot install zsh automatically."
    exit 1
  fi

  if ! command_exists zsh; then
    err "zsh installation failed."
    exit 1
  fi

  info "zsh installation completed: $(command -v zsh)"
}

# 2) Install Oh My Zsh (non-interactive, does not change default shell)
install_oh_my_zsh() {
  if [ -d "$HOME/.oh-my-zsh" ]; then
    info "Existing ~/.oh-my-zsh detected, skipping Oh My Zsh installation."
    return
  fi

  info "Installing Oh My Zsh (non-interactive mode)..."

  if command_exists curl; then
    sh -c "$(curl -fsSL https://raw.github.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
  elif command_exists wget; then
    sh -c "$(wget -qO- https://raw.github.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
  else
    err "Neither curl nor wget is available. Cannot download Oh My Zsh installer."
    exit 1
  fi

  info "Oh My Zsh installation completed."
}

# 3) Install plugins
install_plugins() {
  mkdir -p "$ZSH_CUSTOM/plugins"

  for name in "${!PLUGINS[@]}"; do
    repo="${PLUGINS[$name]}"
    target="$ZSH_CUSTOM/plugins/$name"

    if [ -d "$target/.git" ]; then
      info "Plugin $name already exists, skipping clone."
      if command_exists git; then
        info "Attempting to update plugin $name..."
        git -C "$target" pull --ff-only || true
      fi
    else
      info "Cloning plugin $name..."
      git clone "$repo" "$target" || warn "Failed to clone plugin $name. You may install it manually later."
    fi
  done
}

# 4) Update ~/.zshrc
update_zshrc() {
  ZSHRC="$HOME/.zshrc"

  if [ -f "$ZSHRC" ]; then
    cp -a "$ZSHRC" "$BACKUP"
    info "Backed up existing ~/.zshrc to $BACKUP"
  else
    info "~/.zshrc not found, creating a new one."
    touch "$ZSHRC"
  fi

  plugins_line="plugins=(${PLUGINS_ENABLE[*]})"

  if grep -qE '^\s*plugins=' "$ZSHRC"; then
    awk -v repl="$plugins_line" '
      !done && $0 ~ /^\s*plugins=/ {
        print repl; done=1; next
      }
      { print }
    ' "$ZSHRC" > "$ZSHRC.tmp" && mv "$ZSHRC.tmp" "$ZSHRC"
    info "Updated plugins configuration in ~/.zshrc."
  else
    {
      echo "$plugins_line"
      echo
      cat "$ZSHRC"
    } > "$ZSHRC.tmp" && mv "$ZSHRC.tmp" "$ZSHRC"
    info "Added plugins configuration to ~/.zshrc."
  fi

  if ! grep -q "autoload -Uz compinit" "$ZSHRC"; then
    cat >> "$ZSHRC" <<'EOF'

# Initialize completion system
autoload -Uz compinit && compinit
EOF
    info "Added compinit initialization."
  fi

  # Remove any existing explicit source lines to avoid duplication
  sed -i.bak -E "/zsh-autosuggestions\.zsh/d" "$ZSHRC" || true
  sed -i.bak -E "/zsh-syntax-highlighting\.zsh/d" "$ZSHRC" || true

  cat >> "$ZSHRC" <<'EOF'

# Enable zsh-autosuggestions
[ -f $ZSH_CUSTOM/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh ] \
  && source $ZSH_CUSTOM/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh

# Enable zsh-syntax-highlighting (must be sourced last)
[ -f $ZSH_CUSTOM/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh ] \
  && source $ZSH_CUSTOM/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
EOF

  info "~/.zshrc configuration completed."
}

# 5) Set default shell to zsh
set_default_shell_to_zsh() {
  ZSH_PATH="$(command -v zsh)"

  if [ -z "$ZSH_PATH" ]; then
    err "zsh not found, cannot set default shell."
    exit 1
  fi

  if [ "$SHELL" = "$ZSH_PATH" ]; then
    info "Default shell is already zsh ($ZSH_PATH)."
    return
  fi

  info "Changing default shell to zsh ($ZSH_PATH)..."
  chsh -s "$ZSH_PATH"

  info "Default shell changed to zsh. You may need to log out and log back in for it to take effect."
}

main() {
  install_zsh_if_missing
  install_oh_my_zsh
  install_plugins
  update_zshrc
  set_default_shell_to_zsh

  info "All installations and configurations are complete."
  echo
  echo "If the default shell was changed, please log out and log back in for it to take effect."
}

main "$@"
