# neo-term

A one-shot script that provisions a modern terminal toolchain on macOS.

```
ghostty · zsh · oh-my-zsh · powerlevel10k
fzf · zoxide · fd · ripgrep · eza · bat · atuin · yazi · btop · neovim
```

## Usage

```sh
./setup-terminal.sh
```

The script is **idempotent** — run it as often as you like. It installs anything
missing and skips whatever is already present. Your `~/.zshrc` is only touched to
set the theme and enable plugins, and a timestamped backup is made first.

> Targets macOS (Apple Silicon paths). It warns and continues on other systems,
> but is untested there.

## What it does

1. **Homebrew** — installs it if absent.
2. **CLI tools** — `brew install`s the formulae above, plus the **MesloLGS Nerd
   Font** cask recommended by powerlevel10k.
3. **Ghostty** — appends an `include` for `~/App/ghostty/config` to Ghostty's
   config so your own settings are sourced.
4. **oh-my-zsh** — unattended install if missing (keeps your existing `.zshrc`).
5. **Theme + plugins** — clones powerlevel10k, `zsh-autosuggestions`,
   `zsh-completions`, and `fast-syntax-highlighting`, then enables them in
   `~/.zshrc` alongside the built-in `kubectl`, `docker`, and `docker-compose`
   plugins (extra completions plus `k`/`kgp`/… and `dco`/`dcup`/… aliases).
6. **Integrations + aliases** — writes `~/.oh-my-zsh/custom/modern-cli.zsh`, which
   oh-my-zsh sources *after* plugins so tool init and aliases win.

## After running

```sh
exec zsh              # reload the shell
p10k configure        # configure the prompt
atuin import auto     # import existing history (optional)
```

Then set the Ghostty font to **MesloLGS NF**.

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
