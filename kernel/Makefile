ARCH = x86_64
TARGET = ../kernel.elf
SRCS = kernel.c

all: $(TARGET)

CC = clang -target $(ARCH)-elf
LD = ld.lld

# UEFI wastes lots and lots of memory. Link our "kernel" at an address (32M) which isn't used by UEFI
$(TARGET): kernel.c
	$(CC) -ffreestanding -fno-stack-protector -fno-stack-check -D__$(ARCH)__ -I. -c $< -o kernel.o
	$(LD) -nostdlib -z max-page-size=0x1000 -Ttext=0x01000000 kernel.o -o $(TARGET)

clean:
	rm -f *.o $(TARGET)
