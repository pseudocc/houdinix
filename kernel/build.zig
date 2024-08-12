const std = @import("std");

pub fn build(b: *std.Build) void {
    const elf_target = b.standardTargetOptions(.{
        .default_target = .{
            .cpu_arch = .x86_64,
            .os_tag = .freestanding,
            .ofmt = .elf,
        },
    });

    const optimize = b.standardOptimizeOption(.{
        .preferred_optimize_mode = .ReleaseSmall,
    });

    const kernel_elf = b.addExecutable(.{
        .name = "houdinix",
        .root_source_file = b.path("houdinix.zig"),
        .target = elf_target,
        .optimize = optimize,
    });

    b.installArtifact(kernel_elf);
}
