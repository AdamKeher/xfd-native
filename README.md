# xfd-native

Decrunch Amiga executables and data files packed with classic crunchers
(PowerPacker, Imploder, DefJam, TetraPack, Titanics, ByteKiller,
StoneCracker, CrunchMania and a few hundred more) on Linux, macOS or Windows.
No Amiga or emulator setup needed.

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

## Download (Windows)

Prebuilt Windows x64 packages are on the
[Releases](https://github.com/AdamKeher/xfd-native/releases) page. Unzip
`xfd-native-<version>-windows-x64.zip` and run `xfdnative.exe` from a command
prompt. It is a single self-contained executable with no installer and no
extra DLLs.

The 139 built-in slaves work straight away. To add the external slaves, run
`python scripts\fetch_slaves.py` in the unzipped folder. That needs Python 3
and [7-Zip](https://www.7-zip.org/), and it creates `slaves\` next to
`xfdnative.exe`, where the program finds it automatically.

## Build

Needs a C99 compiler and GNU make.

```sh
make            # -> build/xfdnative   (build/xfdnative.exe on Windows)
make check      # self-tests
```

The internal slaves are prebuilt into `m68k/xfd-m68k.bin` and embedded in the
binary, so the normal build needs no 68k assembler. To rebuild that blob from
the assembly sources you need [vasm](http://sun.hasenbraten.de/vasm/)
(`vasmm68k_mot`): `make blob`.

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

Seven game-specific Wanted Team slaves accept almost any file, so they would
"decrunch" everything else into garbage. In a screen against 805
uncrunched files they matched 791–805 each, while every other added slave
matched none. They go to `slaves-catchall/` and are only used when asked
for, on a file you know comes from that game:
`xfdnative -x slaves-catchall FILE OUT`.

The slaves are fetched rather than included because of their licences, for
example "freely distributable for noncommercial use, keep all files
together" for XFD. See [THIRD_PARTY.md](THIRD_PARTY.md).

## Usage

```
xfdnative [options] SOURCE [DEST]
```

| Option | xfdDecrunch | Meaning |
| --- | --- | --- |
| `-f`, `--force` | `FORCE` | overwrite DEST |
| `-p`, `--linkpro` | `LP` | absolute-address images (e.g. DefJam) get xfdDecrunch's "professional" loader header, which makes them runnable executables again |
| `-s`, `--linksimple` | `LS` | same with the simple loader header |
| `-c`, `--copyall` | `CA` | write DEST even when SOURCE is not crunched |
| `-n`, `--noextern` | `NE` | use built-in slaves only |
| `-a`, `--all-layers` | – | keep going while the result is crunched again |
| `-x DIR`, `--slaves DIR` | – | load external slaves from DIR |
| `--password TEXT`, `--key N` | – | for protected files (xfdDecrunch prompts instead) |
| `-i`, `--identify` | – | only name the packer, don't decrunch |
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

Exit codes: `0` decrunched (or not crunched), `10` recognised but decrunching
failed, `20` usage or I/O error. (The original xfdDecrunch exits with 0 even
when decrunching fails. xfd-native reports 10.)

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
```

Every library base's jump table entry holds an `ILLEGAL` instruction. Musashi
reports it through its illegal-instruction callback, and the host works out
which library function was called from the address. The C code keeps all
shared structures in emulated memory, so the 68k slaves and the native code
see the same data. Calls nest: a slave can call `xfdDecrunchBuffer()` again,
which runs more 68k code. Every file gets a fresh heap and a cycle and time
budget, so broken input can't hang the tool.

## Differences from the Amiga original

- Segment, linker (unlink), scan and strip-hunks functions are not ported.
  Only buffer decrunching is supported.
- The XPK slave is not included (it needs xpkmaster.library).
- `xfdRelocate()` accepts `HUNK_END`. The OS4 C source it was ported from
  rejects it, which is a bug in that port.
- Allocated memory is always zeroed, so output never depends on leftover
  memory contents.
- Slave code is called with the same register contents the original 68k
  library sets up, not just the documented arguments. At least ProPack
  depends on this.

## Related work

[amiscan](https://github.com/creep-ltx/amiscan) also runs real Amiga
decruncher code on Musashi. It loads the complete 68k xfdmaster, xpkmaster
and xvs libraries, where xfd-native ports the library to C and runs only the
slaves.

## Licence

LGPL-2.1-or-later, like xfdmaster.library ([LICENSE](LICENSE)). Musashi is MIT.
[THIRD_PARTY.md](THIRD_PARTY.md) records where every file came from, its
licence, and any changes.
