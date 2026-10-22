SHELL := /bin/bash
.SHELLFLAGS := -eu -o pipefail -c

-include .env
export

TF_ROOTS := terraform/k3s-cluster terraform/cloudflare
AGE_KEY_FILE ?= $(HOME)/.config/sops/age/keys.txt

.PHONY: help
help:
	@grep -E '^[a-zA-Z0-9_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "%-22s %s\n", $$1, $$2}'

.PHONY: test
test: test-terraform test-scripts test-kubernetes ## run every tofu test, standalone script test, and kustomize-build test, no real infra touched

.PHONY: test-terraform
test-terraform:
	@for dir in $$(find terraform -name '*.tftest.hcl' -exec dirname {} \; | sed 's#/tests$$##' | sort -u); do \
		echo "== tofu test: $$dir =="; \
		(cd "$$dir" && tofu init -input=false >/dev/null && tofu test); \
	done

.PHONY: test-scripts
test-scripts:
	@for script in $$(find terraform scripts -path '*/tests/*.test.sh' | sort); do \
		echo "== script test: $$script =="; \
		bash "$$script"; \
	done

.PHONY: test-kubernetes
test-kubernetes:
	@for script in $$(find kubernetes -path '*/tests/test.sh' | sort); do \
		echo "== kustomize test: $$script =="; \
		bash "$$script"; \
	done

.PHONY: fmt
fmt: ## tofu fmt every terraform root and module
	@for dir in $(TF_ROOTS) $$(find terraform/modules -mindepth 1 -maxdepth 1 -type d); do \
		tofu fmt -recursive "$$dir"; \
	done

.PHONY: validate
validate: ## tofu validate every terraform root and module
	@for dir in $(TF_ROOTS) $$(find terraform/modules -mindepth 1 -maxdepth 1 -type d); do \
		echo "== tofu validate: $$dir =="; \
		(cd "$$dir" && tofu init -input=false >/dev/null && tofu validate); \
	done

.PHONY: init
init: ## tofu init the two deployable roots (k3s-cluster, cloudflare)
	@for dir in $(TF_ROOTS); do \
		(cd "$$dir" && tofu init); \
	done

.PHONY: plan-cluster
plan-cluster: ## show what applying the k3s cluster would change, no real infra touched
	cd terraform/k3s-cluster && tofu plan

.PHONY: confirm
confirm:
	@read -r -p "$(MSG) type 'yes' to continue: " reply; \
	[ "$$reply" = "yes" ] || { echo "aborted"; exit 1; }

.PHONY: apply-cluster
apply-cluster: ## create the k3s lxc node on proxmox and install k3s on it -- REAL CHANGE
	$(MAKE) confirm MSG="about to create/update the k3s lxc node on your proxmox host."
	cd terraform/k3s-cluster && tofu apply

.PHONY: destroy-cluster
destroy-cluster: ## destroy the k3s lxc node on proxmox -- REAL, DESTRUCTIVE CHANGE
	$(MAKE) confirm MSG="about to DESTROY the k3s node on your proxmox host."
	$(MAKE) confirm MSG="really sure? this cannot be undone."
	cd terraform/k3s-cluster && tofu destroy

.PHONY: plan-cloudflare
plan-cloudflare: ## show what applying the cloudflare config would change, no real infra touched
	cd terraform/cloudflare && tofu plan

.PHONY: apply-cloudflare
apply-cloudflare: ## create/update cloudflare dns records and tunnel ingress rules -- REAL CHANGE
	$(MAKE) confirm MSG="about to change DNS records and tunnel ingress rules on cloudflare."
	cd terraform/cloudflare && tofu apply

.PHONY: kubeconfig
kubeconfig: ## merge the k3s-cluster-generated kubeconfig into ~/.kube/config
	KUBECONFIG=$$HOME/.kube/config:terraform/k3s-cluster/kubeconfig kubectl config view --flatten > /tmp/davros-kubeconfig-merged
	mv /tmp/davros-kubeconfig-merged $$HOME/.kube/config

.PHONY: flux-bootstrap
flux-bootstrap: ## wire this repo to the cluster via flux -- REAL CHANGE, run once per cluster lifetime
	$(MAKE) confirm MSG="about to run flux bootstrap github against fabriciooml/davros."
	flux bootstrap github \
		--owner=fabriciooml \
		--repository=davros \
		--branch=main \
		--path=kubernetes/flux-system \
		--personal

.PHONY: sops-age-key
sops-age-key: ## generate the sops age keypair if it doesn't already exist -- REAL CHANGE, never overwrites an existing key
	@if [ -f "$(AGE_KEY_FILE)" ]; then \
		echo "age key already exists at $(AGE_KEY_FILE), leaving it alone"; \
	else \
		$(MAKE) confirm MSG="no age key found at $(AGE_KEY_FILE), about to generate a new one."; \
		mkdir -p "$$(dirname "$(AGE_KEY_FILE)")"; \
		age-keygen -o "$(AGE_KEY_FILE)"; \
		echo "generated new age key at $(AGE_KEY_FILE) -- add its public key to .sops.yaml if not already present"; \
	fi

.PHONY: sops-age-secret
sops-age-secret: sops-age-key ## deliver the sops age private key into the cluster so flux can decrypt secrets -- REAL CHANGE
	$(MAKE) confirm MSG="about to put the sops age private key into the flux-system namespace."
	kubectl create secret generic sops-age \
		--namespace flux-system \
		--from-file=age.agekey=$(AGE_KEY_FILE) \
		--dry-run=client -o yaml | kubectl apply -f -

.PHONY: bootstrap
bootstrap: ## full first-time cluster bring-up, step by step, each step asks to confirm -- REAL CHANGES
	$(MAKE) apply-cluster
	$(MAKE) kubeconfig
	$(MAKE) flux-bootstrap
	$(MAKE) sops-age-secret
	$(MAKE) apply-cloudflare
