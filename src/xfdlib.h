/*
 * xfd-native: the parts of xfdmaster.library needed for buffer decrunching,
 * ported to run natively on structures held in emulated 68k memory.
 *
 * Copyright (C) 1994-1998 Georg Hörmann
 * Copyright (C) 1998 Dirk Stöcker
 * Copyright (C) 2014 Fredrik Wikström (OS4 C port these functions derive from)
 * Copyright (C) 2026 the xfd-native authors
 * SPDX-License-Identifier: LGPL-2.1-or-later
 */
#ifndef XFDN_XFDLIB_H
#define XFDN_XFDLIB_H

#include <stddef.h>
#include <stdint.h>

/* Load the internal 68k slave blob and register the xfdmaster LVO handler.
 * Returns the number of internal slaves, or -1 on error. */
int xfd_init(const uint8_t *blob, size_t len);

/* Load one external slave file (a 68k hunk executable with an xfdForeMan).
 * Returns the number of slaves it added (0 if the file is not a slave). */
int xfd_load_external(const char *path);
/* Load every external slave in a directory, in case-insensitive name order
 * (the order AmigaDOS returns them from a WinUAE directory drive).
 * Returns the number of slaves added, or -1 if the directory can't be read. */
int xfd_load_external_dir(const char *dir);

uint32_t xfd_first_slave(void);

/* xfdmaster.library API, operating on 68k addresses. */
uint32_t xfd_alloc_bufferinfo(void);
int xfd_recog_buffer(uint32_t bufferinfo);
int xfd_decrunch_buffer(uint32_t bufferinfo);
uint32_t xfd_test_hunk_structure_flags(uint32_t buffer, uint32_t length, uint32_t flags);
uint32_t xfd_relocate(uint32_t buffer, uint32_t length, uint32_t result, uint32_t mode);
const char *xfd_error_text(uint32_t error);

#endif
