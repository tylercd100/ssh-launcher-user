#!/usr/bin/env bash
# rollback.sh — undo a previous ssh-launcher-user setup.
#
# Removes the user (incl. their home directory), and optionally moves a
# relocated directory back to its original location and removes a binary
# installed under /usr/local/bin/.
#
# Examples:
#   ./rollback.sh --username codebot
#   ./rollback.sh --username codebot \
#       --restore-dir /home/tyler/code/proj --from-dest proj \
#       --uninstall-binary /usr/local/bin/claude

set -euo pipefail

USERNAME=""
RESTORE_DIR=""
FROM_DEST=""
UNINSTALL_BINARY=""
ASSUME_YES=0

usage() {
    cat <<EOF
USAGE
    $(basename "$0") --username NAME [OPTIONS]

OPTIONS
    --username NAME             User to remove (required)
    --restore-dir PATH          Original path to restore the moved dir to
    --from-dest NAME            Name of the dir inside ~USERNAME (required if --restore-dir set)
    --uninstall-binary PATH     Remove a binary installed in /usr/local/bin/
    -y, --yes                   Skip confirmation
    -h, --help                  Show this help
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --username)         USERNAME="$2"; shift 2 ;;
        --restore-dir)      RESTORE_DIR="$2"; shift 2 ;;
        --from-dest)        FROM_DEST="$2"; shift 2 ;;
        --uninstall-binary) UNINSTALL_BINARY="$2"; shift 2 ;;
        -y|--yes)           ASSUME_YES=1; shift ;;
        -h|--help)          usage; exit 0 ;;
        *) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
    esac
done

[[ -n "$USERNAME" ]] || { echo "--username required" >&2; exit 2; }
[[ $EUID -eq 0 ]] && { echo "Run as a sudoer, not root." >&2; exit 1; }

if [[ -n "$RESTORE_DIR" && -z "$FROM_DEST" ]]; then
    echo "--from-dest is required when --restore-dir is used" >&2
    exit 2
fi

echo "Plan:"
echo "  Remove user:      $USERNAME (and home directory)"
[[ -n "$RESTORE_DIR" ]]      && echo "  Restore dir:      /home/$USERNAME/$FROM_DEST → $RESTORE_DIR"
[[ -n "$UNINSTALL_BINARY" ]] && echo "  Remove binary:    $UNINSTALL_BINARY"

if (( ! ASSUME_YES )); then
    read -r -p "Proceed? [y/N]: " ans
    [[ "${ans:-n}" =~ ^[Yy]$ ]] || { echo "Aborted."; exit 1; }
fi

sudo bash <<EOF
set -euo pipefail

USERNAME='$USERNAME'
RESTORE_DIR='$RESTORE_DIR'
FROM_DEST='$FROM_DEST'
UNINSTALL_BINARY='$UNINSTALL_BINARY'

# Restore the moved directory before deleting the user's home
if [[ -n "\$RESTORE_DIR" && -d "/home/\$USERNAME/\$FROM_DEST" ]]; then
    if [[ -e "\$RESTORE_DIR" ]]; then
        echo "[!] \$RESTORE_DIR already exists, skipping restore" >&2
    else
        mkdir -p "\$(dirname "\$RESTORE_DIR")"
        mv "/home/\$USERNAME/\$FROM_DEST" "\$RESTORE_DIR"
        # chown back to the original owner of the parent dir
        OWNER="\$(stat -c '%U:%G' "\$(dirname "\$RESTORE_DIR")")"
        chown -R "\$OWNER" "\$RESTORE_DIR"
        echo "[+] Restored \$RESTORE_DIR (owner: \$OWNER)"
    fi
fi

# Remove the user (and home)
if id "\$USERNAME" &>/dev/null; then
    pkill -KILL -u "\$USERNAME" 2>/dev/null || true
    userdel -r "\$USERNAME"
    echo "[+] Removed user \$USERNAME"
else
    echo "[~] User \$USERNAME not present"
fi

# Remove installed binary
if [[ -n "\$UNINSTALL_BINARY" && -e "\$UNINSTALL_BINARY" ]]; then
    rm -f "\$UNINSTALL_BINARY"
    echo "[+] Removed \$UNINSTALL_BINARY"
fi
EOF

echo "Rollback complete."
