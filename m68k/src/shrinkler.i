;
; shrinkler.i - Shrinkler range decoder for the xfd slave
;
; A port of the decoder in Shrinkler's decrunch headers and
; ShrinklerDecompress.S (Copyright 1999-2022 Aske Simon Christensen; "free to
; use, in whole or in part, modified or as is, for any legal purpose"). The
; bit and number coding, the context layout and the probability update are
; unchanged. Added for the slave:
;   - the decoder state lives in a structure, so one stream can be decoded
;     a hunk at a time with the slave's own code in between;
;   - output, lookbehind and input bounds are checked;
;   - a number with more than 32 bits stops the decoder (corrupt data
;     would otherwise loop forever on the unary prefix).
; The input is a forward byte stream. The slave turns the backward longword
; streams of the executable headers into this form first.
;
; Copyright (C) 2026 the xfd-native authors
; SPDX-License-Identifier: LGPL-2.1-or-later
;

SD_NUMCTX	= 1536			; LZ contexts + reloc contexts

; decoder state
sd_In		= 0			; next input byte
sd_InEnd	= 4			; reading here or beyond is an error
sd_Range	= 8			; D2: range value
sd_Size		= 12			; D3: interval size
sd_Bits		= 16			; D4: input bit buffer
sd_Flags	= 20			; D7: bit 0 parity context, bit 31 error
sd_Ctx		= 24			; SD_NUMCTX+1 words of probabilities
SD_SIZEOF	= 28

; register use while decoding:
;   a0 input, a1 output, a2 context 0, a3 output start, a4 output end,
;   a5 input end, a6/d1 scratch, d2/d3/d4 coder, d5 match offset,
;   d6 context, d7 flags, d0 result

;------------------------------------------------------------------------------
; SD_Init: a0 = state, a1 = stream, d0.l = readable length, d1.l = 1 for the
; parity context (executables, default data), 0 without (--bytes data),
; a2 = context buffer of (SD_NUMCTX+1) words. Contexts are not reset.
SD_Init
	move.l	a1,sd_In(a0)
	add.l	a1,d0
	move.l	d0,sd_InEnd(a0)
	clr.l	sd_Range(a0)
	moveq	#1,d0
	move.l	d0,sd_Size(a0)
	moveq	#-$80,d0
	move.l	d0,sd_Bits(a0)
	and.l	#1,d1
	move.l	d1,sd_Flags(a0)
	move.l	a2,sd_Ctx(a0)
	rts

; SD_ResetCtx: a0 = state. Set every probability to one half.
SD_ResetCtx
	movem.l	d0/a1,-(sp)
	move.l	sd_Ctx(a0),a1
	move.w	#SD_NUMCTX,d0
.init	move.w	#$8000,(a1)+
	dbf	d0,.init
	movem.l	(sp)+,d0/a1
	rts

;------------------------------------------------------------------------------
; SD_LZ: decode one LZ block (up to its end marker).
;   a0 = state, a1 = output, d0.l = output size limit
; Out: d0.l = bytes decoded, or -1 (N set) for corrupt data.
SD_LZ
	movem.l	d1-d7/a0-a6,-(sp)
	move.l	a0,-(sp)
	move.l	a1,a3
	lea	(a1,d0.l),a4
	bsr	SD_Load
	moveq	#0,d5			; no previous offset yet
	moveq	#0,d6
.lit	addq.b	#1,d6
.getlit	bsr	SD_GetBit
	addx.b	d6,d6
	bcc.s	.getlit
	cmp.l	a4,a1
	bcc	.bad			; output overrun
	move.b	d6,(a1)+
	tst.l	d7
	bmi	.bad
	bsr	SD_GetKind
	bcc.s	.lit
	moveq	#-1,d6
	bsr	SD_GetBit
	bcc.s	.offset
.length	moveq	#4,d6
	bsr	SD_GetNumber
	move.l	a4,d1
	sub.l	a1,d1
	cmp.l	d0,d1
	bcs	.bad			; output overrun
	move.l	a1,d1
	sub.l	a3,d1
	add.l	d5,d1
	bmi	.bad			; lookbehind overrun
	lea	(a1,d5.l),a6
.copy	move.b	(a6)+,(a1)+
	subq.l	#1,d0
	bne.s	.copy
	tst.l	d7
	bmi	.bad
	bsr	SD_GetKind
	bcc.s	.lit
.offset	moveq	#3,d6
	bsr	SD_GetNumber
	moveq	#2,d5
	sub.l	d0,d5
	bne.s	.length
	tst.l	d7			; end marker
	bmi.s	.bad
	move.l	a1,d0
	sub.l	a3,d0
	bra.s	.save
.bad	moveq	#-1,d0
.save	move.l	(sp)+,a6
	bsr	SD_Store
	movem.l	(sp)+,d1-d7/a0-a6
	tst.l	d0
	rts

;------------------------------------------------------------------------------
; SD_Relocs: decode the relocations of one hunk: for each target hunk, the
; distances between relocated longwords (the first from offset -4), ended
; by a 2.
;   a0 = state, a1 = output (HUNK_RELOC32 groups), d0.l = hunk data length,
;   d1.l = number of target hunks, d2.l = output buffer size
; Out: d0.l = bytes written, or -1 (N set) for corrupt data;
;      d1.l = end of the highest relocated longword (0 if none)
SD_Relocs
	movem.l	d2-d7/a0-a6,-(sp)
	link	a3,#-28
	move.l	a0,-4(a3)		; state
	move.l	a1,-8(a3)		; output start
	move.l	d0,-12(a3)		; data length
	move.l	d1,-16(a3)		; target hunks left
	clr.l	-20(a3)			; current target hunk
	clr.l	-24(a3)			; highest reloc end
	add.l	a1,d2
	move.l	d2,-28(a3)		; output end
	bsr	SD_Load
	tst.l	-16(a3)
	beq.s	.done
.target	move.l	a1,a4			; group: count, target, offsets
	move.l	a1,d1
	addq.l	#8,d1
	cmp.l	-28(a3),d1
	bhi.s	.bad
	clr.l	(a1)+
	move.l	-20(a3),(a1)+
	moveq	#-4,d5			; offset
.entry	moveq	#5,d6
	bsr	SD_GetNumber
	tst.l	d7
	bmi.s	.bad
	cmp.l	#4,d0
	bcs.s	.endtgt
	cmp.l	-12(a3),d0
	bhi.s	.bad			; distance beyond the hunk
	add.l	d0,d5			; (from -4: no overflow possible)
	move.l	d5,d1
	addq.l	#4,d1
	cmp.l	-12(a3),d1
	bhi.s	.bad			; outside the hunk
	cmp.l	-24(a3),d1
	bls.s	.nomax
	move.l	d1,-24(a3)
.nomax	move.l	a1,d1
	addq.l	#4,d1
	cmp.l	-28(a3),d1
	bhi.s	.bad
	move.l	d5,(a1)+
	addq.l	#1,(a4)
	bra.s	.entry
.endtgt	tst.l	(a4)
	bne.s	.keep
	move.l	a4,a1			; no relocs to this hunk: drop the group
.keep	addq.l	#1,-20(a3)
	subq.l	#1,-16(a3)
	bne.s	.target
.done	move.l	a1,d0
	sub.l	-8(a3),d0
	move.l	-24(a3),d1
	bra.s	.save
.bad	moveq	#-1,d0
.save	move.l	-4(a3),a6
	bsr	SD_Store
	unlk	a3
	movem.l	(sp)+,d2-d7/a0-a6
	tst.l	d0
	rts

;------------------------------------------------------------------------------
; load the coder registers from the state at a0 (a0 becomes the input)
SD_Load	move.l	sd_Ctx(a0),a2
	addq.l	#2,a2			; context -1 is the first word
	move.l	sd_InEnd(a0),a5
	move.l	sd_Range(a0),d2
	move.l	sd_Size(a0),d3
	move.l	sd_Bits(a0),d4
	move.l	sd_Flags(a0),d7
	move.l	sd_In(a0),a0
	rts

; store the coder registers into the state at a6
SD_Store
	move.l	a0,sd_In(a6)
	move.l	d2,sd_Range(a6)
	move.l	d3,sd_Size(a6)
	move.l	d4,sd_Bits(a6)
	move.l	d7,sd_Flags(a6)
	rts

; context for the literal/reference decision: parity of the output position
SD_GetKind
	move.l	a1,d6
	sub.l	a3,d6
	and.l	d7,d6
	and.l	#1,d6
	lsl.w	#8,d6
	bra.s	SD_GetBit

; d6 = number context (3, 4 or 5). Out: d0 = number (>= 2).
SD_GetNumber
	lsl.w	#8,d6
.unary	addq.b	#2,d6
	cmp.b	#62,d6
	bhi.s	.big			; more than 32 bits: corrupt
	bsr.s	SD_GetBit
	bcs.s	.unary
	moveq	#1,d0
	subq.b	#1,d6
.bits	bsr.s	SD_GetBit
	addx.l	d0,d0
	subq.b	#2,d6
	bcc.s	.bits
	rts
.big	bset	#31,d7
	moveq	#2,d0
	rts

; d6.l = bit context. Out: bit in C and X. Uses d1 and a6.
SD_GetBit
.read	tst.w	d3
	bmi.s	.decode
	add.b	d4,d4
	bne.s	.have
	cmp.l	a5,a0
	bcc.s	.past
	move.b	(a0)+,d4
	bra.s	.fill
.past	bset	#31,d7			; input overrun: feed zeros, flag it
	moveq	#0,d4
.fill	addx.b	d4,d4
.have	addx.w	d2,d2
	add.w	d3,d3
	bra.s	.read
.decode	move.l	d6,d1
	add.l	d1,d1
	lea	(a2,d1.l),a6
	move.w	(a6),d1
	lsr.w	#4,d1
	sub.w	d1,(a6)
	add.w	(a6),d1
	mulu.w	d3,d1
	swap	d1
	sub.w	d1,d2
	bcs.s	.one
	sub.w	d1,d3			; 0 in C and X
	rts
.one	add.w	#$0fff,(a6)
	move.w	d1,d3
	add.w	d1,d2			; 1 in C and X
	rts
