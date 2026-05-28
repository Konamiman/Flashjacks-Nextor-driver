# Makefile for the FlashJacks driver for Nextor 3.
#
# Builds one ROM (combining this driver with the Nextor kernel base file
# pointed at by NEXTOR_BASE), placed in `bin/`:
#
#   * bin/Nextor-<ver>.Flashjacks.ROM
#
# Intermediate build artifacts (.bin files produced by N80) go to
# `tmp/` and are dropped by `make clean`. The shippable ROM in `bin/`
# survives `make clean` and is removed only by `make clean-bin` (or
# `make distclean` for both).
#
# <ver> and any variant suffix (e.g. ".NO_UNDOC.SHIFT_INV") are taken
# from the NEXTOR_BASE filename, which must follow the convention
# Nextor-<ver>.base[<suffix>].dat as produced by the Nextor kernel
# Makefile. If NEXTOR_BASE has a non-standard filename, the ROM is
# named after that filename's stem instead.


### Configurable variables ###################################################

# NEXTOR_BASE: path to the Nextor kernel base .dat file (mandatory for
# every target except `setup` and the clean ones).
ifeq ($(strip $(NEXTOR_BASE)),)
ifeq ($(filter setup clean clean-bin distclean,$(MAKECMDGOALS)),)
$(error NEXTOR_BASE is not set. Point it at a Nextor kernel base .dat file)
endif
else
ifeq ($(wildcard $(NEXTOR_BASE)),)
$(error NEXTOR_BASE points at '$(NEXTOR_BASE)' which does not exist)
endif
endif

# NEXTOR_SDK: path to the Nextor SDK directory (the one containing 'asm/').
# Defaults to the bundled git submodule.
NEXTOR_SDK ?= external/Nextor/sdk

# Tool overrides. Default to invoking the executables from PATH.
N80      ?= N80
MKNEXROM ?= mknexrom

# NO_UNDOC_CPU_INSTRUCTIONS: when set (e.g. =1) the driver is assembled
# with undocumented Z80 opcodes (those operating on ixh/ixl/iyh/iyl)
# replaced with documented equivalents, for compatibility with
# Z180-based MSX machines. Set this whenever NEXTOR_BASE points at a
# .NO_UNDOC. variant; the driver developer is responsible for keeping
# the two consistent.
NO_UNDOC_CPU_INSTRUCTIONS ?=


### Output directories #######################################################

BIN := bin
TMP := tmp


### Filename derivation ######################################################

# Decompose NEXTOR_BASE's basename: 'Nextor-<ver>.base[.<suffix>].dat'.
_BASE_NAME    := $(notdir $(NEXTOR_BASE))
_BASE_STEM    := $(_BASE_NAME:.dat=)
_BASE_VERSION := $(firstword $(subst .base, ,$(_BASE_STEM)))
_BASE_SUFFIX  := $(patsubst $(_BASE_VERSION).base%,%,$(_BASE_STEM))

# If the filename didn't parse (no '.base' found), fall back to using
# the whole stem as the prefix and no variant suffix.
ifeq ($(_BASE_SUFFIX),$(_BASE_STEM))
_DRIVER_PREFIX := $(_BASE_STEM)
_VARIANT       :=
else
_DRIVER_PREFIX := $(_BASE_VERSION).Flashjacks
_VARIANT       := $(_BASE_SUFFIX)
endif

ROM := $(BIN)/$(_DRIVER_PREFIX)$(_VARIANT).ROM


### Assembly flags ###########################################################

N80_FLAGS := --no-string-escapes --no-show-banner --verbosity 0 \
             --build-type abs --output-file-extension bin \
             --output-file-case lower \
             --include-directory $(NEXTOR_SDK)

_DEFINES_NO_UNDOC := $(if $(NO_UNDOC_CPU_INSTRUCTIONS),--define-symbols NO_UNDOC_CPU_INSTRUCTIONS)


### Default target ###########################################################

.PHONY: all clean clean-bin distclean setup
all: $(ROM)

# Order-only prereqs for outputs that live in the build directories:
# ensure the directory exists without making its mtime affect rebuild
# decisions.
$(BIN) $(TMP):
	@mkdir -p $@


### Driver and chgbnk binaries (intermediates) ###############################

$(TMP)/driver.bin: driver.asm | $(TMP)
	$(N80) driver.asm $(TMP)/ $(N80_FLAGS) $(_DEFINES_NO_UNDOC)

$(TMP)/chgbnk.bin: chgbnk.asm | $(TMP)
	$(N80) chgbnk.asm $(TMP)/ $(N80_FLAGS) $(_DEFINES_NO_UNDOC)


### ROM combination via mknexrom (final output) ##############################

$(ROM): $(TMP)/driver.bin $(TMP)/chgbnk.bin | $(BIN)
	$(MKNEXROM) $(NEXTOR_BASE) $@ /d:$(TMP)/driver.bin /m:$(TMP)/chgbnk.bin


### Housekeeping #############################################################

# `make clean` keeps the shippable ROM in bin/, only wipes intermediates.
clean:
	rm -rf $(TMP)

# `make clean-bin` removes the shippable ROM.
clean-bin:
	rm -rf $(BIN)

# `make distclean` removes both.
distclean: clean clean-bin


### One-time setup ###########################################################

# `make setup` initializes the Nextor SDK submodule as a blobless
# partial clone with sparse-checkout for the `sdk/` directory only, so
# that the full Nextor repository is never fetched. Run this once,
# right after cloning this repo, instead of using `git clone
# --recurse-submodules`.
setup:
	@echo "Setting up the Nextor SDK submodule (blobless + sparse-checkout for sdk/ only)..."
	git submodule init external/Nextor
	git submodule update --init --filter=blob:none external/Nextor
	git -C external/Nextor sparse-checkout init --cone
	git -C external/Nextor sparse-checkout set sdk
	git -C external/Nextor checkout
	@echo "Done. Set NEXTOR_BASE and run 'make' to build."
