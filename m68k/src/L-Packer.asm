;
; L-Packer.asm - xfd external slaves for L-Packer by Leonard/Oxygene
; (Arnaud Carre)
;
; Executables. L-Packer merges all hunks into two, one per memory type
; (slot 0: the first hunk's memory type, slot 1: the other one), and packs
; each with LZ4, ZX0 or DEFLATE. The file has three code hunks: the boot
; code (with "LPK!" in front of its depacker), then one hunk per slot
; holding [packed size][memory size][packed data]. Decoded, a slot is its
; data followed by a relocation table that is read backwards from the end:
; for slot 0 then slot 1 as target, bytes giving the distance to the next
; relocated longword in words (0: skip 508 bytes), ended by $ff. The
; relocated longwords already hold offsets into the target slot. The slave
; writes the two slots as a two-hunk executable; the original hunk layout is
; not stored. Memory sizes include L-Packer's in-place depacking margin.
;
; Data files (-data): "LPZ4", "LPX0" or "LPDE", the decoded size, the packed
; size, the packed data.
;
; Copyright (C) 2026 the xfd-native authors
; SPDX-License-Identifier: LGPL-2.1-or-later
;

	include	exec/types.i
	include	exec/memory.i
	include	dos/doshunks.i
	include	libraries/xfdmaster.i
	include	lvo/exec_lib.i

ALGO_LZ4	= 0
ALGO_ZX0	= 1
ALGO_DEFLATE	= 2

ForeMan	dc.l	$70FF4E75,XFDF_ID
	dc.w	XFDF_VERSION
	dcb.w	5,0
	dc.l	S_LZ4

SLAVE	macro	; next, name, flags, recog, decrunch, minsize
	dc.l	\1
	dc.w	2,39
	dc.l	\2
	dc.w	\3,0
	dc.l	\4,\5,0,0
	dc.w	0,0
	dc.l	\6
	endm

S_LZ4		SLAVE	S_ZX0,N_LZ4,XFDPFF_RELOC,RB_LZ4,DB_Exe,64
S_ZX0		SLAVE	S_Deflate,N_ZX0,XFDPFF_RELOC,RB_ZX0,DB_Exe,64
S_Deflate	SLAVE	S_DataLZ4,N_Deflate,XFDPFF_RELOC,RB_Deflate,DB_Exe,64
S_DataLZ4	SLAVE	S_DataZX0,N_DataLZ4,XFDPFF_DATA,RB_DataLZ4,DB_Data,16
S_DataZX0	SLAVE	S_DataDeflate,N_DataZX0,XFDPFF_DATA,RB_DataZX0,DB_Data,16
S_DataDeflate	SLAVE	0,N_DataDeflate,XFDPFF_DATA,RB_DataDeflate,DB_Data,16

N_LZ4		dc.b	"L-Packer LZ4",0
N_ZX0		dc.b	"L-Packer ZX0",0
N_Deflate	dc.b	"L-Packer Deflate",0
N_DataLZ4	dc.b	"L-Packer Data LZ4",0
N_DataZX0	dc.b	"L-Packer Data ZX0",0
N_DataDeflate	dc.b	"L-Packer Data Deflate",0
	dc.b	"$VER: L-Packer 1.0 (21.11.2026) xfd-native",0
	even

; LP_Header results
lpi_Sizes	= 0			; hunk header sizes
lpi_Slot	= 4			; slot 0 and 1: [packed][memory][data]
LPI_SIZEOF	= 12

;------------------------------------------------------------------------------
; LP_Header: check the file layout and find the depacker.
;   a0 = buffer, d0.l = length, a1 = LPI_SIZEOF result area
; Out: d0.l = ALGO_xxx, or -1 if this is not an L-Packer executable.
LP_Header
	movem.l	d1-d4/a0-a4,-(sp)
	move.l	a1,a3
	lea	(a0,d0.l),a2		; a2 = end of file
	cmp.l	#64,d0
	bcs	.fail
	cmp.l	#HUNK_HEADER,(a0)+
	bne	.fail
	tst.l	(a0)+
	bne	.fail
	cmp.l	#3,(a0)+		; boot hunk + two slots
	bne	.fail
	tst.l	(a0)+
	bne	.fail
	cmp.l	#2,(a0)+
	bne	.fail
	move.l	a0,lpi_Sizes(a3)
	lea	12(a0),a0

	; boot hunk
	bsr	.hunk
	beq	.fail
	move.l	a1,a4			; a4/d4 = boot code
	move.l	d1,d4
	; slots
	moveq	#0,d3
.slot	bsr	.hunk
	beq	.fail
	cmp.l	#8,d1
	bcs	.fail
	move.l	(a1),d2			; packed size
	addq.l	#8,d2
	cmp.l	d1,d2
	bhi	.fail
	move.l	lpi_Sizes(a3),a4
	move.l	4(a4,d3.l),d2		; the memory size is also in the header
	and.l	#$3fffffff,d2
	lsl.l	#2,d2
	cmp.l	4(a1),d2
	bne	.fail
	move.l	a1,lpi_Slot(a3,d3.l)
	addq.l	#4,d3
	cmp.l	#8,d3
	bcs.s	.slot

	; boot code: "LPK!" after the common end of the loader
	move.l	lpi_Sizes(a3),a4
	lea	12(a4),a0
	bsr	.hunk
	cmp.l	#400,d1
	bls.s	.len
	move.l	#400,d1
.len	sub.l	#32,d1
	bcs.s	.fail
	lsr.l	#1,d1
	lea	20(a1),a0
.find	cmp.l	#"LPK!",(a0)
	beq.s	.found
	addq.l	#2,a0
	subq.l	#1,d1
	bne.s	.find
	bra.s	.fail
.found	lea	.common(pc),a1		; 0.93+
	bsr	.tail
	beq.s	.tailok
	lea	.common2(pc),a1		; 0.90-0.92
	bsr.s	.tail
	bne.s	.fail
.tailok	addq.l	#4,a0
	cmp.w	#$47f9,(a0)		; -flash: lea $dff1a2,a3/a5 first
	beq.s	.flash
	cmp.w	#$4bf9,(a0)
	bne.s	.algo
.flash	addq.l	#6,a0
.algo	moveq	#ALGO_LZ4,d0
	cmp.w	#$49f0,(a0)		; lea (a0,d0.l),a4
	beq.s	.exit
	moveq	#ALGO_ZX0,d0
	cmp.l	#$728074ff,(a0)		; moveq #-128,d1 / moveq #-1,d2
	beq.s	.exit
	moveq	#ALGO_DEFLATE,d0
	cmp.l	#$ff5b006c,(a0)		; inflate's first table
	beq.s	.exit
.fail	moveq	#-1,d0
.exit	movem.l	(sp)+,d1-d4/a0-a4
	rts

; a0 = hunk -> a1 = data, d1 = length, a0 = next hunk; Z set if malformed
.hunk	lea	8(a0),a1
	cmp.l	a2,a1
	bhi.s	.hbad
	move.l	(a0)+,d1
	and.l	#$3fffffff,d1
	cmp.l	#HUNK_CODE,d1
	bne.s	.hbad
	move.l	(a0)+,d1
	and.l	#$3fffffff,d1
	lsl.l	#2,d1
	move.l	a0,a1
	add.l	d1,a0
	cmp.l	a2,a0
	bhi.s	.hbad
.hend	cmp.l	a2,a0
	bcc.s	.hok
	cmp.l	#HUNK_END,(a0)
	bne.s	.hok
	addq.l	#4,a0
	bra.s	.hend
.hok	moveq	#1,d2			; (clears Z)
	rts
.hbad	moveq	#0,d2
	rts

; do the 20 bytes before a0 match the 5 longwords at a1? (Z set if so)
.tail	movem.l	d1/a0,-(sp)
	lea	-20(a0),a0
	moveq	#4,d1
.tcmp	cmpm.l	(a0)+,(a1)+
	dbne	d1,.tcmp
	movem.l	(sp)+,d1/a0		; (movem leaves the flags alone)
	rts

	; the end of the loader: flush caches (2.04+), drop a stack entry, rts
.common	dc.l	$2c780004,$0c6e0025,$00146d04,$4eaefd84,$584f4e75
.common2
	dc.l	$2a780004,$0c6d0025,$00146d04,$4eadfd84,$584f4e75

;------------------------------------------------------------------------------
RB_LZ4	moveq	#ALGO_LZ4,d1
	bra.s	RB_Exe
RB_ZX0	moveq	#ALGO_ZX0,d1
	bra.s	RB_Exe
RB_Deflate
	moveq	#ALGO_DEFLATE,d1
RB_Exe	movem.l	d1/a0-a1,-(sp)
	lea	-LPI_SIZEOF(sp),sp
	move.l	sp,a1
	bsr	LP_Header
	lea	LPI_SIZEOF(sp),sp
	movem.l	(sp)+,d1/a0-a1
	cmp.l	d1,d0
	seq	d0
	and.l	#1,d0
	rts

;------------------------------------------------------------------------------
; LP_Unpack: decode with one of the three algorithms.
;   d2 = ALGO_xxx, a0 = packed, d0.l = packed length, a1 = output,
;   d1.l = output limit, a6 = xfdmaster base
; Out: d0.l = decoded length, or -1 (N set)
LP_Unpack
	cmp.l	#ALGO_LZ4,d2
	beq	LZ4_Decode
	cmp.l	#ALGO_ZX0,d2
	beq	ZX0_Decode
	movem.l	d1/a0-a2,-(sp)		; DEFLATE needs a workspace
	move.l	d0,-(sp)
	move.l	#IF_WSIZE,d0
	bsr	HO_Alloc
	move.l	d0,a2
	move.l	(sp)+,d0
	move.l	a2,d1
	beq.s	.nomem
	movem.l	(sp),d1/a0-a1
	bsr	INF_Inflate
	move.l	d0,-(sp)
	move.l	a2,a1
	move.l	#IF_WSIZE,d0
	bsr	HO_Free
	move.l	(sp)+,d0
	bra.s	.exit
.nomem	moveq	#-1,d0
.exit	movem.l	(sp)+,d1/a0-a2
	tst.l	d0
	rts

;------------------------------------------------------------------------------
; LP_Relocs: read a slot's relocation table backwards from the end of its
; decoded data.
;   a0 = decoded data, d0.l = decoded length, a1 = output groups or 0
; Out: d0.l = data length (decoded length minus the table), or -1;
;      d1.l = bytes of HUNK_RELOC32 groups
LP_Relocs
	movem.l	d2-d6/a0-a4,-(sp)
	lea	(a0,d0.l),a2		; a2 = read pointer (backwards)
	move.l	a0,a3			; a3 = start of the data
	; pass 1: find the size of the table
	move.l	a2,a4
	moveq	#2,d2
.t	cmp.l	a3,a4
	bls.s	.bad
	cmp.b	#$ff,-(a4)
	bne.s	.t
	subq.l	#1,d2
	bne.s	.t
	move.l	a4,d3
	sub.l	a3,d3			; d3 = data length
	; pass 2: check (and write) the relocs
	moveq	#0,d1			; group bytes
	moveq	#0,d2			; target slot
.group	moveq	#0,d4			; offset
	moveq	#0,d5			; count
	move.l	a1,d6
	beq.s	.byte
	clr.l	(a1)+			; count, patched below
	move.l	d2,(a1)+
.byte	moveq	#0,d0
	move.b	-(a2),d0
	cmp.b	#$ff,d0
	beq.s	.gend
	tst.b	d0
	bne.s	.rel
	add.l	#508,d4
	bra.s	.byte
.rel	add.l	d0,d4
	add.l	d0,d4
	move.l	d4,d0
	addq.l	#4,d0
	cmp.l	d3,d0
	bhi.s	.bad			; outside the data
	addq.l	#1,d5
	tst.l	d6
	beq.s	.byte
	move.l	d4,(a1)+
	bra.s	.byte
.gend	tst.l	d5
	beq.s	.empty
	move.l	d5,d0
	addq.l	#2,d0
	lsl.l	#2,d0
	add.l	d0,d1
	tst.l	d6
	beq.s	.gnext
	move.l	d6,a4
	move.l	d5,(a4)
	bra.s	.gnext
.empty	tst.l	d6
	beq.s	.gnext
	subq.l	#8,a1			; no relocs to this slot: drop the group
.gnext	move.l	a1,d6
	tst.l	d2
	bne.s	.done
	moveq	#1,d2
	tst.l	d6
	beq.s	.group
	bra.s	.group
.done	move.l	d3,d0
	bra.s	.exit
.bad	moveq	#-1,d0
.exit	movem.l	(sp)+,d2-d6/a0-a4
	tst.l	d0
	rts

;------------------------------------------------------------------------------
; Executable: decrunching
DB_Exe	movem.l	d2-d7/a2-a6,-(sp)
	move.l	a0,a4
	lea	-LPI_SIZEOF(sp),sp
	sub.l	a3,a3
	move.w	#XFDERR_CORRUPTEDDATA,xfdbi_Error(a4)
	move.l	xfdbi_SourceBuffer(a4),a0
	move.l	xfdbi_SourceBufLen(a4),d0
	move.l	sp,a1
	bsr	LP_Header
	tst.l	d0
	bmi	.fail
	move.l	d0,d7			; d7 = algorithm
	moveq	#2,d0
	bsr	HO_AllocTable
	beq	.nomem
	move.l	a0,a3
	move.l	a3,a5			; a5 = descriptor
	moveq	#0,d6			; d6 = slot * 4
.slot	move.l	lpi_Sizes(sp),a0
	move.l	4(a0,d6.l),d0
	move.l	d0,d1
	and.l	#$c0000000,d1
	move.l	d1,hd_MemFlags(a5)
	move.l	#HUNK_CODE,hd_Type(a5)
	move.l	lpi_Slot(sp,d6.l),a2	; [packed][memory][data]
	move.l	4(a2),d5		; d5 = memory size
	move.l	d5,hd_MemSize(a5)
	move.l	d5,d0
	bsr	HO_Alloc
	tst.l	d0
	beq	.nomem2
	move.l	d0,hd_Data(a5)
	move.l	d5,hd_DataAlloc(a5)
	move.l	d0,a1
	lea	8(a2),a0
	move.l	(a2),d0
	move.l	d5,d1
	move.l	d7,d2
	bsr	LP_Unpack
	bmi	.corrupt
	move.l	hd_Data(a5),a0
	move.l	d0,d4			; d4 = decoded length
	sub.l	a1,a1
	bsr	LP_Relocs
	bmi	.corrupt
	move.l	d0,hd_DataLen(a5)
	move.l	d1,hd_RelocLen(a5)
	beq.s	.next
	move.l	d1,d0
	bsr	HO_Alloc
	tst.l	d0
	beq.s	.nomem2
	move.l	d0,hd_Reloc(a5)
	move.l	d1,hd_RelocAlloc(a5)
	move.l	d0,a1
	move.l	hd_Data(a5),a0
	move.l	d4,d0
	bsr	LP_Relocs
.next	lea	HD_SIZEOF(a5),a5
	addq.l	#4,d6
	cmp.l	#8,d6
	bcs	.slot

	move.l	a3,a0
	moveq	#2,d0
	bsr	HO_Build
	move.l	d0,d2
	move.l	a3,a0
	moveq	#2,d0
	bsr	HO_FreeTable
	tst.l	d2
	beq.s	.exit
	clr.w	xfdbi_Error(a4)
	moveq	#1,d0
	bra.s	.exit
.nomem2	move.w	#XFDERR_NOMEMORY,xfdbi_Error(a4)
	bra.s	.free
.corrupt
	move.w	#XFDERR_CORRUPTEDDATA,xfdbi_Error(a4)
.free	move.l	a3,a0
	moveq	#2,d0
	bsr	HO_FreeTable
	bra.s	.fail
.nomem	move.w	#XFDERR_NOMEMORY,xfdbi_Error(a4)
.fail	moveq	#0,d0
.exit	lea	LPI_SIZEOF(sp),sp
	movem.l	(sp)+,d2-d7/a2-a6
	rts

;------------------------------------------------------------------------------
; Data files: recognition
RB_DataLZ4
	move.l	#"LPZ4",d1
	bra.s	RB_Data
RB_DataZX0
	move.l	#"LPX0",d1
	bra.s	RB_Data
RB_DataDeflate
	move.l	#"LPDE",d1
RB_Data	movem.l	d1-d2,-(sp)
	cmp.l	#16,d0
	bcs.s	.no
	cmp.l	(a0),d1
	bne.s	.no
	move.l	4(a0),d1		; decoded size
	beq.s	.no
	cmp.l	#$01000000,d1
	bcc.s	.no
	move.l	8(a0),d1		; packed size
	beq.s	.no
	add.l	#12,d1
	bcs.s	.no
	cmp.l	d0,d1
	bhi.s	.no
	moveq	#1,d0
	bra.s	.exit
.no	moveq	#0,d0
.exit	movem.l	(sp)+,d1-d2
	rts

; Data files: decrunching
DB_Data	movem.l	d2-d7/a2-a6,-(sp)
	move.l	a0,a4
	move.w	#XFDERR_NOMEMORY,xfdbi_Error(a4)
	move.l	xfdbi_SourceBuffer(a4),a2
	move.l	4(a2),d3		; decoded size
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
	moveq	#ALGO_LZ4,d2
	cmp.l	#"LPZ4",(a2)
	beq.s	.algo
	moveq	#ALGO_ZX0,d2
	cmp.l	#"LPX0",(a2)
	beq.s	.algo
	moveq	#ALGO_DEFLATE,d2
.algo	lea	12(a2),a0
	move.l	8(a2),d0
	move.l	d3,d1
	bsr	LP_Unpack
	bmi.s	.bad
	cmp.l	d3,d0
	bne.s	.bad
	clr.w	xfdbi_Error(a4)
	moveq	#1,d0
	bra.s	.exit
.bad	move.w	#XFDERR_CORRUPTEDDATA,xfdbi_Error(a4)
	move.l	xfdbi_TargetBuffer(a4),a1
	move.l	d3,d0
	bsr	HO_Free
	clr.l	xfdbi_TargetBuffer(a4)
.fail	moveq	#0,d0
.exit	movem.l	(sp)+,d2-d7/a2-a6
	rts

;------------------------------------------------------------------------------
	include	hunkout.i
	include	lz4zx0.i
	include	inflate.i
