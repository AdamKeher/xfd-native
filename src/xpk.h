/*
 * xfd-native: XPK decoding for the emulated xpkmaster.library (xpkmaster.c),
 * done by Teemu Suutari's ancient library (vendor/ancient, BSD-2-Clause).
 *
 * Copyright (C) 2026 the xfd-native authors.
 * SPDX-License-Identifier: LGPL-2.1-or-later
 */
#ifndef XFDN_XPK_H
#define XFDN_XPK_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/* xpkmaster.library error codes (xpk/xpk.h) */
#define XPKERR_OK          0
#define XPKERR_NOFUNC     -1
#define XPKERR_NOFILES    -2
#define XPKERR_CHECKSUM   -5
#define XPKERR_NOMEM      -7
#define XPKERR_SMALLBUF  -10
#define XPKERR_CORRUPTPKD -14
#define XPKERR_MISSINGLIB -15
#define XPKERR_BADPARAMS  -16
#define XPKERR_NOMETHOD   -18
#define XPKERR_TRUNCATED  -20
#define XPKERR_NOTPACKED  -23

/* Decode the XPKF file in in[0..inlen). On success returns XPKERR_OK and a
 * malloc()ed buffer in *out (free() it) holding *outlen bytes; otherwise an
 * XPKERR_ code. name, if not NULL, receives the sub-packer's description
 * (e.g. "XPK-SQSH: ..."), truncated to namelen. */
int xfdn_xpk_unpack(const uint8_t *in, size_t inlen, uint8_t **out, size_t *outlen,
	char *name, size_t namelen);

#ifdef __cplusplus
}
#endif

#endif
