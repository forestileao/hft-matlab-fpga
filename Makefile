SHELL := /bin/bash

DOCKER ?= docker
DOCKER_IMAGE ?= hft-mfast-builder:latest
DOCKER_IMAGE_CROSS_ARMHF ?= hft-cross-armhf-builder:latest
DOCKER_PLATFORM ?=
DOCKER_PLATFORM_ARG := $(if $(DOCKER_PLATFORM),--platform $(DOCKER_PLATFORM),)
ARMV7_PLATFORM ?= linux/arm/v7
ARMV7_DOCKER_IMAGE ?= hft-mfast-builder-armv7:latest

MFAST_REPO ?= https://github.com/objectcomputing/mFAST.git
MFAST_DIR ?= mFAST
MFAST_BUILD_DIR ?= $(MFAST_DIR)/build
MFAST_INSTALL_DIR ?= $(MFAST_DIR)/install
CROSS_MFAST_BUILD_DIR ?= $(MFAST_DIR)/build-cross
CROSS_MFAST_INSTALL_DIR ?= $(MFAST_DIR)/install-cross
MFAST_PATCH ?= patches/mfast-armv7-boost-hash.patch
CPP_DIR ?= cpp
CPP_BUILD_DIR ?= $(CPP_DIR)/build
CROSS_CPP_BUILD_DIR ?= $(CPP_DIR)/build-cross
CROSS_TOOLCHAIN_FILE ?= toolchains/arm-linux-gnueabihf-sysroot.cmake
CROSS_TRIPLET ?= arm-linux-gnueabihf
CROSS_CC ?= $(CROSS_TRIPLET)-gcc
CROSS_CXX ?= $(CROSS_TRIPLET)-g++
CROSS_SYSROOT ?=
CROSS_SYSROOT_MOUNT ?= /opt/target-sysroot
CROSS_CMAKE_FLAGS ?=
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
CROSS_TOOLCHAIN_FLAGS := -DCMAKE_TOOLCHAIN_FILE=$(CURDIR)/$(CROSS_TOOLCHAIN_FILE) \
	-DHFT_TOOLCHAIN_TRIPLET=$(CROSS_TRIPLET) \
	-DHFT_C_COMPILER=$(CROSS_CC) \
	-DHFT_CXX_COMPILER=$(CROSS_CXX) \
	$(if $(CROSS_SYSROOT),-DHFT_SYSROOT=$(CROSS_SYSROOT_MOUNT),)
CROSS_SYSROOT_VOLUME := $(if $(CROSS_SYSROOT),-v "$(abspath $(CROSS_SYSROOT)):$(CROSS_SYSROOT_MOUNT):ro",)

.PHONY: help docker-image docker-image-cross-armhf mfast-clone mfast-patch mfast-configure mfast-build mfast-install mfast-rebuild mfast-clean mfast-cross-configure mfast-cross-build mfast-cross-install cpp-configure cpp-build cpp-test cpp-test-armv7 cpp-cross-configure cpp-cross-build cpp-cross-abi cpp-clean vhdl-test vhdl-test-fast vhdl-wave vhdl-clean docker-shell docker-shell-cross-armhf

help:
	@echo "Targets:"
	@echo "  docker-image    Build the Docker image with C++/CMake/Boost toolchain"
	@echo "  docker-image-cross-armhf Build the cross-compiler image for ARM hard-float"
	@echo "  mfast-clone     Clone mFAST recursively if missing; always sync submodules"
	@echo "  mfast-patch     Apply repository patches to mFAST after clone"
	@echo "  mfast-configure Configure mFAST in Docker"
	@echo "  mfast-build     Build mFAST in Docker"
	@echo "  mfast-install   Install mFAST artifacts to mFAST/install on host"
	@echo "  mfast-cross-configure Configure mFAST with the sysroot-aware ARM cross toolchain"
	@echo "  mfast-cross-build Build mFAST with the sysroot-aware ARM cross toolchain"
	@echo "  mfast-cross-install Install ARM cross-built mFAST artifacts to mFAST/install-cross"
	@echo "  mfast-rebuild   Clean and build mFAST in Docker"
	@echo "  mfast-clean     Remove mFAST build directory"
	@echo "  cpp-configure   Configure cpp/ against mFAST install in Docker"
	@echo "  cpp-build       Build cpp/ targets in Docker"
	@echo "  cpp-test        Build and run cpp tests (CTest) in Docker"
	@echo "  cpp-test-armv7  Build and run cpp tests under emulated ARMv7 Docker"
	@echo "  cpp-cross-configure Configure cpp/ for ARM cross-build against CROSS_SYSROOT"
	@echo "  cpp-cross-build Build ARM cross targets into cpp/build-cross"
	@echo "  cpp-cross-abi   Print ABI/version requirements for the cross-built receiver"
	@echo "  cpp-clean       Remove cpp build directory"
	@echo "  vhdl-test       Run VHDL testbench with GHDL and emit VCD"
	@echo "  vhdl-test-fast  Run burst/FAST-like VHDL testbench with GHDL"
	@echo "  vhdl-wave       Open generated VCD in GTKWave if available"
	@echo "  vhdl-clean      Remove VHDL build artifacts"
	@echo "  docker-shell    Open an interactive shell in the build container"
	@echo "  docker-shell-cross-armhf Open a shell in the ARM cross-compiler container"

docker-image:
	$(DOCKER) build $(DOCKER_PLATFORM_ARG) -t $(DOCKER_IMAGE) -f Dockerfile .

docker-image-cross-armhf:
	$(DOCKER) build -t $(DOCKER_IMAGE_CROSS_ARMHF) -f Dockerfile.cross-armhf .

mfast-clone:
	@if [ ! -d "$(MFAST_DIR)/.git" ]; then \
		git clone --recursive "$(MFAST_REPO)" "$(MFAST_DIR)"; \
	fi
	@git -C "$(MFAST_DIR)" submodule update --init --recursive

mfast-patch: mfast-clone
	@if [ -f "$(MFAST_PATCH)" ]; then \
		if git -C "$(MFAST_DIR)" apply --reverse --check "$(CURDIR)/$(MFAST_PATCH)" >/dev/null 2>&1; then \
			echo "mFAST patch already applied: $(MFAST_PATCH)"; \
		else \
			git -C "$(MFAST_DIR)" apply "$(CURDIR)/$(MFAST_PATCH)"; \
		fi; \
	fi

mfast-configure: docker-image mfast-patch
	$(DOCKER) run --rm \
		$(DOCKER_PLATFORM_ARG) \
		-u $(UID):$(GID) \
		-v "$(CURDIR):$(CURDIR)" \
		-w "$(CURDIR)" \
		$(DOCKER_IMAGE) \
		bash -lc "cmake -S $(MFAST_DIR) -B $(MFAST_BUILD_DIR) $(MFAST_CMAKE_FLAGS)"

mfast-build: mfast-configure
	$(DOCKER) run --rm \
		$(DOCKER_PLATFORM_ARG) \
		-u $(UID):$(GID) \
		-v "$(CURDIR):$(CURDIR)" \
		-w "$(CURDIR)" \
		$(DOCKER_IMAGE) \
		bash -lc "cmake --build $(MFAST_BUILD_DIR) --parallel $(JOBS)"

mfast-install: mfast-build
	$(DOCKER) run --rm \
		$(DOCKER_PLATFORM_ARG) \
		-u $(UID):$(GID) \
		-v "$(CURDIR):$(CURDIR)" \
		-w "$(CURDIR)" \
		$(DOCKER_IMAGE) \
		bash -lc "cmake --install $(MFAST_BUILD_DIR) --prefix $(CURDIR)/$(MFAST_INSTALL_DIR)"

mfast-cross-configure: docker-image-cross-armhf mfast-patch
	$(DOCKER) run --rm \
		-u $(UID):$(GID) \
		$(CROSS_SYSROOT_VOLUME) \
		-v "$(CURDIR):$(CURDIR)" \
		-w "$(CURDIR)" \
		$(DOCKER_IMAGE_CROSS_ARMHF) \
		bash -lc "cmake -S $(MFAST_DIR) -B $(CROSS_MFAST_BUILD_DIR) $(MFAST_CMAKE_FLAGS) $(CROSS_TOOLCHAIN_FLAGS) $(CROSS_CMAKE_FLAGS)"

mfast-cross-build: mfast-cross-configure
	$(DOCKER) run --rm \
		-u $(UID):$(GID) \
		$(CROSS_SYSROOT_VOLUME) \
		-v "$(CURDIR):$(CURDIR)" \
		-w "$(CURDIR)" \
		$(DOCKER_IMAGE_CROSS_ARMHF) \
		bash -lc "cmake --build $(CROSS_MFAST_BUILD_DIR) --parallel $(JOBS)"

mfast-cross-install: mfast-cross-build
	$(DOCKER) run --rm \
		-u $(UID):$(GID) \
		$(CROSS_SYSROOT_VOLUME) \
		-v "$(CURDIR):$(CURDIR)" \
		-w "$(CURDIR)" \
		$(DOCKER_IMAGE_CROSS_ARMHF) \
		bash -lc "cmake --install $(CROSS_MFAST_BUILD_DIR) --prefix $(CURDIR)/$(CROSS_MFAST_INSTALL_DIR)"

mfast-rebuild: mfast-clean mfast-build

mfast-clean:
	rm -rf "$(MFAST_BUILD_DIR)"

cpp-configure: docker-image mfast-install
	$(DOCKER) run --rm \
		$(DOCKER_PLATFORM_ARG) \
		-u $(UID):$(GID) \
		-v "$(CURDIR):$(CURDIR)" \
		-w "$(CURDIR)" \
		$(DOCKER_IMAGE) \
		bash -lc "cmake -S $(CPP_DIR) -B $(CPP_BUILD_DIR) -DCMAKE_BUILD_TYPE=Release -DCMAKE_PREFIX_PATH=$(CURDIR)/$(MFAST_INSTALL_DIR)"

cpp-build: cpp-configure
	$(DOCKER) run --rm \
		$(DOCKER_PLATFORM_ARG) \
		-u $(UID):$(GID) \
		-v "$(CURDIR):$(CURDIR)" \
		-w "$(CURDIR)" \
		$(DOCKER_IMAGE) \
		bash -lc "cmake --build $(CPP_BUILD_DIR) --parallel $(JOBS)"

cpp-test: cpp-configure
	$(DOCKER) run --rm \
		$(DOCKER_PLATFORM_ARG) \
		-u $(UID):$(GID) \
		-v "$(CURDIR):$(CURDIR)" \
		-w "$(CURDIR)" \
		$(DOCKER_IMAGE) \
		bash -lc "cmake --build $(CPP_BUILD_DIR) --parallel $(JOBS) --target fpga_shared_stream_test && ctest --test-dir $(CPP_BUILD_DIR) --output-on-failure"

cpp-test-armv7:
	$(MAKE) cpp-test DOCKER_PLATFORM=$(ARMV7_PLATFORM) DOCKER_IMAGE=$(ARMV7_DOCKER_IMAGE)

cpp-cross-configure: docker-image-cross-armhf mfast-cross-install mfast-install
	$(DOCKER) run --rm \
		-u $(UID):$(GID) \
		$(CROSS_SYSROOT_VOLUME) \
		-v "$(CURDIR):$(CURDIR)" \
		-w "$(CURDIR)" \
		$(DOCKER_IMAGE_CROSS_ARMHF) \
		bash -lc "cmake -S $(CPP_DIR) -B $(CROSS_CPP_BUILD_DIR) -DCMAKE_BUILD_TYPE=Release -DCMAKE_PREFIX_PATH=$(CURDIR)/$(CROSS_MFAST_INSTALL_DIR) -DmFAST_DIR=$(CURDIR)/$(CROSS_MFAST_INSTALL_DIR)/lib/cmake/mFAST -DMFAST_FAST_TYPE_GEN_EXECUTABLE=$(CURDIR)/$(MFAST_INSTALL_DIR)/bin/fast_type_gen $(CROSS_TOOLCHAIN_FLAGS) $(CROSS_CMAKE_FLAGS)"

cpp-cross-build: cpp-cross-configure
	$(DOCKER) run --rm \
		-u $(UID):$(GID) \
		$(CROSS_SYSROOT_VOLUME) \
		-v "$(CURDIR):$(CURDIR)" \
		-w "$(CURDIR)" \
		$(DOCKER_IMAGE_CROSS_ARMHF) \
		bash -lc "cmake --build $(CROSS_CPP_BUILD_DIR) --parallel $(JOBS)"

cpp-cross-abi: cpp-cross-build
	$(DOCKER) run --rm \
		-u $(UID):$(GID) \
		-v "$(CURDIR):$(CURDIR)" \
		-w "$(CURDIR)" \
		$(DOCKER_IMAGE_CROSS_ARMHF) \
		bash -lc "echo '== file ==' && file $(CROSS_CPP_BUILD_DIR)/fast_receiver && echo && echo '== needed ==' && readelf -d $(CROSS_CPP_BUILD_DIR)/fast_receiver | sed -n '1,120p' && echo && echo '== versions ==' && readelf --version-info $(CROSS_CPP_BUILD_DIR)/fast_receiver | sed -n '1,220p'"

cpp-clean:
	rm -rf "$(CPP_BUILD_DIR)"

vhdl-test: docker-image
	mkdir -p "$(VHDL_BUILD_DIR)"
	$(DOCKER) run --rm \
		$(DOCKER_PLATFORM_ARG) \
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
		$(DOCKER_PLATFORM_ARG) \
		-u $(UID):$(GID) \
		-v "$(CURDIR):$(CURDIR)" \
		-w "$(CURDIR)" \
		$(DOCKER_IMAGE) \
		bash

docker-shell-cross-armhf: docker-image-cross-armhf
	$(DOCKER) run --rm -it \
		-u $(UID):$(GID) \
		$(CROSS_SYSROOT_VOLUME) \
		-v "$(CURDIR):$(CURDIR)" \
		-w "$(CURDIR)" \
		$(DOCKER_IMAGE_CROSS_ARMHF) \
		bash
