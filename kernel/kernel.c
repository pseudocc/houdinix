/**
 * vim: ts=4:noet
 **/
#include "bootparam.h"
#include "embeded.h"
#include "memory.h"

#define SSFN_IMPLEMENTATION
#include <ssfn.h>

ssfn_t ctx = { 0 };
ssfn_buf_t buf = { 0 };

void fb_print(int x, int y, const char *s) {
	int n;

	buf.x = x;
	buf.y = y;

	while (*s) {
		n = ssfn_render(&ctx, &buf, s);
		if (n < 0)
			break;
		s += n;
	}
}

void _start(bootparam_t *bp) {
	const int FONT_SIZE = 16;
	int i;

	buf = (ssfn_buf_t) {
		.ptr = (unsigned char *)bp->framebuffer,
		.w = bp->width,
		.h = bp->height,
		.p = bp->pitch,
		.fg = 0xFF808080,
	};

	kmalloc_init();

	for (i = 0; i < bp->height * bp->width; i++)
		bp->framebuffer[i] = 0;

	if (ssfn_load(&ctx, SSFN_GOHU_NERD) != SSFN_OK) {
		return;
	}

	int ret;
	ret = ssfn_select(&ctx, SSFN_FAMILY_ANY, NULL, SSFN_STYLE_REGULAR, FONT_SIZE);
	if (ret) {
		return;
	}

	fb_print(10, FONT_SIZE, "Hello, world!");
	fb_print(10, FONT_SIZE * 2, "I got these arguments:");

	for (i = 0; i < bp->argc; i++)
		fb_print(20, (i + 3) * FONT_SIZE, bp->argv[i]);

	/* there's nowhere to return to, hang */
	while (1);
}
