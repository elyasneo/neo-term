#!/usr/bin/env bash
#
# setup-terminal.sh — provision a modern terminal toolchain.
#
#   Stack : iTerm2 + zsh + oh-my-zsh + powerlevel10k
#   Tools : fzf · zoxide · fd · ripgrep · eza · bat · atuin · yazi · btop · neovim
#
# Idempotent: safe to run repeatedly. Installs anything missing, then wires the
# tools into the shell via ~/.oh-my-zsh/custom/modern-cli.zsh (auto-sourced by
# oh-my-zsh after plugins). Your ~/.zshrc is only touched to enable plugins,
# and a timestamped backup is made first.
#
# Usage: ./setup-terminal.sh
#
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ---- pretty output ---------------------------------------------------------
c_ok=$'\033[32m'; c_info=$'\033[36m'; c_warn=$'\033[33m'; c_off=$'\033[0m'
say()  { printf '%s==>%s %s\n' "$c_info" "$c_off" "$*"; }
ok()   { printf '%s  ok%s %s\n' "$c_ok" "$c_off" "$*"; }
warn() { printf '%s  !!%s %s\n' "$c_warn" "$c_off" "$*"; }

[[ "$(uname -s)" == "Darwin" ]] || { warn "This script targets macOS."; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help) sed -n '2,13p' "$0"; exit 0 ;;
    *)         warn "unknown argument: $1"; exit 1 ;;
  esac
done

# ---- 1. Homebrew -----------------------------------------------------------
# On a fresh Mac brew is absent and, once installed, not on PATH: the installer
# only *prints* the shellenv line. We load it for this run and persist it in
# ~/.zprofile (iTerm2 opens login shells, which read it).
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

# ---- 1b. install iTerm2 if missing ---------------------------------------
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
ensure_app iTerm.app com.googlecode.iterm2 iterm2

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

# ---- 2b. iTerm2: font + Option-as-Meta ------------------------------------
# The profile gets the MesloLGS NF font and a Meta Option key, so Option-C
# (fzf cd), Option-. and friends work instead of typing ç / ≥.
TERM_FONT="MesloLGS-NF-Regular"   # PostScript name
TERM_FONT_SIZE=13
DEFAULT_THEME="One Dark"          # a theme name in themes/iterm2/, minus the extension

setup_iterm2() {
  say "Configuring iTerm2"
  # Color schemes live in themes/iterm2 next to this script (from terminalcolors.com);
  # DEFAULT_THEME colors the neo-term profile, and all of them become presets.
  local themes="$SCRIPT_DIR/themes/iterm2" theme_file="$SCRIPT_DIR/themes/iterm2/$DEFAULT_THEME.itermcolors"
  # A Dynamic Profile is a plain JSON file iTerm2 watches, so it works even
  # before iTerm2's first launch and is fully rewritten on every run.
  local dir="$HOME/Library/Application Support/iTerm2/DynamicProfiles"
  local guid="neo-term-profile" PB=/usr/libexec/PlistBuddy tmp
  mkdir -p "$dir"
  tmp="$(mktemp -t neo-term-profile)"
  cat >"$tmp" <<JSON
{
  "Profiles": [
    {
      "Name": "neo-term",
      "Guid": "$guid",
      "Normal Font": "$TERM_FONT $TERM_FONT_SIZE",
      "Option Key Sends": 2,
      "Right Option Key Sends": 0,
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
  # Keyboard Map: Cmd-Left/Right send Ctrl-A/Ctrl-E (line start/end),
  # Option-Left/Right send Esc-b/Esc-f (word back/forward).
  # Colors: an .itermcolors file uses the same keys as a profile, so merge the
  # default theme straight into it (as a plist, then back to JSON).
  plutil -convert xml1 "$tmp"
  if [[ -f "$theme_file" ]]; then
    "$PB" -c "Merge \"$theme_file\" :Profiles:0" "$tmp" >/dev/null
  else
    warn "theme '$DEFAULT_THEME' not found in $themes; keeping iTerm2's default colors"
  fi
  plutil -convert json -o "$dir/neo-term.json" "$tmp"
  rm -f "$tmp"
  ok "profile 'neo-term' -> $dir/neo-term.json (left Option = Esc+, right Option = normal)"
  ok "colors -> $DEFAULT_THEME"
  ok "Cmd-←/→ jump to line start/end, Option-←/→ jump by word"

  # iTerm2 rewrites its prefs on quit, so these only stick if it isn't running.
  if pgrep -xq iTerm2; then
    warn "iTerm2 is running; quit it and re-run to add the color presets and make 'neo-term' the default"
    return
  fi
  # Each theme becomes a Color Preset named after its file, replacing a preset
  # of the same name; other custom presets are left alone. Edited through
  # cfprefsd (export -> PlistBuddy -> import) rather than the plist file directly.
  local prefs f name n=0
  prefs="$(mktemp -t iterm2-prefs)"
  defaults export com.googlecode.iterm2 "$prefs"
  "$PB" -c "Add ':Custom Color Presets' dict" "$prefs" 2>/dev/null || true
  for f in "$themes"/*.itermcolors; do
    [[ -f "$f" ]] || continue
    name="$(basename "$f" .itermcolors)"
    "$PB" -c "Delete ':Custom Color Presets:$name'" "$prefs" 2>/dev/null || true
    "$PB" -c "Add ':Custom Color Presets:$name' dict" -c "Merge \"$f\" ':Custom Color Presets:$name'" "$prefs" >/dev/null
    n=$((n + 1))
  done
  defaults import com.googlecode.iterm2 "$prefs"
  rm -f "$prefs"
  ok "$n color presets added (Settings > Profiles > Colors > Color Presets)"

  defaults write com.googlecode.iterm2 "Default Bookmark Guid" -string "$guid"
  ok "neo-term set as the default iTerm2 profile"
}

setup_iterm2

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
  # Keybindings + completion (Homebrew path). Binds Ctrl-T / Option-C / Ctrl-R.
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

# --- neo-term: cheat sheet of everything this setup provides --------------
function neo-term() {
  case "${1:-}" in
    ""|-h|--help|help) ;;
    *) print -u2 "neo-term: unknown argument: $1 (try: neo-term --help)"; return 1 ;;
  esac
  local b=$'\e[1;36m' c=$'\e[32m' o=$'\e[0m'
  cat <<EOF
${b}neo-term${o} — commands provided by setup-terminal.sh

${b}Navigation${o}
  ${c}cd <dir>${o}        frecency-aware jump, e.g. "cd proj" (zoxide)
  ${c}cdi${o}             interactive directory picker (zoxide)
  ${c}y${o}               file manager; cd's to the dir you quit in (yazi)

${b}Listing & viewing${o}
  ${c}ls${o}              icons, dirs first (eza)
  ${c}l${o}               long list, newest first, git status
  ${c}ll${o}              long list incl. hidden files
  ${c}la${o}              long list, all details
  ${c}lt${o}              tree, 2 levels
  ${c}tree${o}            full tree
  ${c}cat <file>${o}      syntax-highlighted output (bat)

${b}Search${o}
  ${c}fd <pattern>${o}    find files (instead of find)
  ${c}rg <pattern>${o}    search file contents (instead of grep)
  ${c}fzf${o}             fuzzy finder

${b}Editing & monitoring${o}
  ${c}vim${o} / ${c}vi${o}        neovim
  ${c}top${o} / ${c}htop${o}      resource monitor (btop)

${b}Keybindings${o}
  ${c}Ctrl-T${o}          pick a file, with preview (fzf)
  ${c}Option-C${o}        pick a directory and cd into it (fzf)
  ${c}Ctrl-R${o}          search shell history (atuin)
  ${c}Cmd-←/→${o}         jump to line start / end (iTerm2)
  ${c}Option-←/→${o}      jump word back / forward (iTerm2)

${b}oh-my-zsh plugins${o}
  ${c}git${o}             g, gst, gco, gp, gl, ...
  ${c}kubectl${o}         k, kgp, kgs, kl, kaf, ...
  ${c}docker-compose${o}  dco, dcup, dcdn, dcl, ...
  (list any plugin's aliases with: alias | grep '^k')

${b}Setup${o}
  ${c}p10k configure${o}     reconfigure the prompt
  ${c}atuin import auto${o}  import existing shell history
  ${c}neo-term${o}           show this help (also: neo-term --help)
EOF
}
ZRC
ok "modern-cli.zsh written"

# ---- 7. done ---------------------------------------------------------------
echo
ok "Setup complete."
say "Next steps:"
cat <<EOF
  1. Quit iTerm2 (Cmd-Q) and reopen it so the font + Option key settings apply.
  2. Configure the prompt:   p10k configure
  3. Import existing history into atuin (optional): atuin import auto

  New commands: cd (zoxide) · cdi · ls/l/ll/la/lt · cat (bat) · vim (nvim)
                top (btop) · y (yazi) · fd · rg · fzf (Ctrl-T/Option-C/Ctrl-R)
  Run 'neo-term' (or 'neo-term --help') any time to list them all.
EOF
