SEVERITIES = HIGH,CRITICAL

BUILDDIR ?= $(CURDIR)/build

UNAME_M = $(shell uname -m)
ARCH=
ifeq ($(UNAME_M), x86_64)
	ARCH=amd64
else ifeq ($(UNAME_M), aarch64)
	ARCH=arm64
else 
	ARCH=$(UNAME_M)
endif

ifndef TARGET_PLATFORMS
	ifeq ($(UNAME_M), x86_64)
		TARGET_PLATFORMS:=linux/amd64
	else ifeq ($(UNAME_M), aarch64)
		TARGET_PLATFORMS:=linux/arm64
	else 
		TARGET_PLATFORMS:=linux/$(UNAME_M)
	endif
endif

IID_FILE_FLAG ?=
IID_FILE_PATH := $(if $(IID_FILE_FLAG),$(word 2, $(IID_FILE_FLAG)))

K3S_ROOT_VERSION ?= v0.15.2
BUILD_META=-build$(shell date +%Y%m%d)
MACHINE := rancher
TAG ?= ${GITHUB_ACTION_TAG}

ifeq ($(TAG),)
TAG := $(shell cat TAG)$(BUILD_META)
endif

REPO ?= rancher
CALICO_IMAGE = $(REPO)/hardened-calico:$(TAG)
CALICO_NODE_IMAGE = $(REPO)/hardened-calico-node:$(TAG)
CALICO_METADATA_FILE = $(BUILDDIR)/$(subst /,-,$(REPO)/hardened-calico)-$(ARCH).metadata.json
CALICO_NODE_METADATA_FILE = $(BUILDDIR)/$(subst /,-,$(REPO)/hardened-calico-node)-$(ARCH).metadata.json

LABEL_ARGS = $(foreach label,$(META_LABELS),--label $(label))

ifeq (,$(filter %$(BUILD_META),$(TAG)))
$(error TAG $(TAG) needs to end with build metadata: $(BUILD_META))
endif

buildx-machine:
	docker buildx inspect $(MACHINE) > /dev/null 2>&1 || \
		docker buildx create --name=$(MACHINE) --platform=linux/arm64,linux/amd64

.PHONY: image-build-calico
image-build-calico:
	docker buildx build --no-cache \
		--platform=$(ARCH) \
		--pull \
		--target calico_image \
		--build-arg TAG=$(TAG:$(BUILD_META)=) \
		--build-arg K3S_ROOT_VERSION=$(K3S_ROOT_VERSION) \
		--tag $(CALICO_IMAGE) \
		--load \
		.

.PHONY: image-build-calico-node
image-build-calico-node:
	docker buildx build --no-cache \
		--platform=$(ARCH) \
		--pull \
		--target calico_node_image \
		--build-arg TAG=$(TAG:$(BUILD_META)=) \
		--build-arg K3S_ROOT_VERSION=$(K3S_ROOT_VERSION) \
		--tag $(CALICO_NODE_IMAGE) \
		--load \
		.

.PHONY: image-build
image-build: image-build-calico image-build-calico-node

.PHONY: image-push-calico
image-push-calico: $(BUILDDIR) | buildx-machine
	docker buildx build \
		--builder=$(MACHINE) \
		$(IID_FILE_FLAG) \
		--sbom=true \
		--attest type=provenance,mode=max \
		--platform=$(TARGET_PLATFORMS) \
		--target calico_image \
		--build-arg TAG=$(TAG:$(BUILD_META)=) \
		--build-arg K3S_ROOT_VERSION=$(K3S_ROOT_VERSION) \
		--output type=image,name=$(CALICO_IMAGE),push-by-digest=true,name-canonical=true,push=true \
		$(LABEL_ARGS) \
		--push \
		--metadata-file $(CALICO_METADATA_FILE) \
		.

.PHONY: image-push-calico-node
image-push-calico-node: $(BUILDDIR) | buildx-machine
	docker buildx build \
		--builder=$(MACHINE) \
		$(IID_FILE_FLAG) \
		--sbom=true \
		--attest type=provenance,mode=max \
		--platform=$(TARGET_PLATFORMS) \
		--target calico_node_image \
		--build-arg TAG=$(TAG:$(BUILD_META)=) \
		--build-arg K3S_ROOT_VERSION=$(K3S_ROOT_VERSION) \
		--output type=image,name=$(CALICO_NODE_IMAGE),push-by-digest=true,name-canonical=true,push=true \
		$(LABEL_ARGS) \
		--push \
		--metadata-file $(CALICO_NODE_METADATA_FILE) \
		.

.PHONY: image-push
image-push: image-push-calico image-push-calico-node

.PHONY: manifest-push-calico
manifest-push-calico: | buildx-machine
	d=""; \
	for architecture in $(MULTI_ARCH); do \
		metadata_file=$(BUILDDIR)/$(subst /,-,$(REPO)/hardened-calico)-$$architecture.metadata.json; \
		d="$$d $$(jq -r '.["containerimage.digest"]' $$metadata_file)"; \
	done; \
	docker buildx imagetools create \
		--builder=$(MACHINE) \
		-t $(CALICO_IMAGE) -t $(REPO)/hardened-calico:latest \
		$$d

.PHONY: manifest-push-calico-node
manifest-push-calico-node: | buildx-machine
	d=""; \
	for architecture in $(MULTI_ARCH); do \
		metadata_file=$(BUILDDIR)/$(subst /,-,$(REPO)/hardened-calico-node)-$$architecture.metadata.json; \
		d="$$d $$(jq -r '.["containerimage.digest"]' $$metadata_file)"; \
	done; \
	docker buildx imagetools create \
		--builder=$(MACHINE) \
		-t $(CALICO_NODE_IMAGE) -t $(REPO)/hardened-calico-node:latest \
		$$d

.PHONY: manifest-push
manifest-push: manifest-push-calico manifest-push-calico-node

ifneq ($(strip $(IID_FILE_PATH)),)
	docker buildx imagetools inspect --format "{{json .Manifest}}" $(CALICO_IMAGE) | jq -r '.digest' > "$(IID_FILE_PATH)"
endif

.PHONY: image-scan
image-scan:
	trivy image --severity $(SEVERITIES) --no-progress --ignore-unfixed $(CALICO_IMAGE)
	trivy image --severity $(SEVERITIES) --no-progress --ignore-unfixed $(CALICO_NODE_IMAGE)

PHONY: log
log:
	@echo "BUILDDIR=$(BUILDDIR)"
	@echo "ARCH=$(ARCH)"
	@echo "TAG=$(TAG:$(BUILD_META)=)"
	@echo "REPO=$(REPO)"
	@echo "BUILD_META=$(BUILD_META)"
	@echo "UNAME_M=$(UNAME_M)"
	@echo "META_LABELS=$(META_LABELS)"
	@echo "LABEL_ARGS=$(LABEL_ARGS)"
