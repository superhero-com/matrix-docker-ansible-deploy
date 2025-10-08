#!/usr/bin/env bash
# Bulk auto-encrypt inventory YAML files into .enc and stage them.
export LC_ALL=${LC_ALL:-C}
export LANG=${LANG:-C.UTF-8}
set -euo pipefail

REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
VAULT_PASSWORD_FILE="$REPO_ROOT/vault-password"

if ! command -v ansible-vault >/dev/null 2>&1; then
  echo "ansible-vault not found; skipping auto-encrypt." >&2
  exit 0
fi

# Only attempt bulk encryption if we have a password available
if [[ -z "${VAULT_PASS-}" && ! -f "$VAULT_PASSWORD_FILE" ]]; then
  echo "No VAULT_PASS and no $VAULT_PASSWORD_FILE — skipping auto-encrypt" >&2
  exit 0
fi

if [[ -n "${VAULT_PASS-}" ]]; then
  VAULT_PASS="$VAULT_PASS" ./scripts/encrypt-inventory.sh || { echo "encrypt-inventory.sh failed" >&2; exit 1; }
else
  ./scripts/encrypt-inventory.sh --password-file "$VAULT_PASSWORD_FILE" || { echo "encrypt-inventory.sh failed" >&2; exit 1; }
fi

# Stage the created .enc files and remove plaintext from the index
while IFS= read -r -d '' f; do
  ENC_FILE="${f}.enc"
  if [[ -f "$ENC_FILE" ]]; then
    git add -- "$ENC_FILE"
    git rm --cached --force --quiet -- "$f" || true
  fi
done < <(find "$REPO_ROOT/inventory" -type f \( -name '*.yml' -o -name '*.yaml' \) -print0)

exit 0
          # already encrypted
