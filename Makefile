# define which architecture you're targeting
ARCH = x86_64
# define your target file here
TARGET = helloworld.efi
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

uefi.img: uefi.manifest all
	scripts/build.sh $@ $^

run: uefi.img
	scripts/run.sh $<

ADDITIONAL_CLEAN = clean distclean
$(ADDITIONAL_CLEAN):
	$(MAKE) -C uefi $@
	rm -f uefi.img boot.img

.PHONY: run all $(ADDITIONAL_CLEAN)
