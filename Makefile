# Makefile for poc-app-platform-aws

.PHONY: help plan apply destroy

help:
	@echo "Usage: make [target]"
	@echo ""
	@echo "Targets:"
	@echo "  help         Show this help message."
	@echo "  plan         Run terraform plan."
	@echo "  apply        Run terraform apply."
	@echo "  destroy      Run terraform destroy."
	@echo "  docr-login   Log in to DigitalOcean Container Registry."
	@echo "  build        Build docker image."
	@echo "  push         Push docker image."

REGISTRY_NAME := do-solutions-sfo3
IMAGE_NAME := poc-app-platform-aws
IMAGE_TAG ?= latest

docr-login:
	@echo "Logging in to DigitalOcean Container Registry..."
	doctl registry login

build:
	@echo "Building docker image..."
	docker build -t registry.digitalocean.com/$(REGISTRY_NAME)/$(IMAGE_NAME):$(IMAGE_TAG) -t registry.digitalocean.com/$(REGISTRY_NAME)/$(IMAGE_NAME):latest -f app/Dockerfile app

push:
	@echo "Pushing docker image..."
	docker push registry.digitalocean.com/$(REGISTRY_NAME)/$(IMAGE_NAME):$(IMAGE_TAG)
	docker push registry.digitalocean.com/$(REGISTRY_NAME)/$(IMAGE_NAME):latest

plan:
	@echo "Running terraform plan..."
	terraform -chdir=terraform init
	terraform -chdir=terraform plan -var="image_tag=$(IMAGE_TAG)"

apply:
	@echo "Running terraform apply..."
	terraform -chdir=terraform init
	terraform -chdir=terraform apply -auto-approve -var="image_tag=$(IMAGE_TAG)"

destroy:
	@echo "Running terraform destroy..."
	terraform -chdir=terraform init
	terraform -chdir=terraform destroy -auto-approve
