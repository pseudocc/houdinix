#ifndef _KERNEL_MEMORY_H
#define _KERNEL_MEMORY_H

#define NULL ((void *)0)
typedef unsigned long size_t;

extern void *heap_start;
extern size_t heap_size;

void kmalloc_init();

void *memcpy(void *dest, const void *src, size_t n);
void *memmove(void *dest, const void *src, size_t n);

void *memset(void *s, int c, size_t n);
int memcmp(const void *s1, const void *s2, size_t n);

void *malloc(size_t size);
void free(void *ptr);
void *realloc(void *ptr, size_t size);

#endif // !_KERNEL_MEMORY_H
