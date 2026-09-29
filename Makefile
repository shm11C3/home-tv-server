SHELL := /bin/bash
TF_DIR := infra/proxmox
ANSIBLE_DIR := ansible

.PHONY: fmt init validate plan apply deps host configure check lint lint-ansible lint-compose lint-actions

## OpenTofu -------------------------------------------------------------------
fmt:
	tofu -chdir=$(TF_DIR) fmt -recursive

init:
	tofu -chdir=$(TF_DIR) init

validate:
	tofu -chdir=$(TF_DIR) init -backend=false -input=false >/dev/null
	tofu -chdir=$(TF_DIR) fmt -check -recursive
	tofu -chdir=$(TF_DIR) validate

plan:
	tofu -chdir=$(TF_DIR) plan

apply:
	tofu -chdir=$(TF_DIR) apply

## Ansible --------------------------------------------------------------------
deps:
	ansible-galaxy collection install -r $(ANSIBLE_DIR)/requirements.yml

host: deps ## Proxmox ホストの passthrough 前提設定（一度実行し、ホストを再起動）
	ansible-playbook -i $(ANSIBLE_DIR)/inventory/hosts.yml $(ANSIBLE_DIR)/proxmox-host.yml

configure: deps ## recorder VM のゲスト構成
	ansible-playbook -i $(ANSIBLE_DIR)/inventory/hosts.yml $(ANSIBLE_DIR)/site.yml

check: deps
	ansible-playbook --check --diff -i $(ANSIBLE_DIR)/inventory/hosts.yml $(ANSIBLE_DIR)/site.yml

## Lint -----------------------------------------------------------------------
lint: validate lint-ansible lint-compose lint-actions

lint-ansible: deps
	yamllint -s .
	ansible-lint
	ansible-playbook --syntax-check -i $(ANSIBLE_DIR)/inventory/hosts.example.yml $(ANSIBLE_DIR)/site.yml
	ansible-playbook --syntax-check -i $(ANSIBLE_DIR)/inventory/hosts.example.yml $(ANSIBLE_DIR)/proxmox-host.yml

lint-compose:
	cd apps/recorder && docker compose --env-file .env.example config --quiet

lint-actions:
	actionlint -color
