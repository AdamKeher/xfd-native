# Changelog

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
