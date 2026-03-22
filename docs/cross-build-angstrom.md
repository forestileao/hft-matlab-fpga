# Cross-Building Against An Older ARM Sysroot

This repository now supports a sysroot-aware ARM hard-float cross-build path intended for older DE10-class Linux images where the host-built Ubuntu 24.04 ARM binaries are too new.

## Why This Exists

The emulated `linux/arm/v7` build is useful for reproducing ARM-only compile errors, but it still links against the container's modern runtime. That can produce target errors such as:

- `GLIBCXX_* not found`
- `CXXABI_* not found`
- `GLIBC_* not found`

Those are ABI/version mismatches, not source-level bugs in this repository.

## New Build Path

The cross-build uses:

- `Dockerfile.cross-armhf`
- `toolchains/arm-linux-gnueabihf-sysroot.cmake`
- `make mfast-cross-install`
- `make cpp-cross-build`
- `make cpp-cross-abi`

During `cpp-cross-build`, the repository reuses the host-native `mFAST/install/bin/fast_type_gen` for code generation and links the generated sources against the ARM cross-built `mFAST/install-cross/` libraries.

Key variables:

- `CROSS_SYSROOT`: absolute path to the target rootfs/sysroot on the host
- `CROSS_TRIPLET`: defaults to `arm-linux-gnueabihf`
- `CROSS_TOOLCHAIN_FILE`: defaults to `toolchains/arm-linux-gnueabihf-sysroot.cmake`

Example:

```bash
make cpp-cross-build CROSS_SYSROOT=/abs/path/to/de10-sysroot JOBS=4
make cpp-cross-abi
```

Cross-built outputs land in:

- `mFAST/install-cross/`
- `cpp/build-cross/`

## Getting A Sysroot From The Board

If you have shell access to the board, the simplest approach is to copy the target runtime into a local sysroot directory.

Example:

```bash
mkdir -p /tmp/de10-sysroot
rsync -a root@BOARD:/lib/ /tmp/de10-sysroot/lib/
rsync -a root@BOARD:/usr/lib/ /tmp/de10-sysroot/usr/lib/
rsync -a root@BOARD:/usr/include/ /tmp/de10-sysroot/usr/include/
```

You may also need additional paths if the image stores libraries elsewhere, for example:

- `/usr/libexec/`
- `/opt/`
- `/lib/arm-linux-gnueabihf/`
- `/usr/lib/arm-linux-gnueabihf/`

The sysroot must contain the runtime loader and libc expected by the target, typically including:

- `ld-linux-armhf.so.3`
- `libc.so.6`
- `libm.so.6`
- `libstdc++.so.6`

## Checking The Board First

Before cross-building, capture the board's ABI baseline:

```bash
ldd --version
strings /usr/lib/libstdc++.so.6 | grep GLIBCXX | tail
```

If `libstdc++.so.6` lives elsewhere, adjust the path accordingly:

```bash
find /lib /usr/lib -name 'libstdc++.so.6*'
```

## Important Notes

- `cpp-cross-build` builds the binaries, but does not run them.
- `cpp-cross-abi` prints the version requirements so you can compare them with the board.
- If you omit `CROSS_SYSROOT`, the cross compiler falls back to its default sysroot, which is useful for build validation but not for target compatibility.
- The `patches/mfast-armv7-boost-hash.patch` file is still needed because `mFAST` has a 32-bit ARM compile issue independent of the runtime ABI mismatch.
