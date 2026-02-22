SHELL := /bin/bash

DOCKER ?= docker
DOCKER_IMAGE ?= hft-mfast-builder:latest

MFAST_REPO ?= https://github.com/objectcomputing/mFAST.git
MFAST_DIR ?= mFAST
MFAST_BUILD_DIR ?= $(MFAST_DIR)/build
MFAST_INSTALL_DIR ?= $(MFAST_DIR)/install
CPP_DIR ?= cpp
CPP_BUILD_DIR ?= $(CPP_DIR)/build
VHDL_DIR ?= vhdl
VHDL_BUILD_DIR ?= $(VHDL_DIR)/build
VHDL_TB ?= tb_arm_fpga_shared_stream_bridge
VHDL_TB_FILE ?= $(VHDL_DIR)/$(VHDL_TB).vhd
VHDL_TB_FAST ?= tb_arm_fpga_shared_stream_bridge_fast
VHDL_VCD ?= $(VHDL_BUILD_DIR)/$(VHDL_TB).vcd
VHDL_STOP_TIME ?= 20us

JOBS ?= $(shell nproc)
UID ?= $(shell id -u)
GID ?= $(shell id -g)

MFAST_CMAKE_FLAGS ?= -DCMAKE_BUILD_TYPE=Release -DBUILD_TESTS=OFF -DBUILD_EXAMPLES=OFF -DBUILD_PACKAGES=OFF

.PHONY: help docker-image mfast-clone mfast-configure mfast-build mfast-install mfast-rebuild mfast-clean cpp-configure cpp-build cpp-test cpp-clean vhdl-test vhdl-test-fast vhdl-wave vhdl-clean docker-shell

help:
	@echo "Targets:"
	@echo "  docker-image    Build the Docker image with C++/CMake/Boost toolchain"
	@echo "  mfast-clone     Clone mFAST recursively if missing; always sync submodules"
	@echo "  mfast-configure Configure mFAST in Docker"
	@echo "  mfast-build     Build mFAST in Docker"
	@echo "  mfast-install   Install mFAST artifacts to mFAST/install on host"
	@echo "  mfast-rebuild   Clean and build mFAST in Docker"
	@echo "  mfast-clean     Remove mFAST build directory"
	@echo "  cpp-configure   Configure cpp/ against mFAST install in Docker"
	@echo "  cpp-build       Build cpp/ targets in Docker"
	@echo "  cpp-test        Build and run cpp tests (CTest) in Docker"
	@echo "  cpp-clean       Remove cpp build directory"
	@echo "  vhdl-test       Run VHDL testbench with GHDL and emit VCD"
	@echo "  vhdl-test-fast  Run burst/FAST-like VHDL testbench with GHDL"
	@echo "  vhdl-wave       Open generated VCD in GTKWave if available"
	@echo "  vhdl-clean      Remove VHDL build artifacts"
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
		-v "$(CURDIR):$(CURDIR)" \
		-w "$(CURDIR)" \
		$(DOCKER_IMAGE) \
		bash -lc "cmake -S $(MFAST_DIR) -B $(MFAST_BUILD_DIR) $(MFAST_CMAKE_FLAGS)"

mfast-build: mfast-configure
	$(DOCKER) run --rm \
		-u $(UID):$(GID) \
		-v "$(CURDIR):$(CURDIR)" \
		-w "$(CURDIR)" \
		$(DOCKER_IMAGE) \
		bash -lc "cmake --build $(MFAST_BUILD_DIR) --parallel $(JOBS)"

mfast-install: mfast-build
	$(DOCKER) run --rm \
		-u $(UID):$(GID) \
		-v "$(CURDIR):$(CURDIR)" \
		-w "$(CURDIR)" \
		$(DOCKER_IMAGE) \
		bash -lc "cmake --install $(MFAST_BUILD_DIR) --prefix $(CURDIR)/$(MFAST_INSTALL_DIR)"

mfast-rebuild: mfast-clean mfast-build

mfast-clean:
	rm -rf "$(MFAST_BUILD_DIR)"

cpp-configure: docker-image mfast-install
	$(DOCKER) run --rm \
		-u $(UID):$(GID) \
		-v "$(CURDIR):$(CURDIR)" \
		-w "$(CURDIR)" \
		$(DOCKER_IMAGE) \
		bash -lc "cmake -S $(CPP_DIR) -B $(CPP_BUILD_DIR) -DCMAKE_BUILD_TYPE=Release -DCMAKE_PREFIX_PATH=$(CURDIR)/$(MFAST_INSTALL_DIR)"

cpp-build: cpp-configure
	$(DOCKER) run --rm \
		-u $(UID):$(GID) \
		-v "$(CURDIR):$(CURDIR)" \
		-w "$(CURDIR)" \
		$(DOCKER_IMAGE) \
		bash -lc "cmake --build $(CPP_BUILD_DIR) --parallel $(JOBS)"

cpp-test: cpp-configure
	$(DOCKER) run --rm \
		-u $(UID):$(GID) \
		-v "$(CURDIR):$(CURDIR)" \
		-w "$(CURDIR)" \
		$(DOCKER_IMAGE) \
		bash -lc "cmake --build $(CPP_BUILD_DIR) --parallel $(JOBS) --target fpga_shared_stream_test && ctest --test-dir $(CPP_BUILD_DIR) --output-on-failure"

cpp-clean:
	rm -rf "$(CPP_BUILD_DIR)"

vhdl-test: docker-image
	mkdir -p "$(VHDL_BUILD_DIR)"
	$(DOCKER) run --rm \
		-u $(UID):$(GID) \
		-v "$(CURDIR):$(CURDIR)" \
		-w "$(CURDIR)" \
		$(DOCKER_IMAGE) \
		bash -lc "ghdl -a --std=08 --workdir=$(VHDL_BUILD_DIR) $(VHDL_DIR)/arm_fpga_shared_stream_bridge.vhd $(VHDL_TB_FILE) && ghdl -e --std=08 --workdir=$(VHDL_BUILD_DIR) $(VHDL_TB) && ghdl -r --std=08 --workdir=$(VHDL_BUILD_DIR) $(VHDL_TB) --vcd=$(VHDL_VCD) --stop-time=$(VHDL_STOP_TIME)"

vhdl-test-fast: VHDL_TB=$(VHDL_TB_FAST)
vhdl-test-fast: VHDL_TB_FILE=$(VHDL_DIR)/$(VHDL_TB_FAST).vhd
vhdl-test-fast: vhdl-test

vhdl-wave:
	@if [ -f "$(VHDL_VCD)" ]; then \
		if command -v gtkwave >/dev/null 2>&1; then \
			gtkwave "$(VHDL_VCD)"; \
		else \
			echo "VCD ready at $(VHDL_VCD). Install GTKWave and open it manually."; \
		fi; \
	else \
		echo "VCD file not found. Run 'make vhdl-test' first."; \
	fi

vhdl-clean:
	rm -rf "$(VHDL_BUILD_DIR)"

docker-shell: docker-image
	$(DOCKER) run --rm -it \
		-u $(UID):$(GID) \
		-v "$(CURDIR):$(CURDIR)" \
		-w "$(CURDIR)" \
		$(DOCKER_IMAGE) \
		bash
