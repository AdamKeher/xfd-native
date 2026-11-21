;
; Cranker.asm - xfd external slave for Cranker by bifat/TEK (Timm S. Mueller)
;
; Cranker executables are AmigaDOS overlay files whose first hunk is the
; "decranker" loader. The original hunks are written as one-longword BSS
; hunks, and the overlay part holds each code/data hunk (LZO1X-compressed or
; stored) with its relocations packed into 1, 2 or 4 byte deltas. The slave
; rebuilds a normal executable. Hunk sizes come from the hunk header, so a
; crunched hunk keeps the few bytes of in-place decrunch overhead Cranker
; added to it. Hunk types are not stored: hunks with data become CODE.
;
; Cranker data files: $b0 (or the overhead, with -eo) and the 24-bit
; decrunched length, followed by an LZO1X stream.
;
; xfdmaster tests the hunk structure of every relocatable file before it
; calls the slave, and an overlay file does not pass that test. Both slaves
; are therefore flagged as data packers.
;
; LZO_Decode (lzo.i) does the LZO1X decoding with full bounds checks. It is
; used instead of Cranker's 68k decruncher, which counts lengths in 16 bits
; and so mis-decodes the runs over 64 KB that "cranker -1" can produce.
;
; Copyright (C) 2026 the xfd-native authors
; SPDX-License-Identifier: LGPL-2.1-or-later
;

	include	exec/types.i
	include	exec/memory.i
	include	dos/doshunks.i
	include	libraries/xfdmaster.i
	include	lvo/exec_lib.i

ForeMan	dc.l	$70FF4E75,XFDF_ID
	dc.w	XFDF_VERSION
	dcb.w	5,0
	dc.l	S_CrankerExe

S_CrankerExe
	dc.l	S_CrankerData
	dc.w	2,39
	dc.l	N_CrankerExe
	dc.w	XFDPFF_DATA,0
	dc.l	RB_CrankerExe,DB_CrankerExe,0,0
	dc.w	0,0
	dc.l	64

S_CrankerData
	dc.l	0
	dc.w	2,39
	dc.l	N_CrankerData
	dc.w	XFDPFF_DATA,0
	dc.l	RB_CrankerData,DB_CrankerData,0,0
	dc.w	0,0
	dc.l	8

N_CrankerExe	dc.b	"Cranker",0
N_CrankerData	dc.b	"Cranker Data",0
	dc.b	"$VER: Cranker 1.0 (21.11.2026) xfd-native",0
	even

; private hunk descriptor fields
hd_Src		= hd_P0			; hunk data in the source buffer
hd_Crunched	= hd_P1			; 1: LZO stream, 0: stored
hd_RelSrc	= hd_P2			; reloc bytes in the source buffer
hd_InStream	= hd_P3			; 1: the overlay part has this hunk
hd_SrcLen	= hd_P4			; length of the hunk data in the source

; CR_Header results
cr_Sizes	= 0			; hunk header sizes of the original hunks
cr_Hunks	= 4			; number of original hunks
cr_Stream	= 8			; first hunk entry in the overlay part
cr_StreamEnd	= 12			; end of the crunched data
CR_SIZEOF	= 16

;------------------------------------------------------------------------------
; CR_Header: check the file layout up to the overlay part.
;   a0 = buffer, d0.l = length, a1 = CR_SIZEOF result area
; Out: d0 = 1 if this looks like a Cranker executable, else 0.
CR_Header
	movem.l	d1-d5/a0-a3,-(sp)
	lea	(a0,d0.l),a3		; a3 = end of file
	cmp.l	#64,d0
	bcs	.fail
	cmp.l	#HUNK_HEADER,(a0)+
	bne	.fail
	tst.l	(a0)+			; no resident library names
	bne	.fail
	move.l	(a0)+,d1		; number of hunks, decranker included
	cmp.l	#2,d1
	bcs	.fail
	cmp.l	#$4000,d1
	bcc	.fail
	tst.l	(a0)+
	bne	.fail
	move.l	(a0)+,d2
	addq.l	#1,d2
	cmp.l	d1,d2
	bne	.fail
	move.l	d1,d2
	lsl.l	#2,d2
	lea	16(a0,d2.l),a2
	cmp.l	a3,a2
	bcc	.fail
	lea	4(a0),a2
	move.l	a2,cr_Sizes(a1)
	move.l	d1,d2
	subq.l	#1,d2
	move.l	d2,cr_Hunks(a1)
	move.l	d1,d4
.flags	move.l	(a0)+,d2		; no extended memory attributes
	rol.l	#2,d2
	and.w	#3,d2
	cmp.w	#3,d2
	beq	.fail
	subq.l	#1,d4
	bne.s	.flags

	; the decranker: HUNK_CODE starting with bra.w and $0000abcd
	move.l	(a0)+,d2
	and.l	#$3fffffff,d2
	cmp.l	#HUNK_CODE,d2
	bne	.fail
	move.l	(a0)+,d2
	cmp.l	#4,d2
	bcs	.fail
	cmp.w	#$6000,(a0)
	bne	.fail
	cmp.l	#$0000abcd,4(a0)
	bne	.fail
	lsl.l	#2,d2
	add.l	d2,a0
	cmp.l	a3,a0
	bcc	.fail

	; the original hunks are BSS hunks
	move.l	d1,d4
	subq.l	#1,d4
.bss	bsr	.skipend
	lea	8(a0),a2
	cmp.l	a3,a2
	bcc	.fail
	move.l	(a0)+,d2
	and.l	#$3fffffff,d2
	cmp.l	#HUNK_BSS,d2
	bne	.fail
	addq.l	#4,a0
	subq.l	#1,d4
	bne.s	.bss
	bsr	.skipend

	; HUNK_OVERLAY, table of 1 (0.1-0.62) or 2 (0.63+) longwords, HUNK_BREAK
	lea	20(a0),a2
	cmp.l	a3,a2
	bcc	.fail
	cmp.l	#HUNK_OVERLAY,(a0)+
	bne	.fail
	move.l	(a0)+,d4		; table length - 1
	cmp.l	#2,d4
	bcc	.fail
	move.l	(a0)+,d2		; total length of the overlay part
	move.l	d2,d3			; crunched length (0.1-0.62: no field)
	tst.l	d4
	beq.s	.break
	move.l	(a0)+,d3
	cmp.l	d2,d3
	bhi.s	.fail
.break	cmp.l	#HUNK_BREAK,(a0)+
	bne.s	.fail
	move.l	a3,d5
	sub.l	a0,d5			; bytes after HUNK_BREAK
	cmp.l	d5,d2
	bhi.s	.fail
	move.l	a3,a0
	sub.l	d2,a0			; the decranker seeks to EOF - length
	lea	(a0,d3.l),a2
	move.l	a2,cr_StreamEnd(a1)

	; skip the initial payload (text etc.)
	moveq	#0,d5
	tst.l	d4
	beq.s	.oldini
	cmp.l	#2,d3
	bcs.s	.fail
	move.b	(a0)+,d5
	lsl.w	#8,d5
	move.b	(a0)+,d5
	subq.l	#2,d3
	bra.s	.ini
.oldini	tst.l	d3
	beq.s	.fail
	move.b	(a0)+,d5
	and.b	#$7f,d5
	subq.l	#1,d3
.ini	sub.l	d5,d3
	bcs.s	.fail
	cmp.l	#8,d3			; room for the first hunk entry
	bcs.s	.fail
	add.l	d5,a0
	move.l	a0,cr_Stream(a1)
	moveq	#1,d0
	bra.s	.exit
.fail	moveq	#0,d0
.exit	movem.l	(sp)+,d1-d5/a0-a3
	rts

.skipend
	cmp.l	a3,a0
	bcc.s	.se
	cmp.l	#HUNK_END,(a0)
	bne.s	.se
	addq.l	#4,a0
	bra.s	.skipend
.se	rts

;------------------------------------------------------------------------------
; CR_Walk: walk the hunk entries of the overlay part.
;   a0 = CR_Header results, a1 = hunk descriptor table, or 0 to only check
;   the structure (recognition)
; With a table, each LZO stream is checked with LZO_Decode, and the hunks get
; hd_Src, hd_SrcLen, hd_Crunched, hd_RelSrc, hd_InStream, hd_DataLen and
; hd_RelocLen.
; Out: d0 = 1 if the overlay part is well formed, else 0.
CR_Walk
	movem.l	d1-d7/a0-a5,-(sp)
	move.l	sp,a2			; for error exits from subroutines
	move.l	cr_Sizes(a0),a4
	move.l	cr_Hunks(a0),d7
	move.l	cr_StreamEnd(a0),a3
	move.l	cr_Stream(a0),a0
	moveq	#0,d6			; the first entry is hunk 0
.hunk	cmp.l	d7,d6
	bcc	.bad
	move.l	d6,d0
	lsl.l	#2,d0
	move.l	(a4,d0.l),d5
	and.l	#$3fffffff,d5
	lsl.l	#2,d5			; d5 = hunk memory size
	bsr	.rl
	move.l	d0,d1			; d1 = crunched length
	bsr	.rl
	move.l	d0,d2			; d2 = hunk offset (negative: stored)
	move.l	a3,d0
	sub.l	a0,d0
	cmp.l	d1,d0
	bcs	.bad			; data runs past the end
	move.l	d5,d4			; d4 = decoded length (recog: maximum)
	tst.l	d2
	bpl.s	.lzo
	cmp.l	d5,d1
	bhi	.bad			; stored data larger than the hunk
	move.l	d1,d4
.lzo	move.l	a1,d0
	beq.s	.data
	move.l	d6,d0
	mulu.w	#HD_SIZEOF,d0
	lea	(a1,d0.l),a5
	tst.l	hd_InStream(a5)
	bne	.bad			; hunk appears twice
	moveq	#1,d0
	move.l	d0,hd_InStream(a5)
	move.l	a0,hd_Src(a5)
	move.l	d1,hd_SrcLen(a5)
	tst.l	d2
	bmi.s	.setlen
	move.l	d0,hd_Crunched(a5)
	move.l	d1,d0
	move.l	d1,-(sp)
	move.l	d5,d1
	move.l	a1,-(sp)
	sub.l	a1,a1
	bsr	LZO_Decode		; check only; preserves all but d0
	move.l	(sp)+,a1
	move.l	(sp)+,d1
	tst.l	d0
	bmi	.bad
	move.l	d0,d4
.setlen	move.l	d4,hd_DataLen(a5)
	move.l	a0,d0
	add.l	d1,d0
	move.l	d0,hd_RelSrc(a5)
.data	add.l	d1,a0

	; relocations: groups of count, target hunk, deltas; count 0 ends
	moveq	#0,d3			; d3 = bytes of HUNK_RELOC32 groups
.group	bsr	.rb
	tst.l	d0
	beq.s	.rdone
	move.l	d0,d1			; d1 = count
	bsr	.rb
	cmp.l	d7,d0
	bcc.s	.bad			; no such hunk
	move.l	d1,d0
	addq.l	#2,d0
	lsl.l	#2,d0
	add.l	d0,d3
	moveq	#0,d2			; d2 = offset
.entry	bsr.s	.rb			; (d5 is free from here on)
	bclr	#7,d0
	beq.s	.add			; < $80: one byte
	move.l	d0,d5
	bclr	#6,d5
	bne.s	.four
	lsl.l	#8,d5			; two bytes: 14 bits
	bsr.s	.rb
	or.l	d5,d0
	bra.s	.add
.four	lsl.l	#8,d5			; four bytes: 30 bits
	bsr.s	.rb
	or.l	d0,d5
	lsl.l	#8,d5
	bsr.s	.rb
	or.l	d0,d5
	lsl.l	#8,d5
	bsr.s	.rb
	or.l	d5,d0
.add	add.l	d0,d2
	move.l	d4,d0
	subq.l	#4,d0
	bcs.s	.bad
	cmp.l	d0,d2
	bhi.s	.bad			; reloc outside the hunk data
	subq.l	#1,d1
	bne.s	.entry
	bra.s	.group
.rdone	move.l	a1,d0
	beq.s	.next
	move.l	d3,hd_RelocLen(a5)
.next	bsr.s	.rw
	move.l	d0,d6
	bne	.hunk
	moveq	#1,d0
	bra.s	.exit
.bad	move.l	a2,sp
	moveq	#0,d0
.exit	movem.l	(sp)+,d1-d7/a0-a5
	rts

; read a byte, word or longword (any alignment) from the stream
.rb	cmp.l	a3,a0
	bcc.s	.bad
	moveq	#0,d0
	move.b	(a0)+,d0
	rts
.rw	move.l	d1,-(sp)
	bsr.s	.rb
	move.l	d0,d1
	bsr.s	.rb
	lsl.w	#8,d1
	or.w	d1,d0
	move.l	(sp)+,d1
	rts
.rl	move.l	d1,-(sp)
	bsr.s	.rw
	move.l	d0,d1
	bsr.s	.rw
	swap	d1
	clr.w	d1
	or.l	d1,d0
	move.l	(sp)+,d1
	rts

;------------------------------------------------------------------------------
; CR_Relocs: copy one hunk's relocations (already checked by CR_Walk) into
; HUNK_RELOC32 groups.  a0 = reloc bytes, a1 = output
CR_Relocs
	movem.l	d0-d3/a0-a1,-(sp)
.group	moveq	#0,d0
	move.b	(a0)+,d0
	beq.s	.done
	move.l	d0,d1			; count
	move.l	d0,(a1)+
	moveq	#0,d0
	move.b	(a0)+,d0
	move.l	d0,(a1)+		; target hunk
	moveq	#0,d2			; offset
.entry	moveq	#0,d0
	move.b	(a0)+,d0
	bclr	#7,d0
	beq.s	.add
	bclr	#6,d0
	beq.s	.short
	lsl.l	#8,d0
	move.b	(a0)+,d0
	lsl.l	#8,d0
	move.b	(a0)+,d0
.short	lsl.l	#8,d0
	move.b	(a0)+,d0
.add	add.l	d0,d2
	move.l	d2,(a1)+
	subq.l	#1,d1
	bne.s	.entry
	bra.s	.group
.done	movem.l	(sp)+,d0-d3/a0-a1
	rts

;------------------------------------------------------------------------------
; Executable: recognition
RB_CrankerExe
	movem.l	d1/a0-a1,-(sp)
	lea	-CR_SIZEOF(sp),sp
	move.l	sp,a1
	bsr	CR_Header
	tst.l	d0
	beq.s	.no
	move.l	sp,a0
	sub.l	a1,a1
	bsr	CR_Walk
.no	lea	CR_SIZEOF(sp),sp
	movem.l	(sp)+,d1/a0-a1
	rts

; Executable: decrunching.  a0 = xfdBufferInfo, a6 = xfdmaster base
DB_CrankerExe
	movem.l	d2-d7/a2-a6,-(sp)
	move.l	a0,a4
	move.w	#XFDERR_CORRUPTEDDATA,xfdbi_Error(a4)
	lea	-CR_SIZEOF(sp),sp
	move.l	xfdbi_SourceBuffer(a4),a0
	move.l	xfdbi_SourceBufLen(a4),d0
	move.l	sp,a1
	bsr	CR_Header
	tst.l	d0
	beq	.fail
	move.l	cr_Hunks(sp),d7
	move.l	d7,d0
	bsr	HO_AllocTable
	beq	.nomem
	move.l	a0,a3			; a3 = descriptor table
	move.l	sp,a0
	move.l	a3,a1
	bsr	CR_Walk
	tst.l	d0
	beq	.free

	move.l	cr_Sizes(sp),a2
	move.l	a3,a5
	move.l	d7,d6
.hunk	move.l	(a2)+,d0
	move.l	d0,d1
	and.l	#$c0000000,d1
	move.l	d1,hd_MemFlags(a5)
	and.l	#$3fffffff,d0
	lsl.l	#2,d0
	move.l	d0,hd_MemSize(a5)
	move.l	#HUNK_BSS,hd_Type(a5)
	tst.l	hd_InStream(a5)
	beq.s	.next
	move.l	#HUNK_CODE,hd_Type(a5)
	move.l	hd_Src(a5),hd_Data(a5)	; stored hunks are used in place
	tst.l	hd_Crunched(a5)
	beq.s	.relocs
	move.l	hd_DataLen(a5),d0
	beq.s	.relocs
	bsr	HO_Alloc
	tst.l	d0
	beq	.nomem2
	move.l	d0,hd_Data(a5)
	move.l	hd_DataLen(a5),hd_DataAlloc(a5)
	move.l	d0,a1
	move.l	hd_Src(a5),a0
	move.l	hd_SrcLen(a5),d0
	move.l	hd_DataLen(a5),d1
	bsr	LZO_Decode
.relocs	move.l	hd_RelocLen(a5),d0
	beq.s	.next
	bsr	HO_Alloc
	tst.l	d0
	beq.s	.nomem2
	move.l	d0,hd_Reloc(a5)
	move.l	hd_RelocLen(a5),hd_RelocAlloc(a5)
	move.l	d0,a1
	move.l	hd_RelSrc(a5),a0
	bsr	CR_Relocs
.next	lea	HD_SIZEOF(a5),a5
	subq.l	#1,d6
	bne	.hunk

	move.l	a3,a0
	move.l	d7,d0
	bsr	HO_Build
	move.l	d0,d2
	move.l	a3,a0
	move.l	d7,d0
	bsr	HO_FreeTable
	tst.l	d2
	beq.s	.exit
	clr.w	xfdbi_Error(a4)
	moveq	#1,d0
	bra.s	.exit
.nomem2	move.w	#XFDERR_NOMEMORY,xfdbi_Error(a4)
.free	move.l	a3,a0
	move.l	d7,d0
	bsr	HO_FreeTable
	bra.s	.fail
.nomem	move.w	#XFDERR_NOMEMORY,xfdbi_Error(a4)
.fail	moveq	#0,d0
.exit	lea	CR_SIZEOF(sp),sp
	movem.l	(sp)+,d2-d7/a2-a6
	rts

;------------------------------------------------------------------------------
; Data: recognition.  The first byte is $b0 or, with -eo, the overhead (both
; a multiple of 4 from 4 to 252); the stream must decode to the stored length.
RB_CrankerData
	movem.l	d1-d2/a0,-(sp)
	move.l	d0,d2
	cmp.l	#8,d2
	bcs.s	.no
	move.b	(a0),d0
	beq.s	.no
	cmp.b	#252,d0
	bhi.s	.no
	and.b	#3,d0
	bne.s	.no
	move.l	(a0),d1
	and.l	#$00ffffff,d1
	beq.s	.no
	cmp.b	#$11,-3(a0,d2.l)	; LZO end marker
	bne.s	.no
	tst.b	-2(a0,d2.l)
	bne.s	.no
	tst.b	-1(a0,d2.l)
	bne.s	.no
	addq.l	#4,a0
	move.l	d2,d0
	subq.l	#4,d0
	sub.l	a1,a1
	bsr	LZO_Decode
	bmi.s	.no
	cmp.l	d1,d0
	bne.s	.no
	moveq	#1,d0
	bra.s	.exit
.no	moveq	#0,d0
.exit	movem.l	(sp)+,d1-d2/a0
	rts

; Data: decrunching
DB_CrankerData
	movem.l	d2-d7/a2-a6,-(sp)
	move.l	a0,a4
	move.w	#XFDERR_CORRUPTEDDATA,xfdbi_Error(a4)
	move.l	xfdbi_SourceBuffer(a4),a2
	move.l	xfdbi_SourceBufLen(a4),d0
	move.l	(a2),d3
	and.l	#$00ffffff,d3
	lea	4(a2),a0
	subq.l	#4,d0
	move.l	d3,d1
	sub.l	a1,a1
	bsr	LZO_Decode
	bmi.s	.fail
	cmp.l	d3,d0
	bne.s	.fail
	move.w	#XFDERR_NOMEMORY,xfdbi_Error(a4)
	move.l	d3,d0
	move.l	xfdbi_TargetBufMemType(a4),d1
	move.l	a6,-(sp)
	move.l	xfdm_ExecBase(a6),a6
	jsr	_LVOAllocMem(a6)
	move.l	(sp)+,a6
	tst.l	d0
	beq.s	.fail
	move.l	d0,xfdbi_TargetBuffer(a4)
	move.l	d3,xfdbi_TargetBufLen(a4)
	move.l	d3,xfdbi_TargetBufSaveLen(a4)
	move.l	d0,a1
	lea	4(a2),a0
	move.l	xfdbi_SourceBufLen(a4),d0
	subq.l	#4,d0
	move.l	d3,d1
	bsr	LZO_Decode
	clr.w	xfdbi_Error(a4)
	moveq	#1,d0
	bra.s	.exit
.fail	moveq	#0,d0
.exit	movem.l	(sp)+,d2-d7/a2-a6
	rts

;------------------------------------------------------------------------------
	include	hunkout.i
	include	lzo.i
