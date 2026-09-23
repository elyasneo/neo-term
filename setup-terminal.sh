#!/usr/bin/env bash
#
# setup-terminal.sh — provision a modern terminal toolchain.
#
#   Stack : Terminal.app | iTerm2 | Ghostty + zsh + oh-my-zsh + powerlevel10k
#   Tools : fzf · zoxide · fd · ripgrep · eza · bat · atuin · yazi · btop · neovim
#
# Idempotent: safe to run repeatedly. Installs anything missing, then wires the
# tools into the shell via ~/.oh-my-zsh/custom/modern-cli.zsh (auto-sourced by
# oh-my-zsh after plugins). Your ~/.zshrc is only touched to enable plugins,
# and a timestamped backup is made first.
#
# Usage: ./setup-terminal.sh [--terminal terminal|iterm2|ghostty]
#        Without --terminal it asks (defaults to Terminal.app when not a TTY).
#
set -euo pipefail

# ---- pretty output ---------------------------------------------------------
c_ok=$'\033[32m'; c_info=$'\033[36m'; c_warn=$'\033[33m'; c_off=$'\033[0m'
say()  { printf '%s==>%s %s\n' "$c_info" "$c_off" "$*"; }
ok()   { printf '%s  ok%s %s\n' "$c_ok" "$c_off" "$*"; }
warn() { printf '%s  !!%s %s\n' "$c_warn" "$c_off" "$*"; }

[[ "$(uname -s)" == "Darwin" ]] || { warn "This script targets macOS."; }

# ---- 0. pick the terminal emulator -----------------------------------------
TERMINAL=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --terminal)   TERMINAL="${2:-}"; shift 2 ;;
    --terminal=*) TERMINAL="${1#*=}"; shift ;;
    -h|--help)    sed -n '2,16p' "$0"; exit 0 ;;
    *)            warn "unknown argument: $1"; exit 1 ;;
  esac
done
if [[ -z "$TERMINAL" ]]; then
  if [[ -t 0 ]]; then
    say "Which terminal do you want to set up?"
    printf '    1) Terminal.app  (macOS default)\n'
    printf '    2) iTerm2\n'
    printf '    3) Ghostty\n'
    while [[ -z "$TERMINAL" ]]; do
      printf 'Choose 1-3 [1]: '
      read -r choice || choice=1   # Ctrl-D -> default
      case "${choice:-1}" in
        1) TERMINAL=terminal ;;
        2) TERMINAL=iterm2 ;;
        3) TERMINAL=ghostty ;;
        *) warn "please enter 1, 2 or 3" ;;
      esac
    done
  else
    TERMINAL=terminal
  fi
fi
case "$TERMINAL" in
  terminal|iterm2|ghostty) ok "terminal: $TERMINAL" ;;
  *) warn "unknown terminal '$TERMINAL' (use terminal, iterm2 or ghostty)"; exit 1 ;;
esac

# ---- 1. Homebrew -----------------------------------------------------------
# On a fresh Mac brew is absent and, once installed, not on PATH: the installer
# only *prints* the shellenv line. We load it for this run and persist it in
# ~/.zprofile (Terminal.app opens login shells, which read it).
say "Checking Homebrew"
brew_bin() {
  command -v brew 2>/dev/null && return
  for b in /opt/homebrew/bin/brew /usr/local/bin/brew; do [[ -x "$b" ]] && { echo "$b"; return; }; done
  return 1
}
if ! BREW="$(brew_bin)"; then
  say "Installing Homebrew (also installs the Xcode Command Line Tools / git)"
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  BREW="$(brew_bin)" || { warn "brew not found after install"; exit 1; }
fi
eval "$("$BREW" shellenv)"
ok "brew: $BREW"

SHELLENV_LINE="eval \"\$($BREW shellenv)\""
ZPROFILE="$HOME/.zprofile"
if [[ -f "$ZPROFILE" ]] && grep -qF "$SHELLENV_LINE" "$ZPROFILE"; then
  ok "brew shellenv already in ~/.zprofile"
else
  printf '\n%s\n' "$SHELLENV_LINE" >>"$ZPROFILE"
  ok "added brew shellenv -> ~/.zprofile"
fi

# ---- 1b. install the chosen terminal if missing ----------------------------
# Done right after brew so a failed install stops the run before anything else.
# Looks in both Applications folders and asks Spotlight by bundle id, so an app
# installed by hand (not via brew) is detected too.
app_installed() { # app_installed <App.app> <bundle-id>
  [[ -d "/Applications/$1" || -d "$HOME/Applications/$1" ]] && return 0
  [[ -n "$(mdfind "kMDItemCFBundleIdentifier == '$2'" 2>/dev/null | head -1)" ]]
}
ensure_app() { # ensure_app <App.app> <bundle-id> <cask>
  if app_installed "$1" "$2"; then
    ok "${1%.app} already installed"
  else
    say "Installing ${1%.app} (brew install --cask $3)"
    brew install --cask "$3" || { warn "failed to install ${1%.app}"; exit 1; }
    ok "${1%.app} installed"
  fi
}
case "$TERMINAL" in
  terminal) ok "Terminal.app is built into macOS" ;;
  iterm2)   ensure_app iTerm.app   com.googlecode.iterm2 iterm2 ;;
  ghostty)  ensure_app Ghostty.app com.mitchellh.ghostty ghostty ;;
esac

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

# Nerd font: the exact MesloLGS NF files powerlevel10k is tuned for. Needed for
# the prompt glyphs and eza icons.
say "Ensuring MesloLGS NF font"
FONT_DIR="$HOME/Library/Fonts"
FONT_URL="https://github.com/romkatv/powerlevel10k-media/raw/master"
mkdir -p "$FONT_DIR"
for style in Regular Bold Italic "Bold Italic"; do
  file="MesloLGS NF $style.ttf"
  if [[ -f "$FONT_DIR/$file" ]]; then
    ok "$file present"
  else
    curl -fsSL -o "$FONT_DIR/$file" "$FONT_URL/${file// /%20}" \
      && ok "installed $file" || warn "failed to download $file"
  fi
done

# ---- 2b. terminal emulator: font + Option-as-Meta -------------------------
# Every option gets the MesloLGS NF font and a Meta/Alt Option key, so Alt-C
# (fzf cd), Alt-. and friends work instead of typing ç / ≥.
TERM_FONT="MesloLGS-NF-Regular"   # PostScript name
TERM_FONT_SIZE=13

setup_terminal_app() {
  say "Configuring Terminal.app"
  local profile
  if profile="$(osascript 2>/dev/null <<OSA
tell application "Terminal"
  set font name of default settings to "$TERM_FONT"
  set font size of default settings to $TERM_FONT_SIZE
  set font name of startup settings to "$TERM_FONT"
  set font size of startup settings to $TERM_FONT_SIZE
  return name of default settings
end tell
OSA
  )"; then
    ok "font -> $TERM_FONT $TERM_FONT_SIZE (profile: $profile)"
    # Not scriptable via AppleScript, so edit the prefs through cfprefsd
    # (export -> PlistBuddy -> import) rather than the plist file directly.
    sleep 1   # let Terminal flush the font change first
    local PB=/usr/libexec/PlistBuddy tplist meta_key
    tplist="$(mktemp -t terminal-prefs)"
    meta_key=":Window Settings:$profile:useOptionAsMetaKey"
    if defaults export com.apple.Terminal "$tplist" \
      && { "$PB" -c "Set \"$meta_key\" true" "$tplist" 2>/dev/null \
        || "$PB" -c "Add \"$meta_key\" bool true" "$tplist"; } \
      && defaults import com.apple.Terminal "$tplist"; then
      ok "Option key -> Meta (profile: $profile)"
    else
      warn "could not enable Option-as-Meta; set it in Terminal > Settings > Profiles > Keyboard"
    fi
    rm -f "$tplist"
  else
    warn "could not script Terminal.app (allow it under System Settings > Privacy > Automation)"
    warn "set the font manually: Terminal > Settings > Profiles > Text > MesloLGS NF"
  fi
}

setup_iterm2() {
  say "Configuring iTerm2"
  # A Dynamic Profile is a plain JSON file iTerm2 watches, so it works even
  # before iTerm2's first launch and is fully rewritten on every run.
  local dir="$HOME/Library/Application Support/iTerm2/DynamicProfiles"
  local guid="neo-term-profile"
  mkdir -p "$dir"
  cat >"$dir/neo-term.json" <<JSON
{
  "Profiles": [
    {
      "Name": "neo-term",
      "Guid": "$guid",
      "Normal Font": "$TERM_FONT $TERM_FONT_SIZE",
      "Option Key Sends": 2,
      "Right Option Key Sends": 0,
      "Ansi 0 Color": { "Color Space": "sRGB", "Red Component": 0.1020, "Green Component": 0.1020, "Blue Component": 0.1020 },
      "Ansi 1 Color": { "Color Space": "sRGB", "Red Component": 0.7993, "Green Component": 0.2163, "Blue Component": 0.1818 },
      "Ansi 2 Color": { "Color Space": "sRGB", "Red Component": 0.1492, "Green Component": 0.6415, "Blue Component": 0.2238 },
      "Ansi 3 Color": { "Color Space": "sRGB", "Red Component": 0.8030, "Green Component": 0.6739, "Blue Component": 0.0315 },
      "Ansi 4 Color": { "Color Space": "sRGB", "Red Component": 0.0313, "Green Component": 0.4128, "Blue Component": 0.7975 },
      "Ansi 5 Color": { "Color Space": "sRGB", "Red Component": 0.5896, "Green Component": 0.2778, "Blue Component": 0.7471 },
      "Ansi 6 Color": { "Color Space": "sRGB", "Red Component": 0.2791, "Green Component": 0.6203, "Blue Component": 0.7598 },
      "Ansi 7 Color": { "Color Space": "sRGB", "Red Component": 0.5961, "Green Component": 0.5961, "Blue Component": 0.6157 },
      "Ansi 8 Color": { "Color Space": "sRGB", "Red Component": 0.2745, "Green Component": 0.2745, "Blue Component": 0.2745 },
      "Ansi 9 Color": { "Color Space": "sRGB", "Red Component": 1.0000, "Green Component": 0.2706, "Blue Component": 0.2275 },
      "Ansi 10 Color": { "Color Space": "sRGB", "Red Component": 0.1961, "Green Component": 0.8431, "Blue Component": 0.2941 },
      "Ansi 11 Color": { "Color Space": "sRGB", "Red Component": 1.0000, "Green Component": 0.8392, "Blue Component": 0.0392 },
      "Ansi 12 Color": { "Color Space": "sRGB", "Red Component": 0.0392, "Green Component": 0.5176, "Blue Component": 1.0000 },
      "Ansi 13 Color": { "Color Space": "sRGB", "Red Component": 0.7490, "Green Component": 0.3529, "Blue Component": 0.9490 },
      "Ansi 14 Color": { "Color Space": "sRGB", "Red Component": 0.4620, "Green Component": 0.8383, "Blue Component": 1.0000 },
      "Ansi 15 Color": { "Color Space": "sRGB", "Red Component": 1.0000, "Green Component": 1.0000, "Blue Component": 1.0000 },
      "Background Color": { "Color Space": "sRGB", "Red Component": 0.1176, "Green Component": 0.1176, "Blue Component": 0.1176 },
      "Foreground Color": { "Color Space": "sRGB", "Red Component": 1.0000, "Green Component": 1.0000, "Blue Component": 1.0000 },
      "Bold Color": { "Color Space": "sRGB", "Red Component": 1.0000, "Green Component": 1.0000, "Blue Component": 1.0000 },
      "Cursor Color": { "Color Space": "sRGB", "Red Component": 0.5961, "Green Component": 0.5961, "Blue Component": 0.6157 },
      "Cursor Text Color": { "Color Space": "sRGB", "Red Component": 1.0000, "Green Component": 1.0000, "Blue Component": 1.0000 },
      "Selection Color": { "Color Space": "sRGB", "Red Component": 0.2471, "Green Component": 0.3882, "Blue Component": 0.5451 },
      "Selected Text Color": { "Color Space": "sRGB", "Red Component": 1.0000, "Green Component": 1.0000, "Blue Component": 1.0000 },
      "Link Color": { "Color Space": "sRGB", "Red Component": 0.2549, "Green Component": 0.6118, "Blue Component": 1.0000 },
      "Badge Color": { "Color Space": "sRGB", "Red Component": 1.0000, "Green Component": 0.1491, "Blue Component": 0.0000, "Alpha Component": 0.50 },
      "Cursor Guide Color": { "Color Space": "sRGB", "Red Component": 0.7021, "Green Component": 0.9268, "Blue Component": 1.0000, "Alpha Component": 0.25 },
      "Keyboard Map": {
        "0xf702-0x300000": { "Action": 11, "Text": "0x01" },
        "0xf703-0x300000": { "Action": 11, "Text": "0x05" },
        "0xf702-0x280000": { "Action": 10, "Text": "b" },
        "0xf703-0x280000": { "Action": 10, "Text": "f" }
      }
    }
  ]
}
JSON
  # Colors: the "Apple System Colors" scheme from iTerm2-Color-Schemes.
  # Keyboard Map: Cmd-Left/Right send Ctrl-A/Ctrl-E (line start/end),
  # Option-Left/Right send Esc-b/Esc-f (word back/forward).
  ok "profile 'neo-term' -> $dir/neo-term.json (left Option = Esc+, right Option = normal)"
  ok "colors -> Apple System Colors"
  ok "Cmd-←/→ jump to line start/end, Option-←/→ jump by word"

  # iTerm2 rewrites its prefs on quit, so this only sticks if it isn't running.
  if pgrep -xq iTerm2; then
    warn "iTerm2 is running; make 'neo-term' the default in Settings > Profiles (or quit iTerm2 and re-run)"
  else
    defaults write com.googlecode.iterm2 "Default Bookmark Guid" -string "$guid"
    ok "neo-term set as the default iTerm2 profile"
  fi
}

setup_ghostty() {
  say "Configuring Ghostty"
  local GHOSTTY_DIR="$HOME/Library/Application Support/com.mitchellh.ghostty"
  local GHOSTTY_CFG="$GHOSTTY_DIR/config.ghostty"
  local GHOSTTY_LINE="config-file = ~/App/ghostty/config"
  mkdir -p "$GHOSTTY_DIR"
  if [[ -f "$GHOSTTY_CFG" ]] && grep -qxF "$GHOSTTY_LINE" "$GHOSTTY_CFG"; then
    ok "Ghostty include already present"
  else
    printf '%s\n' "$GHOSTTY_LINE" >>"$GHOSTTY_CFG"
    ok "added include -> $GHOSTTY_CFG"
  fi

  # Settings go into your own config (~/App/ghostty/config); each is only added
  # when that key isn't set yet, so your choices win.
  #  - font: the Nerd Font p10k is tuned for.
  #  - Option as Alt: for Alt-C / Alt-. (Ghostty's default types ç / ≥).
  #  - ssh-terminfo: Ghostty sets TERM=xterm-ghostty, which most remotes lack a
  #    terminfo entry for, breaking cursor/line-editing over SSH. ssh-terminfo
  #    installs it on the remote; ssh-env falls back to xterm-256color.
  local USER_GHOSTTY_CFG="$HOME/App/ghostty/config" line
  mkdir -p "$(dirname "$USER_GHOSTTY_CFG")"
  touch "$USER_GHOSTTY_CFG"
  for line in \
    "font-family = MesloLGS NF" \
    "macos-option-as-alt = true" \
    "shell-integration-features = ssh-env,ssh-terminfo"; do
    if grep -q "^${line%% =*}" "$USER_GHOSTTY_CFG"; then
      ok "Ghostty ${line%% =*} already set"
    else
      printf '%s\n' "$line" >>"$USER_GHOSTTY_CFG"
      ok "set '$line' -> $USER_GHOSTTY_CFG"
    fi
  done
}

case "$TERMINAL" in
  terminal) setup_terminal_app; TERM_NAME="Terminal" ;;
  iterm2)   setup_iterm2;       TERM_NAME="iTerm2" ;;
  ghostty)  setup_ghostty;      TERM_NAME="Ghostty" ;;
esac

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

# Ensure the desired plugins are enabled (order matters: syntax-highlighting last).
WANT_PLUGINS="git kubectl docker docker-compose fast-syntax-highlighting"
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
  alias l='eza -lbF -snew --git --icons --group-directories-first'
  alias ll='eza -lbha -snew --git --icons --group-directories-first'
  alias la='eza -lbhHigUmuSa -snew --git --icons --group-directories-first'
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
  1. Quit $TERM_NAME (Cmd-Q) and reopen it so the font + Option key settings apply.
  2. Configure the prompt:   p10k configure
  3. Import existing history into atuin (optional): atuin import auto

  New commands: cd (zoxide) · cdi · ls/l/ll/la/lt · cat (bat) · vim (nvim)
                top (btop) · y (yazi) · fd · rg · fzf (Ctrl-T/Alt-C/Ctrl-R)
EOF
