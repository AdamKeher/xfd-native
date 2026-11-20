/*
 * xfd-native: Amiga constants and structure offsets.
 *
 * Offsets follow the 68k layout in xfdmaster.i (vendor/xfdmaster/m68k/
 * include/libraries/xfdmaster.i), because all structures live in emulated
 * big-endian 68k memory and are shared with the original 68k slave code.
 *
 * Copyright (C) 2026 the xfd-native authors.
 * SPDX-License-Identifier: LGPL-2.1-or-later
 */
#ifndef XFDN_AMIGA_H
#define XFDN_AMIGA_H

/* ---- exec -------------------------------------------------------------- */

#define MEMF_ANY     0x00000000u
#define MEMF_PUBLIC  0x00000001u
#define MEMF_CHIP    0x00000002u
#define MEMF_FAST    0x00000004u
#define MEMF_CLEAR   0x00010000u
#define MEMF_LARGEST 0x00020000u
#define MEMF_REVERSE 0x00040000u
#define MEMF_TOTAL   0x00080000u

#define LIB_VERSION   20 /* UWORD in struct Library */
#define LIB_REVISION  22
#define LIB_SIZE      34
#define EXEC_ATTNFLAGS 296 /* UWORD in struct ExecBase */
#define AFF_68010 (1u << 0)
#define AFF_68020 (1u << 1)

/* exec.library LVOs (vendor/xfdmaster/m68k/include/lvo/exec_lib.i) */
#define LVO_EXEC_SUPERVISOR     (-30)
#define LVO_EXEC_DISABLE        (-120)
#define LVO_EXEC_ENABLE         (-126)
#define LVO_EXEC_FORBID         (-132)
#define LVO_EXEC_PERMIT         (-138)
#define LVO_EXEC_SETSR          (-144)
#define LVO_EXEC_SUPERSTATE     (-150)
#define LVO_EXEC_USERSTATE      (-156)
#define LVO_EXEC_ALLOCMEM       (-198)
#define LVO_EXEC_FREEMEM        (-210)
#define LVO_EXEC_AVAILMEM       (-216)
#define LVO_EXEC_FINDTASK       (-294)
#define LVO_EXEC_SETSIGNAL      (-306)
#define LVO_EXEC_OLDOPENLIBRARY (-408)
#define LVO_EXEC_CLOSELIBRARY   (-414)
#define LVO_EXEC_TYPEOFMEM      (-534)
#define LVO_EXEC_OPENLIBRARY    (-552)
#define LVO_EXEC_COPYMEM        (-624)
#define LVO_EXEC_COPYMEMQUICK   (-630)
#define LVO_EXEC_CACHECLEARU    (-636)
#define LVO_EXEC_ALLOCVEC       (-684)
#define LVO_EXEC_FREEVEC        (-690)

/* dos.library LVOs (vendor/xfdmaster/m68k/include/lvo/dos_lib.i) */
#define LVO_DOS_READ      (-42)
#define LVO_DOS_SEEK      (-66)
#define LVO_DOS_IOERR     (-132)
#define LVO_DOS_UNLOADSEG (-156)

/* ---- dos hunks ---------------------------------------------------------- */

#define HUNK_NAME          1000
#define HUNK_CODE          1001
#define HUNK_DATA          1002
#define HUNK_BSS           1003
#define HUNK_RELOC32       1004
#define HUNK_SYMBOL        1008
#define HUNK_DEBUG         1009
#define HUNK_END           1010
#define HUNK_HEADER        1011
#define HUNK_OVERLAY       1013
#define HUNK_BREAK         1014
#define HUNK_DREL32        1015
#define HUNK_RELOC32SHORT  1020
#define HUNKF_CHIP (1u << 30)
#define HUNKF_FAST (1u << 31)

/* ---- xfdmaster.library ---------------------------------------------------- */

#define XFDM_VERSION 39
#define XFDF_ID 0x58464446u /* 'XFDF' */

/* struct xfdMasterBase (starts with a struct Library) */
#define XFDM_SEGLIST       34
#define XFDM_DOSBASE       38
#define XFDM_FIRSTSLAVE    42
#define XFDM_FIRSTFOREMAN  46
#define XFDM_MINBUFSIZE    50
#define XFDM_MINLINKERSIZE 54
#define XFDM_EXECBASE      58
#define XFDM_SIZEOF        62

/* struct xfdBufferInfo */
#define XFDBI_SOURCEBUFFER      0
#define XFDBI_SOURCEBUFLEN      4
#define XFDBI_SLAVE             8
#define XFDBI_PACKERNAME        12
#define XFDBI_PACKERFLAGS       16 /* UWORD */
#define XFDBI_ERROR             18 /* UWORD; also xfdbi_MaxSpecialLen */
#define XFDBI_MAXSPECIALLEN     18
#define XFDBI_TARGETBUFFER      20
#define XFDBI_TARGETBUFMEMTYPE  24
#define XFDBI_TARGETBUFLEN      28
#define XFDBI_TARGETBUFSAVELEN  32
#define XFDBI_DECRADDRESS       36
#define XFDBI_JMPADDRESS        40
#define XFDBI_SPECIAL           44
#define XFDBI_FLAGS             48 /* UWORD */
#define XFDBI_RESERVED0         50
#define XFDBI_MINTARGETLEN      52
#define XFDBI_FINALTARGETLEN    56
#define XFDBI_USERTARGETBUF     60
#define XFDBI_USERTARGETBUFLEN  64
#define XFDBI_MINSOURCELEN      68
#define XFDBI_SIZEOF            72

/* struct xfdSlave */
#define XFDS_NEXT            0
#define XFDS_VERSION         4  /* UWORD */
#define XFDS_MASTERVERSION   6  /* UWORD */
#define XFDS_PACKERNAME      8
#define XFDS_PACKERFLAGS     12 /* UWORD */
#define XFDS_MAXSPECIALLEN   14 /* UWORD */
#define XFDS_RECOGBUFFER     16
#define XFDS_DECRUNCHBUFFER  20
#define XFDS_RECOGSEGMENT    24
#define XFDS_DECRUNCHSEGMENT 28
#define XFDS_SLAVEID         32 /* UWORD, version >= 2 */
#define XFDS_REPLACEID       34 /* UWORD, version >= 2 */
#define XFDS_MINBUFFERSIZE   36 /* ULONG, version >= 2 */
#define XFDS_SIZEOF          40
#define XFDS_VERSION_MAX     2

/* struct xfdLinkerInfo */
#define XFDLI_BUFFER     0
#define XFDLI_BUFLEN     4
#define XFDLI_LINKERNAME 8
#define XFDLI_UNLINK     12
#define XFDLI_RESERVED   16 /* UWORD */
#define XFDLI_ERROR      18 /* UWORD */
#define XFDLI_HUNK1      20
#define XFDLI_HUNK2      24
#define XFDLI_AMOUNT1    28
#define XFDLI_AMOUNT2    32
#define XFDLI_SAVE1      36
#define XFDLI_SAVE2      40
#define XFDLI_SAVELEN1   44
#define XFDLI_SAVELEN2   48
#define XFDLI_SIZEOF     52

/* struct xfdForeMan (start of an external slave's first hunk) */
#define XFDF_SECURITY  0
#define XFDF_ID_OFS    4
#define XFDF_VERSION   8  /* UWORD */
#define XFDF_NEXT      12
#define XFDF_SEGLIST   16
#define XFDF_FIRSTSLAVE 20

/* struct xfdRecogResult */
#define XFDRR_MINTARGETLEN   0
#define XFDRR_FINALTARGETLEN 4
#define XFDRR_MINSOURCELEN   8
#define XFDRR_SIZEOF         12

/* xfd??_PackerFlags */
#define XFDPFF_RELOC      (1u << 0)
#define XFDPFF_ADDR       (1u << 1)
#define XFDPFF_DATA       (1u << 2)
#define XFDPFF_PASSWORD   (1u << 4)
#define XFDPFF_RELMODE    (1u << 5)
#define XFDPFF_KEY16      (1u << 6)
#define XFDPFF_KEY32      (1u << 7)
#define XFDPFF_RECOGLEN   (1u << 8)
#define XFDPFF_USERTARGET (1u << 9)
#define XFDPFF_EXTERN     (1u << 15)

/* xfd??_Flags */
#define XFDFF_RECOGEXTERN     (1u << 0)
#define XFDFF_RECOGTARGETLEN  (1u << 1)
#define XFDFF_RECOGUSERTARGET (1u << 2)
#define XFDFF_USERTARGET      (1u << 3)
#define XFDFF_MASTERALLOC     (1u << 4)

/* xfdTestHunkStructureFlags() */
#define XFDTHF_NOOVERLAYS (1u << 0)

/* relocation modes */
#define XFDREL_DEFAULT   0
#define XFDREL_FORCECHIP 1
#define XFDREL_FORCEFAST 2

/* xfdmaster.library LVOs (vendor/xfdmaster/m68k/include/lvo/xfdmaster_lib.i) */
#define LVO_XFD_ALLOCBUFFERINFO         (-30)
#define LVO_XFD_FREEBUFFERINFO          (-36)
#define LVO_XFD_ALLOCSEGMENTINFO        (-42)
#define LVO_XFD_FREESEGMENTINFO         (-48)
#define LVO_XFD_RECOGBUFFER             (-54)
#define LVO_XFD_DECRUNCHBUFFER          (-60)
#define LVO_XFD_RECOGSEGMENT            (-66)
#define LVO_XFD_DECRUNCHSEGMENT         (-72)
#define LVO_XFD_GETERRORTEXT            (-78)
#define LVO_XFD_TESTHUNKSTRUCTURE       (-84)
#define LVO_XFD_TESTHUNKSTRUCTURENEW    (-90)
#define LVO_XFD_RELOCATE                (-96)
#define LVO_XFD_TESTHUNKSTRUCTUREFLAGS  (-102)
#define LVO_XFD_STRIPHUNKS              (-108)
#define LVO_XFD_ALLOCOBJECT             (-114)
#define LVO_XFD_FREEOBJECT              (-120)
#define LVO_XFD_RECOGLINKER             (-126)
#define LVO_XFD_UNLINK                  (-132)

/* error codes */
#define XFDERR_OK                 0x0000
#define XFDERR_NOMEMORY           0x0001
#define XFDERR_NOSLAVE            0x0002
#define XFDERR_NOTSUPPORTED       0x0003
#define XFDERR_UNKNOWN            0x0004
#define XFDERR_NOSOURCE           0x0005
#define XFDERR_WRONGPASSWORD      0x0006
#define XFDERR_BADHUNK            0x0007
#define XFDERR_CORRUPTEDDATA      0x0008
#define XFDERR_MISSINGRESOURCE    0x0009
#define XFDERR_WRONGKEY           0x000a
#define XFDERR_BETTERCPU          0x000b
#define XFDERR_HOOKBREAK          0x000c
#define XFDERR_DOSERROR           0x000d
#define XFDERR_NOTARGET           0x000e
#define XFDERR_TARGETTOOSMALL     0x000f
#define XFDERR_TARGETNOTSUPPORTED 0x0010
#define XFDERR_UNDEFINEDHUNK      0x1000
#define XFDERR_NOHUNKHEADER       0x1001
#define XFDERR_BADEXTTYPE         0x1002
#define XFDERR_BUFFERTRUNCATED    0x1003
#define XFDERR_WRONGHUNKAMOUNT    0x1004
#define XFDERR_NOOVERLAYS         0x1005
#define XFDERR_UNSUPPORTEDHUNK    0x2000
#define XFDERR_BADRELMODE         0x2001

#endif
