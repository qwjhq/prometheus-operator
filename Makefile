# Get docker path or an empty string
DOCKER               := $(shell command -v docker)

# Get the unix user id for the user running make (to be used by docker-compose later)
UID                  := $(shell id -u)

# CMDs
UPDATE_CODEGEN_CMD   := ./hack/update-codegen.sh

# environment dirs
APP_DIR              := docker/app

#####################################################
# Support multiple build image
#####################################################
IMAGE_REGISTRY        := my.registry.cn
IMAGE_PROJECT         := dkcloudv3
TAG                   ?= v0.57
CODEGEN_VERSION      := v0.20.15
GO_VERSION           := 1.17.13
DOCKERFILE_AMD64      := ./Dockerfile.amd64
DOCKERFILE_ARM64      := ./Dockerfile.arm64
BUILDER_NAME          := dev
CGO_ENABLED          := 0
GO111MODULE          := on
DOCKER_BUILDX_OUTPUT := type=docker
TARGETS              := linux/amd64,linux/arm64
GO_FILE_NAME          := ./cmd/operator/main.go
# APPLICATION_NAME can't use _
APPLICATION_NAME      := prometheus-operator
SYSTEM_BASE_AMD64_IMAGE_NAME := scratch
SYSTEM_BASE_ARM64_IMAGE_NAME := scratch
#####################################################
# Relation to code
#####################################################

GIT_SHA_SHORT         := $$(git rev-parse --short HEAD)
# GIT_TREE_DIFF         := $$(git diff-index --quiet HEAD; echo $$?)
GIT_TREE_STATUS       ?=

ifeq ($(shell git diff-index --quiet HEAD; echo $$?),0)
    GIT_TREE_STATUS := "clean"
else
	GIT_TREE_STATUS := "dirty"
endif

.PHONY: check-git-status
check-git-status:
	@echo $(GIT_TREE_STATUS)

.PHONY: check-git-sha
check-git-sha:
	@echo $(GIT_SHA_SHORT)

# The default action of this Makefile is to build project
.PHONY: default
default: build-multi-image

.PHONY: generate
generate:
	./hack/run-update-generated.sh $(GO_VERSION) $(CODEGEN_VERSION) $(GO111MODULE)

.PHONY: debug
debug:
	./hack/build-debug.sh $(GO_VERSION) $(CODEGEN_VERSION) $(GO111MODULE)

##########################################################
# Multiple architecture builder creation
##########################################################


.PHONY: multi-driver
multi-driver:
	docker buildx create --name $(BUILDER_NAME) --platform $(TARGETS) --config ./docker-buildx/buildkitd.toml --driver-opt network=host --use --bootstrap


.PHONY: test-multi-driver
test-multi-driver:
	docker buildx ls


##########################################################
# Multiple binary local building pipline
##########################################################


.PHONY: build-binary-indocker-amd64
build-binary-indocker-amd64:
	docker buildx build --builder $(BUILDER_NAME) \
    --platform linux/amd64 \
    --no-cache -f Dockerfile.binary \
    --build-arg GOARCH=amd64 \
    --build-arg GO_VERSION=$(GO_VERSION) \
    --build-arg CGO_ENABLED=0 \
    --build-arg GO111MODULE=$(GO111MODULE) \
    --build-arg APPLICATION_NAME=$(APPLICATION_NAME) \
    --target archived --output type=local,dest=./local_bin .


.PHONY: build-binary-indocker-arm64
build-binary-indocker-arm64:
	docker buildx build --builder $(BUILDER_NAME) \
    --platform linux/arm64 \
    --no-cache -f Dockerfile.binary \
    --build-arg GOARCH=arm64 \
    --build-arg GO_VERSION=$(GO_VERSION) \
    --build-arg CGO_ENABLED=0 \
    --build-arg GO111MODULE=$(GO111MODULE) \
    --build-arg APPLICATION_NAME=$(APPLICATION_NAME) \
    --target archived --output type=local,dest=./local_bin .


.PHONY: build-binary-indokcer-multi
build-binary-indokcer-multi: build-binary-indocker-amd64 build-binary-indocker-arm64


##########################################################
# Multiple image local building pipline
##########################################################

.PHONY: build-${APPLICATION_NAME}-amd64
build-${APPLICATION_NAME}-amd64:
	docker buildx build --builder $(BUILDER_NAME) \
    --platform linux/amd64 \
    -o $(DOCKER_BUILDX_OUTPUT) \
    -t $(IMAGE_REGISTRY)/$(IMAGE_PROJECT)/$(APPLICATION_NAME):$(TAG)-amd64  \
    -f $(DOCKERFILE_AMD64) \
    --build-arg GOARCH=amd64 \
    --build-arg GO_VERSION=$(GO_VERSION) \
    --build-arg CGO_ENABLED=0 \
    --build-arg GO111MODULE=$(GO111MODULE) \
    --build-arg APPLICATION_NAME=$(APPLICATION_NAME) \
    --build-arg FILE_NAME=$(GO_FILE_NAME) \
    --build-arg  IMAGE_REGISTRY=$(IMAGE_REGISTRY)  \
    --build-arg BASE_IMAGE=$(SYSTEM_BASE_AMD64_IMAGE_NAME) \
    --build-arg COMMIT_ID=$(GIT_SHA_SHORT)+$(GIT_TREE_STATUS)  .


.PHONY: build-${APPLICATION_NAME}-arm64
build-${APPLICATION_NAME}-arm64:
	docker buildx build --builder $(BUILDER_NAME) \
    --platform linux/arm64 \
    -o $(DOCKER_BUILDX_OUTPUT) \
    -t $(IMAGE_REGISTRY)/$(IMAGE_PROJECT)/$(APPLICATION_NAME):$(TAG)-arm64  \
    -f $(DOCKERFILE_ARM64) \
    --build-arg GOARCH=arm64 \
    --build-arg GO_VERSION=$(GO_VERSION) \
    --build-arg CGO_ENABLED=0 \
    --build-arg GO111MODULE=$(GO111MODULE)  \
    --build-arg APPLICATION_NAME=$(APPLICATION_NAME) \
    --build-arg FILE_NAME=$(GO_FILE_NAME) \
    --build-arg  IMAGE_REGISTRY=$(IMAGE_REGISTRY)  \
    --build-arg BASE_IMAGE=$(SYSTEM_BASE_ARM64_IMAGE_NAME) \
    --build-arg COMMIT_ID=$(GIT_SHA_SHORT)+$(GIT_TREE_STATUS) .


.PHONY: build-all
build-all: build-${APPLICATION_NAME}-amd64  build-${APPLICATION_NAME}-arm64


.PHONY: docker-push
docker-push:
	docker push $(IMAGE_REGISTRY)/$(IMAGE_PROJECT)/$(APPLICATION_NAME):$(TAG)-arm64
	docker push $(IMAGE_REGISTRY)/$(IMAGE_PROJECT)/$(APPLICATION_NAME):$(TAG)-amd64


##########################################################
# Manifest
##########################################################

.PHONY: docker-manifest-create .IGNORE manifest-create
docker-manifest-create: .IGNORE manifest-create
.IGNORE:
	docker manifest rm $(IMAGE_REGISTRY)/$(IMAGE_PROJECT)/$(APPLICATION_NAME):$(TAG)
 manifest-create:
	docker manifest create --amend $(IMAGE_REGISTRY)/$(IMAGE_PROJECT)/$(APPLICATION_NAME):$(TAG) $(IMAGE_REGISTRY)/$(IMAGE_PROJECT)/$(APPLICATION_NAME):$(TAG)-arm64 $(IMAGE_REGISTRY)/$(IMAGE_PROJECT)/$(APPLICATION_NAME):$(TAG)-amd64


.PHONY: docker-manifest-push
docker-manifest-push:
	docker manifest push $(IMAGE_REGISTRY)/$(IMAGE_PROJECT)/$(APPLICATION_NAME):$(TAG)

.PHONY: manifest-auto
manifest-auto: docker-push
manifest-auto: docker-manifest-create
manifest-auto: docker-manifest-push