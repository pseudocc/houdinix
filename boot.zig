const std = @import("std");
const kernel = @import("kernel/houdinix.zig");

const uefi = std.os.uefi;
const fmt = std.fmt;
const Type = std.builtin.Type;

const page_size = 4096;

const TextOutput = uefi.protocol.SimpleTextOutput;
const File = uefi.protocol.File;
const FileSystem = uefi.protocol.SimpleFileSystem;
const Error = uefi.Status.EfiError;
const allocator = uefi.pool_allocator;

var stdout: *TextOutput = undefined;
var stderr: *TextOutput = undefined;
var boot_services: *uefi.tables.BootServices = undefined;
var root_dir: *File = undefined;

fn efifwrite(to: *TextOutput, text: []const u8) Error!void {
    const little = std.mem.nativeToLittle;
    var u16buf: [page_size]u16 = undefined;
    const view = std.unicode.Utf8View.init(text) catch unreachable;
    var it = view.iterator();
    var i: usize = 0;

    while (it.nextCodepoint()) |codepoint| {
        if (codepoint < 0x10000) {
            u16buf[i] = little(u16, @intCast(codepoint));
            i += 1;
        } else {
            const high = @as(u16, @intCast((codepoint - 0x10000) >> 10)) + 0xD800;
            const low = @as(u16, @intCast(codepoint & 0x3FF)) + 0xDC00;
            u16buf[i..][0..2].* = .{ little(u16, high), little(u16, low) };
            i += 2;
        }

        if (i + 3 > u16buf.len) {
            u16buf[i] = 0;
            try to.outputString(u16buf[0..i :0]).err();
            i = 0;
        }
    }

    u16buf[i] = 0;
    try to.outputString(u16buf[0..i :0]).err();
}

inline fn efiwrite(text: []const u8) Error!void {
    try efifwrite(stdout, text);
}

inline fn efifprint(to: *TextOutput, comptime format: []const u8, args: anytype) Error!void {
    var u8buf: [page_size]u8 = undefined;
    const utf8 = fmt.bufPrint(&u8buf, format, args) catch return Error.BufferTooSmall;
    try efifwrite(to, utf8);
}

inline fn efiprint(comptime format: []const u8, args: anytype) Error!void {
    try efifprint(stdout, format, args);
}

const MemoryMap = struct {
    const Item = uefi.tables.MemoryDescriptor;

    ptr: [*]Item,
    size: usize,
    alignment: usize,
    key: usize,

    pub inline fn iterator(self: *const MemoryMap) Iterator {
        return .{ .mmap = self, .index = 0 };
    }

    pub const Iterator = struct {
        mmap: *const MemoryMap,
        index: usize,

        pub fn next(self: *@This()) ?*Item {
            if (self.index >= self.mmap.size)
                return null;
            self.index += self.mmap.alignment;
            const addr: usize = @intFromPtr(self.mmap.ptr);
            return @ptrFromInt(addr + self.index);
        }
    };
};

fn memmap() Error!MemoryMap {
    var mmap: [*]uefi.tables.MemoryDescriptor = undefined;
    var key: usize = undefined;
    var mmap_sz: usize = 0;
    var desc_sz: usize = undefined;
    var desc_ver: u32 = undefined;

    const error_union = boot_services.getMemoryMap(&mmap_sz, null, &key, &desc_sz, &desc_ver).err();
    if (error_union) unreachable else |err| if (err != Error.BufferTooSmall) {
        inline for (.{ stdout, stderr }) |to|
            try efifwrite(to, "Failed to retrieve memory map size\r\n");
        return err;
    }

    mmap_sz += 2 * desc_sz;
    const raw_ptr = allocator.alloc(u8, mmap_sz) catch return Error.OutOfResources;
    mmap = @ptrCast(@alignCast(raw_ptr));
    errdefer allocator.free(raw_ptr);

    try boot_services.getMemoryMap(&mmap_sz, mmap, &key, &desc_sz, &desc_ver).err();

    return .{
        .ptr = mmap,
        .size = mmap_sz,
        .alignment = desc_sz,
        .key = key,
    };
}

fn kernel_entry(comptime T: type, root: *const File, path: []const u8) Error!T {
    const u16path = std.unicode.utf8ToUtf16LeAllocZ(allocator, path) catch return Error.OutOfResources;
    defer allocator.free(u16path);

    var file: *File = undefined;
    try root.open(&file, u16path, File.efi_file_mode_read, File.efi_file_read_only).err();
    defer _ = file.close();

    var size: usize = 0;
    try file.setPosition(File.efi_file_position_end_of_file).err();
    try file.getPosition(&size).err();
    try file.setPosition(0).err();

    const buffer = allocator.alloc(u8, size) catch return Error.OutOfResources;

    var reader = file.reader();
    _ = reader.readAll(buffer) catch unreachable;

    var source = std.io.fixedBufferStream(buffer);
    const header = std.elf.Header.read(&source) catch {
        try efiwrite("Failed to read ELF header\r\n");
        return Error.LoadError;
    };

    var phit = header.program_header_iterator(&source);
    while (phit.next() catch return Error.EndOfFile) |ph| {
        if (ph.p_type == std.elf.PT_LOAD) {
            const dest: []u8 = @as([*]u8, @ptrFromInt(ph.p_vaddr))[0..ph.p_memsz];
            @memcpy(dest, buffer[ph.p_offset .. ph.p_offset + ph.p_filesz]);
            @memset(dest[ph.p_filesz..], 0);
        }
    }

    return @ptrFromInt(header.entry);
}

fn efimain() Error!void {
    stdout = uefi.system_table.con_out orelse return Error.NotStarted;
    stderr = uefi.system_table.std_err orelse return Error.NotStarted;
    boot_services = uefi.system_table.boot_services orelse return Error.NotStarted;

    const lip = try boot_services.openProtocolSt(uefi.protocol.LoadedImage, uefi.handle);
    const fs = try boot_services.openProtocolSt(FileSystem, lip.device_handle.?);
    try fs.openVolume(&root_dir).err();
    errdefer _ = root_dir.close();

    const GraphicsOutput = uefi.protocol.GraphicsOutput;
    var maybe_gop: ?*GraphicsOutput = null;
    try boot_services.locateProtocol(&GraphicsOutput.guid, null, @ptrCast(&maybe_gop)).err();
    const gop = maybe_gop orelse return Error.NotFound;

    gop.setMode(0).err() catch |err| {
        try efiprint("Failed to set graphics mode: {}\r\n", .{err});
        return err;
    };
    inline for (.{ stdout, stderr }) |to|
        _ = to.reset(false);
    const gm = gop.mode;
    var bp: kernel.BootParam = .{
        .framebuffer = @ptrFromInt(gm.frame_buffer_base),
        .width = gm.info.horizontal_resolution,
        .height = gm.info.vertical_resolution,
        .pitch = gm.info.pixels_per_scan_line * @sizeOf(u32),
        .argc = 0,
        .argv = null,
    };

    const args = std.os.argv;
    if (args.len > 1) {
        bp.argc = @intCast(args.len - 1);
        var argv = allocator.alloc([*c]u8, args.len) catch return Error.OutOfResources;
        for (0..args.len - 2) |i| {
            argv[i] = allocator.dupeZ(u8, std.mem.sliceTo(args[i + 1], 0)) catch return Error.OutOfResources;
        }
        argv[args.len - 1] = null;
        bp.argv = @ptrCast(argv);
    }

    const KernelEntry = *fn (bp: *kernel.BootParam) callconv(.SysV) noreturn;
    const entry = kernel_entry(KernelEntry, root_dir, "boot\\houdinix") catch |err| {
        try efiprint("Failed to read ELF file: {}\r\n", .{err});
        return;
    };

    const mmap = try memmap();
    boot_services.exitBootServices(uefi.handle, mmap.key).err() catch |err| {
        try efiprint("Failed to exit the UEFI boot services: {}\r\n", .{err});
        return;
    };

    @call(.never_inline, entry, .{&bp});
}

pub fn main() uefi.Status {
    return if (efimain()) .Success else |err| unwrap: {
        inline for (comptime std.meta.fields(Error)) |field| {
            const name = field.name;
            if (err == @field(Error, name))
                break :unwrap @field(uefi.Status, name);
        }
        unreachable;
    };
}
