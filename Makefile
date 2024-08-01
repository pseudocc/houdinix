# define which architecture you're targeting
ARCH = x86_64
# define your target file here
TARGET = exit_bs.efi
# define your sources here
SRCS = $(wildcard *.c)
# define your default compiler flags
CFLAGS = -pedantic -Wall -Wextra -Werror --ansi -O2
# define your default linker flags
#LDFLAGS =
# define your additional libraries here
#LIBS = -lm

# leave the hard work and all the rest to posix-uefi

# set this if you want GNU gcc + ld + objcopy instead of LLVM Clang + Lld
#USE_GCC = 1
include uefi/Makefile

all: kernel.elf
	$(MAKE) -C uefi

kernel.elf:
	$(MAKE) -C kernel

uefi.img: uefi.manifest all
	scripts/build.sh $@ $^

QEMU_TARGETS = run-shell run-boot
$(QEMU_TARGETS): run-%: uefi.img
	scripts/run.sh $* $<

clean:
	$(MAKE) -C uefi $@
	$(MAKE) -C kernel $@
	rm -f uefi.img boot.img
