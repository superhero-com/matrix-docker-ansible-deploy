#!/usr/bin/env bash
# Decrypt ansible-vault encrypted YAML files under inventory/ (or given dir)
export LC_ALL=${LC_ALL:-C}
export LANG=${LANG:-C.UTF-8}
set -euo pipefail

if ! command -v ansible-vault >/dev/null 2>&1; then
  echo "ansible-vault not found; install Ansible first." >&2
  exit 2
fi

PASSWORD_FILE=""
TARGET_DIR="inventory"
POS_ARGS=()
while [[ ${#} -gt 0 ]]; do
  case "$1" in
    --password-file)
      PASSWORD_FILE="$2"
      shift 2
      ;;
    --)
      shift
      break
      ;;
    -* )
      echo "Unknown option: $1" >&2
      exit 2
      ;;
    *)
      POS_ARGS+=("$1")
      shift
      ;;
  esac
done

if [[ ${#POS_ARGS[@]} -gt 0 ]]; then
  # If a specific path was provided, use that (can be .enc or plain file)
  TARGET_DIR="${POS_ARGS[0]}"
fi

# If VAULT_PASS is not set, prefer a repo-local 'vault-password' file at the repository root
# unless an explicit --password-file was provided. This allows non-interactive hooks to work
# for local clones that keep a plain password file (repo may choose to keep it out of git).
if [[ -z "${VAULT_PASS-}" && -z "${PASSWORD_FILE-}" ]]; then
  # Search for a top-level vault-password file in the repository root or current dir
  if [[ -f "./vault-password" ]]; then
    PASSWORD_FILE="./vault-password"
    echo "Using repo vault-password file: $PASSWORD_FILE"
  elif command -v git >/dev/null 2>&1; then
    # If inside a git repo, look at its worktree root
    GROOT=$(git rev-parse --show-toplevel 2>/dev/null || true)
    if [[ -n "$GROOT" && -f "$GROOT/vault-password" ]]; then
      PASSWORD_FILE="$GROOT/vault-password"
      echo "Using repo vault-password file: $PASSWORD_FILE"
    fi
  fi
fi

TS=$(date +%s)

# If there are plaintext YAML files without a matching .enc, warn the user.
# We do not auto-create .enc files here (to avoid surprising writes during
# checkout). If you want auto-creation, we can add an opt-in flag that will
# encrypt plaintext when VAULT_PASS or a password file is available.
while IFS= read -r -d '' _plain; do
  enc_file="${_plain}.enc"
  if [[ ! -f "$enc_file" ]]; then
    echo "Notice: encrypted counterpart missing for plaintext '$_plain' (expected $enc_file)."
    echo "  To create it: scripts/encrypt-inventory.sh --password-file /path/to/vault-password $_plain"
    echo "  Or set VAULT_PASS and run scripts/encrypt-inventory.sh $_plain"
  fi
done < <(find "$TARGET_DIR" -type f \( -name '*.yml' -o -name '*.yaml' \) -print0)

if [[ -f "$TARGET_DIR" && ( "$TARGET_DIR" == *.enc || "$TARGET_DIR" == *.yaml || "$TARGET_DIR" == *.yml ) ]]; then
  # Single file provided: if it's an .enc decrypt to the corresponding plain name
  f="$TARGET_DIR"
  if [[ "$f" == *.enc ]]; then
    PLAINT="${f%.enc}"
    echo "Decrypting $f -> $PLAINT"
    # (fall through to existing decrypt logic for a single file)
    SINGLE_MODE=1
  else
    # Provided file is plain YAML: attempt to find corresponding .enc if present
    if [[ -f "${f}.enc" ]]; then
      ENC_CAND="${f}.enc"
      PLAINT="$f"
      echo "Decrypting $ENC_CAND -> $PLAINT"
      f="$ENC_CAND"
      SINGLE_MODE=1
    else
      echo "No .enc counterpart found for provided file: $f" >&2
      SINGLE_MODE=0
    fi
  fi
fi

if [[ ${SINGLE_MODE-0} -eq 1 ]]; then
  # Single-file decrypt path
  TMPOUT="${f}.decrypted.$TS"
      TMPOUT="${f}.decrypted.$TS"

      # Run ansible-vault view and capture stderr so we can detect wrong password
  if [[ -n "${VAULT_PASS-}" ]]; then
    if ! ansible-vault view --vault-password-file <(printf '%s' "$VAULT_PASS") "$f" > "$TMPOUT" 2>"${TMPOUT}.err"; then
      ERRMSG=$(<"${TMPOUT}.err" 2>/dev/null || true)
      rm -f "$TMPOUT" "${TMPOUT}.err"
      if printf '%s' "$ERRMSG" | grep -qiE 'invalid vault password|decryption failed|stanza header'; then
        echo "Warning: could not decrypt $f — wrong vault password or corrupt vault file. Set VAULT_PASS or provide --password-file to decrypt." >&2
      else
        echo "Warning: failed to decrypt $f: $ERRMSG" >&2
      fi
    else
      rm -f "${TMPOUT}.err" || true
      if [[ -f "$PLAINT" ]] && cmp -s "$PLAINT" "$TMPOUT"; then
        echo "Decrypted content identical to existing $PLAINT; no changes made"
        rm -f "$TMPOUT"
      else
        if [[ -f "$PLAINT" ]]; then
          cp -- "$PLAINT" "${PLAINT}.bak-$TS"
        fi
        mv -f "$TMPOUT" "$PLAINT"
      fi
    fi
  elif [[ -n "$PASSWORD_FILE" ]]; then
    if ! ansible-vault view --vault-password-file "$PASSWORD_FILE" "$f" > "$TMPOUT" 2>"${TMPOUT}.err"; then
      ERRMSG=$(<"${TMPOUT}.err" 2>/dev/null || true)
      rm -f "$TMPOUT" "${TMPOUT}.err"
      if printf '%s' "$ERRMSG" | grep -qiE 'invalid vault password|decryption failed|stanza header'; then
        echo "Warning: could not decrypt $f with provided password file — wrong password or corrupt vault file." >&2
      else
        echo "Warning: failed to decrypt $f: $ERRMSG" >&2
      fi
    else
      rm -f "${TMPOUT}.err" || true
      if [[ -f "$PLAINT" ]] && cmp -s "$PLAINT" "$TMPOUT"; then
        echo "Decrypted content identical to existing $PLAINT; no changes made"
        rm -f "$TMPOUT"
      else
        if [[ -f "$PLAINT" ]]; then
          cp -- "$PLAINT" "${PLAINT}.bak-$TS"
        fi
        mv -f "$TMPOUT" "$PLAINT"
      fi
    fi
  else
    if [[ -t 0 ]]; then
      if ! ansible-vault view "$f" > "$TMPOUT" 2>"${TMPOUT}.err"; then
        ERRMSG=$(<"${TMPOUT}.err" 2>/dev/null || true)
        rm -f "$TMPOUT" "${TMPOUT}.err"
        echo "Warning: interactive decrypt of $f failed: $ERRMSG" >&2
      else
        rm -f "${TMPOUT}.err" || true
        if [[ -f "$PLAINT" ]] && cmp -s "$PLAINT" "$TMPOUT"; then
          echo "Decrypted content identical to existing $PLAINT; no changes made"
          rm -f "$TMPOUT"
        else
          if [[ -f "$PLAINT" ]]; then
            cp -- "$PLAINT" "${PLAINT}.bak-$TS"
          fi
          mv -f "$TMPOUT" "$PLAINT"
        fi
      fi
    else
      echo "No VAULT_PASS and no --password-file provided and no TTY — skipping decrypt of $f" >&2
      rm -f "$TMPOUT" || true
    fi
  fi

  exit 0
fi

# Default behavior: iterate .yml.enc files under TARGET_DIR
while IFS= read -r -d '' f; do
  PLAINT="${f%.enc}"
  echo "Decrypting $f -> $PLAINT"
  TMPOUT="${f}.decrypted.$TS"

  if [[ -n "${VAULT_PASS-}" ]]; then
    if ! ansible-vault view --vault-password-file <(printf '%s' "$VAULT_PASS") "$f" > "$TMPOUT" 2>"${TMPOUT}.err"; then
      ERRMSG=$(<"${TMPOUT}.err" 2>/dev/null || true)
      rm -f "$TMPOUT" "${TMPOUT}.err"
      if printf '%s' "$ERRMSG" | grep -qiE 'invalid vault password|decryption failed|stanza header'; then
        echo "Warning: could not decrypt $f — wrong vault password or corrupt vault file. Set VAULT_PASS or provide --password-file to decrypt." >&2
      else
        echo "Warning: failed to decrypt $f: $ERRMSG" >&2
      fi
      continue
    else
      rm -f "${TMPOUT}.err" || true
    fi
  elif [[ -n "$PASSWORD_FILE" ]]; then
    if ! ansible-vault view --vault-password-file "$PASSWORD_FILE" "$f" > "$TMPOUT" 2>"${TMPOUT}.err"; then
      ERRMSG=$(<"${TMPOUT}.err" 2>/dev/null || true)
      rm -f "$TMPOUT" "${TMPOUT}.err"
      if printf '%s' "$ERRMSG" | grep -qiE 'invalid vault password|decryption failed|stanza header'; then
        echo "Warning: could not decrypt $f with provided password file — wrong password or corrupt vault file." >&2
      else
        echo "Warning: failed to decrypt $f: $ERRMSG" >&2
      fi
      continue
    else
      rm -f "${TMPOUT}.err" || true
    fi
  else
    if [[ -t 0 ]]; then
      if ! ansible-vault view "$f" > "$TMPOUT" 2>"${TMPOUT}.err"; then
        ERRMSG=$(<"${TMPOUT}.err" 2>/dev/null || true)
        rm -f "$TMPOUT" "${TMPOUT}.err"
        echo "Warning: interactive decrypt of $f failed: $ERRMSG" >&2
        continue
      else
        rm -f "${TMPOUT}.err" || true
      fi
    else
      echo "No VAULT_PASS and no --password-file provided and no TTY — skipping decrypt of $f" >&2
      rm -f "$TMPOUT" || true
      continue
    fi
  fi

  # If plaintext exists and is identical, skip replacing it
  if [[ -f "$PLAINT" ]] && cmp -s "$PLAINT" "$TMPOUT"; then
    echo "Decrypted content identical to existing $PLAINT; no changes made"
    rm -f "$TMPOUT"
    continue
  fi

  # Backup existing plaintext (if any) and move new file into place
  if [[ -f "$PLAINT" ]]; then
    cp -- "$PLAINT" "${PLAINT}.bak-$TS"
  fi
  mv -f "$TMPOUT" "$PLAINT"
done < <(find "$TARGET_DIR" -type f \( -name '*.yml.enc' -o -name '*.yaml.enc' \) -print0)

echo "Decrypt pass complete. Backups: *.bak-$TS"
