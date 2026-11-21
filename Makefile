# xfd-native build. Needs a C99 and a C++17 compiler and GNU make.
#
#   make            build build/xfdnative
#   make blob       re-assemble the 68k code in m68k/ from source (needs vasm)
#   make slaves     download the external slaves into slaves/ (needs Python 3)
#   make check      run the self-tests
#   make clean
#
# SPDX-License-Identifier: LGPL-2.1-or-later

VERSION := 0.4.0

CC      ?= cc
CFLAGS  ?= -O2
CXXFLAGS ?= -O2
# LDFLAGS=-static gives a self-contained Windows .exe (no MinGW DLLs)
LDFLAGS ?=
WARN    := -Wall -Wextra
BUILD   := build
MUSASHI := vendor/musashi
ANCIENT := vendor/ancient

ifeq ($(OS),Windows_NT)
  EXE := .exe
else
  EXE :=
endif

# Musashi: enable the illegal-instruction callback (used for OS traps).
# m68kconf.h wraps this option in #ifndef, so no vendor file is edited.
MUSASHI_DEFS := -DM68K_ILLG_HAS_CALLBACK=1

TARGET  := $(BUILD)/xfdnative$(EXE)
SRC     := src/main.c src/emu.c src/xfdlib.c src/xpkmaster.c
OBJ     := $(SRC:src/%.c=$(BUILD)/%.o) $(BUILD)/xpk.o
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

# ---- ancient (XPK decoding) -----------------------------------------------------

ANCIENT_SRC := $(wildcard $(ANCIENT)/src/*.cpp $(ANCIENT)/src/common/*.cpp)
ANCIENT_OBJ := $(patsubst $(ANCIENT)/src/%.cpp,$(BUILD)/ancient/%.o,$(ANCIENT_SRC))
ANCIENT_CXXFLAGS := $(CXXFLAGS) -std=c++17 -fno-rtti -I$(ANCIENT)/src -I$(ANCIENT)/api -I$(ANCIENT)/api/ancient -w

$(BUILD)/ancient/%.o: $(ANCIENT)/src/%.cpp
	@mkdir -p $(dir $@)
	$(CXX) $(ANCIENT_CXXFLAGS) -c -o $@ $<

$(BUILD)/xpk.o: src/xpk.cpp src/xpk.h | $(BUILD)
	$(CXX) $(CXXFLAGS) -std=c++17 -fno-rtti $(WARN) -I$(ANCIENT)/api -c -o $@ $<

# ---- 68k slave blob -----------------------------------------------------------

$(BUILD)/bin2c$(EXE): tools/bin2c.c | $(BUILD)
	$(CC) -O2 -o $@ $<

$(BUILD)/blob.c: $(BLOB) $(BUILD)/bin2c$(EXE)
	$(BUILD)/bin2c$(EXE) $(BLOB) $@ xfd_m68k_blob

$(BUILD)/blob.o: $(BUILD)/blob.c
	$(CC) $(CFLAGS) -c -o $@ $<

# xfd-native's own external slaves, prebuilt in m68k/extra, are built in too
EXTRA_SLAVES := $(sort $(wildcard m68k/extra/*))

$(BUILD)/embed$(EXE): tools/embed.c | $(BUILD)
	$(CC) -O2 -o $@ $<

$(BUILD)/extra.c: $(EXTRA_SLAVES) $(BUILD)/embed$(EXE)
	$(BUILD)/embed$(EXE) $@ $(EXTRA_SLAVES)

$(BUILD)/extra.o: $(BUILD)/extra.c
	$(CC) $(CFLAGS) -c -o $@ $<

# Re-assemble the blob from vendor/xfdmaster/m68k (unmodified upstream source)
# with our NDK-free headers in m68k-include/, the public-domain OBJT external
# slave from vendor/kyzer, and xfd-native's own slaves from m68k/src (plain
# 68000 code, so they also work with xfdmaster.library on an Amiga).
VASM ?= vasmm68k_mot
SLAVE_VASM = $(VASM) -quiet -Fhunkexe -nosym -devpac -guess-ext -m68000 \
	-Im68k-include -Ivendor/xfdmaster/m68k/include -Im68k/src
blob:
	cd vendor/xfdmaster/m68k && $(VASM) -quiet -Fbin -pic -devpac -guess-ext \
		-I../../../m68k-include -o ../../../$(BLOB) xfd-m68k.s
	$(VASM) -quiet -Fhunkexe -nosym -devpac -guess-ext -Im68k-include \
		-Ivendor/xfdmaster/m68k/include -o m68k/extra/OBJT vendor/kyzer/OBJT.asm
	$(SLAVE_VASM) -o m68k/extra/Cranker m68k/src/Cranker.asm
	$(SLAVE_VASM) -o m68k/extra/ImploderHH m68k/src/ImploderHH.asm
	$(SLAVE_VASM) -o m68k/extra/L-Packer m68k/src/L-Packer.asm
	$(SLAVE_VASM) -o m68k/extra/Shrinkler m68k/src/Shrinkler.asm
	$(SLAVE_VASM) -Ivendor/xfdmaster/m68k/slaves -o m68k/extra/XPK m68k/src/XPK.asm

# Download and merge the external slaves (see scripts/fetch_slaves.py)
PYTHON ?= python3
.PHONY: slaves
slaves:
	$(PYTHON) scripts/fetch_slaves.py

# ---- tool -------------------------------------------------------------------------

$(BUILD)/%.o: src/%.c src/amiga.h src/emu.h src/xfdlib.h $(BUILD)/m68kops.h
	$(CC) $(CFLAGS) $(WARN) $(MUSASHI_DEFS) -DXFDN_VERSION=\"$(VERSION)\" -I$(MUSASHI) -I$(BUILD) -c -o $@ $<

# linked by the C++ compiler, for ancient's C++ runtime
$(TARGET): $(OBJ) $(M68K_OBJ) $(BUILD)/blob.o $(BUILD)/extra.o $(ANCIENT_OBJ)
	$(CXX) $(CXXFLAGS) $(LDFLAGS) -o $@ $^ -lm

check: $(TARGET)
	sh tests/run.sh $(TARGET)

clean:
	rm -rf $(BUILD)
