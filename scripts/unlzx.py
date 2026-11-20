#!/usr/bin/env python3
"""Extract Amiga LZX archives (used to unpack some external xfd slaves).

    python3 scripts/unlzx.py ARCHIVE.lzx DEST_DIR     extract (CRC-checked)
    python3 scripts/unlzx.py -l ARCHIVE.lzx           list

A Python port of the LZX client of xadmaster.library: libxad
`portable/clients/LZX.c`, "LZX 1.10 (21.2.2004)", $Id: LZX.c,v 1.12
2005/06/23 stoecker, Copyright (C) 1998 and later by Dirk Stoecker,
LGPL-2.1-or-later. The bit-reader, Huffman table builder and decruncher follow
that file step by step. That code in turn derives from unlzx.c by Oliver
Gantert and David Tritscher.

Every file's CRC-32 is checked. A mismatch aborts with an error, so a port
mistake can't go unnoticed.

SPDX-License-Identifier: LGPL-2.1-or-later
"""
import os
import struct
import sys
import zlib

TABLE_ONE = [0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7, 8, 8, 9, 9,
             10, 10, 11, 11, 12, 12, 13, 13, 14, 14]
TABLE_TWO = [0, 1, 2, 3, 4, 6, 8, 12, 16, 24, 32, 48, 64, 96, 128, 192, 256,
             384, 512, 768, 1024, 1536, 2048, 3072, 4096, 6144, 8192, 12288,
             16384, 24576, 32768, 49152]
MASK_BITS = [(1 << i) - 1 for i in range(16)]
TABLE_FOUR = list(range(17)) * 2


class LZXError(Exception):
    pass


def make_decode_table(number_symbols, table_size, length, table):
    """LZXmake_decode_table(): returns True if the table is invalid."""
    bit_num = 1
    pos = 0
    table_mask = 1 << table_size
    bit_mask = table_mask >> 1
    abort = False

    def rev(value):
        leaf = 0
        for _ in range(table_size):
            leaf = (leaf << 1) + (value & 1)
            value >>= 1
        return leaf

    while not abort and bit_num <= table_size:
        for symbol in range(number_symbols):
            if length[symbol] == bit_num:
                leaf = rev(pos)
                pos += bit_mask
                if pos > table_mask:
                    abort = True
                    break
                next_symbol = 1 << bit_num
                for _ in range(bit_mask):
                    table[leaf] = symbol
                    leaf += next_symbol
        bit_mask >>= 1
        bit_num += 1

    if not abort and pos != table_mask:
        for symbol in range(pos, table_mask):
            table[rev(symbol)] = 0
        next_symbol = table_mask >> 1
        pos <<= 16
        table_mask <<= 16
        bit_mask = 32768
        while not abort and bit_num <= 16:
            for symbol in range(number_symbols):
                if length[symbol] == bit_num:
                    leaf = rev(pos >> 16)
                    for fill in range(bit_num - table_size):
                        if table[leaf] == 0:
                            table[next_symbol << 1] = 0
                            table[(next_symbol << 1) + 1] = 0
                            table[leaf] = next_symbol
                            next_symbol += 1
                        leaf = table[leaf] << 1
                        leaf += (pos >> (15 - fill)) & 1
                    table[leaf] = symbol
                    pos += bit_mask
                    if pos > table_mask:
                        abort = True
                        break
            bit_mask >>= 1
            bit_num += 1
    if pos != table_mask:
        abort = True
    return abort


class Decruncher:
    def __init__(self, packed):
        self.src = packed + bytes(1024)  # the C code reads ahead
        self.sp = 0
        self.control = 0
        self.shift = -16
        self.last_offset = 1
        self.method = 0
        self.decrunch_length = 0
        self.offset_len = [0] * 8
        self.offset_table = [0] * 128
        self.h20_len = [0] * 20
        self.h20_table = [0] * 96
        self.literal_len = [0] * 768
        self.literal_table = [0] * 5120

    # control/shift refills exactly as in the C code
    def _refill(self):
        if self.shift < 0:
            self.shift += 16
            self.control += self.src[self.sp] << (8 + self.shift)
            self.control += self.src[self.sp + 1] << self.shift
            self.sp += 2
            self.control &= 0xFFFFFFFF

    def _take(self, n):
        v = self.control & MASK_BITS[n] if n < 16 else self.control & 0xFFFF
        self.control >>= n
        self.shift -= n
        self._refill()
        return v

    def _take1(self):
        # the "if(!shift--)" single-bit variant
        if self.shift == 0:
            self.shift -= 1
            self.shift += 16
            self.control += self.src[self.sp] << 24
            self.control += self.src[self.sp + 1] << 16
            self.sp += 2
            self.control &= 0xFFFFFFFF
        else:
            self.shift -= 1
        self.control >>= 1

    def _h20_symbol(self):
        symbol = self.h20_table[self.control & 63]
        if symbol >= 20:
            while True:
                symbol = self.h20_table[((self.control >> 6) & 1) + (symbol << 1)]
                self._take1()
                if symbol < 20:
                    break
            temp = 6
        else:
            temp = self.h20_len[symbol]
        self._take(temp)
        return symbol

    def read_literal_table(self):
        self._refill()
        self.method = self._take(3)
        if self.method == 3:
            for i in range(8):
                self.offset_len[i] = self._take(3)
            if make_decode_table(8, 7, self.offset_len, self.offset_table):
                raise LZXError("bad offset table")
        length = self._take(8) << 16
        length += self._take(8) << 8
        length += self._take(8)
        self.decrunch_length = length

        if self.method != 1:
            pos = 0
            fix = 1
            max_symbol = 256
            while True:
                for i in range(20):
                    self.h20_len[i] = self._take(4)
                if make_decode_table(20, 6, self.h20_len, self.h20_table):
                    raise LZXError("bad huffman20 table")
                while True:
                    symbol = self._h20_symbol()
                    if symbol in (17, 18):
                        if symbol == 17:
                            temp, count = 4, 3
                        else:
                            temp, count = 6 - fix, 19
                        count += self._take(temp) + fix
                        while pos < max_symbol and count > 0:
                            self.literal_len[pos] = 0
                            pos += 1
                            count -= 1
                    elif symbol == 19:
                        count = (self.control & 1) + 3 + fix
                        self._take1()
                        symbol = self._h20_symbol()
                        symbol = TABLE_FOUR[self.literal_len[pos] + 17 - symbol]
                        while pos < max_symbol and count > 0:
                            self.literal_len[pos] = symbol
                            pos += 1
                            count -= 1
                    else:
                        self.literal_len[pos] = TABLE_FOUR[self.literal_len[pos] + 17 - symbol]
                        pos += 1
                    if pos >= max_symbol:
                        break
                fix -= 1
                max_symbol += 512
                if max_symbol != 768:
                    break
            if make_decode_table(768, 12, self.literal_len, self.literal_table):
                raise LZXError("bad literal table")

    def decrunch(self, out, limit):
        """LZXdecrunch(): produce at least `limit` bytes (may overshoot)."""
        start = len(out)
        while len(out) - start < limit:
            symbol = self.literal_table[self.control & 4095]
            if symbol >= 768:
                self._take(12)
                while True:
                    symbol = self.literal_table[(self.control & 1) + (symbol << 1)]
                    self._take1()
                    if symbol < 768:
                        break
            else:
                self._take(self.literal_len[symbol])
            if symbol < 256:
                out.append(symbol)
                continue
            symbol -= 256
            temp = symbol & 31
            count = TABLE_TWO[temp]
            temp = TABLE_ONE[temp]
            if temp >= 3 and self.method == 3:
                temp -= 3
                count += (self.control & MASK_BITS[temp]) << 3
                self._take(temp)
                t = self.offset_table[self.control & 127]
                count += t
                self._take(self.offset_len[t])
            else:
                count += self.control & MASK_BITS[temp]
                if not count:
                    count = self.last_offset
                self._take(temp)
            self.last_offset = count
            temp = (symbol >> 5) & 15
            count = TABLE_TWO[temp] + 3
            count += self._take(TABLE_ONE[temp])
            src = len(out) - self.last_offset
            if src < 0:
                raise LZXError("match before start of data")
            for i in range(count):
                out.append(out[src + i])
        return len(out) - start

    def unpack(self, size):
        out = bytearray()
        while len(out) < size:
            if self.decrunch_length <= 0:
                self.read_literal_table()
            made = self.decrunch(out, self.decrunch_length)
            self.decrunch_length -= made
            if self.sp > len(self.src):
                raise LZXError("ran out of packed data")
        return bytes(out[:size])


def read_entries(data):
    if data[:3] != b"LZX":
        raise LZXError("not an LZX archive")
    pos = 10
    group = []
    while pos + 31 <= len(data):
        head = bytearray(data[pos:pos + 31])
        (attr, _p1, size, crsize, _mt, packmode, flags, _p2, comment_size,
         _ev, _p3, _p4, _date, data_crc, head_crc, name_size) = struct.unpack(
            "<BBIIBBBBBBBB4sIIB", bytes(head))
        name = data[pos + 31:pos + 31 + name_size]
        comment = data[pos + 31 + name_size:pos + 31 + name_size + comment_size]
        head[26:30] = b"\0\0\0\0"
        if zlib.crc32(bytes(head) + name + comment) != head_crc:
            raise LZXError("header checksum error at %d" % pos)
        pos += 31 + name_size + comment_size
        group.append({"name": name.decode("latin-1"), "size": size, "crc": data_crc})
        if crsize:
            packed = data[pos:pos + crsize]
            pos += crsize
            yield packmode, packed, group
            group = []


def extract(path, dest=None, listing=False):
    data = open(path, "rb").read()
    names = []
    for packmode, packed, group in read_entries(data):
        total = sum(e["size"] for e in group)
        if listing:
            for e in group:
                print("%8d  %s" % (e["size"], e["name"]))
            continue
        if packmode == 0:
            blob = packed[:total]
        elif packmode == 2:
            blob = Decruncher(packed).unpack(total)
        else:
            raise LZXError("unknown pack mode %d" % packmode)
        offset = 0
        for e in group:
            body = blob[offset:offset + e["size"]]
            offset += e["size"]
            if zlib.crc32(body) != e["crc"]:
                raise LZXError("CRC error in %s" % e["name"])
            if e["name"].endswith("/") and e["size"] == 0:
                os.makedirs(os.path.join(dest, e["name"]), exist_ok=True)
                continue
            target = os.path.normpath(os.path.join(dest, e["name"]))
            if not target.startswith(os.path.normpath(dest)):
                raise LZXError("unsafe path %s" % e["name"])
            os.makedirs(os.path.dirname(target) or ".", exist_ok=True)
            with open(target, "wb") as f:
                f.write(body)
            names.append(e["name"])
    return names


def main(argv):
    if len(argv) == 3 and argv[1] == "-l":
        extract(argv[2], listing=True)
        return 0
    if len(argv) != 3:
        print(__doc__.strip().splitlines()[2], file=sys.stderr)
        return 2
    for name in extract(argv[1], argv[2]):
        print(name)
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main(sys.argv))
    except LZXError as e:
        print("unlzx: %s" % e, file=sys.stderr)
        sys.exit(1)
