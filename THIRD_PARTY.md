# Third-party sources, licences and provenance

This file records where every part of xfd-native came from. It lists each
part's licence and any change made to it. `vendor/MANIFEST.sha256` holds a
SHA-256 for every vendored file, so any edit to upstream code shows up as a
checksum mismatch. Licence texts are in `LICENSE` (the project's own,
LGPL-2.1) and `LICENSES/`.

| Part | Path | Origin | Licence | Modified? |
| --- | --- | --- | --- | --- |
| xfdmaster 68k slaves | `vendor/xfdmaster/` | Aminet `util/libs/xfdmaster_os4.lha` 53.7 | LGPL-2.1-or-later | no |
| Assembled slave blob | `m68k/xfd-m68k.bin` | built from `vendor/xfdmaster/m68k` (see §1) | LGPL-2.1-or-later | n/a (build output) |
| Musashi 68k core | `vendor/musashi/` | GitHub `kstenerud/Musashi` @ `313ebf1` | MIT | no |
| SoftFloat | `vendor/musashi/softfloat/` | John R. Hauser, bundled with Musashi | SoftFloat-2 | no |
| Ported library code | `src/xfdlib.c`, `src/xfdlib.h` | rewritten from xfdmaster_os4 53.7 C sources (§4) | LGPL-2.1-or-later | port |
| Ported command | `src/main.c` | xfdmaster_os4 53.7 `src/utils/xfdDecrunch.c` (§4) | LGPL-2.1-or-later | port and extension |
| OBJT external slave source | `vendor/kyzer/OBJT.asm` | libxad CVS (GitHub mirror `ashang/libxad`) | Public Domain | no |
| OBJT slave binary | `m68k/extra/OBJT` | built from `vendor/kyzer/OBJT.asm` (§8) | Public Domain | n/a (build output) |
| LZX extractor | `scripts/unlzx.py` | Python port of libxad `portable/clients/LZX.c` (§9) | LGPL-2.1-or-later | port |
| Shrinkler, Cranker, L-Packer slaves | `m68k/src/`, built into `m68k/extra/` | written for xfd-native (§11) | LGPL-2.1-or-later; the ZX0 decoder also carries zlib terms | — |
| Packer test files | `tests/data/` | made with the packers from `tests/data/*.asm` (§11) | LGPL-2.1-or-later; packer headers as in §11 | — |
| New code | `src/emu.*`, `src/amiga.h`, `tools/`, `scripts/fetch_slaves.py`, `tests/`, `Makefile`, `m68k-include/` | written for xfd-native | LGPL-2.1-or-later | — |
| External slaves | not in the repo; `scripts/fetch_slaves.py` downloads them | Aminet, Wanted Team (Wayback), Kyzer, R. van Dijk (§5) | various, see §5 | not redistributed |

---

## 1. xfdmaster.library: 68k slave sources

- **Archive:** https://aminet.net/util/libs/xfdmaster_os4.lha
  (readme: https://aminet.net/util/libs/xfdmaster_os4.readme)
- **Version:** 53.7 (11.9.2014). Aminet upload date 2014-09-12.
- **Fetched:** 2026-11-20
- **Archive SHA-256:** `05d5774e29d086269f8489a13bcebb9d732f58c35493212b882e3c8fae6156f4`
- **Copyright:** Georg Hörmann (1994–1998), Dirk Stöcker (1998–),
  Fredrik Wikström (2014, AmigaOS 4 port)
- **Licence:** GNU LGPL 2.1 or later. The notice is in every source file. The
  readme calls the code "the LGPL xfdmaster.library source code made available
  as part of the libxad project on SourceForge". The slave files carry CVS ids
  from that project, such as `$Id: DefJam.a,v 1.2 2005/06/23 14:39:16 stoecker Exp $`.
- **Taken unmodified:**
  - `src/m68k/xfd-m68k.s` → `vendor/xfdmaster/m68k/xfd-m68k.s`
  - `src/m68k/slaves/*.s` (36 files) → `vendor/xfdmaster/m68k/slaves/`
  - `src/m68k/include/**` → `vendor/xfdmaster/m68k/include/`
  - `xfdmaster.readme`, `Changelog` → `vendor/xfdmaster/` (for attribution)
- **Building the blob (`make blob`):** `vasmm68k_mot -Fbin -pic -devpac
  -guess-ext -I m68k-include xfd-m68k.s`. `-guess-ext` makes vasm accept the
  Devpac-style size suffixes the sources use (`move.b #x,ccr`, `dbra.b`,
  `btst.b #n,Dn`) without editing them. The output is one position-independent
  blob of 139 slave entries from 34 slave files. Upstream comments out the
  XPK and MagneticFields slaves in `xfd-m68k.s`, and they stay out here.
- **Blob SHA-256:** `b5f3f0a811f0523d25cf0bb37494775966cd9eed6a08a88461fe5176a48fd298`
  (71,674 bytes)
- **Coverage check:** every decruncher name in the 68k `xfdmaster.library`
  39.15 binary (XFD 1.38, 2003) is also in this blob. Only "XPK Packed"
  (needs xpkmaster.library) and the linker/unlink handlers are absent.
- **Newest upstream:** the libxad project's SourceForge site is gone. Its CVS
  survives in GitHub mirrors, for example https://github.com/ashang/libxad at
  commit `dbe67a865207e49cd917ad9170a11b9eaa83998a` ("init from sf.net libxad").
  That mirror holds xfdmaster 39.16 (`XFDDATE "31.12.2003"`), newer than the
  last binary release, 39.15. Its `libxfd/source/master/slaves/*.a` are the
  originals of the 36 OS4 `.s` files used here. The OS4 versions differ only
  by being rewritten to `-Xfd68KHeader` offsets for the position-independent
  blob, plus a few branch sizes. No newer xfdmaster source or binary was
  found. The OpenAmiga OS4 repository, later 53.8, is private.

## 2. Musashi M680x0 emulator

- **Repository:** https://github.com/kstenerud/Musashi
- **Commit:** `313ebf1bd9f4d0d93341eb5ce21fd8a119e9dbdd` (2026-03-08). `readme.txt`
  says version 4.10. The opcode generator reports v4.60.
- **Tarball:** https://codeload.github.com/kstenerud/Musashi/tar.gz/313ebf1bd9f4d0d93341eb5ce21fd8a119e9dbdd
- **Tarball SHA-256:** `8bed9e28e7e5377256d41aff80a99c9e917a24e7392d9219e1c45c40ad4000e5`
- **Fetched:** 2026-11-20
- **Copyright:** © 1998–2001 Karl Stenerud
- **Licence:** MIT, in `LICENSES/Musashi-MIT.txt` (copied from `readme.txt`)
- **Taken unmodified:** `m68k.h m68k_in.c m68kconf.h m68kcpu.c m68kcpu.h
  m68kdasm.c m68kfpu.c m68kmake.c m68kmmu.h readme.txt history.txt softfloat/*`
- **Configuration:** `-DM68K_ILLG_HAS_CALLBACK=1` is passed on the compiler
  command line. `m68kconf.h` wraps that option in `#ifndef`, so no file is
  edited. `m68kops.c/h` are generated at build time by `m68kmake`.

### SoftFloat (bundled inside Musashi)

- **Author:** John R. Hauser (International Computer Science Institute)
- **Licence:** SoftFloat Release 2 legal notice, in `LICENSES/SoftFloat-2.txt`.
  "Derivative works are acceptable, even for commercial purposes", with an
  as-is / indemnify clause. It is only used by Musashi's FPU instructions,
  which the xfd slaves never execute. It gets compiled in because
  `m68kcpu.c` includes it unconditionally.

## 3. Amiga NDK include replacements (`m68k-include/`)

The slave sources `INCLUDE` a few Amiga NDK headers (`exec/types.i`,
`exec/libraries.i`, `exec/memory.i`, `dos/dos.i`, `dos/doshunks.i`). The NDK
is Commodore/Amiga copyright and is not redistributed. `m68k-include/` is a
from-scratch replacement that holds only the macros and constants the slaves
use.

**Verification:** the blob built with these headers is byte-identical to one
built against the NDK headers that ship with the "Amiga C/C++ Compile, Debug &
Profile" VS Code extension 1.8.2 (bartmanabyss). Both builds give the SHA-256
in §1.

## 4. Ported C code

The C side of xfdmaster comes from the OS4 port in the same archive as §1.
It was rewritten so that every structure lives in emulated big-endian 68k
memory, where the original slaves also read and write it. Pointer accesses
became `emu_r32()`/`emu_w32()` calls. Otherwise the logic follows the source
line for line.

| xfd-native | from (inside xfdmaster_os4.lha) |
| --- | --- |
| `xfd_init()` | `src/xfdmaster.c` `SetupInternal()` |
| `xfd_load_external()`, `xfd_load_external_dir()` | `src/xfdmaster.c` `AddExternal()`, `LoadExternal()` |
| `xfd_recog_buffer()` | `src/main/xfdRecogBuffer.c` |
| `xfd_decrunch_buffer()` | `src/main/xfdDecrunchBuffer.c` |
| `xfd_test_hunk_structure_flags()` | `src/main/xfdTestHunkStructureFlags.c` |
| `xfd_relocate()` | `src/main/xfdRelocate.c` |
| `xfd_error_text()` | `src/main/xfdGetErrorText.c` |
| `alloc_object()`, `free_object()` | `src/main/xfdAllocObject.c`, `xfdFreeObject.c` |
| `xfd_lvo()` (68k → C entry points) | `src/xfdmaster_68k.c` |
| `xfd_recog_linker()` | `src/main/xfdRecogLinker.c`, cross-checked against `RecogLinker` in the 68k `xfdmaster.a` 39.16 |
| `xfd_unlink()` | `src/main/xfdUnlink.c`, cross-checked against `Unlink` in `xfdmaster.a` 39.16 |
| `find_hunk()` | `src/xfdmaster.c` `xfdGetHunk()` (same as the 68k `xfdGetHunk`) |
| linker table relocation in `xfd_init()` | `src/xfdmaster.c` `SetupInternal()` (LinkerBrain loop) |
| `main.c` `write_output()`, `decrunch_once()`, `link_data[]` | `src/utils/xfdDecrunch.c` `write_file()`, `decrunch_file()`, `link_data` |
| `main.c` `run_unlink()` | `src/utils/xfdUnlink.c` `unlink()`; messages as in the original 68k `xfdUnlink` 1.01 (XFD 1.38 `C/xfdUnlink`) |

The 68k linker code itself (`LinkerBrain`, `LB_Analyse*`, `LB_Unlink*`,
`LB_AnalyseDiz`, `LB_UnlinkDiz`) is part of the unmodified `xfd-m68k.s` in
§1 and runs in the emulator.

**Deliberate differences from that source:**

1. `xfd_relocate()` accepts `HUNK_END`. The OS4 code has no case for it and
   returns "unsupported hunk type" for every normal executable.
2. `xfd_decrunch_buffer()` tests the documented `XFDFF_USERTARGET` flag
   (bit 3), where the OS4 code tests `XFDPFF_USERTARGET` (bit 9). Nothing in
   xfd-native sets either flag, so behaviour is unchanged.
3. ReplaceID handling in `xfd_load_external()` unlinks replaced slaves
   correctly. The OS4 loop could leave a second match in the list.
4. `link_data[]` is declared with its real length (0x74 longwords). The OS4
   file declares 0x1d0, which is its length in bytes.
5. The command is non-interactive. Password and key prompts became
   `--password`/`--key`, and the overwrite prompt became `--force`.
6. Slave calls get the registers the **original 68k master** sets up, not just
   the OS4 port's A0/D0/A1/A6. The reference is
   `libxfd/source/master/xfdmaster.a` 39.16 from the libxad mirror in §1.
   `RecogBuffer` gets D1 = packer flags, A2 = bufferinfo, A3 = slave,
   A4 = recog function, A5 = recog result. `DecrunchBuffer` gets
   D0 = A1 = the decrunch function's address. ProPack (RNC) depends on this:
   its decruncher re-runs its recogniser, which uses D0 as the buffer length.
   With D0 = 0 the packed hunks get copied raw.
7. Linker calls follow the same original 68k register state. The analyse
   functions get A0 = hunk 0, A1 = just past the matched table pattern,
   A2 = next table entry, A3 = the function, A5 = linkerinfo and
   D2 = `$deadbeef`. `LB_Analyse4EF9` reads the linked hunk numbers through
   A1; that register was missing in OS4 53.3–53.6. For a table entry with no
   pattern (ExeDescript), A1 keeps its previous value, as in the original.
   Unlink functions get D0 = A1 = their own address.
8. The `--unlink` "Unlinking" line names the linker
   (`Unlinking "4EB9 Linker" files...`), as the original xfdUnlink 1.01
   does. Disassembly confirms it pushes `xfdli_LinkerName` as the argument.
   The OS4 rewrite prints the source file name there instead.
9. The OS4 `xfdUnlink` command allocates a *buffer*-info object for the
   linker info. xfd-native allocates a linker-info object.

## 5. External slaves (fetched, not included)

None of these are redistributed here. `scripts/fetch_slaves.py` downloads
each archive, checks its pinned SHA-256, and assembles the newest version of
every slave in `slaves/`, recording each file's origin in `slaves/SOURCES.txt`.
Fetched on 2026-11-20.

| Source | URL | Version | Archive SHA-256 | Licence as stated | Taken |
| --- | --- | --- | --- | --- | --- |
| XFD package 1.38 (Dirk Stöcker et al.) | https://aminet.net/util/pack/xfdmaster.lha | 1.38 / xfdmaster 39.15, 2003 | `4147a2b29a7d007ab5b5a5f855c2a8095c6a9d9cadcb4f238d86cd8ca1424d62` | "freely distributable for noncommercial use … keep all files together" | all 103 slaves in `xfd_User/Libs/xfd` (4 replaced by newer versions below) |
| Wanted Team (Don Adan, Mr.Larmer) | Wayback Machine copy of `http://amiga.emucamp.com/wt/files/others/xfd_*.lzx`, snapshot 2008-08-29 | slaves v2.0–2.6, 2000–2006 | per file in `fetch_slaves.py` | none stated; offered freely "with source code" | 12 formats not in 1.38: Alcatraz Packer, Alchemy, FUCK, George Kirkham, Huffy-Buffy, Hunt (HFRO), Imagitec, Pack-Fire, PCC 1.4, RA, SP20, ThePowerUnit. Newer than 1.38: ByteKillerClone 2.6, Vice 2.2 |
| Kyzer (Stuart Caie) | https://www.kyzer.me.uk/pack/xfd/xfd_KennyGrant.lha | KennyGrant 1.2 (06.05.2000) | `716d3893fe6ff06f5b547cfa4fa8c4cdd9062c33e41f5bf9bc9a633bdb12cc41` | none in the file (his other slaves say Public Domain) | replaces KennyGrant 1.0 |
| Ronald van Dijk | https://www.amiga-stuff.com/files/decrunchers/ByteKillerData.lha | ByteKillerData 1.19 (22.2.2004) | `36f670b5c6ce5d5cd66bc1a2dd1310c66818875e93183be10ef4d21c45118bcf` | "freeware … © Ronald van Dijk – All rights reserved" | replaces 1.18 |
| Chris Young | https://aminet.net/util/pack/xfd_lzma.lha | 1.2a (68k slave 1.2, 2007) | `6ab754f9653ce037353ca81f3d59bd837bb1622a8123815641938c66ae9194d3` | none stated (as-is) | `OS3/lzma` as `LZMA` |
| Kyzer, built here | `m68k/extra/OBJT` (§8) | OBJT 1.0 (2003) | — | Public Domain | OBJT |

Wanted Team archives where XFD 1.38 already has the same or a newer version
were skipped: ATM4, CATC, CNC, CRUNCH2A, DSC3, EDP1, IFF-HUFF, LOB,
MagneticFieldsCruncher, PP2S, RPck, TheChamp, packII.

**False-positive screen.** Each newly added slave was loaded on its own and
run against 805 files known not to be crunched: every executable WinUAE's
xfd reported as not packed, every decrunched output, and random, text and
zero data. Eighteen slaves claimed none of them. Seven game-specific Wanted
Team slaves claimed 791–805 each because their recognisers accept almost
anything: Agony demo, DD2, Gremlin, MaxDesign, ReadySoft, Rubicon and Simon.
They go to `slaves-catchall/` and are only used when passed explicitly.

The authors of the XFD 1.38 slaves are listed in that archive's `README`:
Georg Hörmann, Dirk Stöcker, Codetapper, Dexter & Bartman/Abyss, Don Adan and
Mr.Larmer/Wanted Team, Stuart Caie/Kyzer, Psygore, WEPL, Ronald van Dijk,
Jan Poruba, Nils Görs, A. Van Helsing/X-Trade, DII and others.

## 6. Build-time tools (not redistributed)

- **vasm** (`vasmm68k_mot`) 1.9, M68k backend 2.5, motorola syntax 3.15d.
  © Volker Barthelmann and Frank Wille, http://sun.hasenbraten.de/vasm/.
  Free for non-commercial use, and commercial use needs the authors'
  permission. Only `make blob` needs it.

## 7. Verification against the Amiga original

The reference was xfdDecrunch 1.9 with xfdmaster.library 39.15 and the 103
XFD 1.38 external slaves, running under WinUAE. Each of these is
byte-identical to the Aminet release. That setup processed 809 Amiga
executables from the demoscene.au archive:

- **691 crunched files:** xfd-native with the same slaves and `LP` gave
  byte-identical output for all 691 and reported the same packer name every
  time. They cover 41 packer variants, including TetraPack, DefJam,
  ByteKiller, Imploder, PowerPacker, Titanics, StoneCracker, CrunchMania,
  Time Cruncher, Mega Cruncher, TNM, HQC, Syncro Packer, TUC, ReloKit,
  TurboSqueezer and ProPack.
- **118 files the original did not decrunch:** 117 are "Not crunched" in both.
  The last is a damaged PowerPacker 3.0 file. Both versions print "Decrunch
  failed: corrupted data". The original then exits with 0, so the pipeline
  logged it as not packed. xfd-native exits with 10.

**Unlinking (0.2.0).** The same archive contains 15 linked executables:
10 4EB9, 4 4EF9 and 1 ExeDescript. All 15 unlink. An independent checker,
which does not use xfd code, confirmed that each part of the 14 program
linkers is exactly a contiguous run of the linked file's hunks (code/data
bytes and relocations, hunk numbers renumbered) with the linker stub removed.
For ExeDescript, part 1 is the program and part 2 its `FLID` description
text. The original xfdUnlink was not run on these files, because the WinUAE
pipeline only runs xfdDecrunch. A synthetic 4EF9-linked file in
`tests/run.sh` must unlink into its two source programs byte for byte.

The corpus is copyrighted demoscene productions, so it is not included.
`tests/run.sh` runs the same check against any local corpus
(`XFD_TEST_CORPUS`).

## 8. OBJT slave (`vendor/kyzer/OBJT.asm`, `m68k/extra/OBJT`)

- **Source:** https://github.com/ashang/libxad, commit
  `dbe67a865207e49cd917ad9170a11b9eaa83998a`, file
  `libxfd/source/external_slaves/OBJT.asm`. Mirror zip SHA-256
  `a0910be07be94af7c86f9c2866c97eb6163f0947bc8de58e01db7a448fcc1319`.
  File SHA-256 `5d33e016de5c8bdeadd054f680e992ed917c1cffed1fe5edff2dae345dc2a516`.
- **Author / licence:** Kyzer/CSG, "This slave code is in the Public Domain."
  It is not in any binary XFD release.
- **Built by `make blob`:** `vasmm68k_mot -Fhunkexe -nosym -devpac -guess-ext
  -I m68k-include -I vendor/xfdmaster/m68k/include`. Output SHA-256
  `91fa43803e6f7c2efaa4d33acfe184aa92da1e8acca395e4c57e9a925c422214`.
  `tests/run.sh` uses it for an end-to-end 68k test.

## 11. Shrinkler, Cranker and L-Packer slaves (`m68k/src/`)

New 68000 code, assembled by `make blob` into `m68k/extra/Shrinkler`,
`m68k/extra/Cranker` and `m68k/extra/L-Packer`. No upstream file is included.
Each decoder was written for xfd-native, using these as references:

- **Shrinkler** (`shrinkler.i`): a port of the range decoder in the decrunch
  headers and `ShrinklerDecompress.S` of Shrinkler 4.7
  (https://github.com/askeksa/Shrinkler, © 1999–2022 Aske Simon
  Christensen). The decompression code's licence: "free to use, in whole or
  in part, modified or as is, for any legal purpose". The stream layouts are
  taken from `cruncher/HunkFile.h` and the headers of releases 4.0–4.7.
- **Cranker** (`lzo.i`): an LZO1X decoder written from the format as
  Cranker's public domain `decruncher.asm` decodes it, with the checks of
  `lzo1x_decompress_safe()`. The executable layout follows `decranker.asm`
  (public domain) in Cranker 0.72 (Aminet `util/pack/cranker`, © Timm S.
  Müller).
- **L-Packer** (`lz4zx0.i`, `inflate.i`): the file layout follows L-Packer
  1.00 (https://github.com/arnaud-carre/L-Packer, MIT, © 2025 Arnaud Carré).
  The LZ4 decoder is new. The ZX0 decoder follows `unzx0_68000.S` by
  Emmanuel Marty (salvador, zlib licence), and its zlib notice is kept in
  `lz4zx0.i` as that licence requires. The DEFLATE decoder follows the
  structure of `puff.c` by Mark Adler.

The packed files in `tests/data/` were made from `tests/data/sample.asm` and
`mini.asm` with Shrinkler 4.7 and 4.4, Cranker 0.72 and L-Packer 1.00. They
contain those packers' decrunch headers:

- Shrinkler's licence allows distributing them "in binary form as part of an
  Amiga executable" without restriction.
- Cranker's are public domain.
- L-Packer's are MIT; its licence is in `LICENSES/L-Packer-MIT.txt`.

## 9. LZX extractor (`scripts/unlzx.py`)

A Python port of the LZX client of xadmaster.library, `portable/clients/LZX.c`
("LZX 1.10 (21.2.2004)", Dirk Stöcker, LGPL-2.1-or-later), from the same
libxad mirror. It derives in turn from unlzx.c by Oliver Gantert and David
Tritscher. It is needed only to unpack the Wanted Team `.lzx` archives. Every
extracted file is CRC-32 checked, and all 35 Wanted Team archives extract
with matching CRCs.

## 10. Related work

[amiscan](https://github.com/creep-ltx/amiscan) (MIT, 2026) also runs the
real 68k xfdmaster, xpkmaster and xvs libraries on Musashi with a built-in
mini AmigaOS. It loads the whole 68k library binaries, where xfd-native
ports the library to C and runs only the slaves. No code from it is used.
