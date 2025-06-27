const std = @import("std");
const SSFN = @import("ssfn.zig");

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

const Progress = struct {
    bp: *BootParam,
    now: u32,
    steps: u32,

    pub fn init(bp: *BootParam, steps: u32) Progress {
        return .{ .bp = bp, .now = 0, .steps = steps };
    }

    pub fn next(self: *Progress, color: u32) void {
        if (self.now >= self.steps)
            return;
        self.now += 1;
        const pace = self.bp.height * self.bp.width / self.steps;
        const start = pace * self.now;
        const end = if (self.now == self.steps - 1) self.bp.width else start + pace;
        for (start..end) |i| {
            self.bp.framebuffer[i] = color;
        }
    }
};

fn main(bp: *BootParam) !void {
    var fake_buffer: [*]u8 = @ptrFromInt(0x80000000);
    var fba = std.heap.FixedBufferAllocator{
        .end_index = 0,
        .buffer = fake_buffer[0 .. 512 << 20],
    };

    var context = SSFN.init(fba.allocator());
    defer context.deinit();

    try context.load(@embedFile("Gohu-Nerd.sfn"));
    var buf: SSFN.Buffer = .{
        .ptr = @ptrCast(bp.framebuffer),
        .width = bp.width,
        .height = bp.height,
        .pitch = bp.pitch,
        .bg = .{ .value = 0xFF000000 },
        .fg = .{ .value = 0xFF77CC44 },
        .x = 10,
        .y = 10,
    };

    context.size = 64;
    _ = try context.render(&buf, "Hello, World!");

    return error.Magic;
}
