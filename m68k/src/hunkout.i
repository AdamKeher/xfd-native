;
; hunkout.i - shared code for xfd-native's own external slaves
;
; Memory helpers, and HO_Build, which writes a hunk executable from a table
; of decoded hunks. Plain 68000 code: the slaves also work with the real
; xfdmaster.library on an Amiga.
;
; Copyright (C) 2026 the xfd-native authors
; SPDX-License-Identifier: LGPL-2.1-or-later
;

; Hunk descriptor, one per output hunk.
hd_Type		= 0		; HUNK_CODE, HUNK_DATA or HUNK_BSS
hd_MemFlags	= 4		; 0, HUNKF_CHIP or HUNKF_FAST (hunk header bits)
hd_MemSize	= 8		; bytes
hd_Data		= 12		; decoded data
hd_DataLen	= 16		; bytes of data to write (padded to longwords)
hd_Reloc	= 20		; HUNK_RELOC32 groups (count, hunk, offsets...)
hd_RelocLen	= 24		; bytes in hd_Reloc, without the final 0
hd_DataAlloc	= 28		; size of the hd_Data allocation (0: not ours)
hd_RelocAlloc	= 32		; size of the hd_Reloc allocation (0: not ours)
hd_P0		= 36		; private to the slave
hd_P1		= 40
hd_P2		= 44
hd_P3		= 48
hd_P4		= 52
HD_SIZEOF	= 56

HUNKF_CHIP_L	= $40000000
HUNKF_FAST_L	= $80000000

;------------------------------------------------------------------------------
; HO_Alloc: d0.l = size -> d0.l = cleared memory or 0. a6 = xfdmaster base.
; Preserves all other registers.
HO_Alloc
	movem.l	d1/a0-a1/a6,-(sp)
	move.l	#MEMF_PUBLIC!MEMF_CLEAR,d1
	move.l	xfdm_ExecBase(a6),a6
	jsr	_LVOAllocMem(a6)
	movem.l	(sp)+,d1/a0-a1/a6
	rts

; HO_Free: a1 = memory (may be 0), d0.l = size. a6 = xfdmaster base.
; Preserves all registers.
HO_Free
	movem.l	d0-d1/a0-a1/a6,-(sp)
	move.l	a1,d1
	beq.s	.none
	move.l	xfdm_ExecBase(a6),a6
	jsr	_LVOFreeMem(a6)
.none	movem.l	(sp)+,d0-d1/a0-a1/a6
	rts

;------------------------------------------------------------------------------
; HO_AllocTable: d0.l = number of hunks -> a0 = cleared descriptor table, or
; 0 (Z set). a6 = xfdmaster base.
HO_AllocTable
	move.l	d0,-(sp)
	mulu.w	#HD_SIZEOF,d0
	bsr.s	HO_Alloc
	move.l	d0,a0
	move.l	(sp)+,d0
	cmp.w	#0,a0
	rts

; HO_FreeTable: a0 = descriptor table (may be 0), d0.l = number of hunks.
; Frees the table and every buffer marked as ours. a6 = xfdmaster base.
HO_FreeTable
	movem.l	d0-d2/a0-a2,-(sp)
	move.l	a0,d1
	beq.s	.done
	move.l	a0,a2
	move.l	d0,d2
	beq.s	.table
.hunk	move.l	hd_Data(a2),a1
	move.l	hd_DataAlloc(a2),d0
	beq.s	.nodata
	bsr.s	HO_Free
.nodata	move.l	hd_Reloc(a2),a1
	move.l	hd_RelocAlloc(a2),d0
	beq.s	.norel
	bsr.s	HO_Free
.norel	lea	HD_SIZEOF(a2),a2
	subq.l	#1,d2
	bne.s	.hunk
.table	move.l	(sp),d0
	mulu.w	#HD_SIZEOF,d0
	move.l	12(sp),a1
	bsr	HO_Free
.done	movem.l	(sp)+,d0-d2/a0-a2
	rts

;------------------------------------------------------------------------------
; HO_Build: write the hunk executable into a new target buffer.
;   a0 = descriptor table, d0.l = number of hunks, a4 = xfdBufferInfo,
;   a6 = xfdmaster base
; Out: d0 = 1, or 0 with xfdbi_Error set.
HO_Build
	movem.l	d2-d4/a2-a3,-(sp)
	move.l	a0,a2
	move.l	d0,d2

	; size: header (5 longs + sizes), then per hunk type, length, data,
	; relocs and HUNK_END
	move.l	d2,d1
	lsl.l	#2,d1
	add.l	#20,d1
	move.l	a2,a0
	move.l	d2,d3
.size	add.l	#12,d1
	cmp.l	#HUNK_BSS,hd_Type(a0)
	beq.s	.sznext
	move.l	hd_DataLen(a0),d0
	addq.l	#3,d0
	and.b	#$fc,d0
	add.l	d0,d1
	move.l	hd_RelocLen(a0),d0
	beq.s	.sznext
	addq.l	#8,d0
	add.l	d0,d1
.sznext	lea	HD_SIZEOF(a0),a0
	subq.l	#1,d3
	bne.s	.size

	move.l	d1,d4
	move.l	d1,d0
	move.l	xfdbi_TargetBufMemType(a4),d1
	move.l	a6,-(sp)
	move.l	xfdm_ExecBase(a6),a6
	jsr	_LVOAllocMem(a6)
	move.l	(sp)+,a6
	tst.l	d0
	beq	.nomem
	move.l	d0,xfdbi_TargetBuffer(a4)
	move.l	d4,xfdbi_TargetBufLen(a4)
	move.l	d4,xfdbi_TargetBufSaveLen(a4)
	move.l	d0,a1

	move.l	#HUNK_HEADER,(a1)+
	clr.l	(a1)+
	move.l	d2,(a1)+
	clr.l	(a1)+
	move.l	d2,d0
	subq.l	#1,d0
	move.l	d0,(a1)+
	move.l	a2,a0
	move.l	d2,d3
.sizes	move.l	hd_MemSize(a0),d0
	addq.l	#3,d0
	lsr.l	#2,d0
	or.l	hd_MemFlags(a0),d0
	move.l	d0,(a1)+
	lea	HD_SIZEOF(a0),a0
	subq.l	#1,d3
	bne.s	.sizes

	move.l	a2,a3
	move.l	d2,d3
.hunk	move.l	hd_Type(a3),d0
	move.l	d0,(a1)+
	cmp.l	#HUNK_BSS,d0
	bne.s	.data
	move.l	hd_MemSize(a3),d0
	addq.l	#3,d0
	lsr.l	#2,d0
	move.l	d0,(a1)+
	bra.s	.end

.data	move.l	hd_DataLen(a3),d1
	move.l	d1,d0
	addq.l	#3,d0
	lsr.l	#2,d0
	move.l	d0,(a1)+
	move.l	hd_Data(a3),a0
	tst.l	d1
	beq.s	.pad
.copy	move.b	(a0)+,(a1)+
	subq.l	#1,d1
	bne.s	.copy
.pad	move.w	a1,d0
	and.w	#3,d0
	beq.s	.relocs
	clr.b	(a1)+
	bra.s	.pad
.relocs	move.l	hd_RelocLen(a3),d1
	beq.s	.end
	move.l	#HUNK_RELOC32,(a1)+
	move.l	hd_Reloc(a3),a0
	lsr.l	#2,d1
.rcopy	move.l	(a0)+,(a1)+
	subq.l	#1,d1
	bne.s	.rcopy
	clr.l	(a1)+
.end	move.l	#HUNK_END,(a1)+
	lea	HD_SIZEOF(a3),a3
	subq.l	#1,d3
	bne.s	.hunk
	moveq	#1,d0
.exit	movem.l	(sp)+,d2-d4/a2-a3
	rts
.nomem	move.w	#XFDERR_NOMEMORY,xfdbi_Error(a4)
	moveq	#0,d0
	bra.s	.exit
