;
; lz4zx0.i - LZ4 block and ZX0 decoders with bounds checks
;
; Both take:  a0 = input, d0.l = input length, a1 = output,
;             d1.l = output size limit
; and return: d0.l = bytes decoded, or -1 (N set) for corrupt data.
;
; ZX0_Decode follows unzx0_68000.S by Emmanuel Marty (the decoder L-Packer's
; own depacker is built from) bit for bit, including the flag and Elias data
; bits it reads without a refill check. It is an altered version: it adds
; bounds checks and takes 32-bit lengths where the original uses dbf. The
; original's notice:
;
;   unzx0_68000.s - ZX0 decompressor for 68000 - 88 bytes
;   Copyright (C) 2021 Emmanuel Marty
;   ZX0 compression (c) 2021 Einar Saukas, https://github.com/einar-saukas/ZX0
;
;   This software is provided 'as-is', without any express or implied
;   warranty.  In no event will the authors be held liable for any damages
;   arising from the use of this software.
;
;   Permission is granted to anyone to use this software for any purpose,
;   including commercial applications, and to alter it and redistribute it
;   freely, subject to the following restrictions:
;
;   1. The origin of this software must not be misrepresented; you must not
;      claim that you wrote the original software. If you use this software
;      in a product, an acknowledgment in the product documentation would be
;      appreciated but is not required.
;   2. Altered source versions must be plainly marked as such, and must not
;      be misrepresented as being the original software.
;   3. This notice may not be removed or altered from any source
;      distribution.
;
; Copyright (C) 2026 the xfd-native authors (LZ4_Decode, and the changes to
; ZX0_Decode)
; SPDX-License-Identifier: LGPL-2.1-or-later
;

;------------------------------------------------------------------------------
; LZ4 block format: token (literal length << 4 | match length - 4), extra
; length bytes while 255, literals, 16-bit little-endian offset, extra match
; length bytes. The last sequence has literals only.
LZ4_Decode
	movem.l	d1-d3/a0-a5,-(sp)
	lea	(a0,d0.l),a2		; a2 = input end
	move.l	a1,a3			; a3 = output start
	lea	(a1,d1.l),a4		; a4 = output end
.seq	cmp.l	a2,a0
	bcc	.bad
	moveq	#0,d2
	move.b	(a0)+,d2		; token
	move.l	d2,d3
	lsr.w	#4,d3			; literal length
	cmp.w	#15,d3
	bne.s	.lits
.lext	cmp.l	a2,a0
	bcc	.bad
	moveq	#0,d0
	move.b	(a0)+,d0
	add.l	d0,d3
	cmp.b	#255,d0
	beq.s	.lext
.lits	move.l	a2,d0
	sub.l	a0,d0
	cmp.l	d3,d0
	bcs.s	.bad
	move.l	a4,d0
	sub.l	a1,d0
	cmp.l	d3,d0
	bcs.s	.bad
	tst.l	d3
	beq.s	.nolit
.lc	move.b	(a0)+,(a1)+
	subq.l	#1,d3
	bne.s	.lc
.nolit	cmp.l	a2,a0
	beq.s	.done			; the last sequence
	move.l	a2,d0
	sub.l	a0,d0
	cmp.l	#2,d0
	bcs.s	.bad
	moveq	#0,d3
	move.b	(a0)+,d3
	moveq	#0,d0
	move.b	(a0)+,d0
	lsl.w	#8,d0
	or.w	d0,d3			; offset
	beq.s	.bad
	move.l	a1,d0
	sub.l	a3,d0
	cmp.l	d3,d0
	bcs.s	.bad			; before the start
	and.w	#15,d2
	cmp.w	#15,d2
	bne.s	.mlen
.mext	cmp.l	a2,a0
	bcc.s	.bad
	moveq	#0,d0
	move.b	(a0)+,d0
	add.l	d0,d2
	cmp.b	#255,d0
	beq.s	.mext
.mlen	addq.l	#4,d2
	move.l	a4,d0
	sub.l	a1,d0
	cmp.l	d2,d0
	bcs.s	.bad
	move.l	a1,a5
	sub.l	d3,a5
.mc	move.b	(a5)+,(a1)+
	subq.l	#1,d2
	bne.s	.mc
	bra	.seq
.done	move.l	a1,d0
	sub.l	a3,d0
	bra.s	.exit
.bad	moveq	#-1,d0
.exit	movem.l	(sp)+,d1-d3/a0-a5
	tst.l	d0
	rts

;------------------------------------------------------------------------------
; ZX0 (version 2 format, as written by salvador with FLG_IS_INVERTED)
ZX0_Decode
	movem.l	d1-d3/a0-a6,-(sp)
	move.l	sp,a6			; for error exits from subroutines
	lea	(a0,d0.l),a5		; a5 = input end
	move.l	a1,a3			; a3 = output start
	lea	(a1,d1.l),a4		; a4 = output end
	moveq	#-128,d1		; empty bit queue
	moveq	#-1,d2			; last offset = 1
.literals
	bsr.s	.elias			; number of literals
	move.l	a5,d3
	sub.l	a0,d3
	cmp.l	d0,d3
	bcs.s	.bad
	move.l	a4,d3
	sub.l	a1,d3
	cmp.l	d0,d3
	bcs.s	.bad
.cl	move.b	(a0)+,(a1)+
	subq.l	#1,d0
	bne.s	.cl
	add.b	d1,d1			; 1: new offset, 0: repeat offset
	bcs.s	.offset
	bsr.s	.elias			; length
.copy	move.l	a4,d3
	sub.l	a1,d3
	cmp.l	d0,d3
	bcs.s	.bad
	move.l	a1,a2
	add.l	d2,a2
	cmp.l	a3,a2
	bcs.s	.bad			; before the start
.cm	move.b	(a2)+,(a1)+
	subq.l	#1,d0
	bne.s	.cm
	add.b	d1,d1			; 0: literals, 1: new offset
	bcc.s	.literals
.offset	moveq	#-2,d0
	bsr.s	.eloop			; offset high byte
	addq.b	#1,d0
	beq.s	.done			; end marker
	move.w	d0,d2
	lsl.w	#8,d2
	moveq	#1,d0
	cmp.l	a5,a0
	bcc.s	.bad
	move.b	(a0)+,d2		; offset low byte and one length bit
	asr.l	#1,d2
	bcs.s	.len2
	bsr.s	.ebt			; rest of the length
.len2	addq.l	#1,d0
	bra.s	.copy
.done	move.l	a1,d0
	sub.l	a3,d0
	bra.s	.exit
.bad	move.l	a6,sp
	moveq	#-1,d0
.exit	movem.l	(sp)+,d1-d3/a0-a6
	tst.l	d0
	rts

; interlaced Elias gamma number -> d0
.elias	moveq	#1,d0
.eloop	add.b	d1,d1
	bne.s	.got
	cmp.l	a5,a0
	bcc.s	.bad
	move.b	(a0)+,d1
	addx.b	d1,d1
.got	bcs.s	.edone
.ebt	add.b	d1,d1
	addx.l	d0,d0
	bra.s	.eloop
.edone	rts
