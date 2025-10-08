#!/usr/bin/env bash
# Avoid locale warnings on systems without en_US.UTF-8 generated
export LC_ALL=${LC_ALL:-C}
export LANG=${LANG:-C.UTF-8}
set -euo pipefail

# This script checks the git index for staged files under inventory/ that
# appear to be plain YAML (not ansible-vault encrypted). It returns non-zero
# if any are found so a commit can be blocked.

exit_code=0

# Use git -z to list staged files with NUL separators to handle spaces
STAGED_FILES=$(git diff --cached --name-only --diff-filter=ACM -z || true)

while IFS= read -r -d '' file; do
  # limit to inventory YAML files
  case "$file" in
    inventory/*.yml|inventory/*.yaml|inventory/*/*.yml|inventory/*/*.yaml)
      # If the file exists in the index, inspect the staged version
      if git show :"$file" >/dev/null 2>&1; then
        if git show :"$file" | sed -n '1p' | grep -q '^\$ANSIBLE_VAULT'; then
          : # encrypted
        else
          echo "Staged unencrypted inventory file: $file" >&2
          exit_code=1
        fi
      fi
      ;;
    *) ;;
  esac
done <<< "$STAGED_FILES"

if [[ $exit_code -ne 0 ]]; then
  echo "Commit blocked: please encrypt inventory files with ansible-vault or remove them from the commit." >&2
  exit $exit_code
fi

exit 0
