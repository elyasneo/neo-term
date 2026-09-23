# neo-term

A one-shot script that sets up a modern terminal toolchain on a fresh Mac, in the
terminal of your choice: **Terminal.app** (built in), **iTerm2** or **Ghostty**.

```
Terminal.app | iTerm2 | Ghostty · zsh · oh-my-zsh · powerlevel10k
fzf · zoxide · fd · ripgrep · eza · bat · atuin · yazi · btop · neovim
```

## Usage

```sh
./setup-terminal.sh                      # asks which terminal to set up
./setup-terminal.sh --terminal iterm2    # or pick one: terminal | iterm2 | ghostty
```

Without `--terminal` and without a TTY (e.g. piped), it uses Terminal.app.

The script is **idempotent** — run it as often as you like. It installs anything
missing and skips whatever is already present. Your `~/.zshrc` is only touched to
set the theme and enable plugins, and a timestamped backup is made first.

> Targets macOS on Apple Silicon or Intel. It warns and continues on other
> systems, but is untested there.

## What it does

1. **Homebrew** — installs it if absent (this also pulls in the Xcode Command
   Line Tools, i.e. `git`), and adds `brew shellenv` to `~/.zprofile` so new
   Terminal windows find it.
   Right after that it installs the terminal you picked (iTerm2 or Ghostty) if
   it isn't already installed, and stops if that install fails.
2. **CLI tools** — `brew install`s the formulae above, and downloads the
   **MesloLGS NF** fonts powerlevel10k is tuned for into `~/Library/Fonts`.
3. **Your terminal** — sets the font to MesloLGS NF and makes Option act as
   Meta/Alt so `Alt-C`, `Alt-.` etc. work instead of typing `ç` / `≥`:
   - **Terminal.app** — edits the default profile (font 13, *Use Option as Meta
     key*). Option then no longer types special characters.
   - **iTerm2** — adds a `neo-term` Dynamic
     Profile (left Option = Esc+, right Option still types special characters),
     made the default when iTerm2 isn't running. It also maps `Cmd-←` / `Cmd-→`
     to line start / end and `Option-←` / `Option-→` to word back / forward.
   - **Ghostty** — includes `~/App/ghostty/config`
     from Ghostty's config, and adds `font-family`, `macos-option-as-alt` and
     SSH terminfo to it only where those keys aren't set yet.
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
| `Ctrl-T` / `Alt-C` / `Ctrl-R` | file / dir / history pickers | fzf + atuin |

`find` and `grep` are intentionally **not** aliased — use `fd` and `rg` directly
(different syntax); fzf already uses them under the hood.

## Managed file

`~/.oh-my-zsh/custom/modern-cli.zsh` is fully managed by the script — edits there
are overwritten on the next run. Customize via your own `~/.zshrc` instead.
