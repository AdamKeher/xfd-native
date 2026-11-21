/*
 * xfd-native: a minimal AmigaOS environment around the Musashi 68k core.
 *
 * Provides 16 MB of flat big-endian memory (68EC020, 24-bit bus), an
 * exec-style memory allocator, stub exec/dos/xfdmaster/xpkmaster library
 * bases whose jump tables trap into C, and a nestable "call this 68k
 * function" helper.
 *
 * Copyright (C) 2026 the xfd-native authors.
 * SPDX-License-Identifier: LGPL-2.1-or-later
 */
#ifndef XFDN_EMU_H
#define XFDN_EMU_H

#include <stddef.h>
#include <stdint.h>

/* ---- memory map ----------------------------------------------------------- */

#define EMU_MEM_SIZE   0x01000000u /* 16 MB: the whole 24-bit address space */
#define EMU_ADDR_MASK  0x00ffffffu

#define EMU_VEC_TRAPS  0x00000400u /* 256 x ILLEGAL, one per exception vector */
#define EMU_STOP_TRAP  0x00000600u /* return address for host -> 68k calls */
#define EMU_EXEC_BASE  0x00002000u
#define EMU_DOS_BASE   0x00003000u
#define EMU_XFD_BASE   0x00003800u
#define EMU_XPK_BASE   0x00003f00u /* xpkmaster.library, if a handler is set */
#define EMU_SCRATCH    0x00004000u /* static strings etc., up to EMU_BLOB */
#define EMU_BLOB       0x00010000u /* internal slave blob is loaded here */
#define EMU_HEAP_LOW   0x00040000u /* heap: EMU_HEAP_LOW .. EMU_STACK_LOW */
#define EMU_STACK_LOW  0x00f00000u
#define EMU_STACK_TOP  0x00fffff0u

extern uint8_t *emu_mem;

static inline uint32_t emu_r8(uint32_t a) { return emu_mem[a & EMU_ADDR_MASK]; }
static inline uint32_t emu_r16(uint32_t a)
{
	return ((uint32_t)emu_r8(a) << 8) | emu_r8(a + 1);
}
static inline uint32_t emu_r32(uint32_t a)
{
	return (emu_r16(a) << 16) | emu_r16(a + 2);
}
static inline void emu_w8(uint32_t a, uint32_t v) { emu_mem[a & EMU_ADDR_MASK] = (uint8_t)v; }
static inline void emu_w16(uint32_t a, uint32_t v)
{
	emu_w8(a, v >> 8);
	emu_w8(a + 1, v);
}
static inline void emu_w32(uint32_t a, uint32_t v)
{
	emu_w16(a, v >> 16);
	emu_w16(a + 2, v);
}

/* Copy between host and emulated memory (handles wrap at 16 MB). */
void emu_write_block(uint32_t addr, const void *src, size_t len);
void emu_read_block(void *dst, uint32_t addr, size_t len);
/* Copy a NUL-terminated string out of emulated memory. */
void emu_read_string(char *dst, size_t dstlen, uint32_t addr);
/* Place a constant string in the scratch area; returns its 68k address. */
uint32_t emu_static_string(const char *s);

/* ---- registers -------------------------------------------------------------- */

enum { EMU_D0 = 0, EMU_A0 = 8, EMU_A6 = 14, EMU_A7 = 15 };

typedef struct {
	uint32_t r[16]; /* D0-D7, A0-A7 */
} emu_regs_t;

uint32_t emu_get_reg(int r);
void emu_set_reg(int r, uint32_t v);

/* ---- heap (exec AllocMem / FreeMem semantics) ------------------------------- */

uint32_t emu_alloc(uint32_t size, uint32_t flags); /* 0 on failure */
void emu_free(uint32_t addr);                       /* size is tracked */
uint32_t emu_avail(uint32_t flags);
/* Snapshot the heap (after loading slaves) and roll back to it per file. */
void emu_heap_checkpoint(void);
void emu_heap_rollback(void);

/* ---- calls ------------------------------------------------------------------ */

enum emu_abort {
	EMU_OK = 0,
	EMU_ABORT_TIMEOUT,     /* ran past the cycle budget */
	EMU_ABORT_EXCEPTION,   /* CPU exception (address error, illegal, ...) */
	EMU_ABORT_UNSUPPORTED, /* call to an OS function we do not provide */
};

/*
 * Call the 68k function at pc with the given registers (A7 is ignored; a
 * stack frame is set up automatically). On return regs holds the final
 * register values. Calls may nest: a 68k slave can call an xfdmaster LVO
 * which in turn calls into 68k code again.
 * Returns EMU_OK, or the reason the call was aborted.
 */
int emu_call(uint32_t pc, emu_regs_t *regs);

/* Describe the last abort (static buffer). */
const char *emu_abort_text(void);
/* Number of 68k calls currently in progress (0 = called from the host). */
int emu_depth(void);

/* Handler for xfdmaster.library LVOs, called with the CPU stopped on the
 * trap. It reads arguments with emu_get_reg() and stores the result with
 * emu_set_reg(EMU_D0, ...). Return 0 if the LVO is not implemented. */
typedef int (*emu_lvo_handler)(int lvo);
void emu_set_xfd_handler(emu_lvo_handler h);
/* The same for xpkmaster.library. Without a handler OpenLibrary() fails. */
void emu_set_xpk_handler(emu_lvo_handler h);

/* Initialise memory, CPU and the library bases. */
int emu_init(void);
/* Limits for one top-level emu_call(): CPU cycles and wall-clock seconds. */
void emu_set_limits(uint64_t cycles, double seconds);
void emu_set_trace(int on);
int emu_trace_enabled(void);

#endif
