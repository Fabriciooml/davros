SHELL := /bin/bash
.SHELLFLAGS := -eu -o pipefail -c

TF_ROOTS := terraform/talos-cluster terraform/cloudflare
AGE_KEY_FILE ?= $(HOME)/.config/sops/age/keys.txt

.PHONY: help
help:
	@grep -E '^[a-zA-Z0-9_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "%-22s %s\n", $$1, $$2}'

.PHONY: test
test: test-terraform test-kubernetes ## run every tofu test and every kustomize-build test, no real infra touched

.PHONY: test-terraform
test-terraform:
	@for dir in $$(find terraform -name '*.tftest.hcl' -exec dirname {} \; | sed 's#/tests$$##' | sort -u); do \
		echo "== tofu test: $$dir =="; \
		(cd "$$dir" && tofu init -input=false >/dev/null && tofu test); \
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
init: ## tofu init the two deployable roots (talos-cluster, cloudflare)
	@for dir in $(TF_ROOTS); do \
		(cd "$$dir" && tofu init); \
	done

.PHONY: plan-cluster
plan-cluster: ## show what applying the talos cluster would change, no real infra touched
	cd terraform/talos-cluster && tofu plan

.PHONY: confirm
confirm:
	@read -r -p "$(MSG) type 'yes' to continue: " reply; \
	[ "$$reply" = "yes" ] || { echo "aborted"; exit 1; }

.PHONY: apply-cluster
apply-cluster: ## create the talos vms on proxmox and render their machine configs -- REAL CHANGE
	$(MAKE) confirm MSG="about to create/update VMs on your proxmox host."
	cd terraform/talos-cluster && tofu apply

.PHONY: destroy-cluster
destroy-cluster: ## destroy the talos vms on proxmox -- REAL, DESTRUCTIVE CHANGE
	$(MAKE) confirm MSG="about to DESTROY the talos VMs on your proxmox host."
	$(MAKE) confirm MSG="really sure? this cannot be undone."
	cd terraform/talos-cluster && tofu destroy

.PHONY: plan-cloudflare
plan-cloudflare: ## show what applying the cloudflare config would change, no real infra touched
	cd terraform/cloudflare && tofu plan

.PHONY: apply-cloudflare
apply-cloudflare: ## create/update cloudflare dns records and tunnel ingress rules -- REAL CHANGE
	$(MAKE) confirm MSG="about to change DNS records and tunnel ingress rules on cloudflare."
	cd terraform/cloudflare && tofu apply

.PHONY: talos-bootstrap
talos-bootstrap: ## bootstrap etcd on the first control-plane node -- REAL CHANGE, run once per cluster lifetime
	$(MAKE) confirm MSG="about to bootstrap etcd on the talos cluster. only do this once."
	talosctl bootstrap --nodes $$(cd terraform/talos-cluster && tofu output -raw -json node_ips | python3 -c 'import json,sys; print(json.load(sys.stdin)["cp-0"])')

.PHONY: kubeconfig
kubeconfig: ## merge talosconfig and kubeconfig from terraform outputs into ~/.talos and ~/.kube
	cd terraform/talos-cluster && tofu output -raw talosconfig | talosctl config merge /dev/stdin
	cd terraform/talos-cluster && tofu output -raw kubeconfig > /tmp/davros-kubeconfig
	KUBECONFIG=$$HOME/.kube/config:/tmp/davros-kubeconfig kubectl config view --flatten > /tmp/davros-kubeconfig-merged
	mv /tmp/davros-kubeconfig-merged $$HOME/.kube/config
	rm -f /tmp/davros-kubeconfig

.PHONY: cilium-bootstrap
cilium-bootstrap: ## one-time helm install of cilium, before flux exists -- REAL CHANGE, run once per cluster lifetime
	$(MAKE) confirm MSG="about to helm-install cilium directly (flux doesn't exist yet)."
	helm repo add cilium https://helm.cilium.io
	helm repo update cilium
	helm install cilium cilium/cilium \
		--namespace kube-system \
		--set kubeProxyReplacement=true \
		--set k8sServiceHost=192.168.31.243 \
		--set k8sServicePort=6443 \
		--set l2announcements.enabled=true

.PHONY: flux-bootstrap
flux-bootstrap: ## wire this repo to the cluster via flux -- REAL CHANGE, run once per cluster lifetime
	$(MAKE) confirm MSG="about to run flux bootstrap github against fabriciooml/davros."
	flux bootstrap github \
		--owner=fabriciooml \
		--repository=davros \
		--branch=main \
		--path=kubernetes/flux-system \
		--personal

.PHONY: sops-age-secret
sops-age-secret: ## deliver the sops age private key into the cluster so flux can decrypt secrets -- REAL CHANGE
	$(MAKE) confirm MSG="about to put the sops age private key into the flux-system namespace."
	kubectl create secret generic sops-age \
		--namespace flux-system \
		--from-file=age.agekey=$(AGE_KEY_FILE) \
		--dry-run=client -o yaml | kubectl apply -f -

.PHONY: bootstrap
bootstrap: ## full first-time cluster bring-up, step by step, each step asks to confirm -- REAL CHANGES
	$(MAKE) apply-cluster
	$(MAKE) talos-bootstrap
	$(MAKE) kubeconfig
	$(MAKE) cilium-bootstrap
	$(MAKE) flux-bootstrap
	$(MAKE) sops-age-secret
	$(MAKE) apply-cloudflare
