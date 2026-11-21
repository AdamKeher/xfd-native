;
; lzo.i - LZO1X decoder with the checks of lzo1x_decompress_safe()
;
; LZO_Decode checks for input overrun, output overrun and lookbehind overrun,
; and requires the end marker to be the last bytes of the input. Without an
; output buffer it only walks the stream and returns the decoded length.
;
; Lengths are 32 bits. Cranker's own 68k decrunchers count in 16 bits, so a
; literal run or match longer than 64 KB (which "cranker -1" can produce for
; poorly compressible data) comes out wrong on an Amiga. This decoder gives
; the correct result, like lzo1x_decompress_safe() and Cranker's C unpacker.
;
;   a0 = stream, d0.l = stream length, d1.l = maximum decoded length,
;   a1 = output buffer, or 0 to only check the stream
; Out: d0.l = decoded length, or -1 (N set) if the stream is broken.
;
; Copyright (C) 2026 the xfd-native authors
; SPDX-License-Identifier: LGPL-2.1-or-later
;

LZO_Decode
	movem.l	d1-d6/a0-a5,-(sp)
	move.l	sp,a2			; for error exits from subroutines
	move.l	a1,a3			; a3 = output (0: check only)
	lea	(a0,d0.l),a1		; a1 = input end
	moveq	#0,d2			; d2 = output position
	move.l	d1,d3			; d3 = output limit
	moveq	#0,d4			; d4 = t

	bsr	.getb
	cmp.w	#17,d4
	bhi.s	.first
	subq.l	#1,a0			; not a literal start: read it again
	bra.s	.loop
.first	sub.w	#17,d4
	cmp.w	#4,d4
	bcs	.mnext
	bsr	.lits
	bra.s	.firstrun

.loop	bsr	.getb
	cmp.w	#16,d4
	bcc.s	.match
	tst.w	d4
	bne.s	.lit3
	moveq	#15,d0
	bsr	.ext
.lit3	addq.l	#3,d4
	bsr	.lits
.firstrun
	bsr	.getb
	cmp.w	#16,d4
	bcc.s	.match
	move.l	d4,d6			; state = t & 3
	move.l	d4,d5
	lsr.l	#2,d5
	add.l	#$801,d5		; 1 + M2_MAX_OFFSET
	bsr	.getb2
	lsl.l	#2,d0
	add.l	d0,d5
	moveq	#3,d0
	bra	.copy

.match	cmp.w	#64,d4
	bcs.s	.m3
	move.l	d4,d6			; M2
	move.l	d4,d5
	lsr.l	#2,d5
	and.l	#7,d5
	addq.l	#1,d5
	bsr	.getb2
	lsl.l	#3,d0
	add.l	d0,d5
	move.l	d4,d0
	lsr.l	#5,d0
	addq.l	#1,d0			; (t >> 5) - 1 + 2
	bra.s	.copy

.m3	cmp.w	#32,d4
	bcs.s	.m4
	and.l	#31,d4			; M3
	bne.s	.m3len
	moveq	#31,d0
	bsr	.ext
.m3len	bsr	.offs
	addq.l	#1,d5
	bra.s	.mlen

.m4	cmp.w	#16,d4
	bcs.s	.m1
	moveq	#8,d1			; M4
	and.l	d4,d1
	moveq	#11,d0
	lsl.l	d0,d1			; (t & 8) << 11
	and.l	#7,d4
	bne.s	.m4len
	moveq	#7,d0
	bsr	.ext
.m4len	bsr	.offs
	add.l	d1,d5
	beq.s	.eof
	add.l	#$4000,d5
.mlen	move.l	d4,d0
	addq.l	#2,d0
	bra.s	.copy

.m1	move.l	d4,d6			; M1 after a match
	move.l	d4,d5
	lsr.l	#2,d5
	addq.l	#1,d5
	bsr	.getb2
	lsl.l	#2,d0
	add.l	d0,d5
	moveq	#2,d0

	; copy d0 bytes from distance d5
.copy	cmp.l	d2,d5
	bhi	.bad			; lookbehind overrun
	move.l	d2,d1
	add.l	d0,d1
	cmp.l	d3,d1
	bhi	.bad			; output overrun
	move.l	a3,d1
	beq.s	.nocopy
	lea	(a3,d2.l),a4
	move.l	a4,a5
	sub.l	d5,a5
	move.l	d0,d1
.cm	move.b	(a5)+,(a4)+
	subq.l	#1,d1
	bne.s	.cm
.nocopy	add.l	d0,d2
	and.l	#3,d6
	beq	.loop
	move.l	d6,d4
.mnext	bsr.s	.lits			; 1..3 literals
	bsr.s	.getb
	bra	.match

.eof	cmp.l	a1,a0
	bne.s	.bad
	move.l	d2,d0
	bra.s	.exit
.bad	move.l	a2,sp
	moveq	#-1,d0
.exit	movem.l	(sp)+,d1-d6/a0-a5
	tst.l	d0
	rts

; d4 = next byte
.getb	cmp.l	a1,a0
	bcc.s	.bad
	moveq	#0,d4
	move.b	(a0)+,d4
	rts
; d0 = next byte
.getb2	cmp.l	a1,a0
	bcc.s	.bad
	moveq	#0,d0
	move.b	(a0)+,d0
	rts
; d4 literals
.lits	move.l	a1,d0
	sub.l	a0,d0
	cmp.l	d4,d0
	bcs.s	.bad			; input overrun
	move.l	d2,d0
	add.l	d4,d0
	cmp.l	d3,d0
	bhi.s	.bad			; output overrun
	move.l	a3,d0
	bne.s	.lcopy
	add.l	d4,a0
	add.l	d4,d2
	rts
.lcopy	lea	(a3,d2.l),a4
	add.l	d4,d2
	move.l	d4,d0
.lc	move.b	(a0)+,(a4)+
	subq.l	#1,d0
	bne.s	.lc
	rts
; extended length: each zero byte adds 255, then d4 = d0 + next byte
.ext	move.l	d0,d4
.extl	bsr.s	.getb2
	tst.b	d0
	bne.s	.extd
	add.l	#255,d4
	bra.s	.extl
.extd	add.l	d0,d4
	rts
; two offset bytes: d5 = (b0 >> 2) + (b1 << 6), d6 = b0
.offs	bsr.s	.getb2
	move.l	d0,d6
	move.l	d0,d5
	lsr.l	#2,d5
	bsr.s	.getb2
	lsl.l	#6,d0
	add.l	d0,d5
	rts
