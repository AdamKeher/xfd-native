/*
 * xfd-native: command-line decruncher for Amiga crunched files.
 *
 * A native counterpart of the AmigaOS xfdDecrunch command. The decrunch flow,
 * the messages, and the LINKSIMPLE/LINKPRO loader headers (link_data) come
 * from xfdmaster_os4 53.7 src/utils/xfdDecrunch.c (decrunch_file(),
 * write_file()), whose header data was taken from the original
 * xfdDecrunch 1.9 (09.09.1999). --unlink follows src/utils/xfdUnlink.c, with
 * the messages of the original 68k xfdUnlink 1.01. The argument handling,
 * test mode, --all-layers, --identify, --list and the emulator setup are new.
 *
 * Copyright (C) 1994-1999 Georg Hörmann, Dirk Stöcker (xfdDecrunch)
 * Copyright (C) 2014 Fredrik Wikström (OS4 xfdDecrunch rewrite)
 * Copyright (C) 2026 the xfd-native authors
 * SPDX-License-Identifier: LGPL-2.1-or-later
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>

#include "amiga.h"
#include "emu.h"
#include "xfdlib.h"

#ifndef XFDN_VERSION
#define XFDN_VERSION "dev" /* set by the Makefile */
#endif

#define RC_OK    0  /* decrunched, or not crunched */
#define RC_ERROR 10 /* recognised but decrunching failed */
#define RC_FAIL  20 /* bad arguments, I/O error */

extern const unsigned char xfd_m68k_blob[];
extern const size_t xfd_m68k_blob_len;

/* xfd-native's own external slaves (m68k/extra), built in by tools/embed */
struct xfd_embedded {
	const char *name;
	const unsigned char *data;
	size_t size;
};
extern const struct xfd_embedded xfd_embedded_slaves[];
extern const size_t xfd_embedded_slaves_count;

/* ---- options ------------------------------------------------------------------ */

static struct {
	const char *source, *dest, *dest2, *slaves, *password;
	unsigned long key;
	int have_key, force, linkpro, linksimple, copyall, noextern, list, all_layers, identify, unlink;
	unsigned long long max_cycles;
	double timeout;
} opt;

static void usage(FILE *out)
{
	fputs(
		"Usage: xfdnative [options] SOURCE [DEST]\n"
		"       xfdnative --unlink [options] SOURCE [DEST1 DEST2]\n"
		"Decrunch an Amiga file packed with any cruncher known to xfdmaster, or split\n"
		"an executable that a linker joined from two programs.\n"
		"Without DEST the file is recognised and tested, nothing is written.\n"
		"\n"
		"  -u, --unlink         split a linked executable into its two parts\n"
		"                       (4EB9/4EF9, Glue, XLink, UFO, ETA/EXP text,\n"
		"                       FileShield, ExeDescript, FileDescript)  (xfdUnlink)\n"
		"  -f, --force          overwrite DEST if it exists            (xfdDecrunch FORCE)\n"
		"  -p, --linkpro        give absolute-address images the\n"
		"                       \"professional\" loader header          (xfdDecrunch LP)\n"
		"  -s, --linksimple     same, with the simple loader header      (xfdDecrunch LS)\n"
		"  -c, --copyall        write DEST even if SOURCE is not crunched (xfdDecrunch CA)\n"
		"  -n, --noextern       don't use external slaves, including   (xfdDecrunch NE)\n"
		"                       the built-in Shrinkler/Cranker/L-Packer ones\n"
		"  -a, --all-layers     keep decrunching while the result is crunched again\n"
		"  -x, --slaves DIR     load external slaves (LIBS:xfd) from DIR\n"
		"                       default: $XFD_SLAVES, else 'slaves' next to the program\n"
		"                       or in its parent directory\n"
		"      --password TEXT  password for protected files\n"
		"      --key N          16/32-bit key for protected files (decimal or $hex)\n"
		"  -i, --identify       only name the packer (and any linker), change nothing\n"
		"  -l, --list           list all slaves and exit\n"
		"      --max-cycles N   68k cycle budget per file (default 4000000000)\n"
		"      --timeout SECS   wall-clock budget per file (default 120)\n"
		"  -t, --trace          log emulator and library calls to stderr\n"
		"  -V, --version        show version and exit\n"
		"\n"
		"Exit codes: 0 done (or nothing to do: not crunched / not linked),\n"
		"            10 decrunching or unlinking failed, 20 error.\n",
		out);
}

static int parse_key(const char *s, unsigned long *out)
{
	char *end;
	int neg = 0;
	unsigned long v;
	if (*s == '-') {
		neg = 1;
		s++;
	}
	if (*s == '$') v = strtoul(s + 1, &end, 16);
	else if (s[0] == '0' && (s[1] == 'x' || s[1] == 'X')) v = strtoul(s + 2, &end, 16);
	else v = strtoul(s, &end, 10);
	if (*s == '\0' || *end != '\0') return 0;
	*out = neg ? (unsigned long)(-(long)v) : v;
	return 1;
}

static int parse_args(int argc, char **argv)
{
	for (int i = 1; i < argc; i++) {
		const char *a = argv[i];
#define NEXT_ARG() (i + 1 < argc ? argv[++i] : (fprintf(stderr, "%s needs a value\n", a), (char *)NULL))
		if (!strcmp(a, "-f") || !strcmp(a, "--force")) opt.force = 1;
		else if (!strcmp(a, "-p") || !strcmp(a, "--linkpro")) opt.linkpro = 1;
		else if (!strcmp(a, "-s") || !strcmp(a, "--linksimple")) opt.linksimple = 1;
		else if (!strcmp(a, "-c") || !strcmp(a, "--copyall")) opt.copyall = 1;
		else if (!strcmp(a, "-n") || !strcmp(a, "--noextern")) opt.noextern = 1;
		else if (!strcmp(a, "-a") || !strcmp(a, "--all-layers")) opt.all_layers = 1;
		else if (!strcmp(a, "-l") || !strcmp(a, "--list")) opt.list = 1;
		else if (!strcmp(a, "-i") || !strcmp(a, "--identify")) opt.identify = 1;
		else if (!strcmp(a, "-u") || !strcmp(a, "--unlink")) opt.unlink = 1;
		else if (!strcmp(a, "-t") || !strcmp(a, "--trace")) emu_set_trace(1);
		else if (!strcmp(a, "-x") || !strcmp(a, "--slaves")) {
			if (!(opt.slaves = NEXT_ARG())) return 0;
		} else if (!strcmp(a, "--password")) {
			if (!(opt.password = NEXT_ARG())) return 0;
		} else if (!strcmp(a, "--key")) {
			const char *v = NEXT_ARG();
			if (!v || !parse_key(v, &opt.key)) {
				fputs("--key needs a decimal or $hex number\n", stderr);
				return 0;
			}
			opt.have_key = 1;
		} else if (!strcmp(a, "--max-cycles")) {
			const char *v = NEXT_ARG();
			if (!v) return 0;
			opt.max_cycles = strtoull(v, NULL, 10);
		} else if (!strcmp(a, "--timeout")) {
			const char *v = NEXT_ARG();
			if (!v) return 0;
			opt.timeout = atof(v);
		} else if (!strcmp(a, "-V") || !strcmp(a, "--version")) {
			printf("xfdnative %s (xfdmaster 68k slaves, Musashi 68k core)\n", XFDN_VERSION);
			exit(RC_OK);
		} else if (!strcmp(a, "-h") || !strcmp(a, "--help")) {
			usage(stdout);
			exit(RC_OK);
		} else if (a[0] == '-' && a[1] != '\0') {
			fprintf(stderr, "Unknown option %s\n", a);
			return 0;
		} else if (!opt.source) opt.source = a;
		else if (!opt.dest) opt.dest = a;
		else if (!opt.dest2) opt.dest2 = a;
		else {
			fprintf(stderr, "Unexpected argument %s\n", a);
			return 0;
		}
#undef NEXT_ARG
	}
	if (opt.linkpro && opt.linksimple) {
		fputs("You cannot link several headers.\n", stderr);
		return 0;
	}
	if (opt.unlink ? (opt.dest && !opt.dest2) : opt.dest2 != NULL) {
		fputs(opt.unlink ? "--unlink needs both DEST1 and DEST2 (or neither)\n"
		                 : "Too many arguments (DEST2 is only used with --unlink)\n", stderr);
		return 0;
	}
	return opt.list || opt.source;
}

/* ---- files ---------------------------------------------------------------------- */

static int file_exists(const char *path)
{
	struct stat st;
	return stat(path, &st) == 0;
}

static uint8_t *read_file(const char *path, size_t *len)
{
	FILE *f = fopen(path, "rb");
	uint8_t *data;
	long size;
	if (!f) return NULL;
	if (fseek(f, 0, SEEK_END) != 0 || (size = ftell(f)) < 0 || fseek(f, 0, SEEK_SET) != 0) {
		fclose(f);
		return NULL;
	}
	data = malloc(size ? (size_t)size : 1);
	if (data && fread(data, 1, (size_t)size, f) != (size_t)size) {
		free(data);
		data = NULL;
	}
	fclose(f);
	*len = (size_t)size;
	return data;
}

static char *dirname_of(const char *path)
{
	const char *slash = strrchr(path, '/');
	const char *bslash = strrchr(path, '\\');
	char *d;
	size_t n;
	if (bslash && (!slash || bslash > slash)) slash = bslash;
	n = slash ? (size_t)(slash - path) : 1;
	d = malloc(n + 1);
	if (!d) return NULL;
	if (slash) memcpy(d, path, n);
	else d[0] = '.';
	d[n] = '\0';
	return d;
}

/* ---- loader headers (LINKSIMPLE / LINKPRO) --------------------------------------- */

/* Verbatim from xfdmaster_os4 src/utils/xfdDecrunch.c, which took it from the
 * original xfdDecrunch 1.9 (note the embedded $VER string). */
static const uint32_t link_data[0x74] = {
	0x0064006a, 0x00b40000, 0x00000130, 0x000003f3,
	0x00000000, 0x00000002, 0x00000000, 0x00000001,
	0x0000003f, 0x00000000, 0x000003e9, 0x0000003f,
	0x60160000, 0x0000abcd, 0x00000000, 0x00000000,
	0x00000000, 0x00000000, 0x48e7f0c2, 0x43fa00a6,
	0x70212c78, 0x00044eae, 0xfdd841fa, 0xffd42080,
	0x677643f9, 0x12345678, 0x203c1234, 0x56784eae,
	0xff344a80, 0x660841fa, 0x00886164, 0x604e223a,
	0xffb8243c, 0x00000130, 0x76ff2c7a, 0xffa44eae,
	0xffbe223a, 0xffa4243a, 0xffcc263a, 0xffce4eae,
	0xffd6b680, 0x670841fa, 0x006e6134, 0x600e4cdf,
	0x430f4eb9, 0x12345678, 0x4fefffe4, 0x227affa6,
	0x203affa8, 0x2c780004, 0x4eaeff2e, 0x227aff62,
	0x2c780004, 0x4eaefe62, 0x4fef001c, 0x70004e75,
	0x76001618, 0x24082c7a, 0xff484eae, 0xffc42200,
	0x4eeeffd0, 0x646f732e, 0x6c696272, 0x61727900,
	0x154e6f20, 0x6d656d6f, 0x72792061, 0x7661696c,
	0x61626c65, 0x2e0a1445, 0x72726f72, 0x206c6f61,
	0x64696e67, 0x20646174, 0x612e0a00, 0x000003f2,
	0x000003f5, 0x00000000, 0x000003f6, 0x00360062,
	0x00400024, 0x0000000e, 0x0000005c, 0x000003f3,
	0x00000000, 0x00000001, 0x00000000, 0x00000000,
	0x00000000, 0x000003e9, 0x00000000, 0x48e780c0,
	0x43f91234, 0x567841fa, 0x002c203c, 0x12345678,
	0xb1c96714, 0x650822d8, 0x538066fa, 0x600ad1c0,
	0xd3c02320, 0x538066fa, 0x4cdf0301, 0x4ef91234,
	0x56784e71, 0x000003f2, 0x24564552, 0x3a207866,
	0x64446563, 0x72756e63, 0x6820312e, 0x39202830,
	0x392e3039, 0x2e313939, 0x39290d0a, 0x00000000,
};

#define PRO_HEADER    0x0
#define SIMPLE_HEADER 0x13c
#define SIMPLE_FOOTER 0x1a4

static uint8_t ld[sizeof(link_data)]; /* big-endian byte image of link_data */

static uint32_t ld_r16(uint32_t o) { return ((uint32_t)ld[o] << 8) | ld[o + 1]; }
static uint32_t ld_r32(uint32_t o) { return (ld_r16(o) << 16) | ld_r16(o + 2); }
static void ld_w32(uint32_t o, uint32_t v)
{
	ld[o] = (uint8_t)(v >> 24);
	ld[o + 1] = (uint8_t)(v >> 16);
	ld[o + 2] = (uint8_t)(v >> 8);
	ld[o + 3] = (uint8_t)v;
}

static void init_link_data(void)
{
	for (size_t i = 0; i < sizeof(link_data) / 4; i++) ld_w32((uint32_t)i * 4, link_data[i]);
}

/* ---- decrunching ---------------------------------------------------------------- */

static int write_all(FILE *f, const void *p, size_t n) { return n == 0 || fwrite(p, 1, n, f) == n; }

/* Open an output file, honouring --force (the original commands ask). */
static FILE *open_output(const char *fn)
{
	FILE *f;
	if (!opt.force && file_exists(fn)) {
		fprintf(stderr, "%s already exists (use --force to overwrite)\n", fn);
		return NULL;
	}
	f = fopen(fn, "wb");
	if (!f) perror(fn);
	return f;
}

/* Port of write_file(): the output-format decisions for absolute-address
 * images live here. `data` is the decrunched image. */
static int write_output(const char *fn, const uint8_t *data, uint32_t len, uint32_t bi)
{
	uint32_t pflags = emu_r16(bi + XFDBI_PACKERFLAGS);
	FILE *f;
	int ok = 0;

	printf("Writing \"%s\" (%lu bytes)...\n", fn, (unsigned long)len);
	if (!(f = open_output(fn))) return 0;

	if (pflags & XFDPFF_ADDR) {
		uint32_t decr = emu_r32(bi + XFDBI_DECRADDRESS);
		uint32_t jmp = emu_r32(bi + XFDBI_JMPADDRESS);
		uint32_t tb = emu_r32(bi + XFDBI_TARGETBUFFER);
		int is_exe = len >= 4 && ((uint32_t)data[0] << 24 | (uint32_t)data[1] << 16 |
		                          (uint32_t)data[2] << 8 | data[3]) == HUNK_HEADER &&
		             xfd_test_hunk_structure_flags(tb, len, 0) == XFDERR_OK;

		if (is_exe) {
			puts("File seems to be executable...");
			ok = write_all(f, data, len);
		} else if (opt.linksimple) {
			uint32_t d = SIMPLE_HEADER, longs, l32;
			int32_t offset;
			static const uint8_t zero[4] = {0, 0, 0, 0};
			uint32_t padded = (len + 3u) & ~3u;

			puts("Linking simple executable header...");
			offset = (int16_t)ld_r16(d);
			d += 2;
			ld_w32(d + (uint32_t)(offset - 2), decr);
			offset = (int16_t)ld_r16(d);
			d += 2;
			ld_w32(d + (uint32_t)(offset - 4), jmp);
			offset = (int16_t)ld_r16(d);
			d += 2;
			longs = padded >> 2;
			ld_w32(d + (uint32_t)(offset - 6), longs);
			offset = (int16_t)ld_r16(d);
			d += 2;
			longs += ld_r32(d);
			d += 4;
			ld_w32(d + (uint32_t)(offset - 12), longs);
			ld_w32(d + (uint32_t)(offset - 4), longs);
			l32 = ld_r32(d);
			d += 4;
			ok = write_all(f, ld + d, l32) && write_all(f, data, len) &&
			     write_all(f, zero, padded - len) && write_all(f, ld + SIMPLE_FOOTER, 4);
		} else if (opt.linkpro) {
			uint32_t d = PRO_HEADER, l32;
			int32_t offset;

			puts("Linking professional executable header...");
			offset = (int16_t)ld_r16(d);
			d += 2;
			ld_w32(d + (uint32_t)(offset - 2), decr);
			offset = (int16_t)ld_r16(d);
			d += 2;
			ld_w32(d + (uint32_t)(offset - 4), len);
			offset = (int16_t)ld_r16(d);
			d += 2;
			ld_w32(d + (uint32_t)(offset - 6), jmp);
			d += 2;
			l32 = ld_r32(d);
			d += 4;
			ok = write_all(f, ld + d, l32) && write_all(f, data, len);
		} else {
			printf("Saving relocated image (Addr: $%08lx, Jmp: $%08lx)...\n",
				(unsigned long)decr, (unsigned long)jmp);
			ok = write_all(f, data, len);
		}
	} else {
		ok = write_all(f, data, len);
	}

	if (fclose(f) != 0) ok = 0;
	if (!ok) perror(fn);
	return ok;
}

/* Fill in xfdbi_Special for packers that need a password or key. */
static int set_special(uint32_t bi)
{
	uint32_t pflags = emu_r16(bi + XFDBI_PACKERFLAGS);
	uint32_t buf;

	if (!(pflags & (XFDPFF_PASSWORD | XFDPFF_KEY16 | XFDPFF_KEY32))) return 1;
	buf = emu_alloc(104, MEMF_PUBLIC | MEMF_CLEAR);
	if (!buf) return 0;
	if (pflags & XFDPFF_PASSWORD) {
		if (!opt.password) {
			fputs("This file needs a password (use --password).\n", stderr);
			return 0;
		}
		emu_write_block(buf, opt.password, strnlen(opt.password, 99));
	} else {
		if (!opt.have_key) {
			fprintf(stderr, "This file needs a %s-bit key (use --key).\n",
				(pflags & XFDPFF_KEY16) ? "16" : "32");
			return 0;
		}
		if (pflags & XFDPFF_KEY16) emu_w16(buf, (uint32_t)opt.key);
		else emu_w32(buf, (uint32_t)opt.key);
	}
	emu_w32(bi + XFDBI_SPECIAL, buf);
	return 1;
}

/* Recognise and decrunch the buffer at src/len.
 * Returns 1 = decrunched (image left in the bufferinfo), 0 = not crunched,
 * -1 = recognised but failed. */
static int decrunch_once(uint32_t bi, uint32_t src, uint32_t len)
{
	char name[128];

	for (uint32_t o = 0; o < XFDBI_SIZEOF; o += 2) emu_w16(bi + o, 0);
	emu_w32(bi + XFDBI_SOURCEBUFFER, src);
	emu_w32(bi + XFDBI_SOURCEBUFLEN, len);
	emu_w16(bi + XFDBI_FLAGS, opt.noextern ? 0 : XFDFF_RECOGEXTERN);

	if (!xfd_recog_buffer(bi)) return 0;

	emu_read_string(name, sizeof(name), emu_r32(bi + XFDBI_PACKERNAME));
	if (opt.identify) {
		uint32_t pf = emu_r16(bi + XFDBI_PACKERFLAGS);
		printf("Crunched: \"%s\" (%s)\n", name,
			(pf & XFDPFF_DATA) ? "data" : (pf & XFDPFF_ADDR) ? "absolute address" : "executable");
		return 2;
	}
	printf("Decrunching \"%s\" file...\n", name);
	fflush(stdout);

	if (!set_special(bi)) return -1;

	if (!xfd_decrunch_buffer(bi)) {
		printf("Decrunch failed: %s", xfd_error_text(emu_r16(bi + XFDBI_ERROR)));
		if (emu_abort_text()[0]) printf(" (68k emulation: %s)", emu_abort_text());
		putchar('\n');
		return -1;
	}
	return 1;
}

/* Copy a file's contents into emulated memory; 0 if it doesn't fit. */
static uint32_t load_into_emu(const uint8_t *data, size_t len)
{
	uint32_t addr;
	if (len == 0 || len >= EMU_STACK_LOW - EMU_HEAP_LOW) return 0;
	addr = emu_alloc((uint32_t)len, MEMF_PUBLIC);
	if (addr) emu_write_block(addr, data, len);
	return addr;
}

/* xfdRecogLinker() on src/len; on success copies the linker name. */
static int recog_linker(uint32_t li, uint32_t src, uint32_t len, char *name, size_t namelen)
{
	emu_w32(li + XFDLI_BUFFER, src);
	emu_w32(li + XFDLI_BUFLEN, len);
	if (!xfd_recog_linker(li)) return 0;
	emu_read_string(name, namelen, emu_r32(li + XFDLI_LINKERNAME));
	return 1;
}

/* Port of the xfdUnlink command (SOURCE DEST1 DEST2). The messages are those
 * of the original xfdUnlink 1.01; like it (and unlike the OS4 rewrite) the
 * "Unlinking" line names the linker, not the source file. */
static int run_unlink(void)
{
	size_t len;
	uint8_t *data = read_file(opt.source, &len);
	uint32_t src, li;
	char name[128];
	const char *dests[2] = {opt.dest, opt.dest2};

	if (!data) {
		perror(opt.source);
		return RC_FAIL;
	}
	printf("Reading \"%s\"...\n", opt.source);
	src = load_into_emu(data, len);
	free(data);
	li = xfd_alloc_linkerinfo();
	if ((len && !src) || !li) {
		fputs(len >= EMU_STACK_LOW - EMU_HEAP_LOW ? "File too large\n" : "Out of emulated memory\n", stderr);
		return RC_FAIL;
	}

	if (!len || !recog_linker(li, src, (uint32_t)len, name, sizeof(name))) {
		puts("Not linked");
		return RC_OK;
	}
	printf("Unlinking \"%s\" files...\n", name);
	fflush(stdout);

	if (!xfd_unlink(li)) {
		printf("Unlinking failed: %s", xfd_error_text(emu_r16(li + XFDLI_ERROR)));
		if (emu_abort_text()[0]) printf(" (68k emulation: %s)", emu_abort_text());
		putchar('\n');
		return RC_ERROR;
	}

	if (!opt.dest) {
		printf("Unlinked OK (%lu + %lu bytes), nothing written\n",
			(unsigned long)emu_r32(li + XFDLI_SAVELEN1), (unsigned long)emu_r32(li + XFDLI_SAVELEN2));
		return RC_OK;
	}
	for (int i = 0; i < 2; i++) {
		uint32_t part = emu_r32(li + XFDLI_SAVE1 + 4 * i);
		uint32_t plen = emu_r32(li + XFDLI_SAVELEN1 + 4 * i);
		uint8_t *buf = malloc(plen ? plen : 1);
		FILE *f;
		int ok;

		printf("Writing \"%s\"...\n", dests[i]);
		if (!buf) return RC_FAIL;
		emu_read_block(buf, part, plen);
		f = open_output(dests[i]);
		ok = f && write_all(f, buf, plen);
		if (f && fclose(f) != 0) ok = 0;
		free(buf);
		if (!ok) {
			if (f) perror(dests[i]);
			return RC_FAIL;
		}
	}
	return RC_OK;
}

static int run(void)
{
	size_t len;
	uint8_t *data = read_file(opt.source, &len);
	uint32_t src, bi, tb, save;
	int rc, layers = 0;

	if (!data) {
		perror(opt.source);
		return RC_FAIL;
	}
	printf("Reading \"%s\" (%lu bytes)...\n", opt.source, (unsigned long)len);
	if (len == 0 || len >= EMU_STACK_LOW - EMU_HEAP_LOW) {
		puts(len ? "File too large" : "Not crunched");
		free(data);
		return len ? RC_FAIL : RC_OK;
	}

	src = load_into_emu(data, len);
	bi = xfd_alloc_bufferinfo();
	if (!src || !bi) {
		fputs("Out of emulated memory\n", stderr);
		free(data);
		return RC_FAIL;
	}

	for (;;) {
		rc = decrunch_once(bi, src, (uint32_t)len);
		if (rc < 0) {
			free(data);
			return RC_ERROR;
		}
		if (rc == 2) { /* --identify */
			free(data);
			return RC_OK;
		}
		if (rc == 0) break;
		layers++;
		tb = emu_r32(bi + XFDBI_TARGETBUFFER);
		save = emu_r32(bi + XFDBI_TARGETBUFSAVELEN);
		/* Absolute-address images are memory dumps, not files; stop there. */
		if (!opt.all_layers || (emu_r16(bi + XFDBI_PACKERFLAGS) & XFDPFF_ADDR)) break;
		/* Peel the next layer: the result becomes the new source. */
		free(data);
		len = save;
		data = malloc(len ? len : 1);
		if (!data) return RC_FAIL;
		emu_read_block(data, tb, len);
		src = tb;
	}

	if (layers == 0) {
		puts("Not crunched");
		if (opt.identify) {
			uint32_t li = xfd_alloc_linkerinfo();
			char name[128];
			if (li && recog_linker(li, src, (uint32_t)len, name, sizeof(name))) {
				printf("Linked: \"%s\" (split it with --unlink)\n", name);
			}
		}
		if (opt.dest && opt.copyall) {
			int ok = write_output(opt.dest, data, (uint32_t)len, bi);
			free(data);
			return ok ? RC_OK : RC_FAIL;
		}
		free(data);
		return RC_OK;
	}

	tb = emu_r32(bi + XFDBI_TARGETBUFFER);
	save = emu_r32(bi + XFDBI_TARGETBUFSAVELEN);
	free(data);
	data = malloc(save ? save : 1);
	if (!data) return RC_FAIL;
	emu_read_block(data, tb, save);

	if (opt.dest) {
		rc = write_output(opt.dest, data, save, bi) ? RC_OK : RC_FAIL;
	} else {
		printf("Decrunched OK (%lu bytes, %d layer%s), nothing written\n", (unsigned long)save,
			layers, layers == 1 ? "" : "s");
		rc = RC_OK;
	}
	free(data);
	return rc;
}

static void list_slaves(void)
{
	char name[128];
	int n = 0;
	for (uint32_t s = xfd_first_slave(); s; s = emu_r32(s + XFDS_NEXT)) {
		uint32_t pf = emu_r16(s + XFDS_PACKERFLAGS);
		emu_read_string(name, sizeof(name), emu_r32(s + XFDS_PACKERNAME));
		printf("%-4s %-8s %s\n",
			(pf & XFDPFF_DATA) ? "data" : (pf & XFDPFF_ADDR) ? "addr" : "exe",
			(pf & XFDPFF_EXTERN) ? "external" : "internal", name);
		n++;
	}
	printf("%d slaves\n", n);
}

int main(int argc, char **argv)
{
	const char *slaves;
	char *fallback = NULL;
	int internal, external = 0, rc;

	if (!parse_args(argc, argv)) {
		usage(stderr);
		return RC_FAIL;
	}
	init_link_data();

	if (emu_init() != 0) {
		fputs("Could not allocate emulated memory\n", stderr);
		return RC_FAIL;
	}
	emu_set_limits(opt.max_cycles, opt.timeout);
	internal = xfd_init(xfd_m68k_blob, xfd_m68k_blob_len);
	if (internal < 0) {
		fputs("Internal slave blob is invalid\n", stderr);
		return RC_FAIL;
	}

	slaves = opt.slaves ? opt.slaves : getenv("XFD_SLAVES");
	if (!slaves) {
		/* 'slaves' next to the binary, or one level up (build/ in a checkout) */
		static const char *const candidates[] = {"/slaves", "/../slaves"};
		char *dir = dirname_of(argv[0]);
		for (size_t i = 0; dir && !slaves && i < 2; i++) {
			size_t n = strlen(dir) + strlen(candidates[i]) + 1;
			free(fallback);
			fallback = malloc(n);
			if (!fallback) break;
			snprintf(fallback, n, "%s%s", dir, candidates[i]);
			if (file_exists(fallback)) slaves = fallback;
		}
		free(dir);
	}
	if (slaves && !opt.noextern) {
		external = xfd_load_external_dir(slaves);
		if (external < 0) {
			fprintf(stderr, "Cannot read slave directory %s\n", slaves);
			free(fallback);
			return RC_FAIL;
		}
	}
	/* The built-in extra slaves load after the directory, as if they were
	 * more files in it. A file of the same name in the directory wins. */
	for (size_t i = 0; !opt.noextern && i < xfd_embedded_slaves_count; i++) {
		const struct xfd_embedded *e = &xfd_embedded_slaves[i];
		int added;
		if (slaves) {
			size_t n = strlen(slaves) + strlen(e->name) + 2;
			char *path = malloc(n);
			int shadowed = 0;
			if (path) {
				snprintf(path, n, "%s/%s", slaves, e->name);
				shadowed = file_exists(path);
				free(path);
			}
			if (shadowed) continue;
		}
		added = xfd_load_external_mem(e->data, e->size);
		if (emu_trace_enabled()) fprintf(stderr, "[xfd] built-in %s: %d slave(s)\n", e->name, added);
		external += added;
	}
	if (emu_trace_enabled()) {
		fprintf(stderr, "[xfd] %d internal and %d external slaves\n", internal, external);
	}
	emu_heap_checkpoint();

	if (opt.list) {
		list_slaves();
		free(fallback);
		return RC_OK;
	}

	rc = opt.unlink ? run_unlink() : run();
	fflush(stdout);
	free(fallback);
	return rc;
}
