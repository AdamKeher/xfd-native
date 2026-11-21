;
; inflate.i - DEFLATE (RFC 1951) decoder with bounds checks
;
; Follows the structure of puff.c by Mark Adler: canonical Huffman codes
; decoded a bit at a time from per-length counts. Small and slow, but every
; input read, output write and back reference is checked, and the decoded
; length is returned (L-Packer keeps its relocation table at the end of the
; decoded data).
;
;   a0 = raw DEFLATE stream, d0.l = its length, a1 = output,
;   d1.l = output size limit, a2 = workspace of IF_WSIZE bytes
; Out: d0.l = bytes decoded, or -1 (N set) for corrupt data.
;
; Copyright (C) 2026 the xfd-native authors
; SPDX-License-Identifier: LGPL-2.1-or-later
;

; workspace layout (words)
IF_LENGTHS	= 0			; 320 code lengths
IF_LEN		= 640			; literal/length code: count[16], symbol[288]
IF_DIST		= IF_LEN+32+576		; distance code: count[16], symbol[30]
IF_OFFS		= IF_DIST+32+60		; offs[16] for IF_Construct
IF_WSIZE	= IF_OFFS+32

; registers while decoding:
;   a0 input, a1 input end, a2 output, a3 output start, a4 output end,
;   a5 workspace, a6 stack for error exits, d6 bit buffer, d7 bit count

INF_Inflate
	movem.l	d1-d7/a0-a6,-(sp)
	move.l	sp,a6
	move.l	a2,a5
	move.l	a1,a2
	move.l	a1,a3
	lea	(a1,d1.l),a4
	lea	(a0,d0.l),a1
	moveq	#0,d6
	moveq	#0,d7

.block	moveq	#1,d0			; last block?
	bsr	IF_Bits
	move.w	d0,-(sp)
	moveq	#2,d0			; block type
	bsr	IF_Bits
	tst.w	d0
	beq.s	.stored
	cmp.w	#1,d0
	beq	.fixed
	cmp.w	#2,d0
	beq	.dynamic
	bra	IF_Error
.next	tst.w	(sp)+
	beq.s	.block
	move.l	a2,d0
	sub.l	a3,d0
	bra	IF_Exit

	; stored: byte aligned LEN, NLEN, data
.stored	moveq	#0,d6
	moveq	#0,d7
	move.l	a1,d0
	sub.l	a0,d0
	cmp.l	#4,d0
	bcs	IF_Error
	moveq	#0,d2
	move.b	1(a0),d2
	lsl.w	#8,d2
	move.b	(a0),d2
	moveq	#0,d1
	move.b	3(a0),d1
	lsl.w	#8,d1
	move.b	2(a0),d1
	not.w	d1
	cmp.w	d1,d2
	bne	IF_Error
	addq.l	#4,a0
	move.l	a1,d0
	sub.l	a0,d0
	cmp.l	d2,d0
	bcs	IF_Error
	move.l	a4,d0
	sub.l	a2,d0
	cmp.l	d2,d0
	bcs	IF_Error
	tst.w	d2
	beq.s	.next
.sc	move.b	(a0)+,(a2)+
	subq.w	#1,d2
	bne.s	.sc
	bra.s	.next

	; fixed Huffman codes
.fixed	moveq	#0,d2
.fx	moveq	#8,d0
	cmp.w	#144*2,d2
	bcs.s	.fset
	moveq	#9,d0
	cmp.w	#256*2,d2
	bcs.s	.fset
	moveq	#7,d0
	cmp.w	#280*2,d2
	bcs.s	.fset
	moveq	#8,d0
.fset	move.w	d0,(a5,d2.w)
	addq.w	#2,d2
	cmp.w	#318*2,d2
	bcc.s	.fdone
	cmp.w	#288*2,d2
	bcs.s	.fx
.fd	move.w	#5,(a5,d2.w)		; 30 distance codes of 5 bits
	addq.w	#2,d2
	cmp.w	#318*2,d2
	bcs.s	.fd
.fdone	move.w	#IF_LEN,d0
	moveq	#0,d1
	move.w	#288,d2
	bsr	IF_Construct
	move.w	#IF_DIST,d0
	move.w	#288,d1
	moveq	#30,d2
	bsr	IF_Construct
	bra	.codes

	; dynamic Huffman codes
.dynamic
	moveq	#5,d0
	bsr	IF_Bits
	add.w	#257,d0
	move.w	d0,d3			; d3 = literal/length codes
	moveq	#5,d0
	bsr	IF_Bits
	addq.w	#1,d0
	move.w	d0,d4			; d4 = distance codes
	moveq	#4,d0
	bsr	IF_Bits
	addq.w	#4,d0
	move.w	d0,d5			; d5 = code length codes
	cmp.w	#286,d3
	bhi	IF_Error
	cmp.w	#30,d4
	bhi	IF_Error
	bsr	IF_ReadCL
	move.w	#IF_LEN,d0
	moveq	#0,d1
	moveq	#19,d2
	bsr	IF_Construct
	bne	IF_Error		; must be complete
	moveq	#0,d2			; d2 = byte index into the lengths
	move.w	d3,d5
	add.w	d4,d5
	add.w	d5,d5			; d5 = end of the lengths (bytes)
.lens	cmp.w	d5,d2
	bcc.s	.lensd
	move.w	#IF_LEN,d0
	bsr	IF_Decode
	cmp.w	#16,d0
	bcc.s	.rep
	move.w	d0,(a5,d2.w)
	addq.w	#2,d2
	bra.s	.lens
.rep	moveq	#0,d1
	cmp.w	#16,d0
	bne.s	.zero
	tst.w	d2			; 16: repeat the previous length
	beq	IF_Error
	move.w	-2(a5,d2.w),d1
	move.w	d1,-(sp)
	moveq	#2,d0
	bsr	IF_Bits
	addq.w	#3,d0
	bra.s	.fill
.zero	move.w	d1,-(sp)
	cmp.w	#17,d0
	bne.s	.z18
	moveq	#3,d0			; 17: 3-10 zeros
	bsr	IF_Bits
	addq.w	#3,d0
	bra.s	.fill
.z18	moveq	#7,d0			; 18: 11-138 zeros
	bsr	IF_Bits
	add.w	#11,d0
.fill	move.w	(sp)+,d1
.fl	cmp.w	d5,d2
	bcc	IF_Error		; more lengths than codes
	move.w	d1,(a5,d2.w)
	addq.w	#2,d2
	subq.w	#1,d0
	bne.s	.fl
	bra.s	.lens
.lensd	tst.w	256*2(a5)		; there must be an end-of-block code
	beq	IF_Error
	move.w	#IF_LEN,d0
	moveq	#0,d1
	move.w	d3,d2
	bsr	IF_Construct
	bmi	IF_Error
	beq.s	.lok
	move.w	d3,d0			; incomplete: only a single code is ok
	sub.w	IF_LEN(a5),d0
	cmp.w	#1,d0
	bne	IF_Error
.lok	move.w	#IF_DIST,d0
	move.w	d3,d1
	move.w	d4,d2
	bsr	IF_Construct
	bmi	IF_Error
	beq.s	.codes
	move.w	d4,d0
	sub.w	IF_DIST(a5),d0
	cmp.w	#1,d0
	bne	IF_Error

	; decode literals and length/distance pairs up to end-of-block
.codes	move.w	#IF_LEN,d0
	bsr	IF_Decode
	cmp.w	#256,d0
	bcs.s	.lit
	beq	.next
	sub.w	#257,d0
	cmp.w	#29,d0
	bcc	IF_Error
	bsr	IF_Length
	move.l	d0,d2			; d2 = length
	move.w	#IF_DIST,d0
	bsr	IF_Decode
	cmp.w	#30,d0
	bcc	IF_Error
	bsr	IF_Distance		; d0 = distance
	move.l	a2,d1
	sub.l	a3,d1
	cmp.l	d0,d1
	bcs	IF_Error		; before the start
	move.l	a4,d1
	sub.l	a2,d1
	cmp.l	d2,d1
	bcs	IF_Error		; output overrun
	move.l	a1,-(sp)
	move.l	a2,a1
	sub.l	d0,a1
.cp	move.b	(a1)+,(a2)+
	subq.l	#1,d2
	bne.s	.cp
	move.l	(sp)+,a1
	bra.s	.codes
.lit	cmp.l	a4,a2
	bcc	IF_Error
	move.b	d0,(a2)+
	bra.s	.codes

IF_Error
	move.l	a6,sp
	moveq	#-1,d0
IF_Exit	movem.l	(sp)+,d1-d7/a0-a6
	tst.l	d0
	rts

;------------------------------------------------------------------------------
; IF_Bits: d0 = number of bits (0-13) -> d0 = value (LSB first). Uses d1.
IF_Bits
.fill	cmp.w	d0,d7
	bcc.s	.have
	cmp.l	a1,a0
	bcc	IF_Error		; input overrun
	moveq	#0,d1
	move.b	(a0)+,d1
	lsl.l	d7,d1
	or.l	d1,d6
	addq.w	#8,d7
	bra.s	.fill
.have	moveq	#1,d1
	lsl.l	d0,d1
	subq.l	#1,d1
	and.l	d6,d1
	lsr.l	d0,d6
	sub.w	d0,d7
	move.l	d1,d0
	rts

; IF_Decode: d0 = code (IF_LEN or IF_DIST) -> d0 = symbol. Uses d1.
IF_Decode
	movem.l	d2-d5/a3,-(sp)
	lea	(a5,d0.w),a3		; count[0..15], then symbols
	moveq	#0,d2			; code
	moveq	#0,d3			; first code of this length
	moveq	#0,d4			; index of that code's symbol
	moveq	#2,d5			; length * 2
.len	moveq	#1,d0
	bsr.s	IF_Bits
	or.w	d0,d2
	move.w	(a3,d5.w),d1		; count[length]
	move.w	d2,d0
	sub.w	d3,d0
	cmp.w	d1,d0
	bcs.s	.found
	add.w	d1,d4
	add.w	d1,d3
	add.w	d3,d3
	add.w	d2,d2
	addq.w	#2,d5
	cmp.w	#32,d5
	bcs.s	.len
	bra	IF_Error		; ran out of codes
.found	add.w	d4,d0
	add.w	d0,d0
	move.w	32(a3,d0.w),d0
	movem.l	(sp)+,d2-d5/a3
	rts

; IF_Construct: build a code from lengths.
;   d0 = code (IF_LEN/IF_DIST), d1 = first length index, d2 = number
; Out: d0 = 0 complete, > 0 incomplete, < 0 over-subscribed (flags set)
IF_Construct
	movem.l	d1-d5/a2-a4,-(sp)
	lea	(a5,d0.w),a3		; count, symbols
	add.w	d1,d1
	lea	(a5,d1.w),a2		; lengths
	lea	IF_OFFS(a5),a4		; offsets
	moveq	#0,d3
.clr	clr.w	(a3,d3.w)
	addq.w	#2,d3
	cmp.w	#32,d3
	bcs.s	.clr
	moveq	#0,d3
.cnt	cmp.w	d2,d3
	bcc.s	.cntd
	move.w	d3,d4
	add.w	d4,d4
	move.w	(a2,d4.w),d4
	cmp.w	#15,d4
	bhi	IF_Error
	add.w	d4,d4
	addq.w	#1,(a3,d4.w)
	addq.w	#1,d3
	bra.s	.cnt
.cntd	moveq	#0,d0
	cmp.w	(a3),d2			; no codes at all: complete
	beq.s	.out
	moveq	#1,d0			; left = 1
	moveq	#2,d3
.left	add.l	d0,d0
	moveq	#0,d1
	move.w	(a3,d3.w),d1
	sub.l	d1,d0
	bmi.s	.out			; over-subscribed
	addq.w	#2,d3
	cmp.w	#32,d3
	bcs.s	.left
	clr.w	2(a4)			; offs[1] = 0
	moveq	#2,d3
.offs	move.w	(a4,d3.w),d1
	add.w	(a3,d3.w),d1
	move.w	d1,2(a4,d3.w)
	addq.w	#2,d3
	cmp.w	#30,d3
	bcs.s	.offs
	moveq	#0,d3
.sym	cmp.w	d2,d3
	bcc.s	.out
	move.w	d3,d4
	add.w	d4,d4
	move.w	(a2,d4.w),d4
	beq.s	.nos
	add.w	d4,d4
	move.w	(a4,d4.w),d1
	addq.w	#1,(a4,d4.w)
	add.w	d1,d1
	move.w	d3,32(a3,d1.w)
.nos	addq.w	#1,d3
	bra.s	.sym
.out	movem.l	(sp)+,d1-d5/a2-a4
	tst.l	d0
	rts

; IF_ReadCL: d5 = number of code length codes; read their 3-bit lengths
; in the RFC's order into lengths[0..18].
IF_Order
	dc.b	16,17,18,0,8,7,9,6,10,5,11,4,12,3,13,2,14,1,15
	even
IF_ReadCL
	moveq	#0,d2
.clr	clr.w	(a5,d2.w)
	addq.w	#2,d2
	cmp.w	#38,d2
	bcs.s	.clr
	moveq	#0,d2
.rd	cmp.w	d5,d2
	bcc.s	.done
	moveq	#3,d0
	bsr	IF_Bits
	moveq	#0,d1
	move.b	IF_Order(pc,d2.w),d1
	add.w	d1,d1
	move.w	d0,(a5,d1.w)
	addq.w	#1,d2
	bra.s	.rd
.done	rts

; IF_Length: d0 = length symbol - 257 -> d0.l = length
IF_LBase
	dc.w	3,4,5,6,7,8,9,10,11,13,15,17,19,23,27,31
	dc.w	35,43,51,59,67,83,99,115,131,163,195,227,258
IF_LExt
	dc.b	0,0,0,0,0,0,0,0,1,1,1,1,2,2,2,2
	dc.b	3,3,3,3,4,4,4,4,5,5,5,5,0
	even
IF_Length
	move.w	d0,-(sp)
	moveq	#0,d1
	move.b	IF_LExt(pc,d0.w),d1
	move.l	d1,d0
	bsr	IF_Bits
	move.w	(sp)+,d1
	add.w	d1,d1
	add.w	IF_LBase(pc,d1.w),d0
	rts

; IF_Distance: d0 = distance symbol -> d0.l = distance
IF_DBase
	dc.w	1,2,3,4,5,7,9,13,17,25,33,49,65,97,129,193
	dc.w	257,385,513,769,1025,1537,2049,3073,4097,6145
	dc.w	8193,12289,16385,24577
IF_DExt
	dc.b	0,0,0,0,1,1,2,2,3,3,4,4,5,5,6,6
	dc.b	7,7,8,8,9,9,10,10,11,11,12,12,13,13
IF_Distance
	move.w	d0,-(sp)
	moveq	#0,d1
	move.b	IF_DExt(pc,d0.w),d1
	move.l	d1,d0
	bsr	IF_Bits
	move.w	(sp)+,d1
	add.w	d1,d1
	add.w	IF_DBase(pc,d1.w),d0
	rts
