/*
 * xfd-native: XPK decoding through ancient's public API. Only XPKF files are
 * passed in (the XPK slave checks the ID), and the result is checked
 * against ancient's own verification: header and chunk checksums, and the
 * copy of the first 16 decoded bytes kept in the XPKF header.
 *
 * Copyright (C) 2026 the xfd-native authors.
 * SPDX-License-Identifier: LGPL-2.1-or-later
 */
#include "xpk.h"

#include <ancient/ancient.hpp>

#include <cstdlib>
#include <cstring>
#include <new>
#include <string>

static void copy_name(char *name, size_t namelen, const std::string &s)
{
	if (!name || !namelen) return;
	size_t n = s.size() < namelen - 1 ? s.size() : namelen - 1;
	std::memcpy(name, s.data(), n);
	name[n] = '\0';
}

extern "C" int xfdn_xpk_unpack(const uint8_t *in, size_t inlen, uint8_t **out, size_t *outlen,
	char *name, size_t namelen)
{
	*out = nullptr;
	*outlen = 0;
	copy_name(name, namelen, std::string());
	if (inlen < 4 || std::memcmp(in, "XPKF", 4) != 0) return XPKERR_NOTPACKED;
	if (inlen < 44) return XPKERR_TRUNCATED;
	uint32_t packed = (uint32_t)in[4] << 24 | (uint32_t)in[5] << 16 | (uint32_t)in[6] << 8 | in[7];
	if ((uint64_t)packed + 8 > inlen) return XPKERR_TRUNCATED;
	try {
		ancient::Decompressor d(in, inlen, false, true);
		copy_name(name, namelen, d.getName());
		if (d.getName().find("(unimplemented)") != std::string::npos) return XPKERR_MISSINGLIB;
		if (in[32] & 2) return XPKERR_NOMETHOD; /* encrypted: no passwords here */
		std::vector<uint8_t> raw = d.decompress(true);
		uint8_t *buf = static_cast<uint8_t *>(std::malloc(raw.size() ? raw.size() : 1));
		if (!buf) return XPKERR_NOMEM;
		if (!raw.empty()) std::memcpy(buf, raw.data(), raw.size());
		*out = buf;
		*outlen = raw.size();
		return XPKERR_OK;
	} catch (const ancient::VerificationError &) {
		return XPKERR_CHECKSUM;
	} catch (const ancient::Error &) {
		return XPKERR_CORRUPTPKD;
	} catch (const std::bad_alloc &) {
		return XPKERR_NOMEM;
	} catch (...) {
		return XPKERR_CORRUPTPKD;
	}
}
