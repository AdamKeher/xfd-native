;
; Shrinkler.asm - xfd external slaves for Shrinkler by Blueberry
; (Aske Simon Christensen), versions 4.0 to 4.7
;
; Executables. Shrinkler packs every hunk into one range-coded stream: the
; hunk's contents up to its memory size, then for each hunk of the file the
; offsets of the longwords that point into it. Three decrunch headers:
;   default  first hunk: Header1 (trampoline); last hunk: Header2 and the
;            stream (4.0-4.4: forward after the code; 4.5+: longwords in
;            reverse order, ending at the end of the hunk)
;   mini     (-m) first hunk: MiniHeader and the stream (reversed); the
;            original hunks are BSS. Only the first hunk is packed and
;            there are no relocations.
;   overlap  (-o) first hunk: OverlapHeader; each original hunk is a DATA
;            hunk holding its part of the (forward) stream
; Options such as text, flash and commandline only change the header code.
; The slave rebuilds a normal executable. What Shrinkler does not keep is
; guessed: the first hunk becomes CODE (overlap: the others become DATA or,
; if empty, BSS), and each hunk's data ends after its last nonzero longword.
;
; Data files written with --header: "Shri", version, header size, sizes,
; safety margin and flags, then the stream. Raw --data output has no header
; and is not recognised.
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
	dc.l	S_Shrinkler

S_Shrinkler
	dc.l	S_ShrinklerMini
	dc.w	2,39
	dc.l	N_Shrinkler
	dc.w	XFDPFF_RELOC,0
	dc.l	RB_Shrinkler,DB_ShrinklerExe,0,0
	dc.w	0,0
	dc.l	64

S_ShrinklerMini
	dc.l	S_ShrinklerOverlap
	dc.w	2,39
	dc.l	N_ShrinklerMini
	dc.w	XFDPFF_RELOC,0
	dc.l	RB_ShrinklerMini,DB_ShrinklerExe,0,0
	dc.w	0,0
	dc.l	64

S_ShrinklerOverlap
	dc.l	S_ShrinklerData
	dc.w	2,39
	dc.l	N_ShrinklerOverlap
	dc.w	XFDPFF_RELOC,0
	dc.l	RB_ShrinklerOverlap,DB_ShrinklerExe,0,0
	dc.w	0,0
	dc.l	64

S_ShrinklerData
	dc.l	0
	dc.w	2,39
	dc.l	N_ShrinklerData
	dc.w	XFDPFF_DATA,0
	dc.l	RB_ShrinklerData,DB_ShrinklerData,0,0
	dc.w	0,0
	dc.l	32

N_Shrinkler		dc.b	"Shrinkler",0
N_ShrinklerMini		dc.b	"Shrinkler Mini",0
N_ShrinklerOverlap	dc.b	"Shrinkler Overlap",0
N_ShrinklerData		dc.b	"Shrinkler Data",0
	dc.b	"$VER: Shrinkler 1.0 (21.11.2026) xfd-native",0
	even

MODE_DEFAULT	= 0
MODE_MINI	= 1
MODE_OVERLAP	= 2

; SH_Header results
shi_Sizes	= 0			; hunk header size table
shi_Hunks	= 4			; number of hunks in the file
shi_First	= 8			; type longword of the first hunk
shi_End		= 12			; end of the file
shi_Stream	= 16			; default/mini: the packed data
shi_StreamLen	= 20			; its length
shi_Reverse	= 24			; 1: longwords in reverse order
SHI_SIZEOF	= 28

;------------------------------------------------------------------------------
; SH_Hunk: read one hunk of the file.
;   a0 = its type longword, a2 = end of file
; Out: d0 = HUNK_CODE/DATA/BSS (0: malformed), d1 = length in bytes,
;      a1 = data (0 for BSS), a0 = next hunk (after any HUNK_END)
SH_Hunk
	lea	8(a0),a1
	cmp.l	a2,a1
	bhi.s	.bad
	move.l	(a0)+,d0
	and.l	#$3fffffff,d0
	move.l	(a0)+,d1
	and.l	#$3fffffff,d1
	lsl.l	#2,d1
	cmp.l	#HUNK_BSS,d0
	beq.s	.bss
	cmp.l	#HUNK_CODE,d0
	beq.s	.data
	cmp.l	#HUNK_DATA,d0
	bne.s	.bad
.data	move.l	a0,a1
	add.l	d1,a0
	cmp.l	a2,a0
	bhi.s	.bad
	bra.s	.end
.bss	sub.l	a1,a1
.end	cmp.l	a2,a0
	bcc.s	.ok
	cmp.l	#HUNK_END,(a0)
	bne.s	.ok
	addq.l	#4,a0
	bra.s	.end
.ok	rts
.bad	moveq	#0,d0
	rts

; SH_FindSig: is the range decoder of a decrunch header within the first
; 400 bytes of a0 (length d0)? Out: d0 = 1/0
SH_FindSig
	movem.l	d1/a0-a1,-(sp)
	cmp.l	#400,d0
	bls.s	.len
	move.l	#400,d0
.len	sub.l	#12,d0
	bcs.s	.no
	lsr.l	#1,d0
	lea	.sig(pc),a1
.look	move.l	(a1),d1
	cmp.l	(a0),d1
	bne.s	.next
	move.l	4(a1),d1
	cmp.l	4(a0),d1
	bne.s	.next
	move.l	8(a1),d1
	cmp.l	8(a0),d1
	beq.s	.yes
.next	addq.l	#2,a0
	subq.l	#1,d0
	bcc.s	.look
.no	moveq	#0,d0
	bra.s	.exit
.yes	moveq	#1,d0
.exit	movem.l	(sp)+,d1/a0-a1
	rts
	; lsr.w #4,d4 / sub.w d4,(a5) / add.w (a5),d4 / mulu.w d3,d4 /
	; swap d4 / sub.w d4,d2
.sig	dc.l	$e84c9955,$d855c8c3,$48449444

;------------------------------------------------------------------------------
; SH_Header: check the hunk structure and find the decrunch header.
;   a0 = buffer, d0.l = length, a1 = SHI_SIZEOF result area
; Out: d0.l = MODE_xxx, or -1 if this is not a Shrinkler executable.
SH_Header
	movem.l	d1-d7/a0-a5,-(sp)
	move.l	a1,a3
	lea	(a0,d0.l),a2		; a2 = end of file
	cmp.l	#64,d0
	bcs	.fail
	cmp.l	#HUNK_HEADER,(a0)+
	bne	.fail
	tst.l	(a0)+
	bne	.fail
	move.l	(a0)+,d7		; number of hunks
	cmp.l	#2,d7
	bcs	.fail
	cmp.l	#$4000,d7
	bcc	.fail
	tst.l	(a0)+
	bne	.fail
	move.l	(a0)+,d0
	addq.l	#1,d0
	cmp.l	d7,d0
	bne	.fail
	move.l	d7,d0
	lsl.l	#2,d0
	lea	8(a0,d0.l),a1
	cmp.l	a2,a1
	bcc	.fail
	move.l	a0,shi_Sizes(a3)
	move.l	d7,shi_Hunks(a3)
	move.l	a2,shi_End(a3)
	move.l	d7,d1
.flags	move.l	(a0)+,d0		; no extended memory attributes
	rol.l	#2,d0
	and.w	#3,d0
	cmp.w	#3,d0
	beq	.fail
	subq.l	#1,d1
	bne.s	.flags
	move.l	a0,shi_First(a3)

	; first hunk: always code
	bsr	SH_Hunk
	cmp.l	#HUNK_CODE,d0
	bne	.fail
	move.l	a1,a4			; a4/d5 = first hunk data/length
	move.l	d1,d5
	cmp.l	#16,d5
	bcs	.fail

	; the other hunks: note whether they are all DATA / all BSS
	moveq	#3,d4			; bit 0: all DATA, bit 1: all BSS
	move.l	d7,d6
	subq.l	#1,d6
.walk	bsr	SH_Hunk
	tst.l	d0
	beq	.fail
	cmp.l	#HUNK_DATA,d0
	beq.s	.isdata
	bclr	#0,d4
.isdata	cmp.l	#HUNK_BSS,d0
	beq.s	.isbss
	bclr	#1,d4
.isbss	subq.l	#1,d6
	bne.s	.walk
	; d0/d1/a1 = last hunk

	; default: Header2 at the start of the last hunk
	cmp.l	#HUNK_CODE,d0
	bne.s	.notdef
	cmp.l	#216,d1
	bcs.s	.notdef
	move.l	(a4),d2			; Header1: lea (pc),a4 / movea.l a3,a4
	cmp.l	#$49fafffe,d2
	beq.s	.h1
	cmp.l	#$284b241c,d2
	bne.s	.notdef
.h1	move.l	a1,a0
	move.l	d1,d0
	bsr	SH_FindSig
	tst.l	d0
	beq.s	.notdef
	cmp.l	#$4295d9e4,(a1)		; 4.5+: clr.l (a5) / adda.l -(a4),a4
	bne.s	.old
	move.l	a1,shi_Stream(a3)
	move.l	d1,shi_StreamLen(a3)
	moveq	#1,d0
	move.l	d0,shi_Reverse(a3)
	moveq	#MODE_DEFAULT,d0
	bra	.exit
.old	cmp.l	#$42a549fa,(a1)		; 4.0-4.4: clr.l -(a5) / lea x(pc),a4
	bne.s	.notdef
	moveq	#4,d0
	add.w	4(a1),d0		; the lea's target: start of the data
	ext.l	d0
	cmp.l	d1,d0
	bcc.s	.notdef
	lea	(a1,d0.l),a0
	move.l	a0,shi_Stream(a3)
	sub.l	d0,d1
	move.l	d1,shi_StreamLen(a3)
	clr.l	shi_Reverse(a3)
	moveq	#MODE_DEFAULT,d0
	bra	.exit

	; mini or overlap: [movem.l d0/a0,-(a7)] move.l (a3)/x(pc),d2 /
	; lsl.l #2,d2 / movea.l d2,a1 (mini) or movea.l d2,a3 (overlap)
.notdef	move.l	a4,a0
	cmp.l	#$48e78080,(a0)
	bne.s	.nomovem
	addq.l	#4,a0
.nomovem
	cmp.w	#$2413,(a0)
	bne.s	.pcrel
	addq.l	#2,a0
	bra.s	.lsl
.pcrel	cmp.w	#$243a,(a0)
	bne	.fail
	addq.l	#4,a0
.lsl	cmp.w	#$e58a,(a0)+
	bne	.fail
	move.l	a4,a0
	move.l	d5,d0
	bsr	SH_FindSig
	tst.l	d0
	beq	.fail
	move.l	a4,a0
	cmp.l	#$48e78080,(a0)
	bne.s	.nm2
	addq.l	#4,a0
.nm2	cmp.w	#$2413,(a0)
	beq.s	.short
	addq.l	#2,a0
.short	addq.l	#4,a0
	cmp.w	#$2242,(a0)
	beq.s	.mini
	cmp.w	#$2642,(a0)
	bne.s	.fail
	btst	#0,d4			; overlap: the other hunks are DATA
	beq.s	.fail
	moveq	#MODE_OVERLAP,d0
	bra.s	.exit
.mini	btst	#1,d4			; mini: the other hunks are BSS
	beq.s	.fail
	move.l	a4,shi_Stream(a3)
	move.l	d5,shi_StreamLen(a3)
	moveq	#1,d0
	move.l	d0,shi_Reverse(a3)
	moveq	#MODE_MINI,d0
	bra.s	.exit
.fail	moveq	#-1,d0
.exit	movem.l	(sp)+,d1-d7/a0-a5
	rts

;------------------------------------------------------------------------------
; recognition
RB_Shrinkler
	moveq	#MODE_DEFAULT,d1
	bra.s	RB_Mode
RB_ShrinklerMini
	moveq	#MODE_MINI,d1
	bra.s	RB_Mode
RB_ShrinklerOverlap
	moveq	#MODE_OVERLAP,d1
RB_Mode	movem.l	d1/a0-a1,-(sp)
	lea	-SHI_SIZEOF(sp),sp
	move.l	sp,a1
	bsr	SH_Header
	lea	SHI_SIZEOF(sp),sp
	movem.l	(sp)+,d1/a0-a1
	cmp.l	d1,d0
	seq	d0
	and.l	#1,d0
	rts

;------------------------------------------------------------------------------
; decrunching (all three executable slaves)

; frame
fr_Info		= 0
fr_State	= SHI_SIZEOF
fr_Stream	= fr_State+SD_SIZEOF	; normalised forward stream
fr_StreamSize	= fr_Stream+4		; its allocation size
fr_Ctx		= fr_StreamSize+4	; contexts
fr_Mode		= fr_Ctx+4
fr_Walk		= fr_Mode+4		; file hunk of the current hunk
FR_SIZEOF	= fr_Walk+4
CTX_SIZE	= (SD_NUMCTX+1)*2

DB_ShrinklerExe
	movem.l	d2-d7/a2-a6,-(sp)
	move.l	a0,a4			; a4 = xfdBufferInfo
	lea	-FR_SIZEOF(sp),sp
	move.l	sp,a5			; a5 = frame
	move.l	a5,a0
	moveq	#FR_SIZEOF/4-1,d0
.clr	clr.l	(a0)+
	dbf	d0,.clr
	sub.l	a3,a3			; a3 = descriptor table
	move.w	#XFDERR_CORRUPTEDDATA,xfdbi_Error(a4)
	move.l	xfdbi_SourceBuffer(a4),a0
	move.l	xfdbi_SourceBufLen(a4),d0
	lea	fr_Info(a5),a1
	bsr	SH_Header
	tst.l	d0
	bmi	.fail
	move.l	d0,fr_Mode(a5)
	move.l	fr_Info+shi_Hunks(a5),d7
	subq.l	#1,d7			; d7 = original hunks

	bsr	SH_Stream
	tst.l	d0
	beq	.fail
	move.l	#CTX_SIZE,d0
	bsr	HO_Alloc
	move.l	d0,fr_Ctx(a5)
	beq	.nomem
	lea	fr_State(a5),a0
	move.l	fr_Stream(a5),a1
	move.l	fr_StreamSize(a5),d0
	moveq	#1,d1
	move.l	fr_Ctx(a5),a2
	bsr	SD_Init

	move.l	d7,d0
	bsr	HO_AllocTable
	beq	.nomem
	move.l	a0,a3

	; walk the file hunks along: default mode starts at hunk 0, the
	; others at hunk 1
	move.l	fr_Info+shi_First(a5),a0
	tst.l	fr_Mode(a5)
	beq.s	.w0
	move.l	fr_Info+shi_End(a5),a2
	bsr	SH_Hunk
.w0	move.l	a0,fr_Walk(a5)

	move.l	a3,a2			; a2 = descriptor
	moveq	#0,d6			; d6 = hunk number
.hunk	move.l	d6,d0			; file hunk number
	tst.l	fr_Mode(a5)
	beq.s	.f0
	addq.l	#1,d0
.f0	lsl.l	#2,d0
	move.l	fr_Info+shi_Sizes(a5),a0
	move.l	(a0,d0.l),d0
	move.l	d0,d1
	and.l	#$c0000000,d1
	move.l	d1,hd_MemFlags(a2)
	and.l	#$3fffffff,d0
	lsl.l	#2,d0
	move.l	d0,hd_MemSize(a2)	; header size: the most it can hold
	move.l	d0,d5
	move.l	#HUNK_BSS,hd_Type(a2)
	cmp.l	#MODE_MINI,fr_Mode(a5)
	bne.s	.decode
	tst.l	d6
	bne	.next			; mini: only the first hunk is packed

.decode	tst.l	d5
	beq	.corrupt
	move.l	d5,d0
	bsr	HO_Alloc
	tst.l	d0
	beq	.nomem2
	move.l	d0,hd_Data(a2)
	move.l	d5,hd_DataAlloc(a2)
	lea	fr_State(a5),a0
	bsr	SD_ResetCtx
	move.l	d0,a1
	move.l	d5,d0
	bsr	SD_LZ
	bmi	.corrupt
	move.l	d0,d4			; d4 = decoded length
	moveq	#0,d3			; d3 = data must reach this far
	cmp.l	#MODE_MINI,fr_Mode(a5)
	beq.s	.trim
	move.l	d4,hd_MemSize(a2)	; the hunk's real memory size
	moveq	#3,d0
	and.l	d4,d0
	bne	.corrupt

	; relocations into each hunk
	move.l	d7,d0
	lsl.l	#3,d0
	add.l	d4,d0
	add.l	#16,d0
	move.l	d0,d2
	bsr	HO_Alloc
	tst.l	d0
	beq	.nomem2
	move.l	d0,hd_Reloc(a2)
	move.l	d2,hd_RelocAlloc(a2)
	move.l	d0,a1
	lea	fr_State(a5),a0
	move.l	d4,d0
	move.l	d7,d1
	bsr	SD_Relocs
	bmi	.corrupt
	move.l	d0,hd_RelocLen(a2)
	move.l	d1,d3

	; data length: up to the last nonzero longword, but covering relocs
.trim	move.l	hd_Data(a2),a0
	move.l	d4,d0
.tz	tst.l	d0
	beq.s	.tzend
	tst.b	-1(a0,d0.l)
	bne.s	.tzend
	subq.l	#1,d0
	bra.s	.tz
.tzend	addq.l	#3,d0
	and.b	#$fc,d0
	cmp.l	d3,d0
	bcc.s	.tzok
	move.l	d3,d0
.tzok	move.l	d0,hd_DataLen(a2)

	; hunk type
	move.l	#HUNK_CODE,d1
	tst.l	d6
	beq.s	.type
	move.l	#HUNK_DATA,d1
	cmp.l	#MODE_DEFAULT,fr_Mode(a5)
	bne.s	.empty
	move.l	fr_Walk(a5),a0		; default: the type in the file
	move.l	(a0),d1
	and.l	#$3fffffff,d1
	cmp.l	#HUNK_BSS,d1
	bne.s	.type
	move.l	#HUNK_DATA,d1		; BSS that is not empty becomes DATA
.empty	tst.l	hd_DataLen(a2)
	bne.s	.type
	tst.l	hd_RelocLen(a2)
	bne.s	.type
	move.l	#HUNK_BSS,d1
.type	move.l	d1,hd_Type(a2)

.next	move.l	fr_Walk(a5),a0
	move.l	fr_Info+shi_End(a5),a2
	bsr	SH_Hunk
	move.l	a0,fr_Walk(a5)
	move.l	d6,d0
	addq.l	#1,d0
	mulu.w	#HD_SIZEOF,d0
	lea	(a3,d0.l),a2
	addq.l	#1,d6
	cmp.l	d7,d6
	bcs	.hunk

	move.l	a3,a0
	move.l	d7,d0
	bsr	HO_Build
	move.l	d0,d2
	bsr	.cleanup
	tst.l	d2
	beq.s	.exit
	clr.w	xfdbi_Error(a4)
	moveq	#1,d0
	bra.s	.exit
.nomem2	move.w	#XFDERR_NOMEMORY,xfdbi_Error(a4)
	bra.s	.free
.corrupt
	move.w	#XFDERR_CORRUPTEDDATA,xfdbi_Error(a4)
	bra.s	.free
.nomem	move.w	#XFDERR_NOMEMORY,xfdbi_Error(a4)
.free	bsr	.cleanup
.fail	moveq	#0,d0
.exit	lea	FR_SIZEOF(sp),sp
	movem.l	(sp)+,d2-d7/a2-a6
	rts

.cleanup
	move.l	a3,a0
	move.l	d7,d0
	bsr	HO_FreeTable
	move.l	fr_Ctx(a5),a1
	move.l	#CTX_SIZE,d0
	bsr	HO_Free
	move.l	fr_Stream(a5),a1
	move.l	fr_StreamSize(a5),d0
	addq.l	#8,d0
	bsr	HO_Free
	rts

;------------------------------------------------------------------------------
; SH_Stream: copy the packed data into one forward byte stream.
;   a5 = frame (fr_Info, fr_Mode set), a4 = xfdBufferInfo,
;   a6 = xfdmaster base
; Sets fr_Stream and fr_StreamSize (the data plus 4 readable zero bytes;
; the allocation has 8 more). Out: d0 = 1, or 0 with xfdbi_Error set.
SH_Stream
	movem.l	d1-d4/a0-a3,-(sp)
	cmp.l	#MODE_OVERLAP,fr_Mode(a5)
	beq.s	.overlap
	move.l	fr_Info+shi_StreamLen(a5),d2
	move.l	d2,d0
	bsr	.alloc
	beq	.nomem
	move.l	d0,a1
	move.l	fr_Info+shi_Stream(a5),a0
	tst.l	fr_Info+shi_Reverse(a5)
	bne.s	.rev
	tst.l	d2
	beq.s	.ok
.fwd	move.b	(a0)+,(a1)+
	subq.l	#1,d2
	bne.s	.fwd
	bra.s	.ok
.rev	lsr.l	#2,d2			; longwords from the end backwards
	beq.s	.ok
	move.l	d2,d0
	lsl.l	#2,d0
	add.l	d0,a0
.rl	move.l	-(a0),(a1)+
	subq.l	#1,d2
	bne.s	.rl
	bra.s	.ok

	; overlap: each DATA hunk is [byte count][part of the stream]. Pass 0
	; adds up the parts, pass 1 copies them.
.overlap
	move.l	fr_Info+shi_End(a5),a2
	moveq	#0,d3
.pass	move.l	fr_Info+shi_First(a5),a0
	bsr	SH_Hunk			; skip the header hunk
	moveq	#0,d2
	move.l	fr_Info+shi_Hunks(a5),d4
	subq.l	#1,d4
.part	bsr	SH_Hunk
	cmp.l	#HUNK_DATA,d0
	bne.s	.bad
	subq.l	#4,d1
	bcs.s	.bad
	add.l	d1,d2
	tst.l	d3
	beq.s	.pnext
	addq.l	#4,a1
	tst.l	d1
	beq.s	.pnext
.pcopy	move.b	(a1)+,(a3)+
	subq.l	#1,d1
	bne.s	.pcopy
.pnext	subq.l	#1,d4
	bne.s	.part
	tst.l	d3
	bne.s	.ok
	move.l	d2,d0
	bsr.s	.alloc
	beq.s	.nomem
	move.l	d0,a3
	moveq	#1,d3
	bra.s	.pass

.ok	moveq	#1,d0
	bra.s	.exit
.bad	move.w	#XFDERR_CORRUPTEDDATA,xfdbi_Error(a4)
	moveq	#0,d0
	bra.s	.exit
.nomem	move.w	#XFDERR_NOMEMORY,xfdbi_Error(a4)
	moveq	#0,d0
.exit	movem.l	(sp)+,d1-d4/a0-a3
	rts

; d0 = data length -> d0 = buffer (Z set if none); sets fr_Stream/Size
.alloc	addq.l	#4,d0
	move.l	d0,fr_StreamSize(a5)
	addq.l	#8,d0
	bsr	HO_Alloc
	move.l	d0,fr_Stream(a5)
	rts

;------------------------------------------------------------------------------
; Data files with a header: recognition
RB_ShrinklerData
	movem.l	d1-d2/a0,-(sp)
	cmp.l	#32,d0
	bcs.s	.no
	cmp.l	#"Shri",(a0)
	bne.s	.no
	cmp.b	#4,4(a0)		; major version
	bne.s	.no
	moveq	#0,d1
	move.w	6(a0),d1		; header size
	cmp.w	#16,d1
	bcs.s	.no
	addq.l	#8,d1
	move.l	8(a0),d2		; compressed size
	add.l	d2,d1
	bcs.s	.no
	cmp.l	d0,d1
	bhi.s	.no
	move.l	12(a0),d2		; decompressed size
	beq.s	.no
	cmp.l	#$01000000,d2
	bcc.s	.no
	moveq	#1,d0
	bra.s	.exit
.no	moveq	#0,d0
.exit	movem.l	(sp)+,d1-d2/a0
	rts

; Data files with a header: decrunching
dfr_State	= 0
dfr_Stream	= SD_SIZEOF
dfr_Ctx		= dfr_Stream+4
DFR_SIZEOF	= dfr_Ctx+4

DB_ShrinklerData
	movem.l	d2-d7/a2-a6,-(sp)
	move.l	a0,a4
	lea	-DFR_SIZEOF(sp),sp
	move.l	sp,a5
	clr.l	dfr_Stream(a5)
	clr.l	dfr_Ctx(a5)
	move.w	#XFDERR_NOMEMORY,xfdbi_Error(a4)
	move.l	xfdbi_SourceBuffer(a4),a2
	moveq	#0,d2
	move.w	6(a2),d2
	addq.l	#8,d2			; d2 = offset of the stream
	move.l	8(a2),d3		; d3 = compressed size
	move.l	12(a2),d4		; d4 = decompressed size
	move.l	20(a2),d5		; d5 = flags (bit 0: parity context)

	move.l	d3,d0
	add.l	#12,d0
	bsr	HO_Alloc
	move.l	d0,dfr_Stream(a5)
	beq	.free
	move.l	d0,a1
	lea	(a2,d2.l),a0
	move.l	d3,d0
	beq.s	.copied
.copy	move.b	(a0)+,(a1)+
	subq.l	#1,d0
	bne.s	.copy
.copied	move.l	#CTX_SIZE,d0
	bsr	HO_Alloc
	move.l	d0,dfr_Ctx(a5)
	beq	.free

	move.l	d4,d0
	move.l	xfdbi_TargetBufMemType(a4),d1
	move.l	a6,-(sp)
	move.l	xfdm_ExecBase(a6),a6
	jsr	_LVOAllocMem(a6)
	move.l	(sp)+,a6
	tst.l	d0
	beq.s	.free
	move.l	d0,xfdbi_TargetBuffer(a4)
	move.l	d4,xfdbi_TargetBufLen(a4)
	move.l	d4,xfdbi_TargetBufSaveLen(a4)

	move.l	a5,a0
	move.l	dfr_Stream(a5),a1
	move.l	d3,d0
	addq.l	#4,d0
	move.l	d5,d1
	move.l	dfr_Ctx(a5),a2
	bsr	SD_Init
	bsr	SD_ResetCtx
	move.l	xfdbi_TargetBuffer(a4),a1
	move.l	d4,d0
	bsr	SD_LZ
	bmi.s	.bad
	cmp.l	d4,d0
	bne.s	.bad
	clr.w	xfdbi_Error(a4)
	moveq	#1,d2
	bra.s	.done
.bad	move.w	#XFDERR_CORRUPTEDDATA,xfdbi_Error(a4)
	move.l	xfdbi_TargetBuffer(a4),a1
	move.l	d4,d0
	bsr	HO_Free
	clr.l	xfdbi_TargetBuffer(a4)
.free	moveq	#0,d2
.done	move.l	dfr_Stream(a5),a1
	move.l	d3,d0
	add.l	#12,d0
	bsr	HO_Free
	move.l	dfr_Ctx(a5),a1
	move.l	#CTX_SIZE,d0
	bsr	HO_Free
	move.l	d2,d0
	lea	DFR_SIZEOF(sp),sp
	movem.l	(sp)+,d2-d7/a2-a6
	rts

;------------------------------------------------------------------------------
	include	hunkout.i
	include	shrinkler.i
