#!/usr/bin/env bash
# Avoid locale warnings on systems without en_US.UTF-8 generated
export LC_ALL=${LC_ALL:-C}
export LANG=${LANG:-C.UTF-8}
set -euo pipefail

# Helper to encrypt inventory files with ansible-vault.
# Usage: ./scripts/encrypt-inventory.sh [--password-file /path/to/pass] [--in-place] file1 [file2 ...]
# By default this script writes encrypted outputs to <file>.enc. Pass
# `--in-place` to encrypt files in-place (replace plaintext with vault
# encrypted file). The default `.enc` output is useful when you track `.enc`
# files in git and keep plaintext locally.

if ! command -v ansible-vault >/dev/null 2>&1; then
  echo "ansible-vault not found; install Ansible first." >&2
  exit 2
fi

PASSWORD_FILE=""
# Default to writing to .enc files
TO_ENC=1

# Add an alternative flag to force in-place encryption
IN_PLACE=0

# Parse optional flags
while [[ ${1-} ]]; do
  case "$1" in
    --password-file)
      PASSWORD_FILE="$2"
      shift 2
      ;;
    --in-place)
      IN_PLACE=1
      TO_ENC=0
      shift
      ;;
    --)
      shift
      break
      ;;
    -* )
      break
      ;;
    *)
      break
      ;;
  esac
done

# If no files provided, default to encrypting all YAML files under inventory/
if [[ $# -lt 1 ]]; then
  # gather files (NUL-separated safe list)
  mapfile -d $'\0' files < <(find inventory -type f \( -name '*.yml' -o -name '*.yaml' \) -print0)
  if [[ ${#files[@]} -eq 0 ]]; then
    echo "No files found under inventory/ to encrypt." >&2
    exit 2
  fi
  set -- "${files[@]}"
fi

# If VAULT_PASS is not set and no explicit password file provided, prefer a repo-local
# 'vault-password' file in the current directory or git top-level. This mirrors
# scripts/decrypt-inventory.sh so hooks and CI can be non-interactive using a
# local password file. VAULT_PASS still overrides any file.
if [[ -z "${VAULT_PASS-}" && -z "${PASSWORD_FILE-}" ]]; then
  if [[ -f "./vault-password" ]]; then
    PASSWORD_FILE="./vault-password"
    echo "Using repo vault-password file: $PASSWORD_FILE"
  elif command -v git >/dev/null 2>&1; then
    GROOT=$(git rev-parse --show-toplevel 2>/dev/null || true)
    if [[ -n "$GROOT" && -f "$GROOT/vault-password" ]]; then
      PASSWORD_FILE="$GROOT/vault-password"
      echo "Using repo vault-password file: $PASSWORD_FILE"
    fi
  fi
fi

for f in "$@"; do
  if [[ ! -f "$f" ]]; then
    echo "Skipping $f: not a regular file." >&2
    continue
  fi

  # If input already looks encrypted, avoid calling ansible-vault encrypt on it
  if sed -n '1p' "$f" 2>/dev/null | grep -q '^\$ANSIBLE_VAULT'; then
    if [[ "$TO_ENC" -eq 1 ]]; then
      ENC_FILE="${f}.enc"
      echo "Input $f already encrypted — copying to $ENC_FILE"
      if [[ -f "$ENC_FILE" ]]; then
        if cmp -s "$f" "$ENC_FILE"; then
          echo "Encrypted target up-to-date: $ENC_FILE"
        else
          cp -- "$f" "$ENC_FILE"
        fi
      else
        cp -- "$f" "$ENC_FILE"
      fi
    else
      echo "Skipping $f: already encrypted (in-place mode)"
    fi
    continue
  fi

  if [[ "$TO_ENC" -eq 1 ]]; then
    ENC_FILE="${f}.enc"
    echo "Encrypting $f -> $ENC_FILE"
    if [[ -n "${VAULT_PASS-}" ]]; then
      ansible-vault encrypt --vault-password-file <(printf '%s' "$VAULT_PASS") --output "$ENC_FILE" "$f"
    elif [[ -n "$PASSWORD_FILE" ]]; then
      ansible-vault encrypt --vault-password-file "$PASSWORD_FILE" --output "$ENC_FILE" "$f"
    else
      ansible-vault encrypt --output "$ENC_FILE" "$f"
    fi
  else
    echo "Encrypting $f in-place..."
    if [[ -n "${VAULT_PASS-}" ]]; then
      ansible-vault encrypt --vault-password-file <(printf '%s' "$VAULT_PASS") "$f"
    elif [[ -n "$PASSWORD_FILE" ]]; then
      ansible-vault encrypt --vault-password-file "$PASSWORD_FILE" "$f"
    else
      ansible-vault encrypt "$f"
    fi
  fi
done

echo "Done. Remember to git add the encrypted files if using --to-enc." 
