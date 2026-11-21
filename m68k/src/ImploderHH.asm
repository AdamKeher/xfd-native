;
; ImploderHH.asm - xfd external slave for executables packed by hitchhikr's
; Imploder 1.2-1.4d (https://github.com/hitchhikr/imploder, 2026)
;
; The packed file is an overlay executable. Its one loaded hunk is the
; depacker (an overlay manager: $ABCD in its second longword, then
; "Overlay"), followed by HUNK_END, HUNK_OVERLAY with an empty table and
; HUNK_BREAK. The depacker reads the rest of the file itself:
;   number of hunks - 1
;   per hunk: relocation offset (-1: BSS), allocation size (+12),
;             AllocMem flags, packed size (-1: BSS)
;   per non-BSS hunk: an Imploder "IMP!" stream, padded to a longword
; A stream decodes to the hunk's contents (as long as its memory size),
; followed by the hunk's HUNK_RELOC32 block without the hunk ID:
; [count][target hunk][offsets...] ... [0]. The streams are classic Imploder
; data, so this slave hands each one to xfdmaster's "Imploder Data" slave.
;
; Every non-BSS hunk comes back as HUNK_CODE, because the file does not
; record whether a hunk was code or data. Contents, memory sizes, memory
; types and relocations are exact.
;
; Copyright (C) 2026 the xfd-native authors
; SPDX-License-Identifier: LGPL-2.1-or-later
;

	include	exec/types.i
	include	exec/memory.i
	include	dos/doshunks.i
	include	libraries/xfdmaster.i
	include	lvo/exec_lib.i
	include	lvo/xfdmaster_lib.i

MAXDEPACKER	= 1024			; longwords; the depacker is about 180
MAXHUNKS	= 1024

ForeMan	dc.l	$70FF4E75,XFDF_ID
	dc.w	XFDF_VERSION
	dcb.w	5,0
	dc.l	S_Exe

S_Exe	dc.l	0
	dc.w	2,39
	dc.l	N_Exe
	dc.w	XFDPFF_RELOC,0
	dc.l	RB_Exe,DB_Exe,0,0
	dc.w	0,0
	dc.l	128

N_Exe	dc.b	"Imploder (hitchhikr)",0
	dc.b	"$VER: ImploderHH 1.0 (21.11.2026) xfd-native",0
	even

; one entry of the file's hunk table
ht_Reloc	= 0
ht_Alloc	= 4
ht_Flags	= 8
ht_Packed	= 12
HT_SIZEOF	= 16

;------------------------------------------------------------------------------
; HH_Header: check the file layout.
;   a0 = buffer, d0.l = length
; Out: d0.l = number of hunks, or 0 if this is not such a file (Z set);
;      a1 = hunk table, a2 = first packed stream
HH_Header
	movem.l	d1-d4/a0/a3-a4,-(sp)
	lea	(a0,d0.l),a3		; a3 = end of file
	cmp.l	#36+16+4,d0
	bcs	.fail
	cmp.l	#HUNK_HEADER,(a0)
	bne	.fail
	tst.l	4(a0)			; no resident libraries
	bne	.fail
	cmp.l	#2,8(a0)		; two hunks: depacker and a dummy
	bne	.fail
	tst.l	12(a0)
	bne	.fail
	cmp.l	#1,16(a0)
	bne	.fail
	tst.l	24(a0)			; dummy hunk size 0
	bne	.fail
	move.l	20(a0),d1		; depacker size in longwords
	beq	.fail
	cmp.l	#MAXDEPACKER,d1
	bhi	.fail
	cmp.l	#HUNK_CODE,28(a0)
	bne	.fail
	cmp.l	32(a0),d1
	bne	.fail
	lea	36(a0),a4		; a4 = depacker
	lsl.l	#2,d1
	cmp.l	#40,d1
	bcs	.fail
	cmp.l	#$0000abcd,4(a4)	; overlay manager magic
	bne	.fail
	cmp.l	#$074f7665,28(a4)	; 7,"Overlay"
	bne	.fail
	cmp.l	#"rlay",32(a4)
	bne	.fail
	add.l	d1,a4			; after the depacker
	lea	20(a4),a1
	cmp.l	a3,a1
	bhi	.fail
	cmp.l	#HUNK_END,(a4)+
	bne	.fail
	cmp.l	#HUNK_OVERLAY,(a4)+
	bne	.fail
	tst.l	(a4)+			; empty overlay table
	bne	.fail
	cmp.l	#HUNK_BREAK,(a4)+
	bne	.fail
	move.l	(a4)+,d2		; number of hunks - 1
	cmp.l	#MAXHUNKS-1,d2
	bhi	.fail
	addq.l	#1,d2			; d2 = number of hunks
	move.l	a4,a1			; a1 = hunk table
	move.l	d2,d0
	lsl.l	#4,d0
	lea	(a4,d0.l),a2		; a2 = first stream
	cmp.l	a3,a2
	bhi	.fail

	; check every entry, and that each stream is an IMP! stream that
	; decodes to the allocation size - 12
	move.l	a2,a0
	move.l	d2,d3
.entry	move.l	ht_Flags(a4),d0
	cmp.l	#MEMF_PUBLIC!MEMF_CLEAR,d0
	beq.s	.flagok
	cmp.l	#MEMF_CHIP!MEMF_CLEAR,d0
	beq.s	.flagok
	cmp.l	#MEMF_FAST!MEMF_CLEAR,d0
	bne	.fail
.flagok	move.l	ht_Alloc(a4),d4
	sub.l	#12,d4			; d4 = decoded size (or BSS size)
	bcs	.fail
	move.l	d4,d0
	and.l	#3,d0
	bne	.fail
	move.l	ht_Packed(a4),d1
	cmp.l	#-1,d1
	bne.s	.packed
	cmp.l	#-1,ht_Reloc(a4)	; BSS
	bne	.fail
	bra.s	.next
.packed	move.l	ht_Reloc(a4),d0		; memory size
	cmp.l	d4,d0
	bhi	.fail
	and.l	#3,d0
	bne	.fail
	tst.l	d1
	beq	.fail
	move.l	d1,d0
	and.l	#3,d0
	bne	.fail
	move.l	a3,d0
	sub.l	a0,d0
	cmp.l	d0,d1
	bhi	.fail
	cmp.l	#12+4+$2e,d1
	bcs	.fail
	cmp.l	#"IMP!",(a0)
	bne	.fail
	cmp.l	4(a0),d4
	bne	.fail
	add.l	d1,a0
.next	lea	HT_SIZEOF(a4),a4
	subq.l	#1,d3
	bne	.entry
	move.l	d2,d0
	bra.s	.exit
.fail	moveq	#0,d0
.exit	movem.l	(sp)+,d1-d4/a0/a3-a4
	tst.l	d0
	rts

;------------------------------------------------------------------------------
RB_Exe	movem.l	a1-a2,-(sp)
	bsr	HH_Header
	movem.l	(sp)+,a1-a2
	sne	d0
	and.l	#1,d0
	rts

;------------------------------------------------------------------------------
; HH_Explode: decode one IMP! stream with xfdmaster's "Imploder Data" slave.
;   a0 = stream, d0.l = length, d1.l = expected decoded size,
;   a6 = xfdmaster base
; Out: d0 = decoded buffer, or 0 (Z set) with the xfdbi error code in d2;
;      d1 = size of the buffer's allocation (free it with FreeMem)
HH_Explode
	movem.l	d3-d4/a0-a3,-(sp)
	move.l	a0,a2
	move.l	d0,d3
	move.l	d1,d4
	moveq	#XFDERR_NOMEMORY,d2
	jsr	_LVOxfdAllocBufferInfo(a6)
	tst.l	d0
	beq	.fail
	move.l	d0,a3
	moveq	#XFDERR_CORRUPTEDDATA,d2
	move.l	a2,xfdbi_SourceBuffer(a3)
	move.l	d3,xfdbi_SourceBufLen(a3)
	move.l	#MEMF_PUBLIC,xfdbi_TargetBufMemType(a3)
	move.l	a3,a0
	jsr	_LVOxfdRecogBuffer(a6)
	tst.l	d0
	beq.s	.freebi
	move.l	xfdbi_Slave(a3),a0
	cmp.w	#XFDID_FileImploder,xfds_SlaveID(a0)
	bne.s	.freebi
	move.l	a3,a0
	jsr	_LVOxfdDecrunchBuffer(a6)
	tst.l	d0
	bne.s	.done
	move.w	xfdbi_Error(a3),d2
	bra.s	.freebi
.done	move.l	xfdbi_TargetBuffer(a3),d0
	move.l	xfdbi_TargetBufLen(a3),d1
	cmp.l	xfdbi_TargetBufSaveLen(a3),d4
	beq.s	.ok
	move.l	d0,a1			; wrong size
	move.l	d1,d0
	move.l	a6,-(sp)
	move.l	xfdm_ExecBase(a6),a6
	jsr	_LVOFreeMem(a6)
	move.l	(sp)+,a6
.freebi	move.l	a3,a1
	jsr	_LVOxfdFreeBufferInfo(a6)
.fail	moveq	#0,d0
	bra.s	.exit
.ok	movem.l	d0-d1,-(sp)
	move.l	a3,a1
	jsr	_LVOxfdFreeBufferInfo(a6)
	movem.l	(sp)+,d0-d1
.exit	movem.l	(sp)+,d3-d4/a0-a3
	tst.l	d0
	rts

;------------------------------------------------------------------------------
; HH_Relocs: check a hunk's relocation block.
;   a0 = block, d0.l = bytes available, d1.l = hunk memory size,
;   d2.l = number of hunks
; Out: d0.l = bytes of groups without the final 0, or -1 (N set)
HH_Relocs
	movem.l	d1-d5/a0-a3,-(sp)
	move.l	a0,a1
	lea	(a0,d0.l),a2		; a2 = end
	subq.l	#4,d1			; highest offset
.group	lea	4(a0),a3
	cmp.l	a2,a3
	bhi.s	.bad
	move.l	(a0)+,d3		; count
	beq.s	.end
	lea	4(a0),a3
	cmp.l	a2,a3
	bhi.s	.bad
	move.l	(a0)+,d4		; target hunk
	cmp.l	d2,d4
	bcc.s	.bad
	move.l	d3,d5
	lsl.l	#2,d5
	bcs.s	.bad
	move.l	a2,d4
	sub.l	a0,d4
	cmp.l	d4,d5
	bhi.s	.bad
.off	move.l	(a0)+,d4
	cmp.l	d1,d4
	bhi.s	.bad
	subq.l	#1,d3
	bne.s	.off
	bra.s	.group
.end	move.l	a0,d0
	sub.l	a1,d0
	subq.l	#4,d0
	bra.s	.exit
.bad	moveq	#-1,d0
.exit	movem.l	(sp)+,d1-d5/a0-a3
	tst.l	d0
	rts

;------------------------------------------------------------------------------
DB_Exe	movem.l	d2-d7/a2-a6,-(sp)
	move.l	a0,a4			; a4 = xfdBufferInfo
	sub.l	a3,a3
	move.w	#XFDERR_CORRUPTEDDATA,xfdbi_Error(a4)
	move.l	xfdbi_SourceBuffer(a4),a0
	move.l	xfdbi_SourceBufLen(a4),d0
	bsr	HH_Header
	beq	.fail
	move.l	d0,d7			; d7 = number of hunks
	move.l	a1,d6			; d6 = hunk table
	move.l	a2,d5			; d5 = next stream
	move.l	d7,d0
	bsr	HO_AllocTable
	beq	.nomem
	move.l	a0,a3
	move.l	a3,a5			; a5 = descriptor
	move.l	d7,d4			; d4 = hunks left
.hunk	move.l	d6,a2			; a2 = table entry
	moveq	#0,d0
	move.l	ht_Flags(a2),d1
	btst	#MEMB_CHIP,d1
	beq.s	.notchip
	move.l	#HUNKF_CHIP_L,d0
.notchip
	btst	#MEMB_FAST,d1
	beq.s	.notfast
	move.l	#HUNKF_FAST_L,d0
.notfast
	move.l	d0,hd_MemFlags(a5)
	move.l	ht_Alloc(a2),d3
	sub.l	#12,d3			; d3 = decoded size
	cmp.l	#-1,ht_Packed(a2)
	bne.s	.packed
	move.l	#HUNK_BSS,hd_Type(a5)
	move.l	d3,hd_MemSize(a5)
	bra.s	.next
.packed	move.l	#HUNK_CODE,hd_Type(a5)
	move.l	ht_Reloc(a2),hd_MemSize(a5)
	move.l	d5,a0
	move.l	ht_Packed(a2),d0
	add.l	d0,d5
	move.l	d3,d1
	bsr	HH_Explode
	beq	.error
	move.l	d0,hd_Data(a5)
	move.l	d1,hd_DataAlloc(a5)
	move.l	hd_MemSize(a5),d1
	move.l	d1,hd_DataLen(a5)
	beq.s	.norel			; (an empty hunk has no room for relocs)
	move.l	d0,a0
	add.l	d1,a0			; the relocation block follows the data
	move.l	d3,d0
	sub.l	d1,d0
	beq.s	.norel			; the hunk had no HUNK_RELOC32
	move.l	d7,d2
	bsr	HH_Relocs
	bmi.s	.corrupt
	move.l	a0,hd_Reloc(a5)
	move.l	d0,hd_RelocLen(a5)
.norel
.next	add.l	#HT_SIZEOF,d6
	lea	HD_SIZEOF(a5),a5
	subq.l	#1,d4
	bne	.hunk

	move.l	a3,a0
	move.l	d7,d0
	bsr	HO_Build
	move.l	d0,d2
	move.l	a3,a0
	move.l	d7,d0
	bsr	HO_FreeTable
	tst.l	d2
	beq.s	.fail
	clr.w	xfdbi_Error(a4)
	moveq	#1,d0
	bra.s	.exit
.error	move.w	d2,xfdbi_Error(a4)
	bra.s	.free
.corrupt
	move.w	#XFDERR_CORRUPTEDDATA,xfdbi_Error(a4)
.free	move.l	a3,a0
	move.l	d7,d0
	bsr	HO_FreeTable
	bra.s	.fail
.nomem	move.w	#XFDERR_NOMEMORY,xfdbi_Error(a4)
.fail	moveq	#0,d0
.exit	movem.l	(sp)+,d2-d7/a2-a6
	rts

;------------------------------------------------------------------------------
	include	hunkout.i
