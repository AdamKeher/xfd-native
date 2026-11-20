; Minimal stand-in for the Amiga NDK's dos/dos.i, written for xfd-native.
; Part of demoscene.au xfd-native; LGPL-2.1-or-later (see ../../THIRD_PARTY.md).

	IFND	DOS_DOS_I
DOS_DOS_I	SET	1

	INCLUDE	"exec/types.i"

DOSTRUE		EQU	-1
DOSFALSE	EQU	0

MODE_OLDFILE	EQU	1005
MODE_NEWFILE	EQU	1006
MODE_READWRITE	EQU	1004

OFFSET_BEGINNING EQU	-1
OFFSET_CURRENT	EQU	0
OFFSET_END	EQU	1

	ENDC
