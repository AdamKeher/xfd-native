/*
 * xfd-native: xfdmaster.library functions needed for buffer decrunching.
 *
 * Ported from the AmigaOS 4 C port of xfdmaster.library 53.7 (Aminet
 * util/libs/xfdmaster_os4.lha, src/), which is itself a rewrite of the
 * original 68k library. The logic is kept line-for-line where possible; the
 * difference is that every structure lives in emulated big-endian 68k memory
 * and is accessed through the emu_rNN/emu_wNN helpers instead of C pointers, because the
 * original 68k slaves read and write the same structures.
 *
 * Origin of each function (paths inside xfdmaster_os4.lha):
 *   xfd_init                      src/xfdmaster.c        SetupInternal()
 *   xfd_load_external             src/xfdmaster.c        AddExternal()
 *   xfd_load_external_dir         src/xfdmaster.c        LoadExternal()
 *   xfd_recog_buffer              src/main/xfdRecogBuffer.c
 *   xfd_decrunch_buffer           src/main/xfdDecrunchBuffer.c
 *   xfd_test_hunk_structure_flags src/main/xfdTestHunkStructureFlags.c
 *   xfd_relocate                  src/main/xfdRelocate.c
 *   xfd_error_text                src/main/xfdGetErrorText.c
 *   alloc_object / free_object    src/main/xfdAllocObject.c, xfdFreeObject.c
 *   xfd_recog_linker              src/main/xfdRecogLinker.c (and RecogLinker
 *                                 in the 68k xfdmaster.a 39.16, libxad CVS)
 *   xfd_unlink                    src/main/xfdUnlink.c (and 68k Unlink)
 *   find_hunk                     src/xfdmaster.c        xfdGetHunk()
 *   xfd_lvo (68k entry points)    src/xfdmaster_68k.c
 *
 * Copyright (C) 1994-1998 Georg Hörmann
 * Copyright (C) 1998 Dirk Stöcker <soft@dstoecker.de>
 * Copyright (C) 2014 Fredrik Wikström <fredrik@a500.org>
 * Copyright (C) 2026 the xfd-native authors
 *
 * This library is free software; you can redistribute it and/or modify it
 * under the terms of the GNU Lesser General Public License as published by
 * the Free Software Foundation; either version 2.1 of the License, or (at
 * your option) any later version.
 * SPDX-License-Identifier: LGPL-2.1-or-later
 */
#include "xfdlib.h"

#include <dirent.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>

#include "amiga.h"
#include "emu.h"
#include "xpkmaster.h"

#define XFDOBJ_BUFFERINFO  1
#define XFDOBJ_SEGMENTINFO 2
#define XFDOBJ_LINKERINFO  3
#define XFDOBJ_SCANNODE    4
#define XFDOBJ_SCANHOOK    5
#define XFDOBJ_MAX         5

static int16_t s16(uint32_t v) { return (int16_t)(uint16_t)v; }

uint32_t xfd_first_slave(void) { return emu_r32(EMU_XFD_BASE + XFDM_FIRSTSLAVE); }

/* ---- objects ------------------------------------------------------------------ */

/* struct sizes from xfdmaster.i, plus the 4-byte object header */
static const uint16_t object_sizes[XFDOBJ_MAX] = {72 + 4, 24 + 4, 52 + 4, 18 + 4, 16 + 4};

static uint32_t alloc_object(uint32_t type)
{
	uint32_t obj;
	if (type == 0 || type > XFDOBJ_MAX) return 0;
	obj = emu_alloc(object_sizes[type - 1], MEMF_PUBLIC | MEMF_CLEAR);
	if (!obj) return 0;
	emu_w16(obj, 0xfd0b);
	emu_w16(obj + 2, type);
	return obj + 4;
}

static void free_object(uint32_t object)
{
	uint32_t obj;
	if (!object) return;
	obj = object - 4;
	if (emu_r16(obj) == 0xfd0b && emu_r16(obj + 2) > 0 && emu_r16(obj + 2) <= XFDOBJ_MAX) {
		emu_free(obj);
	}
}

uint32_t xfd_alloc_bufferinfo(void) { return alloc_object(XFDOBJ_BUFFERINFO); }
uint32_t xfd_alloc_linkerinfo(void) { return alloc_object(XFDOBJ_LINKERINFO); }

/* ---- error texts ------------------------------------------------------------- */

static const struct {
	uint16_t error;
	const char *text;
} error_table[] = {
	{XFDERR_OK, "no errors"},
	{XFDERR_NOMEMORY, "out of memory"},
	{XFDERR_NOSLAVE, "missing slave entry"},
	{XFDERR_NOTSUPPORTED, "not supported"},
	{XFDERR_UNKNOWN, "unknown file"},
	{XFDERR_NOSOURCE, "no source specified"},
	{XFDERR_WRONGPASSWORD, "wrong password"},
	{XFDERR_BADHUNK, "bad hunk structure"},
	{XFDERR_CORRUPTEDDATA, "corrupted data"},
	{XFDERR_MISSINGRESOURCE, "missing resource"},
	{XFDERR_WRONGKEY, "wrong 16/32 bit key"},
	{XFDERR_BETTERCPU, "better cpu required"},
	{XFDERR_HOOKBREAK, "hook caused break"},
	{XFDERR_DOSERROR, "dos error"},
	{XFDERR_NOTARGET, "no user target"},
	{XFDERR_TARGETTOOSMALL, "user target too small"},
	{XFDERR_TARGETNOTSUPPORTED, "user target not supported"},
	{XFDERR_UNDEFINEDHUNK, "undefined hunk type"},
	{XFDERR_NOHUNKHEADER, "file is not executable"},
	{XFDERR_BADEXTTYPE, "bad hunk_ext type"},
	{XFDERR_BUFFERTRUNCATED, "buffer truncated"},
	{XFDERR_WRONGHUNKAMOUNT, "wrong amount of hunks"},
	{XFDERR_NOOVERLAYS, "overlays not allowed"},
	{XFDERR_UNSUPPORTEDHUNK, "unsupported hunk type"},
	{XFDERR_BADRELMODE, "unknown relocation mode"},
	{0xffff, "undefined error"},
};
#define N_ERRORS (sizeof(error_table) / sizeof(error_table[0]))
static uint32_t error_text_addr[N_ERRORS]; /* 68k copies for xfdGetErrorText() */

static size_t error_index(uint32_t error)
{
	size_t i = 0;
	while (error_table[i].error != 0xffff && error_table[i].error != error) i++;
	return i;
}

const char *xfd_error_text(uint32_t error) { return error_table[error_index(error)].text; }

/* ---- hunk structure ------------------------------------------------------------ */

uint32_t xfd_test_hunk_structure_flags(uint32_t buffer, uint32_t length, uint32_t flags)
{
	uint32_t bufstart, bufend;
	int16_t num, hunks;
	int32_t type, size;

	if (buffer == 0 || length == 0) return XFDERR_NOSOURCE;
	if (emu_r32(buffer) != HUNK_HEADER) return XFDERR_NOHUNKHEADER;

	bufstart = buffer;
	bufend = buffer + length;
	num = 0;

	do {
		type = (int32_t)(emu_r32(buffer) & 0x3fffffff);
		buffer += 4;
		switch (type) {
		case HUNK_CODE:
		case HUNK_DATA:
			num -= 1;
			/* fall through */
		case HUNK_NAME:
		case HUNK_DEBUG:
			size = (int32_t)(emu_r32(buffer) << 2);
			buffer += 4;
			buffer += (uint32_t)size;
			break;
		case HUNK_BSS:
			buffer += 4;
			num -= 1;
			/* fall through */
		case HUNK_END:
		case HUNK_BREAK:
			break;
		case HUNK_RELOC32:
		case HUNK_SYMBOL:
			for (;;) {
				if (buffer >= bufend || buffer < bufstart) return XFDERR_BUFFERTRUNCATED;
				size = (int32_t)(emu_r32(buffer) << 2);
				buffer += 4;
				if (size == 0) break;
				buffer += (uint32_t)size + 4;
			}
			break;
		case HUNK_DREL32:
		case HUNK_RELOC32SHORT:
			for (;;) {
				if (buffer >= bufend || buffer < bufstart) return XFDERR_BUFFERTRUNCATED;
				size = (int32_t)(emu_r16(buffer) << 1);
				buffer += 2;
				if (size == 0) break;
				buffer += (uint32_t)size + 2;
			}
			if ((bufend - buffer) & 0x2) buffer += 2;
			break;
		case HUNK_HEADER:
			if (emu_r32(buffer) != 0) return XFDERR_UNSUPPORTEDHUNK;
			buffer += 4;
			hunks = (int16_t)(s16(emu_r16(buffer + 10)) - s16(emu_r16(buffer + 6)) + 1);
			if (hunks <= 0) return XFDERR_BUFFERTRUNCATED;
			num = (int16_t)(num + hunks);
			buffer += 12 + ((uint32_t)hunks << 2);
			break;
		case HUNK_OVERLAY:
			if (flags & XFDTHF_NOOVERLAYS) return XFDERR_NOOVERLAYS;
			size = (int32_t)(emu_r32(buffer) << 2);
			buffer += 4;
			if (size) {
				buffer += (uint32_t)size + 4;
			} else {
				uint32_t v = emu_r32(buffer);
				buffer += 4;
				if (v == 0x3f6) {
					num = 0;
					buffer = bufend;
				}
			}
			break;
		default:
			return XFDERR_UNSUPPORTEDHUNK;
		}
		if (buffer < bufstart || buffer > bufend) return XFDERR_BUFFERTRUNCATED;
	} while (buffer != bufend);

	if (num != 0) return XFDERR_WRONGHUNKAMOUNT;
	return XFDERR_OK;
}

/* GetHunk(): follow the BPTR chain num+1 times, return the hunk's data start */
static uint32_t get_hunk(uint32_t result, int32_t num)
{
	do {
		result = emu_r32(result) << 2;
	} while (num--);
	return result + 4;
}

uint32_t xfd_relocate(uint32_t buffer, uint32_t length, uint32_t result, uint32_t mode)
{
	uint32_t lastseg = result;
	uint32_t error, bufend, seg, hunk, base, size, memtype, seglist;
	int32_t hunks, num, relocs, offs;
	int16_t type;

	emu_w32(result, 0);

	if (buffer == 0 || length == 0) return XFDERR_NOSOURCE;

	error = xfd_test_hunk_structure_flags(buffer, length, XFDTHF_NOOVERLAYS);
	if (error != XFDERR_OK) return error;

	bufend = buffer + length;
	hunks = (int32_t)emu_r32(buffer + 16) - (int32_t)emu_r32(buffer + 12) + 1;
	buffer += 20;

	do {
		size = emu_r32(buffer);
		buffer += 4;
		memtype = MEMF_PUBLIC | MEMF_CLEAR;
		switch (mode) {
		case XFDREL_DEFAULT:
			if (size & HUNKF_CHIP) memtype |= MEMF_CHIP;
			if (size & HUNKF_FAST) memtype |= MEMF_FAST;
			break;
		case XFDREL_FORCECHIP:
			memtype |= MEMF_CHIP;
			break;
		case XFDREL_FORCEFAST:
			memtype |= MEMF_FAST;
			break;
		default:
			error = XFDERR_BADRELMODE;
			goto MemError;
		}

		size = (size + 2) << 2;
		seg = emu_alloc(size, memtype);
		if (seg == 0) {
			error = XFDERR_NOMEMORY;
			goto MemError;
		}

		emu_w32(seg, size);
		seg += 4;
		emu_w32(lastseg, seg >> 2);
		lastseg = seg;
	} while (--hunks);

	num = -1;

	while (buffer != bufend) {
		type = (int16_t)(uint16_t)emu_r32(buffer);
		buffer += 4;
		switch (type) {
		case HUNK_NAME:
		case HUNK_DEBUG:
			size = emu_r32(buffer) << 2;
			buffer += 4 + size;
			break;
		case HUNK_SYMBOL:
			for (;;) {
				size = emu_r32(buffer) << 2;
				buffer += 4;
				if (!size) break;
				buffer += size + 4;
			}
			break;
		case HUNK_CODE:
		case HUNK_DATA:
			hunk = get_hunk(result, ++num);
			size = emu_r32(buffer) << 2;
			buffer += 4;
			if (size) {
				for (uint32_t i = 0; i < size; i++) emu_w8(hunk + i, emu_r8(buffer + i));
				buffer += size;
			}
			break;
		case HUNK_BSS:
			num++;
			buffer += 4;
			break;
		case HUNK_RELOC32:
			hunk = get_hunk(result, num);
			for (;;) {
				relocs = (int32_t)emu_r32(buffer);
				buffer += 4;
				if (!relocs) break;
				base = get_hunk(result, (int32_t)emu_r32(buffer));
				buffer += 4;
				do {
					offs = (int32_t)emu_r32(buffer);
					buffer += 4;
					emu_w32(hunk + (uint32_t)offs, base + emu_r32(hunk + (uint32_t)offs));
				} while (--relocs);
			}
			break;
		case HUNK_DREL32:
		case HUNK_RELOC32SHORT:
			hunk = get_hunk(result, num);
			for (;;) {
				relocs = (int32_t)emu_r16(buffer);
				buffer += 2;
				if (!relocs) break;
				base = get_hunk(result, (int32_t)emu_r16(buffer));
				buffer += 2;
				do {
					offs = (int32_t)emu_r16(buffer);
					buffer += 2;
					emu_w32(hunk + (uint32_t)offs, base + emu_r32(hunk + (uint32_t)offs));
				} while (--relocs);
			}
			if ((bufend - buffer) & 0x2) buffer += 2;
			break;
		case HUNK_END:
			/* Deviation from the OS4 source, which has no HUNK_END case and so
			 * rejects every normal executable (all of them contain HUNK_END).
			 * LoadSeg() and the original 68k library accept it. */
			break;
		default:
			error = XFDERR_UNSUPPORTEDHUNK;
			goto MemError;
		}
	}

	return XFDERR_OK;

MemError:
	seglist = emu_r32(result);
	while ((seg = seglist << 2) != 0) {
		seglist = emu_r32(seg);
		emu_free(seg - 4);
	}
	emu_w32(result, 0);
	return error;
}

/* ---- recognition and decrunching ------------------------------------------------ */

/* An aborted 68k call made from inside another 68k call must abort that one
 * too; at the top level a crashing slave just counts as "no match". */
static int call_slave(uint32_t pc, emu_regs_t *regs, int *aborted)
{
	int rc = emu_call(pc, regs);
	*aborted = rc != EMU_OK;
	if (rc != EMU_OK && emu_trace_enabled()) {
		fprintf(stderr, "[xfd] slave code at $%06x aborted: %s\n", pc, emu_abort_text());
	}
	return rc == EMU_OK;
}

int xfd_recog_buffer(uint32_t bi)
{
	uint32_t src = emu_r32(bi + XFDBI_SOURCEBUFFER);
	uint32_t len = emu_r32(bi + XFDBI_SOURCEBUFLEN);
	uint32_t flags = emu_r16(bi + XFDBI_FLAGS);
	uint32_t slave, rr;

	if (src == 0 || len == 0) {
		emu_w16(bi + XFDBI_ERROR, XFDERR_NOSOURCE);
		return 0;
	}

	rr = emu_alloc(XFDRR_SIZEOF, MEMF_PUBLIC | MEMF_CLEAR);
	if (!rr) {
		emu_w16(bi + XFDBI_ERROR, XFDERR_NOMEMORY);
		return 0;
	}

	for (slave = xfd_first_slave(); slave != 0; slave = emu_r32(slave + XFDS_NEXT)) {
		uint32_t version = emu_r16(slave + XFDS_VERSION);
		uint32_t pflags = emu_r16(slave + XFDS_PACKERFLAGS);
		uint32_t recog = emu_r32(slave + XFDS_RECOGBUFFER);
		emu_regs_t regs = {{0}};
		int aborted;

		if (version > XFDS_VERSION_MAX ||
		    emu_r16(slave + XFDS_MASTERVERSION) > XFDM_VERSION ||
		    recog == 0 ||
		    ((pflags & XFDPFF_EXTERN) && !(flags & XFDFF_RECOGEXTERN)) ||
		    (!(pflags & XFDPFF_USERTARGET) && (flags & XFDFF_RECOGUSERTARGET)) ||
		    (!(pflags & XFDPFF_RECOGLEN) && (flags & XFDFF_RECOGTARGETLEN)) ||
		    (version >= 2 && len < emu_r32(slave + XFDS_MINBUFFERSIZE))) {
			continue;
		}

		emu_w32(rr + XFDRR_MINTARGETLEN, 0);
		emu_w32(rr + XFDRR_FINALTARGETLEN, 0);
		emu_w32(rr + XFDRR_MINSOURCELEN, 0);

		/* Same registers as the original 68k RecogBuffer (xfdmaster.a 39.16)
		 * has at its `jsr (a4)`: some slaves depend on more than A0/D0/A1. */
		regs.r[EMU_D0] = len;
		regs.r[EMU_D0 + 1] = (slave & 0xffff0000u) | pflags;
		regs.r[EMU_A0] = src;
		regs.r[EMU_A0 + 1] = rr;
		regs.r[EMU_A0 + 2] = bi;
		regs.r[EMU_A0 + 3] = slave;
		regs.r[EMU_A0 + 4] = recog;
		regs.r[EMU_A0 + 5] = rr;
		regs.r[EMU_A6] = EMU_XFD_BASE;
		if (!call_slave(recog, &regs, &aborted)) {
			if (emu_depth() > 0) break; /* propagate the abort to our caller */
			continue;
		}
		if (regs.r[EMU_D0]) {
			emu_w32(bi + XFDBI_SLAVE, slave);
			emu_w32(bi + XFDBI_PACKERNAME, emu_r32(slave + XFDS_PACKERNAME));
			emu_w16(bi + XFDBI_PACKERFLAGS, pflags & ~XFDPFF_EXTERN);
			emu_w16(bi + XFDBI_MAXSPECIALLEN, emu_r16(slave + XFDS_MAXSPECIALLEN));
			emu_w32(bi + XFDBI_MINTARGETLEN, emu_r32(rr + XFDRR_MINTARGETLEN));
			emu_w32(bi + XFDBI_FINALTARGETLEN, emu_r32(rr + XFDRR_FINALTARGETLEN));
			emu_w32(bi + XFDBI_MINSOURCELEN, emu_r32(rr + XFDRR_MINSOURCELEN));
			emu_free(rr);
			return 1;
		}
	}

	emu_free(rr);
	emu_w32(bi + XFDBI_SLAVE, 0);
	emu_w32(bi + XFDBI_PACKERNAME, 0);
	emu_w16(bi + XFDBI_PACKERFLAGS, 0);
	emu_w16(bi + XFDBI_ERROR, XFDERR_UNKNOWN);
	return 0;
}

int xfd_decrunch_buffer(uint32_t bi)
{
	uint32_t pflags = emu_r16(bi + XFDBI_PACKERFLAGS);
	uint32_t slave, decrunch, flags;
	emu_regs_t regs = {{0}};
	int aborted;

	if ((pflags & (XFDPFF_DATA | XFDPFF_ADDR)) == 0) {
		uint32_t error = xfd_test_hunk_structure_flags(emu_r32(bi + XFDBI_SOURCEBUFFER),
			emu_r32(bi + XFDBI_SOURCEBUFLEN), 0);
		if (error != XFDERR_OK) {
			emu_w16(bi + XFDBI_ERROR, error);
			return 0;
		}
	}

	if (emu_r32(bi + XFDBI_SOURCEBUFLEN) < emu_r32(bi + XFDBI_MINSOURCELEN)) {
		emu_w16(bi + XFDBI_ERROR, XFDERR_BUFFERTRUNCATED);
		return 0;
	}

	slave = emu_r32(bi + XFDBI_SLAVE);
	if (slave == 0) {
		emu_w16(bi + XFDBI_ERROR, XFDERR_NOSLAVE);
		return 0;
	}

	/* The OS4 source tests XFDPFF_USERTARGET (bit 9) against xfdbi_Flags here;
	 * the documented flag is XFDFF_USERTARGET (bit 3). We use the documented
	 * one. xfd-native never sets either, so both forms behave the same. */
	flags = emu_r16(bi + XFDBI_FLAGS);
	if (flags & XFDFF_USERTARGET) {
		if (!(emu_r16(slave + XFDS_PACKERFLAGS) & XFDPFF_USERTARGET)) {
			emu_w16(bi + XFDBI_ERROR, XFDERR_TARGETNOTSUPPORTED);
			return 0;
		}
		if (emu_r32(bi + XFDBI_USERTARGETBUF) == 0) {
			emu_w16(bi + XFDBI_ERROR, XFDERR_NOTARGET);
			return 0;
		}
		if (emu_r32(bi + XFDBI_USERTARGETBUFLEN) < emu_r32(bi + XFDBI_MINTARGETLEN)) {
			emu_w16(bi + XFDBI_ERROR, XFDERR_TARGETTOOSMALL);
			return 0;
		}
		emu_w32(bi + XFDBI_TARGETBUFFER, emu_r32(bi + XFDBI_USERTARGETBUF));
		emu_w32(bi + XFDBI_TARGETBUFLEN, emu_r32(bi + XFDBI_USERTARGETBUFLEN));
		emu_w32(bi + XFDBI_TARGETBUFSAVELEN, emu_r32(bi + XFDBI_FINALTARGETLEN));
	} else if ((emu_r16(slave + XFDS_PACKERFLAGS) & XFDPFF_USERTARGET) &&
	           emu_r32(bi + XFDBI_MINTARGETLEN) != 0xffffffffu) {
		uint32_t minlen = emu_r32(bi + XFDBI_MINTARGETLEN);
		uint32_t buffer = emu_alloc(minlen, emu_r32(bi + XFDBI_TARGETBUFMEMTYPE));
		if (buffer == 0) {
			emu_w16(bi + XFDBI_ERROR, XFDERR_NOMEMORY);
			goto Error;
		}
		emu_w32(bi + XFDBI_USERTARGETBUF, buffer);
		emu_w32(bi + XFDBI_TARGETBUFFER, buffer);
		emu_w16(bi + XFDBI_FLAGS, flags | XFDFF_USERTARGET | XFDFF_MASTERALLOC);
		emu_w32(bi + XFDBI_USERTARGETBUFLEN, minlen);
		emu_w32(bi + XFDBI_TARGETBUFLEN, minlen);
		emu_w32(bi + XFDBI_TARGETBUFSAVELEN, emu_r32(bi + XFDBI_FINALTARGETLEN));
	}

	decrunch = emu_r32(slave + XFDS_DECRUNCHBUFFER);
	if (decrunch == 0) {
		emu_w16(bi + XFDBI_ERROR, XFDERR_NOTSUPPORTED);
		return 0;
	}

	/* The original 68k DecrunchBuffer does `move.l xfds_DecrunchBuffer(a1),d0;
	 * move.l d0,a1; jsr (a1)`, so D0 and A1 hold the function address. Slaves
	 * rely on that: ProPack's DB_RNC re-runs its recogniser, which passes D0
	 * to xfdGetHunk as the buffer length. With D0 = 0 it fails and the
	 * packed hunks get copied raw. */
	regs.r[EMU_D0] = decrunch;
	regs.r[EMU_A0] = bi;
	regs.r[EMU_A0 + 1] = decrunch;
	regs.r[EMU_A6] = EMU_XFD_BASE;
	if (call_slave(decrunch, &regs, &aborted) && regs.r[EMU_D0]) {
		emu_w16(bi + XFDBI_ERROR, XFDERR_OK);
		return 1;
	}
	if (aborted && emu_r16(bi + XFDBI_ERROR) == XFDERR_OK) {
		emu_w16(bi + XFDBI_ERROR, XFDERR_CORRUPTEDDATA);
	}

Error:
	flags = emu_r16(bi + XFDBI_FLAGS);
	if (flags & XFDFF_MASTERALLOC) {
		emu_free(emu_r32(bi + XFDBI_USERTARGETBUF));
		emu_w16(bi + XFDBI_FLAGS, flags ^ (XFDFF_USERTARGET | XFDFF_MASTERALLOC));
		emu_w32(bi + XFDBI_USERTARGETBUFLEN, 0);
		emu_w32(bi + XFDBI_USERTARGETBUF, 0);
	}
	emu_w32(bi + XFDBI_TARGETBUFFER, 0);
	emu_w32(bi + XFDBI_TARGETBUFLEN, 0);
	emu_w32(bi + XFDBI_TARGETBUFSAVELEN, 0);
	emu_w32(bi + XFDBI_DECRADDRESS, 0);
	emu_w32(bi + XFDBI_JMPADDRESS, 0);
	return 0;
}

/* ---- linkers (unlinking) ----------------------------------------------------------- */

/* Set up by xfd_init() from the blob header: the table of known linkers
 * ("LinkerBrain") and the special FileDescript ("Diz") linker. */
static uint32_t linker_brain, analyse_diz, unlink_diz, name_diz;

/* find_hunk() = xfdGetHunk(): address of the type longword of hunk `num` in a hunk file,
 * or 0. Port of xfdGetHunk() in src/xfdmaster.c (same as the 68k routine
 * in xfdmaster.a 39.16). */
static uint32_t find_hunk(uint32_t buffer, int64_t length, int32_t num)
{
	int32_t hunks;
	int64_t size;
	int16_t type;

	if ((length -= 20) < 0 || emu_r32(buffer) != HUNK_HEADER || emu_r32(buffer + 4) != 0) return 0;
	buffer += 8;
	hunks = s16(emu_r16(buffer + 10)) - s16(emu_r16(buffer + 6)) + 1;
	if (hunks <= num) return 0;
	buffer += 12;

	do {
		uint32_t v;
		if ((length -= 4) < 0) return 0;
		v = emu_r32(buffer);
		buffer += 4;
		if ((v & (3u << 30)) == (3u << 30)) { /* a memory attribute longword follows */
			if (length < 4) return 0;
			length -= 4;
			buffer += 4;
		}
	} while (--hunks > 0);

	for (;;) {
		if ((length -= 4) < 0) return 0;
		type = s16(emu_r32(buffer));
		buffer += 4;
		switch (type) {
		case HUNK_CODE:
		case HUNK_DATA:
			if ((num -= 1) < 0) return buffer - 4;
			/* fall through */
		case HUNK_NAME:
		case HUNK_DEBUG:
			if ((length -= 4) < 0) return 0;
			size = (int64_t)emu_r32(buffer) << 2;
			buffer += 4;
			if ((length -= size) < 0) return 0;
			buffer += (uint32_t)size;
			break;
		case HUNK_BSS:
			if ((num -= 1) < 0) return buffer - 4;
			if ((length -= 4) < 0) return 0;
			buffer += 4;
			break;
		case HUNK_RELOC32:
		case HUNK_SYMBOL:
			for (;;) {
				if ((length -= 4) < 0) return 0;
				size = (int64_t)emu_r32(buffer) << 2;
				buffer += 4;
				if (size == 0) break;
				size += 4;
				if ((length -= size) < 0) return 0;
				buffer += (uint32_t)size;
			}
			break;
		case HUNK_END:
			break;
		default:
			return 0;
		}
	}
}

/* xfdRecogLinker(). Follows the 68k RecogLinker of xfdmaster.a 39.16, which
 * the OS4 C version (src/main/xfdRecogLinker.c) mirrors, including the
 * registers the analyse functions see:
 *   A0 = hunk 0 (its type longword), A1 = just past the matched pattern
 *   (LB_Analyse4EF9 reads the linked hunk numbers at -28(a1) and -16(a1)),
 *   A2 = next table entry, A3 = the analyse function, A5 = linkerinfo,
 *   D2 = $deadbeef (the pattern wildcard). */
int xfd_recog_linker(uint32_t li)
{
	uint32_t buffer = emu_r32(li + XFDLI_BUFFER);
	uint32_t buflen = emu_r32(li + XFDLI_BUFLEN);
	uint32_t hunk, p, a1 = 0, d0, d1 = 0;
	emu_regs_t regs = {{0}};
	int aborted;

	if (buffer == 0 || buflen == 0) {
		emu_w16(li + XFDLI_ERROR, XFDERR_NOSOURCE);
		return 0;
	}

	/* FileDescript ("Diz") text linkers need not be executables. */
	if (analyse_diz) {
		regs.r[EMU_A0] = li;
		regs.r[EMU_A0 + 5] = li;
		regs.r[EMU_A6] = EMU_XFD_BASE;
		if (call_slave(analyse_diz, &regs, &aborted) && regs.r[EMU_D0]) {
			emu_w32(li + XFDLI_LINKERNAME, name_diz);
			emu_w32(li + XFDLI_UNLINK, unlink_diz);
			emu_w16(li + XFDLI_ERROR, XFDERR_OK);
			return 1;
		}
		if (aborted && emu_depth() > 0) return 0;
	}

	hunk = find_hunk(buffer, buflen, 0);
	if (hunk == 0) {
		emu_w16(li + XFDLI_ERROR, XFDERR_NOHUNKHEADER);
		return 0;
	}

	d0 = hunk;
	for (p = linker_brain; p != 0;) {
		int32_t count = s16(emu_r16(p));
		uint32_t analyse;

		p += 2;
		if (count < 0) break;
		d0 = (d0 & 0xffff0000u) | (uint32_t)(uint16_t)count;
		if (count > 0) {
			/* compare count+1 longwords; $deadbeef in the table matches anything */
			int32_t left = count + 1;
			int matched = 1;
			a1 = hunk;
			while (left > 0) {
				uint32_t want = emu_r32(p);
				uint32_t have = emu_r32(a1);
				p += 4;
				a1 += 4;
				left--;
				d1 = (want == 0xdeadbeefu) ? have : want;
				if (d1 != have) {
					matched = 0;
					break;
				}
			}
			if (!matched) { /* skip the rest of the pattern and the 3 pointers */
				p += (uint32_t)left * 4 + 12;
				continue;
			}
			d0 = (d0 & 0xffff0000u) | 0xffffu; /* dbne ran out: D0.w = -1 */
		}

		analyse = emu_r32(p);
		emu_w32(li + XFDLI_UNLINK, emu_r32(p + 4));
		emu_w32(li + XFDLI_LINKERNAME, emu_r32(p + 8));
		p += 12;

		memset(&regs, 0, sizeof(regs));
		regs.r[EMU_D0] = d0;
		regs.r[EMU_D0 + 1] = d1;
		regs.r[EMU_D0 + 2] = 0xdeadbeefu;
		regs.r[EMU_A0] = hunk;
		regs.r[EMU_A0 + 1] = a1;
		regs.r[EMU_A0 + 2] = p;
		regs.r[EMU_A0 + 3] = analyse;
		regs.r[EMU_A0 + 5] = li;
		regs.r[EMU_A6] = EMU_XFD_BASE;
		if (!call_slave(analyse, &regs, &aborted)) {
			if (emu_depth() > 0) return 0;
			d0 = 0;
			continue;
		}
		d0 = regs.r[EMU_D0];
		if (d0 != 0) {
			int32_t amount = 1 + (int32_t)emu_r32(buffer + 16) - (int32_t)emu_r32(buffer + 12) -
			                 (int32_t)emu_r32(li + XFDLI_HUNK2);
			d0 = (uint32_t)amount;
			if (amount > 0) {
				emu_w32(li + XFDLI_AMOUNT2, (uint32_t)amount);
				emu_w16(li + XFDLI_ERROR, XFDERR_OK);
				return 1;
			}
		}
	}

	emu_w32(li + XFDLI_UNLINK, 0);
	emu_w32(li + XFDLI_LINKERNAME, 0);
	emu_w16(li + XFDLI_ERROR, XFDERR_UNKNOWN);
	return 0;
}

/* xfdUnlink(). Follows the 68k Unlink of xfdmaster.a 39.16 / OS4
 * src/main/xfdUnlink.c. The unlink function gets D0 = A1 = its own address,
 * as with the original's `move.l xfdli_Unlink(a0),d0; move.l d0,a1; jsr (a1)`.
 * The two parts are returned in xfdli_Save1/2 and SaveLen1/2. They point
 * into the (rewritten) source buffer. */
int xfd_unlink(uint32_t li)
{
	uint32_t fn;
	emu_regs_t regs = {{0}};
	int aborted;

	if (emu_r32(li + XFDLI_LINKERNAME) != name_diz) {
		uint32_t error = xfd_test_hunk_structure_flags(emu_r32(li + XFDLI_BUFFER),
			emu_r32(li + XFDLI_BUFLEN), XFDTHF_NOOVERLAYS);
		emu_w16(li + XFDLI_ERROR, error);
		if (error != XFDERR_OK) return 0;
	}

	emu_w16(li + XFDLI_ERROR, XFDERR_NOTSUPPORTED);
	fn = emu_r32(li + XFDLI_UNLINK);
	if (fn == 0) return 0;

	regs.r[EMU_D0] = fn;
	regs.r[EMU_A0] = li;
	regs.r[EMU_A0 + 1] = fn;
	regs.r[EMU_A6] = EMU_XFD_BASE;
	if (call_slave(fn, &regs, &aborted) && regs.r[EMU_D0]) {
		emu_w16(li + XFDLI_ERROR, XFDERR_OK);
		return 1;
	}
	if (aborted && emu_r16(li + XFDLI_ERROR) == XFDERR_OK) {
		emu_w16(li + XFDLI_ERROR, XFDERR_CORRUPTEDDATA);
	}
	emu_w32(li + XFDLI_SAVE1, 0);
	emu_w32(li + XFDLI_SAVE2, 0);
	emu_w32(li + XFDLI_SAVELEN1, 0);
	emu_w32(li + XFDLI_SAVELEN2, 0);
	return 0;
}

/* ---- 68k entry points (xfdmaster.library jump table) ---------------------------- */

static int xfd_lvo(int lvo)
{
	uint32_t d0 = emu_get_reg(EMU_D0), d1 = emu_get_reg(EMU_D0 + 1);
	uint32_t a0 = emu_get_reg(EMU_A0), a1 = emu_get_reg(EMU_A0 + 1);
	uint32_t r;

	switch (lvo) {
	case LVO_XFD_ALLOCBUFFERINFO:
		r = emu_alloc(XFDBI_SIZEOF, MEMF_PUBLIC | MEMF_CLEAR);
		break;
	case LVO_XFD_FREEBUFFERINFO:
		emu_free(a1);
		return 1;
	case LVO_XFD_RECOGBUFFER:
		r = (uint32_t)xfd_recog_buffer(a0);
		break;
	case LVO_XFD_DECRUNCHBUFFER:
		r = (uint32_t)xfd_decrunch_buffer(a0);
		break;
	case LVO_XFD_GETERRORTEXT:
		r = error_text_addr[error_index(d0)];
		break;
	case LVO_XFD_TESTHUNKSTRUCTURE:
		r = xfd_test_hunk_structure_flags(a0, d0, 0) == XFDERR_OK;
		break;
	case LVO_XFD_TESTHUNKSTRUCTURENEW:
		r = xfd_test_hunk_structure_flags(a0, d0, 0);
		break;
	case LVO_XFD_RELOCATE:
		r = xfd_relocate(a0, d0, a1, d1);
		break;
	case LVO_XFD_TESTHUNKSTRUCTUREFLAGS:
		r = xfd_test_hunk_structure_flags(a0, d0, d1);
		break;
	case LVO_XFD_ALLOCOBJECT:
		r = alloc_object(d0);
		break;
	case LVO_XFD_FREEOBJECT:
		free_object(a1);
		return 1;
	case LVO_XFD_RECOGLINKER:
		r = (uint32_t)xfd_recog_linker(a0);
		break;
	case LVO_XFD_UNLINK:
		r = (uint32_t)xfd_unlink(a0);
		break;
	default:
		return 0; /* segment and scan functions are not provided */
	}
	emu_set_reg(EMU_D0, r);
	return 1;
}

/* ---- slave list -------------------------------------------------------------------- */

static void append_slaves(uint32_t first)
{
	uint32_t last = xfd_first_slave();
	if (last == 0) {
		emu_w32(EMU_XFD_BASE + XFDM_FIRSTSLAVE, first);
		return;
	}
	while (emu_r32(last + XFDS_NEXT) != 0) last = emu_r32(last + XFDS_NEXT);
	emu_w32(last + XFDS_NEXT, first);
}

int xfd_init(const uint8_t *blob, size_t len)
{
	uint32_t base = EMU_BLOB, first, slave;
	int count = 0;

	if (len < 24 || len > EMU_HEAP_LOW - EMU_BLOB) return -1;
	emu_write_block(EMU_BLOB, blob, len);
	if (emu_r32(base) != XFDF_ID) return -1;

	/* The blob stores pointers as offsets from its start (SetupInternal). */
	first = emu_r32(base + 4);
	if (first) first += base;
	for (slave = first; slave != 0; slave = emu_r32(slave + XFDS_NEXT)) {
		static const uint32_t ptr_fields[] = {XFDS_NEXT, XFDS_PACKERNAME, XFDS_RECOGBUFFER,
			XFDS_DECRUNCHBUFFER, XFDS_RECOGSEGMENT, XFDS_DECRUNCHSEGMENT};
		for (size_t i = 0; i < sizeof(ptr_fields) / sizeof(ptr_fields[0]); i++) {
			uint32_t v = emu_r32(slave + ptr_fields[i]);
			if (v) emu_w32(slave + ptr_fields[i], v + base);
		}
		count++;
	}
	emu_w32(EMU_XFD_BASE + XFDM_FIRSTSLAVE, first);

	/* Linker table: entries are a pattern length word (n: n+1 longwords, 0:
	 * none, -1: end), the pattern, then analyse/unlink/name offsets
	 * (SetupInternal's LinkerBrain loop). */
	linker_brain = emu_r32(base + 8);
	if (linker_brain) {
		uint32_t p;
		int32_t longs;
		linker_brain += base;
		p = linker_brain;
		while ((longs = s16(emu_r16(p))) >= 0) {
			p += 2;
			if (longs > 0) p += (uint32_t)(longs + 1) * 4;
			for (int i = 0; i < 3; i++, p += 4) {
				uint32_t v = emu_r32(p);
				if (v) emu_w32(p, v + base);
			}
		}
	}
	analyse_diz = emu_r32(base + 12) ? emu_r32(base + 12) + base : 0;
	unlink_diz = emu_r32(base + 16) ? emu_r32(base + 16) + base : 0;
	name_diz = emu_r32(base + 20) ? emu_r32(base + 20) + base : 0;

	for (size_t i = 0; i < N_ERRORS; i++) error_text_addr[i] = emu_static_string(error_table[i].text);
	emu_set_xfd_handler(xfd_lvo);
	emu_set_xpk_handler(xpk_lvo);
	return count;
}

int xfd_load_external(const char *path)
{
	FILE *f = fopen(path, "rb");
	uint8_t *data;
	long size;
	int count;

	if (!f) return 0;
	fseek(f, 0, SEEK_END);
	size = ftell(f);
	fseek(f, 0, SEEK_SET);
	if (size < 32 || size > 4 * 1024 * 1024) {
		fclose(f);
		return 0;
	}
	data = malloc((size_t)size);
	if (!data || fread(data, 1, (size_t)size, f) != (size_t)size) {
		free(data);
		fclose(f);
		return 0;
	}
	fclose(f);
	count = xfd_load_external_mem(data, (size_t)size);
	free(data);
	return count;
}

int xfd_load_external_mem(const uint8_t *data, size_t size)
{
	uint32_t buf, result, seglist, foreman, slave, error;
	int count = 0;

	if (size < 32 || size > 4 * 1024 * 1024) return 0;
	buf = emu_alloc((uint32_t)size, MEMF_PUBLIC);
	result = emu_alloc(4, MEMF_PUBLIC | MEMF_CLEAR);
	if (!buf || !result) {
		emu_free(buf);
		emu_free(result);
		return 0;
	}
	emu_write_block(buf, data, size);

	/* LoadSeg() equivalent */
	error = xfd_relocate(buf, (uint32_t)size, result, XFDREL_DEFAULT);
	seglist = emu_r32(result);
	emu_free(buf);
	emu_free(result);
	if (error != XFDERR_OK || seglist == 0) return 0;

	foreman = (seglist << 2) + 4; /* first hunk's data */
	if (emu_r32(foreman + XFDF_ID_OFS) != XFDF_ID) {
		while (seglist) { /* UnLoadSeg() */
			uint32_t seg = seglist << 2;
			seglist = emu_r32(seg);
			emu_free(seg - 4);
		}
		return 0;
	}

	emu_w32(foreman + XFDF_SEGLIST, seglist);
	emu_w32(foreman + XFDF_NEXT, 0);
	{
		uint32_t last = emu_r32(EMU_XFD_BASE + XFDM_FIRSTFOREMAN);
		if (last == 0) {
			emu_w32(EMU_XFD_BASE + XFDM_FIRSTFOREMAN, foreman);
		} else {
			while (emu_r32(last + XFDF_NEXT) != 0) last = emu_r32(last + XFDF_NEXT);
			emu_w32(last + XFDF_NEXT, foreman);
		}
	}

	slave = emu_r32(foreman + XFDF_FIRSTSLAVE);
	if (slave == 0) return 0;
	append_slaves(slave);

	for (; slave != 0; slave = emu_r32(slave + XFDS_NEXT)) {
		uint32_t replace;
		emu_w16(slave + XFDS_PACKERFLAGS, emu_r16(slave + XFDS_PACKERFLAGS) | XFDPFF_EXTERN);
		count++;

		replace = emu_r16(slave + XFDS_REPLACEID);
		if (emu_r16(slave + XFDS_VERSION) >= 2 && replace != 0) {
			/* Drop any slave this one replaces (an updated internal one). */
			uint32_t prev = 0, cur = xfd_first_slave();
			while (cur != 0) {
				uint32_t next = emu_r32(cur + XFDS_NEXT);
				if (cur != slave && emu_r16(cur + XFDS_VERSION) >= 2 &&
				    emu_r16(cur + XFDS_SLAVEID) == replace) {
					if (prev == 0) emu_w32(EMU_XFD_BASE + XFDM_FIRSTSLAVE, next);
					else emu_w32(prev + XFDS_NEXT, next);
				} else {
					prev = cur;
				}
				cur = next;
			}
		}
	}
	return count;
}

static int ci_compare(const void *a, const void *b)
{
	const unsigned char *x = *(const unsigned char *const *)a;
	const unsigned char *y = *(const unsigned char *const *)b;
	for (;; x++, y++) {
		int cx = (*x >= 'A' && *x <= 'Z') ? *x + 32 : *x;
		int cy = (*y >= 'A' && *y <= 'Z') ? *y + 32 : *y;
		if (cx != cy || cx == 0) return cx - cy;
	}
}

int xfd_load_external_dir(const char *dir)
{
	DIR *d = opendir(dir);
	struct dirent *e;
	char **names = NULL;
	size_t n = 0, cap = 0;
	int total = 0;

	if (!d) return -1;
	while ((e = readdir(d)) != NULL) {
		if (e->d_name[0] == '.') continue;
		if (n == cap) {
			cap = cap ? cap * 2 : 64;
			names = realloc(names, cap * sizeof(char *));
			if (!names) break;
		}
		names[n++] = strdup(e->d_name);
	}
	closedir(d);
	if (!names) return 0;

	qsort(names, n, sizeof(char *), ci_compare);
	for (size_t i = 0; i < n; i++) {
		char path[4096];
		struct stat st;
		int added = 0;
		snprintf(path, sizeof(path), "%s/%s", dir, names[i]);
		if (stat(path, &st) == 0 && S_ISREG(st.st_mode)) added = xfd_load_external(path);
		if (emu_trace_enabled()) fprintf(stderr, "[xfd] external %s: %d slave(s)\n", names[i], added);
		total += added;
		free(names[i]);
	}
	free(names);
	return total;
}
