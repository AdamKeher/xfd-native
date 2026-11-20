# xfd-native build. Needs a C99 compiler and GNU make.
#
#   make            build build/xfdnative
#   make blob       re-assemble the 68k code in m68k/ from source (needs vasm)
#   make slaves     download the external slaves into slaves/ (needs Python 3)
#   make check      run the self-tests
#   make clean
#
# SPDX-License-Identifier: LGPL-2.1-or-later

VERSION := 0.1.0

CC      ?= cc
CFLAGS  ?= -O2
WARN    := -Wall -Wextra
BUILD   := build
MUSASHI := vendor/musashi

ifeq ($(OS),Windows_NT)
  EXE := .exe
else
  EXE :=
endif

# Musashi: enable the illegal-instruction callback (used for OS traps).
# m68kconf.h wraps this option in #ifndef, so no vendor file is edited.
MUSASHI_DEFS := -DM68K_ILLG_HAS_CALLBACK=1

TARGET  := $(BUILD)/xfdnative$(EXE)
SRC     := src/main.c src/emu.c src/xfdlib.c
OBJ     := $(SRC:src/%.c=$(BUILD)/%.o)
M68K_OBJ := $(BUILD)/m68kcpu.o $(BUILD)/m68kops.o $(BUILD)/m68kdasm.o $(BUILD)/softfloat.o
BLOB    := m68k/xfd-m68k.bin

.PHONY: all clean blob check
all: $(TARGET)

$(BUILD):
	mkdir -p $(BUILD)

# ---- Musashi ---------------------------------------------------------------

$(BUILD)/m68kmake$(EXE): $(MUSASHI)/m68kmake.c | $(BUILD)
	$(CC) -O2 -o $@ $<

$(BUILD)/m68kops.c $(BUILD)/m68kops.h: $(BUILD)/m68kmake$(EXE) $(MUSASHI)/m68k_in.c
	$(BUILD)/m68kmake$(EXE) $(BUILD) $(MUSASHI)/m68k_in.c

MUSASHI_CFLAGS := $(CFLAGS) $(MUSASHI_DEFS) -I$(BUILD) -I$(MUSASHI) -w

$(BUILD)/m68kcpu.o: $(MUSASHI)/m68kcpu.c $(BUILD)/m68kops.h
	$(CC) $(MUSASHI_CFLAGS) -c -o $@ $<
$(BUILD)/m68kops.o: $(BUILD)/m68kops.c $(BUILD)/m68kops.h
	$(CC) $(MUSASHI_CFLAGS) -c -o $@ $<
$(BUILD)/m68kdasm.o: $(MUSASHI)/m68kdasm.c $(BUILD)/m68kops.h
	$(CC) $(MUSASHI_CFLAGS) -c -o $@ $<
$(BUILD)/softfloat.o: $(MUSASHI)/softfloat/softfloat.c $(BUILD)/m68kops.h
	$(CC) $(MUSASHI_CFLAGS) -c -o $@ $<

# ---- 68k slave blob -----------------------------------------------------------

$(BUILD)/bin2c$(EXE): tools/bin2c.c | $(BUILD)
	$(CC) -O2 -o $@ $<

$(BUILD)/blob.c: $(BLOB) $(BUILD)/bin2c$(EXE)
	$(BUILD)/bin2c$(EXE) $(BLOB) $@ xfd_m68k_blob

$(BUILD)/blob.o: $(BUILD)/blob.c
	$(CC) $(CFLAGS) -c -o $@ $<

# Re-assemble the blob from vendor/xfdmaster/m68k (unmodified upstream source)
# with our NDK-free headers in m68k-include/, and the public-domain OBJT
# external slave from vendor/kyzer.
VASM ?= vasmm68k_mot
blob:
	cd vendor/xfdmaster/m68k && $(VASM) -quiet -Fbin -pic -devpac -guess-ext \
		-I../../../m68k-include -o ../../../$(BLOB) xfd-m68k.s
	$(VASM) -quiet -Fhunkexe -nosym -devpac -guess-ext -Im68k-include \
		-Ivendor/xfdmaster/m68k/include -o m68k/extra/OBJT vendor/kyzer/OBJT.asm

# Download and merge the external slaves (see scripts/fetch_slaves.py)
PYTHON ?= python3
.PHONY: slaves
slaves:
	$(PYTHON) scripts/fetch_slaves.py

# ---- tool -------------------------------------------------------------------------

$(BUILD)/%.o: src/%.c src/amiga.h src/emu.h src/xfdlib.h $(BUILD)/m68kops.h
	$(CC) $(CFLAGS) $(WARN) $(MUSASHI_DEFS) -DXFDN_VERSION=\"$(VERSION)\" -I$(MUSASHI) -I$(BUILD) -c -o $@ $<

$(TARGET): $(OBJ) $(M68K_OBJ) $(BUILD)/blob.o
	$(CC) $(CFLAGS) -o $@ $^ -lm

check: $(TARGET)
	sh tests/run.sh $(TARGET)

clean:
	rm -rf $(BUILD)
