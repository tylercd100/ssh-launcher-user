# ssh-launcher-user

Create a dedicated Linux user that **auto-launches a chosen command on interactive SSH login**. Useful for sandboxing AI coding agents (Claude Code, OpenAI Codex CLI, Aider, Gemini CLI, OpenCode, Goose, Cursor Agent, …) on a host while keeping their state, sudo scope, and code tree isolated from your primary account.

Single bash script. No clone required — pipe and run.

## Quick start

**Interactive (no install):**

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/tylercd100/ssh-launcher-user/main/ssh-launcher-user)
```

`bash <(...)` uses process substitution so the script's own stdin stays attached to your terminal — interactive prompts work normally (unlike `curl | bash`, where stdin is the script itself).

**Non-interactive one-liner:**

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/tylercd100/ssh-launcher-user/main/ssh-launcher-user) \
    create --username codebot --preset claude --yes
```

**Install once, reuse:**

```bash
sudo curl -fsSL -o /usr/local/bin/ssh-launcher-user \
    https://raw.githubusercontent.com/tylercd100/ssh-launcher-user/main/ssh-launcher-user
sudo chmod +x /usr/local/bin/ssh-launcher-user

ssh-launcher-user                  # interactive create
ssh-launcher-user rollback --help  # undo a previous run
```

## What it does

For a chosen `--username`:

1. Creates the user (`useradd -m -s /bin/bash`, optionally in `sudo` group).
2. Mirrors your existing `~/.ssh/authorized_keys` into the new user's `~/.ssh/` so the same SSH key works.
3. Optionally copies your `.gitconfig` so commits keep your name/email.
4. Optionally re-enables `PasswordAuthentication` in `sshd_config.d/*.conf` if cloud-init (or similar) had disabled it.
5. Optionally moves an existing directory into the new user's home (`mv` + `chown -R` — instant on the same filesystem).
6. Optionally installs a binary to `/usr/local/bin/` so the new user can run it (handy when the binary lives in the source user's `~/.local/`).
7. Writes a `.bash_profile` that, on **interactive SSH login**, `cd`s into the chosen directory and `exec`s your launch command. The session ends when the command exits.
8. Optionally runs `passwd USERNAME` interactively.

The `rollback` subcommand undoes all of this in one command.

## Why a separate user?

Running an autonomous agent like `claude --dangerously-skip-permissions` over SSH gives whoever holds that user's credentials a root-capable shell with permission prompts disabled. That's a real blast-radius decision. Keeping it on a dedicated user means:

- Limited sudo scope (you choose passwordless / password / no sudo)
- The agent's `~/.<tool>/` state and login session is isolated from your primary user
- File ownership is unambiguous — anything the agent created is owned by the agent user
- One-command teardown — `ssh-launcher-user rollback --username NAME`

## Presets

| Preset       | Default launch command          | Optional opt-in flag           |
|--------------|----------------------------------|---------------------------------|
| `claude`     | `claude`                         | `--dangerously-skip-permissions`|
| `aider`      | `aider`                          | `--yes-always`                  |
| `codex`      | `codex`                          | —                               |
| `gemini`     | `gemini`                         | —                               |
| `opencode`   | `opencode`                       | —                               |
| `goose`      | `goose session`                  | —                               |
| `cursor-agent` | `cursor-agent`                 | —                               |
| `shell`      | *(none — plain shell on login)*  | —                               |
| `custom`     | *(prompt for a custom command)*  | —                               |

Override or add flags with `--launch-cmd 'codex --my-flag'`.

> **Note on "skip all prompts" flags**: For presets where one exists (`claude`, `aider`), the script defaults to the *safe* command. In interactive mode it asks whether to append the opt-in flag and explains what it does (auto-approves every tool use / confirmation — effectively unattended root-capable execution on a sudoer user). To opt in non-interactively, pass it via `--launch-cmd`, e.g. `--launch-cmd 'claude --dangerously-skip-permissions'`.

## Examples

```bash
# Fully interactive
ssh-launcher-user

# Set up 'codebot' to auto-run claude in ~/code/myapp, move that dir into ~codebot/
ssh-launcher-user create \
    --username codebot \
    --preset claude \
    --source-dir ~/code/myapp \
    --yes

# An 'opsbot' user that drops into a tmux session, no sudo
ssh-launcher-user create \
    --username opsbot \
    --launch-cmd 'tmux attach -t ops || tmux new -s ops' \
    --no-sudo \
    --yes

# Install the claude binary system-wide while creating the user
ssh-launcher-user create \
    --username claudebot \
    --preset claude \
    --install-binary ~/.local/share/claude/versions/2.1.145 \
    --yes

# Preview without making changes
ssh-launcher-user create --username foo --preset aider --dry-run

# Tear it all down
ssh-launcher-user rollback --username codebot \
    --restore-dir ~/code/myapp --from-dest myapp \
    --uninstall-binary /usr/local/bin/claude
```

Run `ssh-launcher-user --help`, `ssh-launcher-user create --help`, or `ssh-launcher-user rollback --help` for the full flag list.

## The recursive-exec trap (important)

Claude Code's Bash tool sources the user's profile (`.bash_profile` on login) on every command it runs. A naïve auto-launch like:

```bash
# DON'T do this — recursive trap
if [[ -n "$SSH_TTY" ]]; then
    exec claude --dangerously-skip-permissions
fi
```

…breaks for any tool that auto-spawns shells, because each subshell sources `.bash_profile` again, sees `$SSH_TTY` (inherited), and recursively `exec`s claude. The inner claude has no controlling TTY, falls into `--print` mode, and dies on missing stdin.

This tool guards against that with a one-shot env var, `AUTO_LAUNCHED`:

```bash
if [[ -n "${SSH_TTY:-}" && -z "${AUTO_LAUNCHED:-}" ]]; then
    export AUTO_LAUNCHED=1
    cd "$LAUNCH_DIR"
    exec $LAUNCH_CMD
fi
```

The outer login shell sets and exports `AUTO_LAUNCHED=1`; any subshell the launched program spawns inherits it and short-circuits past the `exec`. Standard non-recursion pattern; works for any agent that has the same subshell-spawning behavior.

## Requirements

- Linux with a recent OpenSSH server
- `sudo` available to the running user
- Bash 4+ (associative arrays)
- Run as a regular sudoer — the script refuses to run as root so `$SUDO_USER` context stays clean.

## License

MIT
