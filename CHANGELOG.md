# Changelog

## Unreleased

- **XPK.** XPK files (`XPKF`) decrunch through xfdmaster's own XPK slaves,
  built in from the unchanged `XPK.s`. xfd-native provides
  xpkmaster.library's `XpkUnpack()` and decodes with Teemu Suutari's ancient
  library (BSD-2-Clause, `vendor/ancient`): all 51 sub-formats it implements,
  including SQSH, NUKE, IMPL, RAKE and BZP2. Encrypted XPK files are not
  supported. The build now needs a C++17 compiler as well.
- **Imploder (hitchhikr).** New slave for executables packed by hitchhikr's
  Imploder 1.2–1.4d (2026). Its data files already worked as Imploder Data.
- **More Wanted Team slaves.** `fetch_slaves.py` adds HOT!, LIN, LZNP,
  LZSS X68k, Pac1, PAK+ and UPX! from the 2025 copy of their site, and
  replaces NJMP 1.0 with 2.0. The catch-all BCKid slave goes to
  `slaves-catchall/`. With the external set and the new built-in slaves
  there are 334 slaves in total (was 323).
- New tests: an XPK file and a file packed by hitchhikr's Imploder.

## 0.3.0 (2026-11-21)

- **Shrinkler, Cranker and L-Packer.** New slaves, written for xfd-native in
  68000 assembly (`m68k/src`) and built into the binary:
  - Shrinkler 4.0–4.7 executables (default, mini and overlap headers, with
    any option) and data files written with `--header`.
  - Cranker executables and data files.
  - L-Packer 0.92–1.00 executables (LZ4, ZX0, DEFLATE) and data files.
  Each has its own bounds-checked decoder, so a damaged file cannot write
  outside its buffers. Checked against the packers themselves on over 500 packed
  files (see the README).
- The slaves in `m68k/extra` (OBJT and the three new ones) are built into
  the binary and need no slave directory. `-n` turns them off as before. A
  file of the same name in the slave directory replaces the built-in one.
- `make blob` also assembles the new slaves.
- New tests: a small test program (`tests/data`) packed with every packer
  and mode must decrunch to the expected result.

## 0.2.0 (2026-11-20)

- **Unlinking.** `--unlink SOURCE [DEST1 DEST2]` splits executables that a
  linker joined, like the Amiga `xfdUnlink`. Supported: 4EB9/4EF9 linkers, UFO,
  XLink 3.0, Glue 2.2/2.3, EXP 1.1 and ETA 0.91/0.99/1.00 text linkers,
  FileShield, ExeDescript 1.0 and FileDescript. It runs xfdmaster's original
  68k linker code with the original 68k register conventions. Checked on 15
  real linked executables: every part is an exact run of the original's hunks.
- `--identify` also names the linker of a linked file.
- Exit code 0 also covers "not linked". 10 also covers a failed unlink.
- New tests: a synthetic 4EF9-linked file must unlink into its two programs
  byte for byte.

## 0.1.0 (2026-11-20)

First release.

- xfdmaster.library buffer decrunching ported to C. The original 68k slaves
  run on the Musashi 68k core.
- 139 built-in slaves (xfdmaster 39.16 LGPL sources). External slaves are
  loaded from a directory. `scripts/fetch_slaves.py` assembles the newest
  version of every slave (311 in total), and catch-all slaves go to an
  opt-in folder.
- Output identical to xfdDecrunch 1.9, including the `LP`/`LS` loader
  headers. Verified byte for byte on 691 crunched executables.
- Windows x64 release package. CI on Linux, macOS and Windows.
