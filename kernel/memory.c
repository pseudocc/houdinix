/**
 * Kernel memory allocator
 *
 * vim: ts=4:noet
**/

#include "memory.h"

void *memcpy(void *dest, const void *src, size_t n) {
	char *d = dest;
	const char *s = src;
	while (n--)
		*d++ = *s++;
	return dest;
}

void *memmove(void *dest, const void *src, size_t n) {
	char *d = dest;
	const char *s = src;
	if (d < s)
		while (n--)
			*d++ = *s++;
	else {
		d += n;
		s += n;
		while (n--)
			*--d = *--s;
	}
	return dest;
}

void *memset(void *s, int c, size_t n) {
	unsigned char *p = s;
	while (n--)
		*p++ = (unsigned char)c;
	return s;
}

int memcmp(const void *s1, const void *s2, size_t n) {
	const unsigned char *p1 = s1, *p2 = s2;
	int d = 0;
	while (n--)
		if ((d = *p1++ - *p2++))
			break;
	return d;
}

void *heap_start = (void *)(0x01000000);
size_t heap_size = 512 << 20;

struct chunk {
	size_t size;
	int free;
	struct chunk *next;
};
typedef struct chunk chunk_t;

chunk_t *_heap = NULL;
const size_t MIN_SIZE = sizeof(chunk_t) * 2;

// 512MB
void kmalloc_init() {
	if (_heap)
		return;
	_heap = (chunk_t *)heap_start;
	_heap->size = heap_size - sizeof(chunk_t);
	_heap->free = 1;
	_heap->next = NULL;

	// test memory write
	// char *p = (char *)_heap;
	// trace("kmalloc_init: write test");
	// for (size_t i = 0; i < heap_size; i++) {
	// 	p[i] = 0;
	// 	if (i % (1 << 20) == 0)
	// 		trace("kmalloc_init: write x");
	// }
	// trace("kmalloc_init: write last");
}

static void chunk_split(chunk_t *c, size_t size) {
	chunk_t *new;
	new = (chunk_t *)((size_t)c + size + sizeof(chunk_t));
	new->size = c->size - size - sizeof(chunk_t);
	new->free = 1;
	new->next = c->next;
	c->size = size;
	c->next = new;
}

void *malloc(size_t size) {
	if (!size)
		return NULL;

	chunk_t *c = _heap;
	size = size < MIN_SIZE ? MIN_SIZE : size;
	while (c) {
		if (c->free && c->size >= size) {
			if (c->size >= size + MIN_SIZE + sizeof(chunk_t)) {
				chunk_split(c, size);
			}
			c->free = 0;
			return (void *)((size_t)c + sizeof(chunk_t));
		}
		c = c->next;
	}

	return NULL;
}

void free(void *ptr) {
	if (!ptr)
		return;

	chunk_t *c = (chunk_t *)((size_t)ptr - sizeof(chunk_t));
	c->free = 1;

	while (c->next && c->next->free) {
		c->size += c->next->size + sizeof(chunk_t);
		c->next = c->next->next;
	}
}

void *realloc(void *ptr, size_t size) {
	if (!ptr)
		return malloc(size);

	if (!size) {
		free(ptr);
		return NULL;
	}

	chunk_t *c = (chunk_t *)((size_t)ptr - sizeof(chunk_t));
	if (c->size >= size)
		return ptr;

	size = size < MIN_SIZE ? MIN_SIZE : size;
	while (c->next && c->next->free) {
		c->size += c->next->size + sizeof(chunk_t);
		c->next = c->next->next;

		if (c->size >= size) {
			if (c->size >= size + MIN_SIZE + sizeof(chunk_t)) {
				chunk_split(c, size);
			}
			return ptr;
		}
	}
	
	void *new = malloc(size);
	if (new)
		memcpy(new, ptr, c->size);

	free(ptr);
	return new;
}
