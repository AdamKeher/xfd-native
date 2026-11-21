# xfd-native

Decrunch Amiga executables and data files packed with classic crunchers
(PowerPacker, Imploder, DefJam, TetraPack, Titanics, ByteKiller,
StoneCracker, CrunchMania and a few hundred more) on Linux, macOS or Windows.
It can also split executables that a linker joined together, such as a
cracktro stuck in front of a game. No Amiga or emulator setup needed.

xfd-native is the Amiga [xfdmaster.library](https://aminet.net/package/util/pack/xfdmaster)
decrunching system rebuilt as a native command-line tool:

- **The library code** (recognition, decrunch dispatch, hunk checking and
  relocation, xfdDecrunch's output handling) is ported to portable C.
- **The decrunchers themselves** are the original 68000 assembly "slaves"
  written by Georg Hörmann, Dirk Stöcker and many others. They run unchanged
  on the [Musashi](https://github.com/kstenerud/Musashi) 68k emulator core,
  with a small fake AmigaOS (exec/dos/xfdmaster jump tables) around them.

Because the original decruncher code runs, the output matches what
xfdDecrunch produces on a real Amiga, byte for byte. It was checked against
809 Amiga executables that xfdDecrunch 1.9 processed under WinUAE. All 691
crunched files (41 packer variants) decrunched to identical bytes, with the
same packer name reported each time. The 118 files the original left alone
gave the same result too.

It also handles packers that xfdmaster never knew:
[Shrinkler](#newer-packers), Cranker, L-Packer and hitchhikr's Imploder,
through slaves written for xfd-native. [XPK](#xpk) files decrunch through
xfdmaster's own XPK slave, with xpkmaster.library's unpacking done natively.

## Download (Windows)

Prebuilt Windows x64 packages are on the
[Releases](https://github.com/AdamKeher/xfd-native/releases) page. Unzip
`xfd-native-<version>-windows-x64.zip` and run `xfdnative.exe` from a command
prompt. It is a single self-contained executable with no installer and no
extra DLLs.

The 139 xfdmaster slaves, XPK, and the Shrinkler, Cranker, L-Packer and
Imploder (hitchhikr) slaves work straight away. To add the external slaves, run
`python scripts\fetch_slaves.py` in the unzipped folder. That needs Python 3
and [7-Zip](https://www.7-zip.org/), and it creates `slaves\` next to
`xfdnative.exe`, where the program finds it automatically.

## Build

Needs a C99 compiler, a C++17 compiler (for ancient, which decodes XPK) and
GNU make.

```sh
make            # -> build/xfdnative   (build/xfdnative.exe on Windows)
make check      # self-tests
```

The internal slaves are prebuilt into `m68k/xfd-m68k.bin`, and the extra
slaves (OBJT, Shrinkler, Cranker, L-Packer, ImploderHH, XPK) into
`m68k/extra`. Both are
embedded in the binary, so the normal build needs no 68k assembler. To
rebuild them from the assembly sources you need
[vasm](http://sun.hasenbraten.de/vasm/) (`vasmm68k_mot`): `make blob`.

## External slaves

xfdmaster has 139 built-in decrunchers (in `vendor/xfdmaster/m68k/slaves`).
More ship as separate "external slaves" (the files in `LIBS:xfd/` on an
Amiga). xfd-native loads them from a directory:

```sh
make slaves                        # = python3 scripts/fetch_slaves.py -> ./slaves
build/xfdnative -x slaves ...      # or set XFD_SLAVES, or keep 'slaves/' next to the binary
```

`fetch_slaves.py` builds the most complete set it can find. It starts from
the 103 slaves of the last official XFD release (1.38, 2003) and replaces
any slave that has a newer release elsewhere. It then adds formats from
later slave releases (Wanted Team, Kyzer, Ronald van Dijk, Chris Young),
after screening them for false positives (see below). Every download is
checked against a pinned SHA-256. `slaves/SOURCES.txt` records where each
file came from.

Eight game-specific Wanted Team slaves accept almost any file, so they would
"decrunch" everything else into garbage. In a screen against 805
uncrunched files seven of them matched 791–805 each, and BCKid, added later,
matched 6,505 of 6,588, while every other added slave matched none. They go
to `slaves-catchall/` and are only used when asked for, on a file you know
comes from that game:
`xfdnative -x slaves-catchall FILE OUT`.

The slaves are fetched rather than included because of their licences, for
example "freely distributable for noncommercial use, keep all files
together" for XFD. See [THIRD_PARTY.md](THIRD_PARTY.md).

## Newer packers

These packers came after the last XFD release, and the first three are
popular for demos and intros. Their slaves are written for xfd-native (`m68k/src`, prebuilt in
`m68k/extra`) and built into the binary. They load after the external
slaves and count as external, so `-n` turns them off, and a file of the same
name in the slave directory replaces one. They are plain 68000 xfd slaves,
so on an Amiga they can be copied to `LIBS:xfd/`.

| Packer | Supported | Names |
| --- | --- | --- |
| [Shrinkler](https://github.com/askeksa/Shrinkler) by Blueberry | 4.0–4.7 executables: default, mini (`-m`) and overlap (`-o`) headers, with any text, flash or commandline option. Data files written with `--header`. | Shrinkler, Shrinkler Mini, Shrinkler Overlap, Shrinkler Data |
| [Cranker](https://aminet.net/package/util/pack/cranker) by bifat/TEK | Executables with any decranker. Data files (`-cd`, also with `-eo`). | Cranker, Cranker Data |
| [L-Packer](https://github.com/arnaud-carre/L-Packer) by Leonard/Oxygene | 0.92–1.00 executables (LZ4, ZX0 or DEFLATE, with any flash or text option). `-data` files. | L-Packer LZ4/ZX0/Deflate, L-Packer Data LZ4/ZX0/Deflate |
| [Imploder](https://github.com/hitchhikr/imploder) by hitchhikr (2026) | 1.2–1.4d executables, any mode. Its data files are classic `IMP!` files, which xfdmaster's Imploder Data slave already decrunches. | Imploder (hitchhikr) |

Data files come back byte for byte. These executable packers drop part of
the original file, so the result is an equivalent executable rather than the
original bytes:

- **Shrinkler** keeps each hunk's contents, memory size and type, and its
  relocations, and all of that comes back exactly. The first hunk is written
  as CODE. In overlap mode the other hunks become DATA, or BSS if they are
  empty. A hunk's data ends after its last nonzero longword, and the rest of
  its memory is zero as before.
- **Cranker** keeps contents and relocations. Hunks with data become CODE,
  and each crunched hunk keeps the 4–252 bytes Cranker added to its memory
  size for in-place decrunching.
- **L-Packer** merges all hunks into one per memory type, so the result has
  two hunks, and their memory sizes include L-Packer's in-place margin.
- **Imploder (hitchhikr)** keeps each hunk's contents, memory size and type,
  and its relocations, which all come back exactly. It does not record
  whether a hunk was code or data, so every hunk with data comes back as
  CODE. Each hunk is an ordinary `IMP!` stream, which the slave hands to
  xfdmaster's Imploder Data slave.

A Cranker file is an AmigaDOS overlay executable. xfdmaster's hunk check,
which runs before an executable packer's slave, rejects overlays, so the
Cranker slaves are data slaves and `--identify` says "(data)".

Each packer was built from source and run in all of its modes over real
executables of 0.3–580 KB with up to 7 hunks, chip memory, BSS and
relocations between hunks. Older releases were run too: Shrinkler 4.0, 4.1,
4.4 and 4.6, and L-Packer 0.92–0.99. All of the more than 500 results matched their
originals hunk by hunk (memory type and size, contents, relocations), or byte
for byte for data files. The only failures were outputs that Shrinkler 4.0
itself corrupted. In the same run, none of 1,547 other files was mistaken
for one of these packers.

hitchhikr's Imploder was built from source at each release that packs
executables (1.2, 1.3, 1.4, 1.4b and 1.4d, which all write the same file).
Every release packed the 16 test executables (1.4 and later in three
modes), and 1.4d also packed 791 more. Of the 579 files it produced, 535 matched their
originals hunk by hunk. The other 44 have the packer bug described below,
and the slave gives back exactly what the packer stored. None of 6,588
uncrunched files was mistaken for it.

Two upstream bugs are worth knowing about:

- Cranker's 68k decrunchers count lengths in 16 bits. A literal run or match
  over 64 KB, which `cranker -1` writes for poorly compressible data,
  decrunches wrongly on an Amiga. xfd-native decodes it correctly.
- Shrinkler 4.0 sometimes overwrites its own decrunch header, producing a
  broken file. 4.1 fixed this.
- hitchhikr's Imploder (up to 1.4d) packs a hunk's full memory size from the
  input file even when the hunk has less data. The part that should be zero
  gets whatever follows in the file (the relocation table, the next hunk)
  or, past the end of the file, leftover memory of the packing program. The
  packed program runs with those bytes, so the decrunched file has them too.

Not supported: Shrinkler `--data` files without `--header` (nothing marks
them), and L-Packer 0.90 and 0.91, which store the packed data differently.

## XPK

XPK files (`XPKF`) are decrunched by xfdmaster's own XPK slaves ("XPK
Packed", "XPK Crypted"), the same 68k code xfdmaster.library uses. On an
Amiga that code hands the file to xpkmaster.library and its sub-libraries
(xpkSQSH, xpkNUKE, ...). xfd-native provides xpkmaster.library's
`XpkUnpack()` itself and decodes with Teemu Suutari's
[ancient](https://github.com/temisu/ancient) library (`vendor/ancient`), so
no XPK libraries are needed. The slave source is unchanged
(`vendor/xfdmaster/m68k/slaves/XPK.s`). `m68k/src/XPK.asm` only wraps it as
an external slave, built in like the ones above, so `-n` turns it off too.

All 51 sub-formats ancient implements are supported: ACCA, ARTM, BLZW, BZP2,
CBR0, CBR1, CRM2, CRMS, CYB2, DLTA, DUKE, ELZX, FAST, FBR2, FRHT, FRLE,
GZIP, HFMN, HUFF, ILZR, IMPL, LHLB, LIN1–4, LZBS, LZCB, LZW2–5, MASH, NONE,
NUKE, PPMQ, PWPK, RAKE, RDCN, RLEN, SASC, SDHC, SHR3, SHRI, SHSC, SLZ3,
SLZX, SMPL, SQSH, TDCS and ZENO. Header and chunk checksums are checked. All
52 XPK files in ancient's test set, at least one per sub-format, decrunch to
their originals byte for byte.

Not supported: encrypted XPK files ("not supported"), and the formats that
have no decoder: the encryption methods (BLFH, CAST, ENCO, FEAL, IDEA, NUID,
SHID), the floating-point DMC methods (DMCB, DMCD, DMCI, DMCU), and BZIP,
DHUF, L2XZ, LZ40, LZMA and TLTA ("missing resource").

## Usage

```
xfdnative [options] SOURCE [DEST]
xfdnative --unlink [options] SOURCE [DEST1 DEST2]
```

| Option | xfdDecrunch | Meaning |
| --- | --- | --- |
| `-u`, `--unlink` | (`xfdUnlink`) | split a linked executable into its two parts (see [Unlinking](#unlinking)) |
| `-f`, `--force` | `FORCE` | overwrite DEST |
| `-p`, `--linkpro` | `LP` | absolute-address images (e.g. DefJam) get xfdDecrunch's "professional" loader header, which makes them runnable executables again |
| `-s`, `--linksimple` | `LS` | same with the simple loader header |
| `-c`, `--copyall` | `CA` | write DEST even when SOURCE is not crunched |
| `-n`, `--noextern` | `NE` | use xfdmaster's internal slaves only (no external or extra slaves) |
| `-a`, `--all-layers` | – | keep going while the result is crunched again |
| `-x DIR`, `--slaves DIR` | – | load external slaves from DIR |
| `--password TEXT`, `--key N` | – | for protected files (xfdDecrunch prompts instead) |
| `-i`, `--identify` | – | only name the packer (and the linker, if any); change nothing |
| `-l`, `--list` | – | list all slaves |
| `-t`, `--trace` | – | log emulator/library calls to stderr |

Without DEST the file is recognised and test-decrunched, and nothing is written.

The output mirrors xfdDecrunch:

```
$ xfdnative -f -p -x slaves demo demo.unpacked
Reading "demo" (146752 bytes)...
Decrunching "DefJam Cruncher 3.2" file...
Writing "demo.unpacked" (409584 bytes)...
Linking professional executable header...
```

Exit codes: `0` done (or nothing to do: not crunched, not linked), `10`
recognised but decrunching or unlinking failed, `20` usage or I/O error. (The
original xfdDecrunch exits with 0 even when decrunching fails. xfd-native
reports 10.)

## Unlinking

Scene tools often joined two programs into one executable: a "linker" stub
runs the first program, then the second. A cracktro or intro was commonly
glued in front of a game, or a text message in front of a program.
`--unlink` recognises the linker and writes the two original programs back
out, like the Amiga `xfdUnlink` command:

```
$ xfdnative -u linked part1 part2
Reading "linked"...
Unlinking "4EB9 Linker" files...
Writing "part1"...
Writing "part2"...
```

Supported linkers are the ones xfdmaster knows: 4EB9 and 4EF9 linkers, UFO,
XLink 3.0, Glue 2.2/2.3, EXP 1.1 and ETA 0.91/0.99/1.00 text linkers,
FileShield, ExeDescript 1.0 and FileDescript. `--identify` also reports a
linker (`Linked: "4EB9 Linker"`). A crunched file has to be decrunched before
it can be unlinked, and the parts may themselves be crunched.

The unlink code is xfdmaster's original 68k code, run the same way as the
decrunchers. It was checked on the 15 linked executables in the demoscene.au
archive: 10 4EB9, 4 4EF9 and 1 ExeDescript. An independent checker confirmed
that each part is exactly a run of the original's hunks (code, data and
relocations, with hunk numbers renumbered) and that the linker stub is gone.
For ExeDescript the parts are the program and its attached description text.

## How it works

```
 host (C)                                   emulated 68k memory (16 MB, big-endian)
 ─────────────────────────                  ─────────────────────────────────────────
 main.c   xfdDecrunch logic     ──calls──▶  xfdBufferInfo, source + target buffers
 xfdlib.c xfdRecogBuffer(),                 internal slave blob  (m68k/xfd-m68k.bin)
          xfdDecrunchBuffer(),  ──emu_call▶ slave RecogBuffer / DecrunchBuffer code
          xfdRelocate(), ...    ◀──trap───  jsr _LVOxfdRelocate(a6) etc.
 emu.c    exec AllocMem/FreeMem,◀──trap───  jsr _LVOAllocMem(a6) etc.
          CopyMem, OpenLibrary
          Musashi 68EC020 core
 xpkmaster.c XpkUnpack() (ancient) ◀──trap─  jsr _LVOXpkUnpack(a6) (XPK slave)
```

Every library base's jump table entry holds an `ILLEGAL` instruction. Musashi
reports it through its illegal-instruction callback, and the host works out
which library function was called from the address. The C code keeps all
shared structures in emulated memory, so the 68k slaves and the native code
see the same data. Calls nest: a slave can call `xfdDecrunchBuffer()` again,
which runs more 68k code. Every file gets a fresh heap and a cycle and time
budget, so broken input can't hang the tool.

## Differences from the Amiga original

- Segment (already-loaded program), scan (search inside disk images or
  memory dumps) and strip-hunks functions are not ported. Files are
  decrunched and unlinked as buffers, which gives the same result for files.
- xpkmaster.library and the XPK sub-libraries are not run. Only
  `XpkUnpack()` on memory buffers exists, written in C++ around ancient
  (see [XPK](#xpk)). Encrypted XPK files are not supported.
- `xfdRelocate()` accepts `HUNK_END`. The OS4 C source it was ported from
  rejects it, which is a bug in that port.
- Allocated memory is always zeroed, so output never depends on leftover
  memory contents.
- Slave and linker code is called with the same register contents the
  original 68k library sets up, not just the documented arguments. ProPack
  depends on this, and so do the 4EB9/4EF9 linker analysers (A1).

## Related work

[amiscan](https://github.com/creep-ltx/amiscan) also runs real Amiga
decruncher code on Musashi. It loads the complete 68k xfdmaster, xpkmaster
and xvs libraries, where xfd-native ports the library to C and runs only the
slaves.

## Licence

LGPL-2.1-or-later, like xfdmaster.library ([LICENSE](LICENSE)). Musashi is
MIT, and ancient is BSD-2-Clause.
[THIRD_PARTY.md](THIRD_PARTY.md) records where every file came from, its
licence, and any changes.
