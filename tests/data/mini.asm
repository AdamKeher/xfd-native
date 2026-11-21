; mini.asm - test program for Shrinkler's mini mode (tests/data):
; one code hunk without relocations, and a bss hunk.
; vasmm68k_mot -Fhunkexe -kick1hunks -nosym -o mini mini.asm
;
; SPDX-License-Identifier: LGPL-2.1-or-later

	section	code,code
start	lea	text(pc),a0
	moveq	#0,d0
.len	tst.b	(a0)+
	beq.s	.done
	addq.l	#1,d0
	bra.s	.len
.done	rts
text	rept	6
	dc.b	"Shrinkler mini mode test for xfd-native. "
	endr
	dc.b	0
	even

	section	work,bss
	ds.b	512
