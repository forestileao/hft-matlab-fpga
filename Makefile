SHELL := /bin/bash

DOCKER ?= docker
DOCKER_IMAGE ?= hft-mfast-builder:latest

MFAST_REPO ?= https://github.com/objectcomputing/mFAST.git
MFAST_DIR ?= mFAST
MFAST_BUILD_DIR ?= $(MFAST_DIR)/build-docker
MFAST_INSTALL_DIR ?= $(MFAST_DIR)/install

JOBS ?= $(shell nproc)
UID ?= $(shell id -u)
GID ?= $(shell id -g)

MFAST_CMAKE_FLAGS ?= -DCMAKE_BUILD_TYPE=Release -DBUILD_TESTS=OFF -DBUILD_EXAMPLES=OFF -DBUILD_PACKAGES=OFF

.PHONY: help docker-image mfast-clone mfast-configure mfast-build mfast-install mfast-rebuild mfast-clean docker-shell

help:
	@echo "Targets:"
	@echo "  docker-image    Build the Docker image with C++/CMake/Boost toolchain"
	@echo "  mfast-clone     Clone mFAST recursively if missing; always sync submodules"
	@echo "  mfast-configure Configure mFAST in Docker"
	@echo "  mfast-build     Build mFAST in Docker"
	@echo "  mfast-install   Install mFAST artifacts to mFAST/install on host"
	@echo "  mfast-rebuild   Clean and build mFAST in Docker"
	@echo "  mfast-clean     Remove Docker build directory"
	@echo "  docker-shell    Open an interactive shell in the build container"

docker-image:
	$(DOCKER) build -t $(DOCKER_IMAGE) -f Dockerfile .

mfast-clone:
	@if [ ! -d "$(MFAST_DIR)/.git" ]; then \
		git clone --recursive "$(MFAST_REPO)" "$(MFAST_DIR)"; \
	fi
	@git -C "$(MFAST_DIR)" submodule update --init --recursive

mfast-configure: docker-image mfast-clone
	$(DOCKER) run --rm \
		-u $(UID):$(GID) \
		-v "$(CURDIR):/workspace" \
		-w /workspace \
		$(DOCKER_IMAGE) \
		bash -lc "cmake -S $(MFAST_DIR) -B $(MFAST_BUILD_DIR) $(MFAST_CMAKE_FLAGS)"

mfast-build: mfast-configure
	$(DOCKER) run --rm \
		-u $(UID):$(GID) \
		-v "$(CURDIR):/workspace" \
		-w /workspace \
		$(DOCKER_IMAGE) \
		bash -lc "cmake --build $(MFAST_BUILD_DIR) --parallel $(JOBS)"

mfast-install: mfast-build
	$(DOCKER) run --rm \
		-u $(UID):$(GID) \
		-v "$(CURDIR):/workspace" \
		-w /workspace \
		$(DOCKER_IMAGE) \
		bash -lc "cmake --install $(MFAST_BUILD_DIR) --prefix /workspace/$(MFAST_INSTALL_DIR)"

mfast-rebuild: mfast-clean mfast-build

mfast-clean:
	rm -rf "$(MFAST_BUILD_DIR)"

docker-shell: docker-image
	$(DOCKER) run --rm -it \
		-u $(UID):$(GID) \
		-v "$(CURDIR):/workspace" \
		-w /workspace \
		$(DOCKER_IMAGE) \
		bash
