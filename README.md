# FlashJacks driver for Nextor 3

This repository contains the FlashJacks IDE interface driver for [Nextor](https://github.com/Konamiman/Nextor). It produces a Nextor ROM image that combines a Nextor kernel (v3.0 or newer) base file with this driver, ready to be flashed to the FlashJacks cartridge.

Based on Konamiman's Sunrise IDE driver, adapted for the FlashJacks hardware by Aquijacks.

One ROM is built by default:

| Output                              | Notes                           |
| ----------------------------------- | ------------------------------- |
| `Nextor-<ver>.Flashjacks.ROM`       | Master + slave, real hardware.  |

`<ver>` and any kernel-base variant suffix (e.g. `.NO_UNDOC.SHIFT_INV`) are picked up automatically from the `NEXTOR_BASE` filename, see [Building](#building) below.

## Repository contents

| File              | Purpose                                                                                  |
| ----------------- | ---------------------------------------------------------------------------------------- |
| `driver.asm`      | The FlashJacks driver.                                                                   |
| `chgbnk.asm`      | Bank-switching routine for the Sunrise IDE-compatible cartridge mapper used by FlashJacks. |
| `Makefile`        | Build rules; see below.                                                                  |
| `external/Nextor` | Git submodule pointing at the Nextor repo, sparse-checkout to the `sdk/` directory only. |

## Development environment

You need:

- [**Nestor80**](https://github.com/Konamiman/Nestor80) (`N80`) on your `PATH`, or pointed at via the `N80` make variable.
- **`mknexrom`** on your `PATH`, or pointed at via the `MKNEXROM` make variable. The source lives in the Nextor repository under `buildtools/sources/mknexrom.c`.
- A POSIX **`make`**.

## Cloning the repository

This repository uses a git submodule to pull in the Nextor SDK; clone with `--recurse-submodules` and then configure the submodule for a sparse checkout of the `sdk/` directory (the only thing this driver consumes from Nextor):

```sh
git clone --recurse-submodules https://github.com/Konamiman/Flashjacks-Nextor-driver.git [<target-dir>]
cd <target-dir>/external/Nextor
git sparse-checkout init --cone
git sparse-checkout set sdk
cd ../..
```

If you already cloned without `--recurse-submodules`, run `git submodule update --init` first.

If you have a local clone of Nextor and want the submodule to point at it (e.g. while developing the SDK locally), override the URL once:

```sh
git config submodule.external/Nextor.url /path/to/your/local/Nextor
git submodule sync
git submodule update --init
```

### If you'd rather not fetch the full Nextor repository

The sequence above clones the entire Nextor repository before the sparse-checkout limits the working tree. If you'd rather only fetch the SDK files (typically <100 KB instead of tens of MB), clone the driver *without* `--recurse-submodules` and then set up the submodule as a blobless partial clone with sparse-checkout from the start:

```sh
git clone https://github.com/Konamiman/Flashjacks-Nextor-driver.git [<target-dir>]
cd <target-dir>
git submodule init external/Nextor
git submodule update --init --filter=blob:none external/Nextor
git -C external/Nextor sparse-checkout init --cone
git -C external/Nextor sparse-checkout set sdk
git -C external/Nextor checkout
```

...or, equivalently, just `make setup`:

```sh
git clone https://github.com/Konamiman/Flashjacks-Nextor-driver.git [<target-dir>]
cd <target-dir>
make setup
```

## Building

The build needs a Nextor kernel base file, supplied via `NEXTOR_BASE`:

```sh
NEXTOR_BASE=/path/to/Nextor-3.0.0.base.dat make
```

That produces the ROM in the `bin/` directory.

For an undoc-instruction-free build (compatible with Z180-based MSX machines), pair an undoc-free kernel base with the matching driver-side flag:

```sh
NEXTOR_BASE=/path/to/Nextor-3.0.0.base.NO_UNDOC.dat \
NO_UNDOC_CPU_INSTRUCTIONS=1 \
make
```

The Nextor base filename's version and variant suffix (e.g. `.NO_UNDOC.SHIFT_INV`) are mirrored in the output ROM filename. **You are responsible for keeping `NO_UNDOC_CPU_INSTRUCTIONS` consistent with the base file's variant**: the Makefile does not infer it for you.

### Building without `make`

The Makefile is the recommended way, but the ROM is produced by just three tool invocations: two `N80` calls (one for the driver, one for the bank-switching routine) and one `mknexrom` call that combines them with the kernel base:

```sh
mkdir -p tmp

# Assemble the driver  ->  tmp/driver.bin
N80 driver.asm tmp/ \
    --no-string-escapes --build-type abs --output-file-extension bin \
    --include-directory external/Nextor/sdk

# Assemble the bank-switching routine  ->  tmp/chgbnk.bin
N80 chgbnk.asm tmp/ \
    --no-string-escapes --build-type abs --output-file-extension bin \
    --include-directory external/Nextor/sdk

# Combine kernel base + driver + chgbnk  ->  Nextor-<ver>.Flashjacks.ROM
mknexrom /path/to/Nextor-<ver>.base.dat Nextor-<ver>.Flashjacks.ROM \
    /d:tmp/driver.bin /m:tmp/chgbnk.bin
```

For an undoc-free build, add `--define-symbols NO_UNDOC_CPU_INSTRUCTIONS` to *both* `N80` calls and use a `Nextor-<ver>.base.NO_UNDOC.dat` kernel base. The driver-side and base-side undoc settings must match.

## Make variables

| Variable                    | Purpose                                                              | Default                  |
| --------------------------- | -------------------------------------------------------------------- | ------------------------ |
| `NEXTOR_BASE`               | Path to the Nextor kernel base `.dat` file (mandatory).              | _(unset; error)_         |
| `NEXTOR_SDK`                | Path to the Nextor SDK directory (the one containing `asm/`).        | `external/Nextor/sdk`    |
| `N80`                       | Path to the Nestor80 assembler.                                      | `N80` (from `PATH`)      |
| `MKNEXROM`                  | Path to the `mknexrom` tool.                                         | `mknexrom` (from `PATH`) |
| `NO_UNDOC_CPU_INSTRUCTIONS` | If set (e.g. `=1`), assemble the driver without undocumented opcodes. | _(unset)_                |

Cleanup targets:

| Target           | Effect                                                                                                          |
| ---------------- | --------------------------------------------------------------------------------------------------------------- |
| `make clean`     | Removes `tmp/` (intermediate `.bin` files). `bin/` and the shippable ROM in it are kept.                        |
| `make clean-bin` | Removes `bin/` (the shippable ROM).                                                                             |
| `make distclean` | Removes both `tmp/` and `bin/`.                                                                                 |

## License

MIT - see [LICENSE](LICENSE). Note that [Nextor itself has a different license](https://github.com/Konamiman/Nextor/blob/v3.0/LICENSE.md).
