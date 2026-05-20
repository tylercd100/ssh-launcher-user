# ssh-launcher-user

Create a dedicated Linux user that **auto-launches a chosen command on interactive SSH login**. Useful for sandboxing AI coding agents (Claude Code, OpenAI Codex CLI, Aider, Gemini CLI, OpenCode, Goose, Cursor Agent, …) on a host while keeping their state, sudo scope, and code tree isolated from your primary account.

Interactive by default; accepts CLI flags for non-interactive use.

## What it does

For a chosen `--username`:

1. Creates the user (`useradd -m -s /bin/bash`, optionally in `sudo` group).
2. Mirrors your existing `~/.ssh/authorized_keys` into the new user's `~/.ssh/` so the same SSH key works.
3. Optionally copies your `.gitconfig` so commits keep your name/email.
4. Optionally re-enables `PasswordAuthentication` in `sshd_config.d/*.conf` if cloud-init (or similar) had disabled it.
5. Optionally moves an existing directory into the new user's home (`mv` + `chown -R` — instant on the same filesystem).
6. Optionally installs a binary to `/usr/local/bin/` so the new user can run it.
7. Writes a `.bash_profile` that, on **interactive SSH login**, `cd`s into the chosen directory and `exec`s your launch command. The session ends when the command exits.
8. Optionally runs `passwd USERNAME` interactively.

A companion `rollback.sh` undoes all of this in one command.

## Why a separate user?

Running an autonomous agent like `claude --dangerously-skip-permissions` over SSH gives whoever holds that user's credentials a root-capable shell with permission prompts disabled. That's a real blast-radius decision. Keeping it on a dedicated user means:

- Limited sudo scope (you choose passwordless / password / no sudo)
- The agent's `~/.<tool>/` state and login session is isolated from your primary user
- File ownership is unambiguous — anything the agent created is owned by the agent user
- One-command rollback (`./rollback.sh --username NAME`) — clean teardown

## Quick start

```bash
git clone <this-repo>
cd ssh-launcher-user

./ssh-launcher-user
# Answer prompts: username, preset (claude/codex/aider/…), source dir, etc.
# Then verify in a separate terminal:
ssh NEW_USER@<host>
```

## Presets

| Preset       | Default launch command                  |
|--------------|------------------------------------------|
| `claude`     | `claude --dangerously-skip-permissions` |
| `codex`      | `codex`                                  |
| `aider`      | `aider --yes-always`                     |
| `gemini`     | `gemini`                                 |
| `opencode`   | `opencode`                               |
| `goose`      | `goose session`                          |
| `cursor-agent` | `cursor-agent`                         |
| `shell`      | *(none — plain shell on login)*          |
| `custom`     | *(prompt for a custom command)*          |

Flag forms are exact strings — if a tool ships with different default flags than the table above, override with `--launch-cmd 'codex --my-flag'`.

## Non-interactive examples

```bash
# Set up 'codebot' to auto-run claude in ~/code/myapp
./ssh-launcher-user \
    --username codebot \
    --preset claude \
    --source-dir ~/code/myapp \
    --yes

# A 'opsbot' user that drops into a tmux session
./ssh-launcher-user \
    --username opsbot \
    --launch-cmd 'tmux attach -t ops || tmux new -s ops' \
    --no-sudo \
    --yes

# Preview without making changes
./ssh-launcher-user --username foo --preset aider --dry-run
```

Run `./ssh-launcher-user --help` for the full flag list.

## The recursive-exec trap (important)

Claude Code's Bash tool sources the user's profile (`.bash_profile` on login) on every command it runs — see Anthropic's docs. A naive auto-launch like:

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

## Rollback

```bash
./rollback.sh --username codebot \
    --restore-dir ~/code/myapp --from-dest myapp \
    --uninstall-binary /usr/local/bin/claude
```

Removes the user, restores the moved directory to its original location with original ownership, and removes the system-installed binary. The script prints the exact rollback command for your setup after a successful run.

## Requirements

- Linux with a recent OpenSSH server
- `sudo` available to the running user
- Bash 4+
- Run as a regular sudoer — the script refuses to run as root so `$SUDO_USER` context stays clean.

## License

MIT
