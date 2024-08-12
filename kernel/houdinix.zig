const std = @import("std");

pub const BootParam = extern struct {
    framebuffer: [*c]u32,
    width: u32,
    height: u32,
    pitch: u32,
    argc: i32,
    argv: [*c][*:0]u8,
};

pub const ReturnType = noreturn;
const expected_bp: BootParam = .{
    .framebuffer = @ptrFromInt(0x80000000),
    .width = 1280,
    .height = 800,
    .pitch = 5120,
    .argc = 0,
    .argv = null,
};

export fn _start(bp: *BootParam) callconv(.SysV) ReturnType {
    @call(.always_inline, main, .{bp}) catch {};
    while (true) {
        asm volatile ("hlt");
    }
}

fn main(bp: *BootParam) !void {
    for (0..bp.height) |y| {
        for (0..bp.width) |x| {
            bp.framebuffer[y * bp.width + x] = 0xFF00FF;
        }
    }
    return error.Magic;
}
