;
; XPK.asm - xfdmaster's own XPK slaves ("XPK Packed", "XPK Crypted") as an
; external slave file.
;
; The source is vendor/xfdmaster/m68k/slaves/XPK.s, included unchanged. In
; xfdmaster.library these are internal slaves; the OS4 port that
; xfd-native's internal slave set comes from left them out of its 68k code
; (they call xpkmaster.library). This file adds the xfdForeman header around
; them. xfd-native provides xpkmaster.library's XpkUnpack() itself; on an
; Amiga the file is not needed, as xfdmaster.library has the same slaves.
;
; Copyright (C) 2026 the xfd-native authors
; SPDX-License-Identifier: LGPL-2.1-or-later
;

	include	exec/types.i
	include	libraries/xfdmaster.i
	include	lvo/exec_lib.i

ForeMan	dc.l	$70FF4E75,XFDF_ID
	dc.w	XFDF_VERSION
	dcb.w	5,0
	dc.l	S_XPKpacked
	dc.b	"$VER: XPK 1.0 (21.11.2026) xfd-native",0
	even

XFD_LASTSLAVE	SET	1		; "XPK Crypted" ends the list
	include	"XPK.s"
