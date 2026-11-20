/*
 * xfd-native: a minimal AmigaOS environment around the Musashi 68k core.
 * See emu.h for the overview.
 *
 * Copyright (C) 2026 the xfd-native authors.
 * SPDX-License-Identifier: LGPL-2.1-or-later
 */
#include "emu.h"

#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#include "amiga.h"
#include "m68k.h"

uint8_t *emu_mem;

#define OP_ILLEGAL 0x4afc
#define OP_RTS     0x4e75
#define OP_NOP     0x4e71

#define EXEC_TABLE_LOW (EMU_EXEC_BASE - 0x1000u)
#define DOS_TABLE_LOW  (EMU_DOS_BASE - 0x0600u)
#define XFD_TABLE_LOW  (EMU_XFD_BASE - 0x0400u)
#define TASK_STRUCT    EMU_SCRATCH            /* zeroed fake Process for FindTask */
#define STRINGS_LOW    (EMU_SCRATCH + 0x400u) /* emu_static_string() area */

#define MAX_DEPTH 32
#define SLICE_CYCLES 200000

static int trace;
static int depth;
static int stopped[MAX_DEPTH + 1];
static int abort_code;
static char abort_msg[256];
static uint64_t cycle_budget = 4000000000ull; /* ~10 minutes of a 7 MHz 68000 */
static double time_budget = 120.0;
static uint64_t used_cycles;
static clock_t call_started;
static emu_lvo_handler xfd_handler;
static uint32_t strings_next = STRINGS_LOW;

/* ---- Musashi memory interface ----------------------------------------------- */

unsigned int m68k_read_memory_8(unsigned int a) { return emu_r8(a); }
unsigned int m68k_read_memory_16(unsigned int a) { return emu_r16(a); }
unsigned int m68k_read_memory_32(unsigned int a) { return emu_r32(a); }
unsigned int m68k_read_disassembler_8(unsigned int a) { return emu_r8(a); }
unsigned int m68k_read_disassembler_16(unsigned int a) { return emu_r16(a); }
unsigned int m68k_read_disassembler_32(unsigned int a) { return emu_r32(a); }
void m68k_write_memory_8(unsigned int a, unsigned int v) { emu_w8(a, v); }
void m68k_write_memory_16(unsigned int a, unsigned int v) { emu_w16(a, v); }
void m68k_write_memory_32(unsigned int a, unsigned int v) { emu_w32(a, v); }

void emu_write_block(uint32_t addr, const void *src, size_t len)
{
	const uint8_t *s = src;
	addr &= EMU_ADDR_MASK;
	if (addr + len <= EMU_MEM_SIZE) {
		memcpy(emu_mem + addr, s, len);
		return;
	}
	for (size_t i = 0; i < len; i++) emu_w8(addr + (uint32_t)i, s[i]);
}

void emu_read_block(void *dst, uint32_t addr, size_t len)
{
	uint8_t *d = dst;
	addr &= EMU_ADDR_MASK;
	if (addr + len <= EMU_MEM_SIZE) {
		memcpy(d, emu_mem + addr, len);
		return;
	}
	for (size_t i = 0; i < len; i++) d[i] = (uint8_t)emu_r8(addr + (uint32_t)i);
}

void emu_read_string(char *dst, size_t dstlen, uint32_t addr)
{
	size_t i = 0;
	if (dstlen == 0) return;
	for (; i + 1 < dstlen; i++) {
		char c = (char)emu_r8(addr + (uint32_t)i);
		if (c == '\0') break;
		dst[i] = c;
	}
	dst[i] = '\0';
}

uint32_t emu_static_string(const char *s)
{
	size_t len = strlen(s) + 1;
	uint32_t a = strings_next;
	if (a + len > EMU_BLOB) return 0;
	emu_write_block(a, s, len);
	strings_next = (uint32_t)((a + len + 1) & ~1u);
	return a;
}

/* Overlap-safe copy inside emulated memory (exec CopyMem). */
static void emu_copy(uint32_t dst, uint32_t src, uint32_t len)
{
	dst &= EMU_ADDR_MASK;
	src &= EMU_ADDR_MASK;
	if ((uint64_t)dst + len <= EMU_MEM_SIZE && (uint64_t)src + len <= EMU_MEM_SIZE) {
		memmove(emu_mem + dst, emu_mem + src, len);
		return;
	}
	if (dst < src) {
		for (uint32_t i = 0; i < len; i++) emu_w8(dst + i, emu_r8(src + i));
	} else {
		for (uint32_t i = len; i-- > 0;) emu_w8(dst + i, emu_r8(src + i));
	}
}

/* ---- registers ---------------------------------------------------------------- */

uint32_t emu_get_reg(int r) { return m68k_get_reg(NULL, (m68k_register_t)(M68K_REG_D0 + r)); }
void emu_set_reg(int r, uint32_t v) { m68k_set_reg((m68k_register_t)(M68K_REG_D0 + r), v); }

/* ---- heap ------------------------------------------------------------------------ */

typedef struct {
	uint32_t addr, size;
} span_t;

typedef struct {
	span_t *v;
	size_t n, cap;
} spans_t;

static spans_t free_spans, used_spans, ck_free, ck_used;

static void spans_insert(spans_t *s, size_t i, span_t x)
{
	if (s->n == s->cap) {
		s->cap = s->cap ? s->cap * 2 : 256;
		s->v = realloc(s->v, s->cap * sizeof(span_t));
		if (!s->v) {
			fputs("xfd-native: out of host memory\n", stderr);
			exit(20);
		}
	}
	memmove(s->v + i + 1, s->v + i, (s->n - i) * sizeof(span_t));
	s->v[i] = x;
	s->n++;
}

static void spans_remove(spans_t *s, size_t i)
{
	memmove(s->v + i, s->v + i + 1, (s->n - i - 1) * sizeof(span_t));
	s->n--;
}

static void spans_copy(spans_t *dst, const spans_t *src)
{
	if (dst->cap < src->n) {
		dst->cap = src->n;
		dst->v = realloc(dst->v, dst->cap * sizeof(span_t));
		if (!dst->v) {
			fputs("xfd-native: out of host memory\n", stderr);
			exit(20);
		}
	}
	if (src->n) memcpy(dst->v, src->v, src->n * sizeof(span_t));
	dst->n = src->n;
}

/* First index with v[i].addr >= addr */
static size_t spans_lower(const spans_t *s, uint32_t addr)
{
	size_t lo = 0, hi = s->n;
	while (lo < hi) {
		size_t mid = (lo + hi) / 2;
		if (s->v[mid].addr < addr) lo = mid + 1;
		else hi = mid;
	}
	return lo;
}

uint32_t emu_alloc(uint32_t size, uint32_t flags)
{
	uint32_t need, addr = 0;
	size_t i;

	if (size == 0 || size > EMU_MEM_SIZE) return 0;
	need = (size + 7u) & ~7u;

	if (flags & MEMF_REVERSE) {
		for (i = free_spans.n; i-- > 0;) {
			span_t *f = &free_spans.v[i];
			if (f->size >= need) {
				f->size -= need;
				addr = f->addr + f->size;
				if (f->size == 0) spans_remove(&free_spans, i);
				break;
			}
		}
	} else {
		for (i = 0; i < free_spans.n; i++) {
			span_t *f = &free_spans.v[i];
			if (f->size >= need) {
				addr = f->addr;
				f->addr += need;
				f->size -= need;
				if (f->size == 0) spans_remove(&free_spans, i);
				break;
			}
		}
	}
	if (addr == 0) return 0;

	spans_insert(&used_spans, spans_lower(&used_spans, addr), (span_t){addr, need});
	/* Always clear, so output never depends on leftover memory contents. */
	memset(emu_mem + addr, 0, need);
	return addr;
}

void emu_free(uint32_t addr)
{
	size_t i = spans_lower(&used_spans, addr);
	span_t blk;

	if (addr == 0) return;
	if (i >= used_spans.n || used_spans.v[i].addr != addr) {
		if (trace) fprintf(stderr, "[emu] FreeMem of unknown block $%06x ignored\n", addr);
		return;
	}
	blk = used_spans.v[i];
	spans_remove(&used_spans, i);

	i = spans_lower(&free_spans, blk.addr);
	/* merge with the following span */
	if (i < free_spans.n && blk.addr + blk.size == free_spans.v[i].addr) {
		blk.size += free_spans.v[i].size;
		spans_remove(&free_spans, i);
	}
	/* merge with the preceding span */
	if (i > 0 && free_spans.v[i - 1].addr + free_spans.v[i - 1].size == blk.addr) {
		free_spans.v[i - 1].size += blk.size;
		return;
	}
	spans_insert(&free_spans, i, blk);
}

uint32_t emu_avail(uint32_t flags)
{
	uint32_t total = 0, largest = 0;
	for (size_t i = 0; i < free_spans.n; i++) {
		total += free_spans.v[i].size;
		if (free_spans.v[i].size > largest) largest = free_spans.v[i].size;
	}
	return (flags & MEMF_LARGEST) ? largest : total;
}

void emu_heap_checkpoint(void)
{
	spans_copy(&ck_free, &free_spans);
	spans_copy(&ck_used, &used_spans);
}

void emu_heap_rollback(void)
{
	spans_copy(&free_spans, &ck_free);
	spans_copy(&used_spans, &ck_used);
}

/* ---- aborts ----------------------------------------------------------------------- */

static void do_abort(int code, const char *fmt, ...)
{
	if (!abort_code) {
		va_list ap;
		abort_code = code;
		va_start(ap, fmt);
		vsnprintf(abort_msg, sizeof(abort_msg), fmt, ap);
		va_end(ap);
	}
	m68k_end_timeslice();
}

const char *emu_abort_text(void) { return abort_msg; }
int emu_depth(void) { return depth; }

/* ---- library traps ------------------------------------------------------------ */

static uint32_t library_for_name(const char *name)
{
	if (strcmp(name, "exec.library") == 0) return EMU_EXEC_BASE;
	if (strcmp(name, "dos.library") == 0) return EMU_DOS_BASE;
	if (strcmp(name, "xfdmaster.library") == 0) return EMU_XFD_BASE;
	return 0; /* e.g. xpkmaster.library: the slave reports a missing resource */
}

static int exec_lvo(int lvo)
{
	uint32_t d0 = emu_get_reg(EMU_D0), d1 = emu_get_reg(EMU_D0 + 1);
	uint32_t a0 = emu_get_reg(EMU_A0), a1 = emu_get_reg(EMU_A0 + 1);
	char name[64];

	switch (lvo) {
	case LVO_EXEC_ALLOCMEM:
		emu_set_reg(EMU_D0, emu_alloc(d0, d1));
		if (trace) fprintf(stderr, "[emu] AllocMem(%u, $%x) = $%06x\n", d0, d1, emu_get_reg(EMU_D0));
		return 1;
	case LVO_EXEC_FREEMEM:
		if (trace) fprintf(stderr, "[emu] FreeMem($%06x, %u)\n", a1, d0);
		emu_free(a1);
		return 1;
	case LVO_EXEC_AVAILMEM:
		emu_set_reg(EMU_D0, emu_avail(d1));
		return 1;
	case LVO_EXEC_ALLOCVEC: {
		uint32_t a = d0 ? emu_alloc(d0 + 8, d1) : 0;
		if (a) emu_w32(a + 4, d0 + 8);
		emu_set_reg(EMU_D0, a ? a + 8 : 0);
		return 1;
	}
	case LVO_EXEC_FREEVEC:
		if (a1) emu_free(a1 - 8);
		return 1;
	case LVO_EXEC_TYPEOFMEM:
		/* All RAM here counts as both chip and fast, so slaves never move hunks. */
		emu_set_reg(EMU_D0, (a1 >= EMU_HEAP_LOW && a1 < EMU_STACK_LOW)
			? (MEMF_PUBLIC | MEMF_CHIP | MEMF_FAST) : 0);
		return 1;
	case LVO_EXEC_COPYMEM:
	case LVO_EXEC_COPYMEMQUICK:
		emu_copy(a1, a0, d0);
		return 1;
	case LVO_EXEC_CACHECLEARU:
	case LVO_EXEC_FORBID:
	case LVO_EXEC_PERMIT:
	case LVO_EXEC_DISABLE:
	case LVO_EXEC_ENABLE:
	case LVO_EXEC_CLOSELIBRARY:
	case LVO_EXEC_USERSTATE:
		return 1;
	case LVO_EXEC_SUPERSTATE:
		emu_set_reg(EMU_D0, 0); /* already in supervisor mode */
		return 1;
	case LVO_EXEC_SETSR: {
		uint32_t sr = m68k_get_reg(NULL, M68K_REG_SR);
		uint32_t nsr = (sr & ~d1) | (d0 & d1);
		m68k_set_reg(M68K_REG_SR, (nsr & 0xffff) | 0x2000);
		emu_set_reg(EMU_D0, sr);
		return 1;
	}
	case LVO_EXEC_OPENLIBRARY:
	case LVO_EXEC_OLDOPENLIBRARY:
		emu_read_string(name, sizeof(name), a1);
		emu_set_reg(EMU_D0, library_for_name(name));
		if (trace) fprintf(stderr, "[emu] OpenLibrary(\"%s\") = $%06x\n", name, emu_get_reg(EMU_D0));
		return 1;
	case LVO_EXEC_FINDTASK:
		emu_set_reg(EMU_D0, TASK_STRUCT);
		return 1;
	case LVO_EXEC_SETSIGNAL:
		emu_set_reg(EMU_D0, 0); /* no break signals */
		return 1;
	}
	return 0;
}

static int dos_lvo(int lvo)
{
	switch (lvo) {
	case LVO_DOS_READ:
	case LVO_DOS_SEEK:
		emu_set_reg(EMU_D0, (uint32_t)-1);
		return 1;
	case LVO_DOS_IOERR:
		emu_set_reg(EMU_D0, 0);
		return 1;
	case LVO_DOS_UNLOADSEG: {
		uint32_t seg = emu_get_reg(EMU_D0 + 1);
		while (seg) {
			uint32_t a = seg << 2;
			seg = emu_r32(a);
			emu_free(a - 4);
		}
		return 1;
	}
	}
	return 0;
}

static const char *vector_name(int v)
{
	switch (v) {
	case 2: return "bus error";
	case 3: return "address error";
	case 4: return "illegal instruction";
	case 5: return "division by zero";
	case 6: return "CHK";
	case 7: return "TRAPV";
	case 8: return "privilege violation";
	case 9: return "trace";
	case 10: return "line-A";
	case 11: return "line-F";
	}
	if (v >= 32 && v < 48) return "TRAP #n";
	if (v >= 24 && v < 32) return "interrupt";
	return "exception";
}

static int illegal_callback(int opcode)
{
	uint32_t pc = m68k_get_reg(NULL, M68K_REG_PPC) & EMU_ADDR_MASK;
	int lvo, ok = 0;

	if (opcode != OP_ILLEGAL) {
		do_abort(EMU_ABORT_EXCEPTION, "illegal instruction $%04x at $%06x", opcode, pc);
		return 1;
	}
	if (pc == EMU_STOP_TRAP) {
		stopped[depth] = 1;
		m68k_end_timeslice();
		return 1;
	}
	if (pc >= EMU_VEC_TRAPS && pc < EMU_VEC_TRAPS + 512) {
		int v = (int)(pc - EMU_VEC_TRAPS) / 2;
		uint32_t sp = m68k_get_reg(NULL, M68K_REG_A7);
		do_abort(EMU_ABORT_EXCEPTION, "CPU exception %d (%s) at $%06x", v, vector_name(v),
			emu_r32(sp + 2) & EMU_ADDR_MASK);
		return 1;
	}

	if (pc >= EXEC_TABLE_LOW && pc < EMU_EXEC_BASE) {
		lvo = (int)pc - (int)EMU_EXEC_BASE;
		ok = exec_lvo(lvo);
		if (!ok) do_abort(EMU_ABORT_UNSUPPORTED, "exec.library LVO %d is not provided", lvo);
	} else if (pc >= DOS_TABLE_LOW && pc < EMU_DOS_BASE) {
		lvo = (int)pc - (int)EMU_DOS_BASE;
		ok = dos_lvo(lvo);
		if (!ok) do_abort(EMU_ABORT_UNSUPPORTED, "dos.library LVO %d is not provided", lvo);
	} else if (pc >= XFD_TABLE_LOW && pc < EMU_XFD_BASE) {
		lvo = (int)pc - (int)EMU_XFD_BASE;
		if (trace) fprintf(stderr, "[emu] xfdmaster LVO %d\n", lvo);
		ok = xfd_handler ? xfd_handler(lvo) : 0;
		if (!ok) do_abort(EMU_ABORT_UNSUPPORTED, "xfdmaster.library LVO %d is not provided", lvo);
	} else {
		do_abort(EMU_ABORT_EXCEPTION, "ILLEGAL instruction at $%06x", pc);
	}
	return 1;
}

void emu_set_xfd_handler(emu_lvo_handler h) { xfd_handler = h; }

/* ---- calls ------------------------------------------------------------------------ */

int emu_call(uint32_t pc, emu_regs_t *regs)
{
	unsigned char *saved = NULL;
	uint32_t sp;
	int me, i;

	if (depth >= MAX_DEPTH) {
		do_abort(EMU_ABORT_UNSUPPORTED, "68k calls nested too deeply");
		return abort_code;
	}
	if (depth == 0) {
		abort_code = EMU_OK;
		abort_msg[0] = '\0';
		used_cycles = 0;
		call_started = clock();
		sp = EMU_STACK_TOP;
	} else {
		saved = malloc(m68k_context_size());
		if (!saved) {
			fputs("xfd-native: out of host memory\n", stderr);
			exit(20);
		}
		m68k_get_context(saved);
		sp = m68k_get_reg(NULL, M68K_REG_A7) - 64;
	}

	sp &= ~3u;
	sp -= 4;
	emu_w32(sp, EMU_STOP_TRAP); /* the function's RTS lands on the stop trap */

	m68k_set_reg(M68K_REG_SR, 0x2700); /* supervisor, interrupts masked */
	for (i = 0; i < 15; i++) emu_set_reg(i, regs->r[i]);
	m68k_set_reg(M68K_REG_A7, sp);
	m68k_set_reg(M68K_REG_PC, pc & EMU_ADDR_MASK);

	me = ++depth;
	stopped[me] = 0;
	while (!stopped[me] && !abort_code) {
		int ran = m68k_execute(SLICE_CYCLES);
		if (ran > 0) used_cycles += (uint64_t)ran;
		if (used_cycles > cycle_budget) {
			do_abort(EMU_ABORT_TIMEOUT, "gave up after %llu CPU cycles", (unsigned long long)used_cycles);
		} else if ((double)(clock() - call_started) / CLOCKS_PER_SEC > time_budget) {
			do_abort(EMU_ABORT_TIMEOUT, "gave up after %.0f seconds", time_budget);
		}
	}
	for (i = 0; i < 16; i++) regs->r[i] = emu_get_reg(i);
	depth--;

	if (saved) {
		m68k_set_context(saved);
		free(saved);
		if (abort_code) m68k_end_timeslice();
	}
	return abort_code;
}

/* ---- setup ------------------------------------------------------------------------ */

static void make_jump_table(uint32_t base, uint32_t low)
{
	for (uint32_t a = base - 6; a >= low; a -= 6) {
		emu_w16(a, OP_ILLEGAL);
		emu_w16(a + 2, OP_RTS);
		emu_w16(a + 4, OP_NOP);
	}
}

static void make_library(uint32_t base, uint32_t low, const char *name, int version, int revision)
{
	make_jump_table(base, low);
	emu_w8(base + 8, 9);                       /* ln_Type = NT_LIBRARY */
	emu_w32(base + 10, emu_static_string(name)); /* ln_Name */
	emu_w16(base + 16, (uint16_t)(base - low));  /* lib_NegSize */
	emu_w16(base + LIB_VERSION, (uint32_t)version);
	emu_w16(base + LIB_REVISION, (uint32_t)revision);
}

int emu_init(void)
{
	emu_mem = calloc(1, EMU_MEM_SIZE + 16);
	if (!emu_mem) return -1;

	/* Exception vectors 2..255 each point at their own ILLEGAL trap. */
	for (uint32_t v = 0; v < 256; v++) {
		emu_w16(EMU_VEC_TRAPS + v * 2, OP_ILLEGAL);
		if (v >= 2) emu_w32(v * 4, EMU_VEC_TRAPS + v * 2);
	}
	emu_w16(EMU_STOP_TRAP, OP_ILLEGAL);

	make_library(EMU_EXEC_BASE, EXEC_TABLE_LOW, "exec.library", 40, 68);
	emu_w16(EMU_EXEC_BASE + EXEC_ATTNFLAGS, AFF_68010 | AFF_68020);
	emu_w32(4, EMU_EXEC_BASE); /* AbsExecBase */
	make_library(EMU_DOS_BASE, DOS_TABLE_LOW, "dos.library", 40, 3);
	make_library(EMU_XFD_BASE, XFD_TABLE_LOW, "xfdmaster.library", XFDM_VERSION, 15);
	emu_w32(EMU_XFD_BASE + XFDM_EXECBASE, EMU_EXEC_BASE);
	emu_w32(EMU_XFD_BASE + XFDM_DOSBASE, EMU_DOS_BASE);

	free_spans.n = used_spans.n = 0;
	spans_insert(&free_spans, 0, (span_t){EMU_HEAP_LOW, EMU_STACK_LOW - EMU_HEAP_LOW});
	emu_heap_checkpoint();

	m68k_init();
	m68k_set_cpu_type(M68K_CPU_TYPE_68EC020);
	m68k_set_illg_instr_callback(illegal_callback);
	m68k_pulse_reset();
	return 0;
}

void emu_set_limits(uint64_t cycles, double seconds)
{
	if (cycles) cycle_budget = cycles;
	if (seconds > 0) time_budget = seconds;
}

void emu_set_trace(int on) { trace = on; }
int emu_trace_enabled(void) { return trace; }
