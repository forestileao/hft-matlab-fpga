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
QUARTUS_PROJECT_DIR ?= quartus/de10_nano_hft
QUARTUS_PROJECT ?= de10_nano_hft
QSYS_GENERATE ?= /opt/intelFPGA/25.1/quartus/sopc_builder/bin/qsys-generate
QUARTUS_MAP ?= quartus_map
QUARTUS_FIT ?= quartus_fit
QUARTUS_ASM ?= quartus_asm
QUARTUS_PGM ?= quartus_pgm
QUARTUS_SOF ?= $(QUARTUS_PROJECT_DIR)/output_files/$(QUARTUS_PROJECT).sof
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
MATLAB_DIR ?= matlab
MATLAB_STRATEGY_VHDL ?= $(MATLAB_DIR)/generated_hdl/codegen/strategy/hdlsrc/strategy.vhd
MATLAB_RUNNER ?= docker
MATLAB_BIN ?= $(HOME)/MATLAB/R2025b/bin/matlab
MATLAB_DOCKER_BASE_IMAGE ?= mathworks/matlab:r2025b
MATLAB_DOCKER_IMAGE ?= hft-matlab-hdl:r2025b
MATLAB_DOCKER_VOLUME ?= hft-matlab-home-r2025b
MATLAB_DOCKER_FLAGS ?= $(shell test -t 0 && echo -it || true)
MATLAB_DOCKER_REBUILD ?= 0
MATLAB_PRODUCTS ?= MATLAB MATLAB_Coder HDL_Coder Fixed-Point_Designer
MATLAB_FORCE ?= 1
MATLAB_BATCH := cd('$(CURDIR)/$(MATLAB_DIR)'); hdl_generator

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
VHDL_TB_ORDER_BOOK ?= tb_order_book_core
VHDL_TB_STRATEGY ?= tb_generated_strategy_core
VHDL_STRATEGY_SOURCE ?= $(if $(wildcard $(MATLAB_STRATEGY_VHDL)),$(MATLAB_STRATEGY_VHDL),$(VHDL_DIR)/strategy_fallback.vhd)
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

.PHONY: help build deploy check quartus-build quartus-build-no-matlab quartus-program quartus-ip-index docker-image docker-image-cross-armhf matlab-docker-image mfast-clone mfast-patch mfast-configure mfast-build mfast-install mfast-rebuild mfast-clean mfast-cross-configure mfast-cross-build mfast-cross-install cpp-configure cpp-build cpp-test cpp-smoke cpp-test-armv7 cpp-cross-configure cpp-cross-build cpp-cross-abi cpp-clean vhdl-test vhdl-test-fast vhdl-test-order-book vhdl-test-strategy vhdl-test-engine vhdl-test-avalon vhdl-test-all vhdl-wave vhdl-clean matlab-login matlab-test matlab-hdl-generate docker-shell docker-shell-cross-armhf de10-toolchain de10-sysroot de10-sysroot-check de10-setup de10-build-offline de10-build de10-abi de10-copy de10-deploy de10-enable-bridges de10-stop de10-smoke

help:
	@echo "Main workflow:"
	@echo "  make build          Offline build/test: MATLAB HDL, DE10 binaries, and Quartus SOF"
	@echo "  make deploy         Copy already-built DE10 binaries to $(DE10_HOST):$(DE10_HOME)"
	@echo ""
	@echo "Board:"
	@echo "  make quartus-program Program the SOF through JTAG if USB-Blaster is available"
	@echo "  make de10-enable-bridges Enable Linux FPGA bridge sysfs switches after programming"
	@echo "  make de10-stop       Stop fast_receiver and fast_data_feed on the DE10-Nano"
	@echo "  make de10-smoke      Brief board smoke test"
	@echo ""
	@echo "Debug:"
	@echo "  make check           Run host C++ and VHDL tests"
	@echo "  make vhdl-test-engine"
	@echo "  make vhdl-test-avalon"
	@echo "  make vhdl-test-strategy"
	@echo "  make matlab-docker-image"
	@echo "  make matlab-login"
	@echo "  make matlab-hdl-generate"
	@echo "  make de10-sysroot"
	@echo "  make de10-abi"

docker-image:
	$(DOCKER) build $(DOCKER_PLATFORM_ARG) -t $(DOCKER_IMAGE) -f Dockerfile .

docker-image-cross-armhf:
	$(DOCKER) build -t $(DOCKER_IMAGE_CROSS_ARMHF) -f Dockerfile.cross-armhf .

matlab-docker-image:
	@if [ "$(MATLAB_DOCKER_REBUILD)" != "1" ] && $(DOCKER) image inspect "$(MATLAB_DOCKER_IMAGE)" >/dev/null 2>&1; then \
		echo "Using existing MATLAB Docker image $(MATLAB_DOCKER_IMAGE). Set MATLAB_DOCKER_REBUILD=1 to rebuild."; \
	else \
		$(DOCKER) build -t "$(MATLAB_DOCKER_IMAGE)" \
			--build-arg MATLAB_BASE_IMAGE="$(MATLAB_DOCKER_BASE_IMAGE)" \
			--build-arg MATLAB_RELEASE="R2025b" \
			--build-arg MATLAB_PRODUCTS="$(MATLAB_PRODUCTS)" \
			-f Dockerfile.matlab .; \
	fi

build: de10-sysroot-check matlab-hdl-generate check de10-build-offline quartus-build-no-matlab

deploy: de10-deploy

check: cpp-test cpp-smoke vhdl-test-all

quartus-build: matlab-hdl-generate quartus-build-no-matlab

quartus-build-no-matlab:
	cd "$(QUARTUS_PROJECT_DIR)" && "$(QSYS_GENERATE)" hft.qsys --synthesis=VHDL --output-directory=hft
	cd "$(QUARTUS_PROJECT_DIR)" && "$(QUARTUS_MAP)" "$(QUARTUS_PROJECT)" -c "$(QUARTUS_PROJECT)"
	cd "$(QUARTUS_PROJECT_DIR)" && "$(QUARTUS_FIT)" "$(QUARTUS_PROJECT)" -c "$(QUARTUS_PROJECT)"
	cd "$(QUARTUS_PROJECT_DIR)" && "$(QUARTUS_ASM)" "$(QUARTUS_PROJECT)" -c "$(QUARTUS_PROJECT)"

quartus-program: quartus-build
	"$(QUARTUS_PGM)" -m JTAG -o "p;$(QUARTUS_SOF)"

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

de10-sysroot-check:
	@test -d "$(DE10_SYSROOT)" || { echo "Missing $(DE10_SYSROOT). Run 'make de10-sysroot' once while the board is reachable."; exit 1; }
	@test -f "$(DE10_SYSROOT)/usr/include/boost/version.hpp" || { echo "Incomplete $(DE10_SYSROOT): missing usr/include/boost/version.hpp. Run 'make de10-sysroot' once while the board is reachable."; exit 1; }

de10-setup: de10-toolchain de10-sysroot

de10-build-offline: de10-toolchain de10-sysroot-check
	$(MAKE) cpp-cross-build \
		CROSS_SYSROOT="$(DE10_SYSROOT)" \
		CROSS_TOOLCHAIN_DIR="$(CURDIR)/$(DE10_TOOLCHAIN_DIR)" \
		CROSS_TRIPLET="$(DE10_CROSS_TRIPLET)" \
		CROSS_MFAST_BUILD_DIR="$(DE10_MFAST_BUILD_DIR)" \
		CROSS_MFAST_INSTALL_DIR="$(DE10_MFAST_INSTALL_DIR)" \
		CROSS_CPP_BUILD_DIR="$(DE10_CPP_BUILD_DIR)" \
		JOBS="$(JOBS)"

de10-build: de10-setup
	$(MAKE) de10-build-offline JOBS="$(JOBS)"

de10-abi: de10-build
	$(MAKE) cpp-cross-abi \
		CROSS_SYSROOT="$(DE10_SYSROOT)" \
		CROSS_TOOLCHAIN_DIR="$(CURDIR)/$(DE10_TOOLCHAIN_DIR)" \
		CROSS_TRIPLET="$(DE10_CROSS_TRIPLET)" \
		CROSS_MFAST_BUILD_DIR="$(DE10_MFAST_BUILD_DIR)" \
		CROSS_MFAST_INSTALL_DIR="$(DE10_MFAST_INSTALL_DIR)" \
		CROSS_CPP_BUILD_DIR="$(DE10_CPP_BUILD_DIR)" \
		JOBS="$(JOBS)"

de10-copy: de10-build-offline
	scp "$(DE10_CPP_BUILD_DIR)/fast_receiver" "$(DE10_CPP_BUILD_DIR)/fast_data_feed" "$(DE10_HOST):$(DE10_HOME)/"

de10-deploy:
	@test -x "$(DE10_CPP_BUILD_DIR)/fast_receiver" || { echo "Missing $(DE10_CPP_BUILD_DIR)/fast_receiver. Run 'make build' first."; exit 1; }
	@test -x "$(DE10_CPP_BUILD_DIR)/fast_data_feed" || { echo "Missing $(DE10_CPP_BUILD_DIR)/fast_data_feed. Run 'make build' first."; exit 1; }
	ssh "$(DE10_HOST)" 'true'
	scp "$(DE10_CPP_BUILD_DIR)/fast_receiver" "$(DE10_CPP_BUILD_DIR)/fast_data_feed" "$(DE10_HOST):$(DE10_HOME)/"

de10-enable-bridges:
	ssh "$(DE10_HOST)" 'for b in /sys/class/fpga-bridge/*; do [ -e "$$b/enable" ] || continue; echo 1 > "$$b/enable" 2>/dev/null || true; printf "%s=" "$$(basename "$$b")"; cat "$$b/enable" 2>/dev/null || echo unknown; done'

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

vhdl-test-order-book: VHDL_TB=$(VHDL_TB_ORDER_BOOK)
vhdl-test-order-book: VHDL_TB_FILE=$(VHDL_DIR)/$(VHDL_TB_ORDER_BOOK).vhd
vhdl-test-order-book: VHDL_SOURCES=$(VHDL_DIR)/order_book_core.vhd $(VHDL_TB_FILE)
vhdl-test-order-book: vhdl-test

vhdl-test-strategy: VHDL_TB=$(VHDL_TB_STRATEGY)
vhdl-test-strategy: VHDL_TB_FILE=$(VHDL_DIR)/$(VHDL_TB_STRATEGY).vhd
vhdl-test-strategy: VHDL_SOURCES=$(VHDL_STRATEGY_SOURCE) $(VHDL_DIR)/generated_strategy_core.vhd $(VHDL_TB_FILE)
vhdl-test-strategy: vhdl-test

vhdl-test-engine: VHDL_TB=$(VHDL_TB_ENGINE)
vhdl-test-engine: VHDL_TB_FILE=$(VHDL_DIR)/$(VHDL_TB_ENGINE).vhd
vhdl-test-engine: VHDL_SOURCES=$(VHDL_DIR)/arm_fpga_shared_stream_bridge.vhd $(VHDL_DIR)/order_book_core.vhd $(VHDL_STRATEGY_SOURCE) $(VHDL_DIR)/generated_strategy_core.vhd $(VHDL_DIR)/trade_decision_core.vhd $(VHDL_DIR)/hft_trade_engine.vhd $(VHDL_TB_FILE)
vhdl-test-engine: vhdl-test

vhdl-test-avalon: VHDL_TB=$(VHDL_TB_AVALON)
vhdl-test-avalon: VHDL_TB_FILE=$(VHDL_DIR)/$(VHDL_TB_AVALON).vhd
vhdl-test-avalon: VHDL_SOURCES=$(VHDL_DIR)/arm_fpga_shared_stream_bridge.vhd $(VHDL_DIR)/order_book_core.vhd $(VHDL_STRATEGY_SOURCE) $(VHDL_DIR)/generated_strategy_core.vhd $(VHDL_DIR)/trade_decision_core.vhd $(VHDL_DIR)/hft_trade_engine.vhd $(VHDL_DIR)/hft_trade_engine_avalon_mm.vhd $(VHDL_TB_FILE)
vhdl-test-avalon: vhdl-test

vhdl-test-all:
	$(MAKE) vhdl-test
	$(MAKE) vhdl-test-fast
	$(MAKE) vhdl-test-order-book
	$(MAKE) vhdl-test-strategy
	$(MAKE) vhdl-test-engine
	$(MAKE) vhdl-test-avalon

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

matlab-login: matlab-docker-image
	$(DOCKER) run --rm -it -u root -e HOME=/home/matlab \
		-v "$(CURDIR):$(CURDIR)" \
		-v "$(MATLAB_DOCKER_VOLUME):/home/matlab" \
		-w "$(CURDIR)/$(MATLAB_DIR)" \
		"$(MATLAB_DOCKER_IMAGE)" -batch "disp('MATLAB Docker login OK')"

matlab-test: matlab-docker-image
	@if [ "$(MATLAB_RUNNER)" = "docker" ]; then \
		$(DOCKER) run --rm $(MATLAB_DOCKER_FLAGS) -u root -e HOME=/home/matlab \
			-v "$(CURDIR):$(CURDIR)" \
			-v "$(MATLAB_DOCKER_VOLUME):/home/matlab" \
			-w "$(CURDIR)/$(MATLAB_DIR)" \
			"$(MATLAB_DOCKER_IMAGE)" -batch "cd('$(CURDIR)/$(MATLAB_DIR)'); strategy_tb"; \
	else \
		"$(MATLAB_BIN)" -batch "cd('$(CURDIR)/$(MATLAB_DIR)'); strategy_tb"; \
	fi

matlab-hdl-generate: matlab-docker-image
	@if [ "$(MATLAB_FORCE)" != "1" ] && [ -f "$(MATLAB_STRATEGY_VHDL)" ]; then \
		echo "Using existing $(MATLAB_STRATEGY_VHDL). Set MATLAB_FORCE=1 to regenerate."; \
		exit 0; \
	fi; \
	set -e; \
	if [ "$(MATLAB_RUNNER)" = "docker" ]; then \
		$(DOCKER) run --rm $(MATLAB_DOCKER_FLAGS) -u root -e HOME=/home/matlab \
			-v "$(CURDIR):$(CURDIR)" \
			-v "$(MATLAB_DOCKER_VOLUME):/home/matlab" \
			-w "$(CURDIR)/$(MATLAB_DIR)" \
			"$(MATLAB_DOCKER_IMAGE)" -batch "$(MATLAB_BATCH)"; \
	else \
		"$(MATLAB_BIN)" -batch "$(MATLAB_BATCH)"; \
	fi; \
	if [ "$(MATLAB_RUNNER)" = "docker" ] && [ -d "$(MATLAB_DIR)/generated_hdl" ]; then \
		$(DOCKER) run --rm --entrypoint chown -u root \
			-v "$(CURDIR):$(CURDIR)" \
			"$(MATLAB_DOCKER_IMAGE)" -R $(UID):$(GID) "$(CURDIR)/$(MATLAB_DIR)/generated_hdl"; \
	fi; \
	test -f "$(MATLAB_STRATEGY_VHDL)"

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
