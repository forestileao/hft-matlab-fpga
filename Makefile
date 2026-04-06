SHELL := /bin/bash

DOCKER ?= docker
DOCKER_IMAGE ?= hft-mfast-builder:latest
DOCKER_IMAGE_CROSS_ARMHF ?= hft-cross-armhf-builder:latest
DOCKER_PLATFORM ?=
DOCKER_PLATFORM_ARG := $(if $(DOCKER_PLATFORM),--platform $(DOCKER_PLATFORM),)
ARMV7_PLATFORM ?= linux/arm/v7
ARMV7_DOCKER_IMAGE ?= hft-mfast-builder-armv7:latest
IP_MAKE_IPX ?= /opt/intelFPGA/25.1/quartus/sopc_builder/bin/ip-make-ipx
QUARTUS_IP_DIR ?= quartus
QUARTUS_IP_INDEX ?= .quartus-cache/components.ipx
DE10_HOST ?= root@192.168.7.1
DE10_HOME ?= /home/root
DE10_SYSROOT ?= /tmp/de10nano-sysroot
DE10_TOOLCHAIN_NAME ?= armv7-eabihf--glibc--bleeding-edge-2017.05-toolchains-1-2
DE10_TOOLCHAIN_URL ?= https://toolchains.bootlin.com/downloads/releases/toolchains/armv7-eabihf/tarballs/$(DE10_TOOLCHAIN_NAME).tar.bz2
DE10_TOOLCHAIN_ARCHIVE ?= .toolchain-cache/$(DE10_TOOLCHAIN_NAME).tar.bz2
DE10_TOOLCHAIN_DIR ?= .toolchains/armv7-eabihf--glibc--bleeding-edge
DE10_CROSS_TRIPLET ?= arm-buildroot-linux-gnueabihf
DE10_MFAST_BUILD_DIR ?= $(MFAST_DIR)/build-cross-de10
DE10_MFAST_INSTALL_DIR ?= $(MFAST_DIR)/install-cross-de10
DE10_CPP_BUILD_DIR ?= $(CPP_DIR)/build-cross-de10

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
CROSS_TOOLCHAIN_DIR ?=
CROSS_TOOLCHAIN_MOUNT ?= /opt/external-toolchain
CROSS_CMAKE_FLAGS ?=
VHDL_DIR ?= vhdl
VHDL_BUILD_DIR ?= $(VHDL_DIR)/build
VHDL_TB ?= tb_arm_fpga_shared_stream_bridge
VHDL_TB_FILE ?= $(VHDL_DIR)/$(VHDL_TB).vhd
VHDL_TB_FAST ?= tb_arm_fpga_shared_stream_bridge_fast
VHDL_TB_ENGINE ?= tb_hft_trade_engine
VHDL_TB_AVALON ?= tb_hft_trade_engine_avalon_mm
VHDL_SOURCES ?= $(VHDL_DIR)/arm_fpga_shared_stream_bridge.vhd $(VHDL_TB_FILE)
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
CROSS_TOOLCHAIN_VOLUME := $(if $(CROSS_TOOLCHAIN_DIR),-v "$(abspath $(CROSS_TOOLCHAIN_DIR)):$(CROSS_TOOLCHAIN_MOUNT):ro",)
CROSS_TOOLCHAIN_ENV := $(if $(CROSS_TOOLCHAIN_DIR),PATH=$(CROSS_TOOLCHAIN_MOUNT)/bin:$$PATH,)

.PHONY: help check quartus-ip-index docker-image docker-image-cross-armhf mfast-clone mfast-patch mfast-configure mfast-build mfast-install mfast-rebuild mfast-clean mfast-cross-configure mfast-cross-build mfast-cross-install cpp-configure cpp-build cpp-test cpp-smoke cpp-test-armv7 cpp-cross-configure cpp-cross-build cpp-cross-abi cpp-clean vhdl-test vhdl-test-fast vhdl-test-engine vhdl-test-avalon vhdl-test-all vhdl-wave vhdl-clean docker-shell docker-shell-cross-armhf de10-toolchain de10-sysroot de10-setup de10-build de10-abi de10-copy de10-stop de10-smoke

help:
	@echo "Targets:"
	@echo "  check           Run host C++ tests, feed smoke test, and all VHDL simulations"
	@echo "  quartus-ip-index Index the custom Quartus/Platform Designer component"
	@echo "  de10-toolchain  Download/extract the tested DE10-Nano ARM toolchain"
	@echo "  de10-sysroot    Pull /lib + /usr/lib + /usr/include from $(DE10_HOST)"
	@echo "  de10-setup      Prepare both the toolchain and local sysroot"
	@echo "  de10-build      Build ARM binaries for the DE10-Nano target"
	@echo "  de10-abi        Print ABI requirements for the DE10-Nano build"
	@echo "  de10-copy       Copy DE10-Nano binaries to $(DE10_HOST):$(DE10_HOME)"
	@echo "  de10-stop       Stop fast_receiver and fast_data_feed on the DE10-Nano"
	@echo "  de10-smoke      Start both binaries briefly on the DE10-Nano"
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
	@echo "  cpp-smoke       Run fast_data_feed and fast_receiver together in Docker"
	@echo "  cpp-test-armv7  Build and run cpp tests under emulated ARMv7 Docker"
	@echo "  cpp-cross-configure Configure cpp/ for ARM cross-build against CROSS_SYSROOT"
	@echo "  cpp-cross-build Build ARM cross targets into cpp/build-cross"
	@echo "  cpp-cross-abi   Print ABI/version requirements for the cross-built receiver"
	@echo "  cpp-clean       Remove cpp build directory"
	@echo "  vhdl-test       Run VHDL testbench with GHDL and emit VCD"
	@echo "  vhdl-test-fast  Run burst/FAST-like VHDL testbench with GHDL"
	@echo "  vhdl-test-engine Run the bridge + strategy end-to-end VHDL testbench"
	@echo "  vhdl-test-avalon Run the board-facing Avalon-MM wrapper testbench"
	@echo "  vhdl-test-all   Run all VHDL simulations"
	@echo "  vhdl-wave       Open generated VCD in GTKWave if available"
	@echo "  vhdl-clean      Remove VHDL build artifacts"
	@echo "  docker-shell    Open an interactive shell in the build container"
	@echo "  docker-shell-cross-armhf Open a shell in the ARM cross-compiler container"

docker-image:
	$(DOCKER) build $(DOCKER_PLATFORM_ARG) -t $(DOCKER_IMAGE) -f Dockerfile .

docker-image-cross-armhf:
	$(DOCKER) build -t $(DOCKER_IMAGE_CROSS_ARMHF) -f Dockerfile.cross-armhf .

check: cpp-test cpp-smoke vhdl-test-all

quartus-ip-index:
	mkdir -p "$(dir $(QUARTUS_IP_INDEX))"
	"$(IP_MAKE_IPX)" --source-directory="$(CURDIR)/$(QUARTUS_IP_DIR)" --output="$(QUARTUS_IP_INDEX)"

de10-toolchain:
	mkdir -p ".toolchains" ".toolchain-cache"
	@if [ ! -f "$(DE10_TOOLCHAIN_ARCHIVE)" ]; then \
		curl -L --fail -o "$(DE10_TOOLCHAIN_ARCHIVE)" "$(DE10_TOOLCHAIN_URL)"; \
	fi
	@if [ ! -d "$(DE10_TOOLCHAIN_DIR)" ]; then \
		tar -C ".toolchains" -xf "$(DE10_TOOLCHAIN_ARCHIVE)"; \
	fi

de10-sysroot: docker-image-cross-armhf
	rm -rf "$(DE10_SYSROOT)"
	mkdir -p "$(DE10_SYSROOT)"
	ssh "$(DE10_HOST)" 'tar -C / -cf - lib usr/lib usr/include' | tar -C "$(DE10_SYSROOT)" -xf -
	docker run --rm "$(DOCKER_IMAGE_CROSS_ARMHF)" bash -lc 'tar -C /usr/include -cf - boost' | tar -C "$(DE10_SYSROOT)/usr/include" -xf -

de10-setup: de10-toolchain de10-sysroot

de10-build: de10-setup
	$(MAKE) cpp-cross-build \
		CROSS_SYSROOT="$(DE10_SYSROOT)" \
		CROSS_TOOLCHAIN_DIR="$(CURDIR)/$(DE10_TOOLCHAIN_DIR)" \
		CROSS_TRIPLET="$(DE10_CROSS_TRIPLET)" \
		CROSS_MFAST_BUILD_DIR="$(DE10_MFAST_BUILD_DIR)" \
		CROSS_MFAST_INSTALL_DIR="$(DE10_MFAST_INSTALL_DIR)" \
		CROSS_CPP_BUILD_DIR="$(DE10_CPP_BUILD_DIR)" \
		JOBS="$(JOBS)"

de10-abi: de10-build
	$(MAKE) cpp-cross-abi \
		CROSS_SYSROOT="$(DE10_SYSROOT)" \
		CROSS_TOOLCHAIN_DIR="$(CURDIR)/$(DE10_TOOLCHAIN_DIR)" \
		CROSS_TRIPLET="$(DE10_CROSS_TRIPLET)" \
		CROSS_MFAST_BUILD_DIR="$(DE10_MFAST_BUILD_DIR)" \
		CROSS_MFAST_INSTALL_DIR="$(DE10_MFAST_INSTALL_DIR)" \
		CROSS_CPP_BUILD_DIR="$(DE10_CPP_BUILD_DIR)" \
		JOBS="$(JOBS)"

de10-copy: de10-build
	scp "$(DE10_CPP_BUILD_DIR)/fast_receiver" "$(DE10_CPP_BUILD_DIR)/fast_data_feed" "$(DE10_HOST):$(DE10_HOME)/"

de10-stop:
	ssh "$(DE10_HOST)" 'killall fast_receiver fast_data_feed >/dev/null 2>&1 || true'

de10-smoke: de10-copy
	ssh "$(DE10_HOST)" 'cd "$(DE10_HOME)" && chmod +x fast_receiver fast_data_feed && ./fast_data_feed >/dev/null 2>&1 & feed_pid=$$!; ./fast_receiver >/dev/null 2>&1 & rx_pid=$$!; sleep 1; ps | grep -E "(fast_data_feed|fast_receiver)" | grep -v grep; kill $$rx_pid $$feed_pid >/dev/null 2>&1 || true; wait $$rx_pid >/dev/null 2>&1 || true; wait $$feed_pid >/dev/null 2>&1 || true'

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
		$(CROSS_TOOLCHAIN_VOLUME) \
		-v "$(CURDIR):$(CURDIR)" \
		-w "$(CURDIR)" \
		$(DOCKER_IMAGE_CROSS_ARMHF) \
		bash -lc "$(CROSS_TOOLCHAIN_ENV) cmake -S $(MFAST_DIR) -B $(CROSS_MFAST_BUILD_DIR) $(MFAST_CMAKE_FLAGS) $(CROSS_TOOLCHAIN_FLAGS) $(CROSS_CMAKE_FLAGS)"

mfast-cross-build: mfast-cross-configure
	$(DOCKER) run --rm \
		-u $(UID):$(GID) \
		$(CROSS_SYSROOT_VOLUME) \
		$(CROSS_TOOLCHAIN_VOLUME) \
		-v "$(CURDIR):$(CURDIR)" \
		-w "$(CURDIR)" \
		$(DOCKER_IMAGE_CROSS_ARMHF) \
		bash -lc "$(CROSS_TOOLCHAIN_ENV) cmake --build $(CROSS_MFAST_BUILD_DIR) --parallel $(JOBS)"

mfast-cross-install: mfast-cross-build
	$(DOCKER) run --rm \
		-u $(UID):$(GID) \
		$(CROSS_SYSROOT_VOLUME) \
		$(CROSS_TOOLCHAIN_VOLUME) \
		-v "$(CURDIR):$(CURDIR)" \
		-w "$(CURDIR)" \
		$(DOCKER_IMAGE_CROSS_ARMHF) \
		bash -lc "$(CROSS_TOOLCHAIN_ENV) cmake --install $(CROSS_MFAST_BUILD_DIR) --prefix $(CURDIR)/$(CROSS_MFAST_INSTALL_DIR)"

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

cpp-smoke: cpp-build
	$(DOCKER) run --rm \
		$(DOCKER_PLATFORM_ARG) \
		-u $(UID):$(GID) \
		-v "$(CURDIR):$(CURDIR)" \
		-w "$(CURDIR)" \
		$(DOCKER_IMAGE) \
		bash -lc "set -e; stdbuf -oL -eL ./$(CPP_BUILD_DIR)/fast_data_feed >/tmp/fast_data_feed.log 2>&1 & feed_pid=\$$!; sleep 1; timeout 3s stdbuf -oL -eL ./$(CPP_BUILD_DIR)/fast_receiver >/tmp/fast_receiver.log 2>&1 || test \$$? -eq 124; kill \$$feed_pid >/dev/null 2>&1 || true; wait \$$feed_pid >/dev/null 2>&1 || true; sed -n '1,12p' /tmp/fast_receiver.log"

cpp-test-armv7:
	$(MAKE) cpp-test DOCKER_PLATFORM=$(ARMV7_PLATFORM) DOCKER_IMAGE=$(ARMV7_DOCKER_IMAGE)

cpp-cross-configure: docker-image-cross-armhf mfast-cross-install mfast-install
	$(DOCKER) run --rm \
		-u $(UID):$(GID) \
		$(CROSS_SYSROOT_VOLUME) \
		$(CROSS_TOOLCHAIN_VOLUME) \
		-v "$(CURDIR):$(CURDIR)" \
		-w "$(CURDIR)" \
		$(DOCKER_IMAGE_CROSS_ARMHF) \
		bash -lc "$(CROSS_TOOLCHAIN_ENV) cmake -S $(CPP_DIR) -B $(CROSS_CPP_BUILD_DIR) -DCMAKE_BUILD_TYPE=Release -DCMAKE_PREFIX_PATH=$(CURDIR)/$(CROSS_MFAST_INSTALL_DIR) -DmFAST_DIR=$(CURDIR)/$(CROSS_MFAST_INSTALL_DIR)/lib/cmake/mFAST -DMFAST_FAST_TYPE_GEN_EXECUTABLE=$(CURDIR)/$(MFAST_INSTALL_DIR)/bin/fast_type_gen $(CROSS_TOOLCHAIN_FLAGS) $(CROSS_CMAKE_FLAGS)"

cpp-cross-build: cpp-cross-configure
	$(DOCKER) run --rm \
		-u $(UID):$(GID) \
		$(CROSS_SYSROOT_VOLUME) \
		$(CROSS_TOOLCHAIN_VOLUME) \
		-v "$(CURDIR):$(CURDIR)" \
		-w "$(CURDIR)" \
		$(DOCKER_IMAGE_CROSS_ARMHF) \
		bash -lc "$(CROSS_TOOLCHAIN_ENV) cmake --build $(CROSS_CPP_BUILD_DIR) --parallel $(JOBS)"

cpp-cross-abi: cpp-cross-build
	$(DOCKER) run --rm \
		-u $(UID):$(GID) \
		$(CROSS_TOOLCHAIN_VOLUME) \
		-v "$(CURDIR):$(CURDIR)" \
		-w "$(CURDIR)" \
		$(DOCKER_IMAGE_CROSS_ARMHF) \
		bash -lc "$(CROSS_TOOLCHAIN_ENV) echo '== file ==' && file $(CROSS_CPP_BUILD_DIR)/fast_receiver && echo && echo '== needed ==' && readelf -d $(CROSS_CPP_BUILD_DIR)/fast_receiver | sed -n '1,120p' && echo && echo '== versions ==' && readelf --version-info $(CROSS_CPP_BUILD_DIR)/fast_receiver | sed -n '1,220p'"

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
		bash -lc "ghdl -a --std=08 --workdir=$(VHDL_BUILD_DIR) $(VHDL_SOURCES) && ghdl -e --std=08 --workdir=$(VHDL_BUILD_DIR) $(VHDL_TB) && ghdl -r --std=08 --workdir=$(VHDL_BUILD_DIR) $(VHDL_TB) --vcd=$(VHDL_VCD) --stop-time=$(VHDL_STOP_TIME)"

vhdl-test-fast: VHDL_TB=$(VHDL_TB_FAST)
vhdl-test-fast: VHDL_TB_FILE=$(VHDL_DIR)/$(VHDL_TB_FAST).vhd
vhdl-test-fast: vhdl-test

vhdl-test-engine: VHDL_TB=$(VHDL_TB_ENGINE)
vhdl-test-engine: VHDL_TB_FILE=$(VHDL_DIR)/$(VHDL_TB_ENGINE).vhd
vhdl-test-engine: VHDL_SOURCES=$(VHDL_DIR)/arm_fpga_shared_stream_bridge.vhd $(VHDL_DIR)/trade_decision_core.vhd $(VHDL_DIR)/hft_trade_engine.vhd $(VHDL_DIR)/$(VHDL_TB_ENGINE).vhd
vhdl-test-engine: vhdl-test

vhdl-test-avalon: VHDL_TB=$(VHDL_TB_AVALON)
vhdl-test-avalon: VHDL_TB_FILE=$(VHDL_DIR)/$(VHDL_TB_AVALON).vhd
vhdl-test-avalon: VHDL_SOURCES=$(VHDL_DIR)/arm_fpga_shared_stream_bridge.vhd $(VHDL_DIR)/trade_decision_core.vhd $(VHDL_DIR)/hft_trade_engine.vhd $(VHDL_DIR)/hft_trade_engine_avalon_mm.vhd $(VHDL_DIR)/$(VHDL_TB_AVALON).vhd
vhdl-test-avalon: vhdl-test

vhdl-test-all: vhdl-test vhdl-test-fast vhdl-test-engine vhdl-test-avalon

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
		$(CROSS_TOOLCHAIN_VOLUME) \
		-v "$(CURDIR):$(CURDIR)" \
		-w "$(CURDIR)" \
		$(DOCKER_IMAGE_CROSS_ARMHF) \
		bash -lc "$(CROSS_TOOLCHAIN_ENV) exec bash"
