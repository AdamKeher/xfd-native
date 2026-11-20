#!/usr/bin/env python3
"""Assemble the external xfd slave set (LIBS:xfd) in ./slaves.

    python3 scripts/fetch_slaves.py [DEST_DIR]

The external slaves can't be redistributed in this repository (see
THIRD_PARTY.md, section 5), so this script fetches the original archives,
checks each against a pinned SHA-256, and puts the newest version of every
slave in DEST_DIR (default: ./slaves):

  1. XFD 1.38 (Aminet, 2003): the 103 slaves of the last official release
  2. Wanted Team slaves (Wayback Machine copies of their site): 12 formats
     that are not in 1.38, plus ByteKillerClone 2.6 and Vice 2.2, which are
     newer than the 1.38 copies. Older or equal versions are skipped. Seven
     more game-specific catch-all slaves go to DEST_DIR-catchall instead
     (see CATCH_ALL).
  3. Kyzer's KennyGrant 1.2 (1.38 ships 1.0)
  4. Ronald van Dijk's ByteKillerData 1.19 (1.38 ships 1.18)
  5. Chris Young's LZMA slave 1.2a (Aminet)
  6. OBJT, assembled in this repository from Kyzer's public-domain source
     (m68k/extra/OBJT)

Needs Python 3, plus 7z (p7zip) or lha (lhasa) for the .lha archives. LZX
archives are unpacked by scripts/unlzx.py.

SPDX-License-Identifier: LGPL-2.1-or-later
"""
import hashlib
import os
import shutil
import struct
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(HERE)
sys.path.insert(0, HERE)
import unlzx  # noqa: E402

# The Wayback Machine serves the capture nearest to this timestamp, the
# 2008-08-29 snapshot of the Wanted Team "others" page. The SHA-256 pins
# below make sure the same files come back.
WAYBACK = "https://web.archive.org/web/20080829181533id_/http://amiga.emucamp.com:80/wt/files/others/{name}"

# (label, url, sha256, {file in archive: name in slaves/ or None for "all slaves found"})
SOURCES = [
    ("XFD 1.38", "https://aminet.net/util/pack/xfdmaster.lha",
     "4147a2b29a7d007ab5b5a5f855c2a8095c6a9d9cadcb4f238d86cd8ca1424d62", None),
]

# Wanted Team: archive name, sha256, slave file inside
WANTED_TEAM = [
    ("xfd_AgonyDemo.lzx", "8f5dfc2079e51f96183aa698fb6dbf728032d33afa5967c3c70f51a106a7cee4", "Agony demo"),
    ("xfd_AlcatrazPacker.lzx", "b43b2cd21e11f093146253e7a0f3ee75fb96f941f4d1ff70860111bdddd469e6", "Alcatraz Packer"),
    ("xfd_Alchemy.lzx", "c192b1e9c5950b54b7463c6458b0a8a872b1cec348ba137045caa2b44a058cf5", "Alchemy"),
    ("xfd_ByteKillerClone.lzx", "e0618f84bc36799ea6fce4bfd2cb4c3477307004902d64da331bd9a9691c0fc4", "ByteKillerClone"),
    ("xfd_DD2.lzx", "0f4e188ce926c7d6f4445b35871bbd17f57770185d801e3af26b0275ede7e231", "DD2"),
    ("xfd_FUCK.lzx", "65ed59276e1b93c28bdd7b107326c5349bc8bff4b57eb1ce8d3807d7b43d12bd", "FUCK"),
    ("xfd_GeorgeKirkham.lzx", "4cd43554cd1d77f73b6a05056496e582949f8946e2a71b9658d098daf2969b84", "George Kirkham"),
    ("xfd_Gremlin.lzx", "f7e90ae74d31e96b254762b36507471385f777aa0a651e4d326c2ff38146a21c", "Gremlin"),
    ("xfd_Huffy-Buffy.lzx", "06b06778b5c9d10d38ba589d958bd2a02c10a94c66000938d1baaa667df254b7", "Huffy-Buffy_v2"),
    ("xfd_Hunt.lzx", "0635a402fa00a41e1b41142dfa62c61c8fd58d8d9c4ee58ffea3af2cfcff9314", "Hunt"),
    ("xfd_Imagitec.lzx", "2c9a4905db80fea2ad37030d7426769e46ab56326f449fe0dc6f01c690a43a3e", "Imagitec"),
    ("xfd_MaxDesign.lzx", "2c56f83dfbd899c27064afcba5bf7b56da58a1584bc72671ee0b3308624664ce", "MaxDesign"),
    ("xfd_PCC1.4.lzx", "30932d03a327cf11a731aa328cb0c3f1e467de3454b3cadb819af59025ce867f", "PCC 1.4"),
    ("xfd_PackFire.lzx", "6baee629c596bc8ad90afa1243dfe82e638e7ec5e68fc7dd09e01fe42dadeee3", "Pack-Fire"),
    ("xfd_RA.lzx", "17212df47c914f59a9525e20a68c0b205c99ebda2c9c8772a3b9984ed1f34ea2", "RA"),
    ("xfd_ReadySoft.lzx", "f4d1839b1af02f8bc5cab482ea03b336d4b323c5312f5f916209087726467fed", "ReadySoft"),
    ("xfd_Rubicon.lzx", "58261af89a8fb2d3f8920c8ddf18eee19f3a8ce1c510a9ae989a75243d7090b7", "Rubicon"),
    ("xfd_SP20.lzx", "80986ef5846aa1904500ff2623d2c19d39b2e97e4c9da01f29bf765deceb503c", "SP20"),
    ("xfd_Simon.lzx", "9c032897368c148b05d7bea24c078265517485127940ffe706c93e084226dff6", "Simon"),
    ("xfd_ThePowerUnit.lzx", "83ac0974cb7f973a544e980f3be2c590e98105464c036df446958248262cd2f3", "ThePowerUnit"),
    ("xfd_Vice.lzx", "be873d181aab41e2edc624994301b3f2b05ab7facebe16495f147e4cd944fe4f", "Vice"),
]
# Skipped Wanted Team archives, because XFD 1.38 has the same or a newer
# version: ATM4, CATC, CNC, CRUNCH2A, DSC3, EDP1, IFF-HUFF, LOB,
# MagneticFieldsCruncher, PP2S, RPck, TheChamp, packII.

# Game-specific slaves whose recogniser accepts (almost) any file. Each one
# claimed 791-805 of 805 known-uncrunched files in a false-positive screen
# (Amiga executables, already-decrunched files, random/text/zero data); all
# other slaves here claimed none. They would hijack every unrecognised file,
# so they go to a separate directory for deliberate use on files known to
# come from that game:  xfdnative -x slaves-catchall FILE ...
CATCH_ALL = {"Agony demo", "DD2", "Gremlin", "MaxDesign", "ReadySoft", "Rubicon", "Simon"}

SOURCES += [
    ("Kyzer KennyGrant 1.2", "https://www.kyzer.me.uk/pack/xfd/xfd_KennyGrant.lha",
     "716d3893fe6ff06f5b547cfa4fa8c4cdd9062c33e41f5bf9bc9a633bdb12cc41",
     {"KennyGrant": "KennyGrant"}),
    ("Ronald van Dijk ByteKillerData 1.19", "https://www.amiga-stuff.com/files/decrunchers/ByteKillerData.lha",
     "36f670b5c6ce5d5cd66bc1a2dd1310c66818875e93183be10ef4d21c45118bcf",
     {"ByteKillerData": "ByteKillerData"}),
    ("Chris Young LZMA 1.2a", "https://aminet.net/util/pack/xfd_lzma.lha",
     "6ab754f9653ce037353ca81f3d59bd837bb1622a8123815641938c66ae9194d3",
     {"OS3/lzma": "LZMA"}),
]


def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(65536), b""):
            h.update(chunk)
    return h.hexdigest()


def download(url, dest, expected):
    req = urllib.request.Request(url, headers={"User-Agent": "xfd-native fetch_slaves"})
    # The Wayback Machine refuses connections when asked too quickly; back off.
    for attempt, wait in enumerate([0, 5, 15, 30, 60, 120]):
        time.sleep(wait)
        try:
            with urllib.request.urlopen(req, timeout=120) as r, open(dest, "wb") as f:
                shutil.copyfileobj(r, f)
            break
        except (urllib.error.URLError, OSError) as e:
            print("  retrying %s (%s)" % (url, e))
    else:
        raise SystemExit("Could not download %s" % url)
    got = sha256(dest)
    if got != expected:
        raise SystemExit("SHA-256 mismatch for %s\n  got      %s\n  expected %s" % (url, got, expected))


def find_7z():
    found = shutil.which("7z")
    if found:
        return found
    # The 7-Zip installer on Windows does not add itself to PATH
    for base in (os.environ.get("ProgramFiles"), os.environ.get("ProgramFiles(x86)")):
        if base and os.path.isfile(os.path.join(base, "7-Zip", "7z.exe")):
            return os.path.join(base, "7-Zip", "7z.exe")
    return None


def unlha(archive, dest):
    os.makedirs(dest, exist_ok=True)
    sevenzip = find_7z()
    if sevenzip:
        subprocess.run([sevenzip, "x", "-y", "-o" + dest, archive], check=True, stdout=subprocess.DEVNULL)
    elif shutil.which("lha"):
        subprocess.run(["lha", "xqw=" + dest, archive], check=True)
    else:
        raise SystemExit("Need 7-Zip (7z) or lha to unpack %s" % archive)


def is_slave(path):
    """True if path is a hunk executable whose first hunk starts with an xfdForeman."""
    with open(path, "rb") as f:
        data = f.read(4096)
    if len(data) < 40 or data[:4] != b"\0\0\x03\xf3":
        return False
    first, last = struct.unpack(">II", data[12:20])
    pos = 20 + 4 * (last - first + 1)
    # first hunk is HUNK_CODE, or HUNK_DATA for slaves written in C
    if pos + 16 > len(data) or struct.unpack(">I", data[pos:pos + 4])[0] & 0x3FFFFFFF not in (0x3E9, 0x3EA):
        return False
    return data[pos + 12:pos + 16] == b"XFDF"


def find_files(root):
    for d, _, files in os.walk(root):
        for f in files:
            yield os.path.join(d, f)


def main():
    dest = os.path.abspath(sys.argv[1] if len(sys.argv) > 1 else os.path.join(REPO, "slaves"))
    os.makedirs(dest, exist_ok=True)
    installed = {}
    with tempfile.TemporaryDirectory() as work:
        for i, (label, url, digest, picks) in enumerate(SOURCES):
            print("Fetching %s" % label)
            archive = os.path.join(work, "%d.lha" % i)
            download(url, archive, digest)
            out = os.path.join(work, "%d" % i)
            unlha(archive, out)
            if picks is None:
                for p in find_files(out):
                    if is_slave(p):
                        installed[os.path.basename(p)] = (p, label)
            else:
                files = list(find_files(out))
                for inner, name in picks.items():
                    # match on the trailing path, wherever the archive roots it
                    tail = os.path.join(*inner.split("/"))
                    hits = [p for p in files if p.endswith(os.sep + tail) and is_slave(p)]
                    if len(hits) != 1:
                        raise SystemExit("%s: expected one xfd slave %s, found %d" % (label, inner, len(hits)))
                    installed[name] = (hits[0], label)

        print("Fetching %d Wanted Team archives (Wayback Machine)" % len(WANTED_TEAM))
        for name, digest, inner in WANTED_TEAM:
            archive = os.path.join(work, name)
            time.sleep(2)  # be gentle with the Wayback Machine
            download(WAYBACK.format(name=name), archive, digest)
            out = os.path.join(work, name + ".d")
            unlzx.extract(archive, out)
            p = os.path.join(out, inner)
            if not is_slave(p):
                raise SystemExit("%s: %s is not an xfd slave" % (name, inner))
            installed[inner] = (p, "Wanted Team " + name)

        objt = os.path.join(REPO, "m68k", "extra", "OBJT")
        if is_slave(objt):
            installed["OBJT"] = (objt, "OBJT (built from vendor/kyzer/OBJT.asm)")

        catchall_dest = dest + "-catchall"
        os.makedirs(catchall_dest, exist_ok=True)
        for name, (path, _label) in installed.items():
            target = catchall_dest if name in CATCH_ALL else dest
            shutil.copyfile(path, os.path.join(target, name))

    for d, names in ((dest, [n for n in installed if n not in CATCH_ALL]),
                     (catchall_dest, [n for n in installed if n in CATCH_ALL])):
        with open(os.path.join(d, "SOURCES.txt"), "w") as f:
            for name in sorted(names, key=str.lower):
                f.write("%-24s %s\n" % (name, installed[name][1]))
        print("%d external slaves in %s (origins in SOURCES.txt)" % (len(names), d))


if __name__ == "__main__":
    main()
