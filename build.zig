const std = @import("std");

pub fn build(b: *std.Build) void {
    const efi_target = b.standardTargetOptions(.{
        .default_target = .{
            .cpu_arch = .x86_64,
            .os_tag = .uefi,
        },
    });

    const optimize = b.standardOptimizeOption(.{
        .preferred_optimize_mode = .ReleaseFast,
    });

    const boot_efi = b.addExecutable(.{
        .name = "houdinix",
        .root_source_file = b.path("boot.zig"),
        .target = efi_target,
        .optimize = optimize,
    });

    b.installArtifact(boot_efi);
}
