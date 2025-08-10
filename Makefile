# Makefile for poc-app-platform-aws

.PHONY: help plan apply deploy destroy update-js docr-login build push

help:
	@echo "Usage: make [target]"
	@echo ""
	@echo "Targets:"
	@echo "  help             Show this help message."
	@echo "  plan             Run terraform plan."
	@echo "  apply            Run terraform apply."
	@echo "  deploy           Full deployment: build, push, and two-pass terraform apply."
	@echo "  destroy          Run terraform destroy."
	@echo "  update-js        Update frontend JS with the live API URL."
	@echo "  docr-login       Log in to DigitalOcean Container Registry."
	@echo "  build            Build the Docker image."
	@echo "  push             Push the Docker image to the registry."

# Variables
REGISTRY_NAME = do-solutions-sfo3
IMAGE_NAME = poc-app-platform-aws
IMAGE_TAG ?= latest

# Targets
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

update-js:
	@API_URL=$$(terraform -chdir=terraform output -raw app_url); \
	if [ -z "$${API_URL}" ]; then \
		echo "Warning: app_url is not available yet. Skipping JS update."; \
	else \
		echo "Updating app.js with API_URL: $${API_URL}"; \
		sed -i "s|REPLACE_ME_API_URL|$${API_URL}|" frontend/app.js; \
	fi

destroy:
	@echo "Running terraform destroy..."
	terraform -chdir=terraform init
	terraform -chdir=terraform destroy -auto-approve

deploy:
	$(MAKE) docr-login
	$(MAKE) build
	$(MAKE) push
	@echo "Running first terraform apply to create resources and get app_url..."
	$(MAKE) apply
	@echo "Updating frontend assets with live API URL..."
	$(MAKE) update-js
	@echo "Running second terraform apply to upload updated frontend assets..."
	$(MAKE) apply
	@echo "Deployment complete."
