#!/usr/bin/env bash
#
# setup-terminal.sh — provision a modern terminal toolchain.
#
#   Stack : ghostty + zsh + oh-my-zsh + powerlevel10k
#   Tools : fzf · zoxide · fd · ripgrep · eza · bat · atuin · yazi · btop · neovim
#
# Idempotent: safe to run repeatedly. Installs anything missing, then wires the
# tools into the shell via ~/.oh-my-zsh/custom/modern-cli.zsh (auto-sourced by
# oh-my-zsh after plugins). Your ~/.zshrc is only touched to enable plugins,
# and a timestamped backup is made first.
#
set -euo pipefail

# ---- pretty output ---------------------------------------------------------
c_ok=$'\033[32m'; c_info=$'\033[36m'; c_warn=$'\033[33m'; c_off=$'\033[0m'
say()  { printf '%s==>%s %s\n' "$c_info" "$c_off" "$*"; }
ok()   { printf '%s  ok%s %s\n' "$c_ok" "$c_off" "$*"; }
warn() { printf '%s  !!%s %s\n' "$c_warn" "$c_off" "$*"; }

[[ "$(uname -s)" == "Darwin" ]] || { warn "This script targets macOS."; }

# ---- 1. Homebrew -----------------------------------------------------------
say "Checking Homebrew"
if ! command -v brew >/dev/null 2>&1; then
  say "Installing Homebrew"
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  # Make brew available for the rest of this run (Apple Silicon path).
  [[ -x /opt/homebrew/bin/brew ]] && eval "$(/opt/homebrew/bin/brew shellenv)"
fi
ok "brew: $(command -v brew)"

# ---- 2. CLI tools ----------------------------------------------------------
FORMULAE=(fzf zoxide fd ripgrep eza bat atuin yazi btop neovim)
say "Installing CLI tools: ${FORMULAE[*]}"
installed="$(brew list --formula -1 2>/dev/null || true)"
for f in "${FORMULAE[@]}"; do
  if grep -qx "$f" <<<"$installed"; then
    ok "$f already installed"
  else
    say "brew install $f"; brew install "$f"
  fi
done

# Nerd font (powerlevel10k recommended). Cask install is a no-op if present.
say "Ensuring MesloLGS Nerd Font"
if ls "$HOME/Library/Fonts/MesloLGS NF "*.ttf >/dev/null 2>&1; then
  ok "MesloLGS NF font present"
else
  brew install --cask font-meslo-lg-nerd-font || warn "font cask failed; install manually"
fi

# ---- 2b. Ghostty: include the user's config --------------------------------
say "Wiring Ghostty config include"
GHOSTTY_DIR="$HOME/Library/Application Support/com.mitchellh.ghostty"
GHOSTTY_CFG="$GHOSTTY_DIR/config.ghostty"
GHOSTTY_LINE="config-file = ~/App/ghostty/config"
mkdir -p "$GHOSTTY_DIR"
if [[ -f "$GHOSTTY_CFG" ]] && grep -qxF "$GHOSTTY_LINE" "$GHOSTTY_CFG"; then
  ok "Ghostty include already present"
else
  printf '%s\n' "$GHOSTTY_LINE" >>"$GHOSTTY_CFG"
  ok "added include -> $GHOSTTY_CFG"
fi

# ---- 3. oh-my-zsh ----------------------------------------------------------
export ZSH="${ZSH:-$HOME/.oh-my-zsh}"
say "Checking oh-my-zsh"
if [[ ! -d "$ZSH" ]]; then
  say "Installing oh-my-zsh (unattended)"
  RUNZSH=no KEEP_ZSHRC=yes \
    sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
fi
ok "oh-my-zsh: $ZSH"
ZSH_CUSTOM="${ZSH_CUSTOM:-$ZSH/custom}"

# ---- 4. theme + plugins (git clones, idempotent) ---------------------------
clone() { # clone <repo-url> <dest>
  if [[ -d "$2" ]]; then ok "$(basename "$2") present"
  else say "git clone $(basename "$2")"; git clone --depth=1 "$1" "$2"; fi
}
say "Installing powerlevel10k + zsh plugins"
clone https://github.com/romkatv/powerlevel10k.git       "$ZSH_CUSTOM/themes/powerlevel10k"
clone https://github.com/zsh-users/zsh-autosuggestions.git "$ZSH_CUSTOM/plugins/zsh-autosuggestions"
clone https://github.com/zdharma-continuum/fast-syntax-highlighting.git "$ZSH_CUSTOM/plugins/fast-syntax-highlighting"

# ---- 5. .zshrc: theme + plugins line (backup first) ------------------------
ZSHRC="$HOME/.zshrc"
say "Wiring ~/.zshrc"
if [[ -f "$ZSHRC" ]]; then
  backup="$ZSHRC.bak.$(date +%Y%m%d%H%M%S)"
  cp "$ZSHRC" "$backup"; ok "backup -> $backup"
else
  touch "$ZSHRC"
fi

# Ensure powerlevel10k theme.
if grep -q '^ZSH_THEME=' "$ZSHRC"; then
  sed -i '' 's#^ZSH_THEME=.*#ZSH_THEME="powerlevel10k/powerlevel10k"#' "$ZSHRC"
else
  printf '\nZSH_THEME="powerlevel10k/powerlevel10k"\n' >>"$ZSHRC"
fi

# Ensure the three plugins are enabled (order matters: syntax-highlighting last).
WANT_PLUGINS="git zsh-autosuggestions fast-syntax-highlighting"
if grep -q '^plugins=(' "$ZSHRC"; then
  sed -i '' "s#^plugins=(.*)#plugins=($WANT_PLUGINS)#" "$ZSHRC"
else
  printf '\nplugins=(%s)\n' "$WANT_PLUGINS" >>"$ZSHRC"
fi
ok "theme + plugins set ($WANT_PLUGINS)"

# ---- 6. managed integrations + aliases -------------------------------------
# This file is fully managed by the script. oh-my-zsh sources every *.zsh in
# $ZSH_CUSTOM AFTER plugins load, so tool init and aliases land last and win.
say "Writing $ZSH_CUSTOM/modern-cli.zsh"
cat >"$ZSH_CUSTOM/modern-cli.zsh" <<'ZRC'
# ============================================================================
#  modern-cli.zsh  —  MANAGED by setup-terminal.sh. Edits will be overwritten.
#  Modern CLI tooling: fzf zoxide fd ripgrep eza bat atuin yazi btop neovim
# ============================================================================

# --- editor ---------------------------------------------------------------
export EDITOR="nvim"
export VISUAL="nvim"

# --- bat (cat replacement) ------------------------------------------------
export BAT_THEME="ansi"

# --- fzf: powered by fd + ripgrep, with bat/eza previews ------------------
if command -v fzf >/dev/null; then
  # Default source = fd (fast, respects .gitignore, shows hidden).
  export FZF_DEFAULT_COMMAND='fd --type f --hidden --follow --exclude .git'
  export FZF_CTRL_T_COMMAND="$FZF_DEFAULT_COMMAND"
  export FZF_ALT_C_COMMAND='fd --type d --hidden --follow --exclude .git'
  export FZF_DEFAULT_OPTS='--height 40% --layout=reverse --border --info=inline'
  export FZF_CTRL_T_OPTS="--preview 'bat --color=always --style=numbers --line-range=:300 {} 2>/dev/null || eza -la --color=always {}'"
  export FZF_ALT_C_OPTS="--preview 'eza -la --color=always --icons {} 2>/dev/null'"
  # Keybindings + completion (Homebrew path). Binds Ctrl-T / Alt-C / Ctrl-R.
  if [[ -n "${HOMEBREW_PREFIX:-}" ]]; then
    source "$HOMEBREW_PREFIX/opt/fzf/shell/key-bindings.zsh" 2>/dev/null
    source "$HOMEBREW_PREFIX/opt/fzf/shell/completion.zsh"   2>/dev/null
  fi
fi

# --- zoxide: smarter cd (replaces `cd`) -----------------------------------
# --cmd cd makes `cd` itself frecency-aware; `cdi` opens the interactive picker.
command -v zoxide >/dev/null && eval "$(zoxide init zsh --cmd cd)"

# --- atuin: shell history (inits LAST so it owns Ctrl-R over fzf) ----------
command -v atuin >/dev/null && eval "$(atuin init zsh)"

# --- eza (ls replacement) -------------------------------------------------
if command -v eza >/dev/null; then
  alias ls='eza --group-directories-first --icons'
  alias l='eza -lbF --git --icons --group-directories-first'
  alias ll='eza -lbhHigUmuSa --git --icons --group-directories-first'
  alias la='eza -lbhHigUmuSa --color-scale all --git --icons --group-directories-first'
  alias lt='eza --tree --level=2 --icons --group-directories-first'
  alias tree='eza --tree --icons'
fi

# --- bat (cat replacement; falls back to plain output when piped) ---------
command -v bat >/dev/null && alias cat='bat --paging=never'

# --- neovim (vim replacement) ---------------------------------------------
if command -v nvim >/dev/null; then
  alias vim='nvim'
  alias vi='nvim'
fi

# --- btop (top/htop replacement) ------------------------------------------
if command -v btop >/dev/null; then
  alias top='btop'
  alias htop='btop'
fi

# --- yazi: file manager; `y` cd's to the dir you quit in ------------------
if command -v yazi >/dev/null; then
  function y() {
    local tmp; tmp="$(mktemp -t yazi-cwd.XXXXXX)"
    yazi "$@" --cwd-file="$tmp"
    local cwd; cwd="$(command cat -- "$tmp")"
    [[ -n "$cwd" && "$cwd" != "$PWD" ]] && builtin cd -- "$cwd"
    rm -f -- "$tmp"
  }
fi

# NOTE: `find`/`grep` are intentionally NOT aliased — use `fd` and `rg`
# directly (different syntax). fzf already uses them under the hood.
ZRC
ok "modern-cli.zsh written"

# ---- 7. done ---------------------------------------------------------------
echo
ok "Setup complete."
say "Next steps:"
cat <<EOF
  1. Reload your shell:      exec zsh
  2. Configure the prompt:   p10k configure
  3. Import existing history into atuin (optional): atuin import auto
  4. Set Ghostty font to 'MesloLGS NF' (already in App/ghostty/config).

  New commands: cd (zoxide) · cdi · ls/l/ll/la/lt · cat (bat) · vim (nvim)
                top (btop) · y (yazi) · fd · rg · fzf (Ctrl-T/Alt-C/Ctrl-R)
EOF
