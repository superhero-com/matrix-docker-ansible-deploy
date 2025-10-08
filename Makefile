# SPDX-FileCopyrightText: 2022 Slavi Pantaleev
#
# SPDX-License-Identifier: AGPL-3.0-or-later

.PHONY: roles lint

help: ## Show this help.
	@grep -F -h "##" $(MAKEFILE_LIST) | grep -v grep | sed -e 's/\\$$//' | sed -e 's/##//'

roles: ## Pull roles
	rm -rf roles/galaxy
	ansible-galaxy install -r requirements.yml -p roles/galaxy/ --force

lint: ## Runs ansible-lint against all roles in the playbook
	ansible-lint roles/custom

.PHONY: init
init: ## Initialize repo for hooks: set core.hooksPath to .githooks for this clone
	@echo "Configuring this clone to use .githooks as git hooks path"
	@git config core.hooksPath .githooks
	@echo "Hooks path configured to .githooks for this clone."
