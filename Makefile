BOOT_SRCS = $(wildcard *.zig)
KERNEL_SRCS = $(wildcard kernel/*.zig)

KERNEL_ELF = kernel/zig-out/bin/houdinix
BOOT_EFI = zig-out/bin/houdinix.efi

TARGETS = $(KERNEL_ELF) $(BOOT_EFI)

$(KERNEL_ELF): $(KERNEL_SRCS)
	cd kernel && zig build --release

$(BOOT_EFI): $(BOOT_SRCS)
	zig build --release

uefi.img: uefi.manifest $(TARGETS)
	scripts/build.sh $@ $<

QEMU_TARGETS = run-shell run-boot
$(QEMU_TARGETS): run-%: uefi.img
	scripts/run.sh $* $<

clean:
	rm -rf .zig-cache kernel/.zig-cache
	rm -rf zig-out kernel/zig-out
	rm -f uefi.img
