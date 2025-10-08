# Using Ansible Vault in this repository

This repository stores inventory and other configuration that may contain secrets.
To keep secrets in the repo while staying secure, we use `ansible-vault` to
encrypt plaintext files before committing them.

Recommended workflow

- Prefer encrypted inventory checked into git (Ansible Vault) rather than
  committing plaintext secrets.
- Create a local vault password file if you prefer a file-based workflow
  (example names: `vault-password`, `.vault_pass`) and keep it out of git.
- Alternatively, set the `VAULT_PASS` environment variable to avoid keeping a
  password file on disk.
- Use the helper scripts in `scripts/` to encrypt files consistently before
  committing.

Examples


Encrypting with the repository scripts

A helper script is provided to make encryption consistent:

- `scripts/encrypt-inventory.sh [--password-file <path>] [files...]`
  - If no files are provided it defaults to encrypting all `*.yml`/`*.yaml`
    files under `inventory/`.
  - If `VAULT_PASS` is set it is used as the vault password (preferred for
    CI or ephemeral workflows). Otherwise `--password-file` is supported, or
    `ansible-vault` will prompt interactively.

  - Note: `scripts/encrypt-inventory.sh` also defaults to bulk-encrypting all
    YAML files under `inventory/` when no files are provided. Use that as the
    single canonical encrypt helper.

Examples

Interactive (prompts for password):

    ./scripts/encrypt-inventory.sh

Use `VAULT_PASS` environment variable:

    export VAULT_PASS='s3cr3t'
    ./scripts/encrypt-inventory.sh

Use a password file explicitly:

  ./scripts/encrypt-inventory.sh --password-file ~/vault-password


GitHub Actions snippet

Use a repository secret named `ANSIBLE_VAULT_PASSWORD` and create the file at
runtime in the workflow:

- name: Create vault password file
  run: echo "${{ secrets.ANSIBLE_VAULT_PASSWORD }}" > vault-password

- name: Run ansible-playbook
  run: ansible-playbook site.yml --vault-password-file vault-password

Security notes

- Never commit unencrypted secrets. Double-check diffs before committing.
- Do not store the vault password in the repository. Keep it as a local file or
  in your system's secret manager / CI secrets.
- Prefer `--vault-id` and multiple vault IDs for per-environment keys when
  necessary.

Git hooks to protect inventory files

This repository includes a small checker script at
`scripts/check-unencrypted-inventory.sh` and a committed hooks directory
`.githooks/` that runs it on `pre-commit`. To enable the hooks for your
clone run:

    make init

This sets `git config core.hooksPath .githooks` for the clone so the
versioned hooks run automatically without extra dependencies.

Server-side enforcement

Client-side hooks can be bypassed. To make sure plaintext secrets never land
on protected branches add a CI job that runs `scripts/check-unencrypted-inventory.sh`
on PRs. If you want, I can add a GitHub Actions workflow that performs this
check and fails PRs containing unencrypted inventory files.


## Encrypted-files-first workflow (recommended)

To make local development convenient while keeping secrets tracked in git,
this repository uses an "encrypted-files-first" workflow for `vars.yml` files:

- Plaintext `inventory/**/vars.yml` files are ignored by `.gitignore`.
- Encrypted files are tracked as `inventory/.../vars.yml.enc` (these are the
  canonical objects stored in Git).
- On commit, the pre-commit hook (via `scripts/pre-commit-auto-encrypt.sh`) will
  automatically create or update `vars.yml.enc` from your working `vars.yml` and
  stage the `.enc` file while removing the plaintext from the index. This
  avoids committing plaintext by accident.
- After a checkout or merge, `post-checkout`/`post-merge` call
  `scripts/decrypt-inventory.sh` which will:
  - Decrypt `*.yml.enc` -> `*.yml` into the working tree (if a password is
    available),
  - Compare decrypted content against the existing plaintext and only overwrite
    when different (backing up the old plaintext as `*.bak-<ts>`), and
  - Print a notice when a plaintext file exists without a matching `.enc`.

### How it helps

- You keep encrypted data in the repo (auditable, safely shareable).
- Local working copies get decrypted automatically for convenience.
- Pre-commit encryption prevents accidental plaintext commits.

### How to create `.enc` files manually

- One-off (interactive):

    ./scripts/encrypt-inventory.sh inventory/host_vars/example.com/vars.yml

- Non-interactive (CI or scripts):

    export VAULT_PASS='s3cr3t'
    ./scripts/encrypt-inventory.sh inventory/host_vars/example.com/vars.yml

  or

    ./scripts/encrypt-inventory.sh --password-file ~/vault-password inventory/host_vars/example.com/vars.yml

### Troubleshooting

- If `scripts/decrypt-inventory.sh` can't decrypt a file it will print a
  clear warning and continue; it will not fail the hook. Typical causes:
  - `VAULT_PASS` not exported in your shell, or
  - you're using the wrong password file.
- If a decrypt fails with an invalid password, you'll see a message like:

    Warning: could not decrypt inventory/host_vars/foo/vars.yml.enc — wrong vault password or corrupt vault file. Set VAULT_PASS or provide --password-file to decrypt.

- If you want the checkout hooks to be fully non-interactive (for example in
  CI runners), make sure to set `VAULT_PASS` in the environment or create a
  `vault-password` file at repo root and pass it to the scripts with
  `--password-file`.

### Notes and options

- The decrypt script warns (but does not auto-encrypt) when it finds
  plaintext `*.yml` files without a matching `.enc` file. This avoids
  surprising writes on checkouts. If you'd like an opt-in `--auto-encrypt`
  mode that will try to produce `.enc` files during checkout when a password
  is available, I can add it.

### Updated defaults (quick reference)

- `scripts/encrypt-inventory.sh` now writes `*.enc` files by default. Use
  `--in-place` to encrypt files in-place if you prefer replacing plaintext.
- `scripts/decrypt-inventory.sh` looks for `*.yml.enc`/`*.yaml.enc` by default
  and will decrypt them into the corresponding plaintext files. If you pass a
  single path that is a plaintext YAML, the script will look for a matching
  `.enc` partner (and warn if none exists).
- The `pre-commit` hook invokes `scripts/pre-commit-auto-encrypt.sh`, which
  runs the canonical `encrypt-inventory.sh` in bulk to create and `git add`
  `.enc` files, then removes plaintext from the index. Hooks will skip this
  step if neither `VAULT_PASS` nor a `vault-password` file is present.


