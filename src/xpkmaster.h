/*
 * xfd-native: emulated xpkmaster.library (XpkUnpack on memory buffers).
 *
 * Copyright (C) 2026 the xfd-native authors.
 * SPDX-License-Identifier: LGPL-2.1-or-later
 */
#ifndef XFDN_XPKMASTER_H
#define XFDN_XPKMASTER_H

/* Handler for xpkmaster.library LVOs (see emu_set_xpk_handler). */
int xpk_lvo(int lvo);

#endif
