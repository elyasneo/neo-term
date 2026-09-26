# neo-term

A one-shot script that sets up a modern terminal toolchain on a fresh Mac, in
**iTerm2**.

```
iTerm2 · zsh · oh-my-zsh · powerlevel10k
fzf · zoxide · fd · ripgrep · eza · bat · atuin · yazi · btop · neovim
```

## Usage

```sh
./setup-terminal.sh
```

The script is **idempotent** — run it as often as you like. It installs anything
missing and skips whatever is already present. Your `~/.zshrc` is only touched to
set the theme and enable plugins, and a timestamped backup is made first.

> Targets macOS on Apple Silicon or Intel. It warns and continues on other
> systems, but is untested there.

## What it does

1. **Homebrew** — installs it if absent (this also pulls in the Xcode Command
   Line Tools, i.e. `git`), and adds `brew shellenv` to `~/.zprofile` so new
   iTerm2 windows find it.
   Right after that it installs iTerm2 if it isn't already installed, and stops
   if that install fails.
2. **CLI tools** — `brew install`s the formulae above, and downloads the
   **MesloLGS NF** fonts powerlevel10k is tuned for into `~/Library/Fonts`.
3. **iTerm2** — adds a `neo-term` Dynamic Profile with the MesloLGS NF font and
   left Option = Esc+ (so `Option-C`, `Option-.` etc. work instead of typing `ç` / `≥`;
   right Option still types special characters), made the default when iTerm2
   isn't running. It also maps `Cmd-←` / `Cmd-→` to line start / end and
   `Option-←` / `Option-→` to word back / forward. Its colors come from
   `themes/iterm2/One Dark.itermcolors`, and every scheme there is added to
   *Color Presets* (see [Themes](#themes)).
4. **oh-my-zsh** — unattended install if missing (keeps your existing `.zshrc`).
5. **Theme + plugins** — clones powerlevel10k and `fast-syntax-highlighting`,
   then enables them in
   `~/.zshrc` alongside the built-in `kubectl`, `docker`, and `docker-compose`
   plugins (extra completions plus `k`/`kgp`/… and `dco`/`dcup`/… aliases).
6. **Integrations + aliases** — writes `~/.oh-my-zsh/custom/modern-cli.zsh`, which
   oh-my-zsh sources *after* plugins so tool init and aliases win.

## After running

```sh
# Quit your terminal (Cmd-Q) and reopen it, then:
p10k configure        # configure the prompt
atuin import auto     # import existing history (optional)
```

## What changes in your shell

| You type | You get | Tool |
|----------|---------|------|
| `cd` | frecency-aware jump (`cdi` for the picker) | zoxide |
| `ls` / `l` / `ll` / `la` / `lt` | icon-rich listings & trees | eza |
| `cat` | syntax-highlighted output | bat |
| `vim` / `vi` | neovim | neovim |
| `top` / `htop` | resource monitor | btop |
| `y` | file manager that `cd`s to where you quit | yazi |
| `Ctrl-T` / `Option-C` / `Ctrl-R` | file / dir / history pickers | fzf + atuin |
| `neo-term` / `neo-term --help` | cheat sheet of everything above | neo-term |

`find` and `grep` are intentionally **not** aliased — use `fd` and `rg` directly
(different syntax); fzf already uses them under the hood.

## Themes

`themes/iterm2` holds the 80 color schemes from
[terminalcolors.com](https://terminalcolors.com/) as `.itermcolors` files, each
added as an iTerm2 *Color Preset* named after its file.

*One Dark* is the default. To change it, set `DEFAULT_THEME` in
`setup-terminal.sh` to another theme name (without extension) and re-run.
Same-named presets are replaced; others are left alone. Presets are only
written while iTerm2 isn't running (it rewrites its prefs on quit).

## Managed file

`~/.oh-my-zsh/custom/modern-cli.zsh` is fully managed by the script — edits there
are overwritten on the next run. Customize via your own `~/.zshrc` instead.
