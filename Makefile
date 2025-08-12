# Makefile for poc-app-platform-aws

.PHONY: plan apply deploy destroy docr-login build push

# Variables
REGISTRY_NAME = do-solutions-sfo3
IMAGE_NAME = poc-app-platform-aws
DEFAULT_IMAGE_TAG := v1.$(shell date +%Y%m%d.%H%M%S)
IMAGE_TAG ?= $(DEFAULT_IMAGE_TAG)
# freeze value
IMAGE_TAG := $(IMAGE_TAG)

# Targets
docr-login:
	@echo "Logging in to DigitalOcean Container Registry..."
	doctl registry login

build:
	@echo "Building docker image..."
	docker build -t registry.digitalocean.com/$(REGISTRY_NAME)/$(IMAGE_NAME):$(IMAGE_TAG) -f app/Dockerfile app

push:
	@echo "Pushing docker image..."
	docker push registry.digitalocean.com/$(REGISTRY_NAME)/$(IMAGE_NAME):$(IMAGE_TAG)

plan:
	@echo "Running terraform plan..."
	terraform -chdir=terraform init
	terraform -chdir=terraform plan -var="image_tag=$(IMAGE_TAG)" -var="aws_access_key_id=$(AWS_ACCESS_KEY_ID)" -var="aws_secret_access_key=$(AWS_SECRET_ACCESS_KEY)"

apply:
	@echo "Running terraform apply..."
	terraform -chdir=terraform init
	terraform -chdir=terraform apply -auto-approve -var="image_tag=$(IMAGE_TAG)" -var="aws_access_key_id=$(AWS_ACCESS_KEY_ID)" -var="aws_secret_access_key=$(AWS_SECRET_ACCESS_KEY)"

destroy:
	@echo "Running terraform destroy..."
	terraform -chdir=terraform init
	terraform -chdir=terraform destroy -auto-approve

deploy: docr-login build push apply