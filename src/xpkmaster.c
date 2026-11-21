/*
 * xfd-native: the part of xpkmaster.library that xfdmaster's XPK slave uses,
 * XpkUnpack() on memory buffers. The decoding itself is ancient's (xpk.cpp).
 *
 * Copyright (C) 2026 the xfd-native authors.
 * SPDX-License-Identifier: LGPL-2.1-or-later
 */
#include "xpkmaster.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "emu.h"
#include "xpk.h"

/* utility/tagitem.h */
#define TAG_DONE   0u
#define TAG_IGNORE 1u
#define TAG_MORE   2u
#define TAG_SKIP   3u
#define TAG_USER   0x80000000u

/* xpk/xpk.h */
#define XTAG(a) (TAG_USER + ('X' << 8) + 'P' + (a))
#define XPK_InName       XTAG(0x01)
#define XPK_InFH         XTAG(0x02)
#define XPK_InBuf        XTAG(0x03)
#define XPK_InHook       XTAG(0x04)
#define XPK_OutName      XTAG(0x10)
#define XPK_OutFH        XTAG(0x11)
#define XPK_OutBuf       XTAG(0x12)
#define XPK_GetOutBuf    XTAG(0x13)
#define XPK_OutHook      XTAG(0x14)
#define XPK_InLen        XTAG(0x20)
#define XPK_OutBufLen    XTAG(0x21)
#define XPK_GetOutLen    XTAG(0x22)
#define XPK_GetOutBufLen XTAG(0x23)
#define XPK_GetError     XTAG(0x25)
#define XPK_OutMemType   XTAG(0x26)
#define XPK_MARGIN       256u
#define XPKERRMSGSIZE    80u

/* xpkmaster_lib.fd: ##bias 36 */
#define LVO_XPKUNPACK -48

static const char *error_text(int e)
{
	switch (e) {
	case XPKERR_NOFILES: return "No files allowed for this function";
	case XPKERR_CHECKSUM: return "Checksum error";
	case XPKERR_NOMEM: return "Out of memory";
	case XPKERR_SMALLBUF: return "Output buffer too small";
	case XPKERR_CORRUPTPKD: return "Packed file is corrupt";
	case XPKERR_MISSINGLIB: return "Required library is missing";
	case XPKERR_BADPARAMS: return "Caller's TagList was screwed up";
	case XPKERR_NOMETHOD: return "Cannot find requested method";
	case XPKERR_TRUNCATED: return "Input file is truncated";
	case XPKERR_NOTPACKED: return "Data not packed";
	}
	return "Unknown error";
}

static int unpack(uint32_t tags)
{
	uint32_t inbuf = 0, inlen = 0, outbuf = 0, outbuflen = 0;
	uint32_t getoutbuf = 0, getoutlen = 0, getoutbuflen = 0, geterror = 0, memtype = 0;
	int have_inlen = 0, have_outbuflen = 0, files = 0, n = 0;
	uint8_t *in = NULL, *out = NULL;
	size_t outlen = 0;
	char name[128];
	int rc;

	while (tags) {
		uint32_t tag = emu_r32(tags), data = emu_r32(tags + 4);
		if (++n > 10000) return XPKERR_BADPARAMS; /* looping tag list */
		switch (tag) {
		case TAG_DONE: tags = 0; continue;
		case TAG_MORE: tags = data; continue;
		case TAG_SKIP: tags += 8 * data; break;
		case XPK_InBuf: inbuf = data; break;
		case XPK_InLen: inlen = data; have_inlen = 1; break;
		case XPK_OutBuf: outbuf = data; break;
		case XPK_OutBufLen: outbuflen = data; have_outbuflen = 1; break;
		case XPK_GetOutBuf: getoutbuf = data; break;
		case XPK_GetOutLen: getoutlen = data; break;
		case XPK_GetOutBufLen: getoutbuflen = data; break;
		case XPK_GetError: geterror = data; break;
		case XPK_OutMemType: memtype = data; break;
		case XPK_InName: case XPK_InFH: case XPK_InHook:
		case XPK_OutName: case XPK_OutFH: case XPK_OutHook:
			files = 1;
			break;
		default: break; /* TAG_IGNORE, passwords and options */
		}
		tags += 8;
	}

	if (files) {
		rc = XPKERR_NOFILES;
	} else if (!inbuf || !have_inlen || (!getoutbuf && (!outbuf || !have_outbuflen))) {
		rc = XPKERR_BADPARAMS;
	} else if (!(in = malloc(inlen ? inlen : 1))) {
		rc = XPKERR_NOMEM;
	} else {
		emu_read_block(in, inbuf, inlen);
		rc = xfdn_xpk_unpack(in, inlen, &out, &outlen, name, sizeof name);
		if (emu_trace_enabled())
			fprintf(stderr, "[xpk] XpkUnpack(%u bytes) = %d, %lu bytes, %s\n", (unsigned)inlen, rc,
				(unsigned long)outlen, name[0] ? name : "?");
		if (rc == XPKERR_OK && outlen > 0xffffffu) rc = XPKERR_NOMEM;
		if (rc == XPKERR_OK) {
			if (getoutbuf) {
				uint32_t len = (uint32_t)outlen + XPK_MARGIN;
				uint32_t a = emu_alloc(len, memtype);
				if (!a) {
					rc = XPKERR_NOMEM;
				} else {
					emu_write_block(a, out, outlen);
					emu_w32(getoutbuf, a);
					if (getoutbuflen) emu_w32(getoutbuflen, len);
				}
			} else if (outlen > outbuflen) {
				rc = XPKERR_SMALLBUF;
			} else {
				emu_write_block(outbuf, out, outlen);
				if (getoutbuflen) emu_w32(getoutbuflen, outbuflen);
			}
		}
		if (rc == XPKERR_OK && getoutlen) emu_w32(getoutlen, (uint32_t)outlen);
	}
	if (rc != XPKERR_OK && geterror) {
		const char *t = error_text(rc);
		size_t len = strlen(t);
		if (len > XPKERRMSGSIZE - 1) len = XPKERRMSGSIZE - 1;
		emu_write_block(geterror, t, len);
		emu_w8(geterror + (uint32_t)len, 0);
	}
	free(in);
	free(out);
	return rc;
}

int xpk_lvo(int lvo)
{
	switch (lvo) {
	case LVO_XPKUNPACK:
		emu_set_reg(EMU_D0, (uint32_t)unpack(emu_get_reg(EMU_A0)));
		return 1;
	}
	return 0;
}
