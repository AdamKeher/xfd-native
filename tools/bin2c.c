/*
 * bin2c: turn a binary file into a C array (build helper for xfd-native).
 * Usage: bin2c INPUT OUTPUT.c SYMBOL
 * Emits `const unsigned char SYMBOL[]` and `const size_t SYMBOL_len`.
 *
 * Copyright (C) 2026 the xfd-native authors.
 * SPDX-License-Identifier: LGPL-2.1-or-later
 */
#include <stdio.h>

int main(int argc, char **argv)
{
	FILE *in, *out;
	int c;
	unsigned long n = 0;

	if (argc != 4) {
		fputs("usage: bin2c INPUT OUTPUT.c SYMBOL\n", stderr);
		return 2;
	}
	in = fopen(argv[1], "rb");
	if (!in) {
		perror(argv[1]);
		return 1;
	}
	out = fopen(argv[2], "w");
	if (!out) {
		perror(argv[2]);
		fclose(in);
		return 1;
	}
	fprintf(out, "/* Generated from %s by tools/bin2c. Do not edit. */\n", argv[1]);
	fprintf(out, "#include <stddef.h>\n\nconst unsigned char %s[] = {", argv[3]);
	while ((c = fgetc(in)) != EOF) {
		fprintf(out, "%s0x%02x,", (n % 16) ? " " : "\n\t", c);
		n++;
	}
	fprintf(out, "\n};\nconst size_t %s_len = %lu;\n", argv[3], n);
	fclose(in);
	if (fclose(out) != 0) {
		perror(argv[2]);
		return 1;
	}
	return 0;
}
