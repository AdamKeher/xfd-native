; sample.asm - test program for the packer tests (tests/data)
; Four hunks (code, data, chip data, bss) with relocations between them.
; vasmm68k_mot -Fhunkexe -kick1hunks -nosym -o sample sample.asm
;
; SPDX-License-Identifier: LGPL-2.1-or-later

	section	code,code
start	lea	text(pc),a0
	move.l	#table,a1
	move.l	#buffer,a2
	move.l	#image,a3
	moveq	#15,d0
.loop	move.l	(a1)+,(a2)+
	dbf	d0,.loop
	moveq	#0,d0
	rts
text	rept	8
	dc.b	"xfd-native packer test: Shrinkler, Cranker and L-Packer. "
	endr
	even

	section	tables,data
table	dc.l	start,text,buffer,image,table
	rept	32
	dc.w	1,2,3,5,8,13,21,34,55,89,144,233
	endr
	dc.l	buffer+16,image+64

	section	gfx,data_c
image	rept	16
	dc.l	$ffff0000,$f0f0f0f0,$cccccccc,$aaaaaaaa
	endr

	section	work,bss
buffer	ds.b	2048
