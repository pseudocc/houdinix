ARCH = x86_64
TARGET = ../kernel.elf
SRCS = $(wildcard *.c)
OBJS = $(SRCS:.c=.o)

all: $(TARGET)

CC = clang -target $(ARCH)-elf
LD = ld.lld -m elf_$(ARCH)

FONTS = $(wildcard *.sfn)
EMBEDDED_FONTS = $(FONTS:=.elf)

$(EMBEDDED_FONTS): %.sfn.elf: %.sfn
	$(LD) -r -b binary -o $@ $<

$(OBJS): %.o: %.c
	$(CC) -ffreestanding -fno-stack-protector -fno-stack-check -D__$(ARCH)__ -I. -I.. -c $< -o $@

# UEFI wastes lots and lots of memory. Link our "kernel" at an address (32M) which isn't used by UEFI
$(TARGET): $(OBJS) $(EMBEDDED_FONTS)
	$(LD) -nostdlib -z max-page-size=0x1000 -Ttext=0x02000000 -o $@ $(OBJS) $(EMBEDDED_FONTS)

clean:
	rm -f *.o $(TARGET) $(EMBEDDED_FONTS)
