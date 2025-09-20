# Makefile for poc-app-platform-aws

.PHONY: plan apply deploy destroy docr-login build push

# Variables
REGISTRY_NAME = do-solutions-sfo3
IMAGE_NAME = poc-app-platform-aws
DEFAULT_IMAGE_TAG := v1.$(shell date +%Y%m%d.%H%M%S)
IMAGE_TAG ?= $(DEFAULT_IMAGE_TAG)
# freeze value
IMAGE_TAG := $(IMAGE_TAG)

# Save original AWS credentials from environment
AWS_REAL_KEY_ID := $(AWS_ACCESS_KEY_ID)
AWS_REAL_SECRET := $(AWS_SECRET_ACCESS_KEY)

# Terraform variables for secrets and dynamic values only
# Static configuration is in terraform/terraform.tfvars
TF_SECRET_VARS = -var="aws_access_key_id=$(AWS_REAL_KEY_ID)" \
                 -var="aws_secret_access_key=$(AWS_REAL_SECRET)"

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
	@echo "Setting up Spaces credentials for backend..."
	@export AWS_ACCESS_KEY_ID=$(SPACES_ACCESS_KEY_ID) && \
	export AWS_SECRET_ACCESS_KEY=$(SPACES_SECRET_ACCESS_KEY) && \
	terraform -chdir=terraform init && \
	terraform -chdir=terraform plan -var="image_tag=$(IMAGE_TAG)" $(TF_SECRET_VARS)

apply:
	@echo "Running terraform apply..."
	@echo "Setting up Spaces credentials for backend..."
	@export AWS_ACCESS_KEY_ID=$(SPACES_ACCESS_KEY_ID) && \
	export AWS_SECRET_ACCESS_KEY=$(SPACES_SECRET_ACCESS_KEY) && \
	terraform -chdir=terraform init && \
	terraform -chdir=terraform apply -auto-approve -var="image_tag=$(IMAGE_TAG)" $(TF_SECRET_VARS)

destroy:
	@echo "Running terraform destroy..."
	@echo "Setting up Spaces credentials for backend..."
	@export AWS_ACCESS_KEY_ID=$(SPACES_ACCESS_KEY_ID) && \
	export AWS_SECRET_ACCESS_KEY=$(SPACES_SECRET_ACCESS_KEY) && \
	terraform -chdir=terraform init && \
	terraform -chdir=terraform destroy -auto-approve -var="image_tag=$(IMAGE_TAG)" $(TF_SECRET_VARS)

deploy: docr-login build push apply