; Minimal stand-in for the Amiga NDK's exec/libraries.i, written for xfd-native.
; struct Library is 34 bytes: a 14-byte Node, then flags, pad, neg/pos size,
; version, revision, id string, checksum and open count.
; Part of demoscene.au xfd-native; LGPL-2.1-or-later (see ../../THIRD_PARTY.md).

	IFND	EXEC_LIBRARIES_I
EXEC_LIBRARIES_I	SET	1

	INCLUDE	"exec/types.i"

LN_SIZE		EQU	14
LIB_VERSION	EQU	20
LIB_SIZE	EQU	34

	ENDC
