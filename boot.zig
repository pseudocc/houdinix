const std = @import("std");

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

fn cat(root: *const File, path: []const u8) Error!void {
    const u16path = std.unicode.utf8ToUtf16LeAllocZ(allocator, path) catch return Error.OutOfResources;
    defer allocator.free(u16path);

    var file: *File = undefined;
    try root.open(&file, u16path, File.efi_file_mode_read, File.efi_file_read_only).err();
    defer _ = file.close();

    var buf: [page_size]u8 = undefined;
    var reader = file.reader();
    var bytes_read: usize = 0;
    while (true) {
        bytes_read = reader.read(&buf) catch return Error.OutOfResources;
        if (bytes_read == 0)
            break;
        try efiwrite(buf[0..bytes_read]);
    }
}

fn efimain() Error!void {
    stdout = uefi.system_table.con_out orelse return Error.NotStarted;
    stderr = uefi.system_table.std_err orelse return Error.NotStarted;
    boot_services = uefi.system_table.boot_services orelse return Error.NotStarted;

    const lip = try boot_services.openProtocolSt(uefi.protocol.LoadedImage, uefi.handle);
    const fs = try boot_services.openProtocolSt(FileSystem, lip.device_handle.?);
    try fs.openVolume(&root_dir).err();
    defer _ = root_dir.close();

    const mmap = try memmap();
    var ram_sz: usize = 0;
    var it = mmap.iterator();
    while (it.next()) |desc| {
        if (desc.type == .ConventionalMemory)
            ram_sz += desc.number_of_pages * page_size;
    }

    const KB = 1 << 10;
    const MB = 1 << 20;
    const GB = 1 << 30;

    const unit: u8 = value: {
        if (ram_sz < KB) break :value 0;
        if (ram_sz < MB) break :value 'K';
        if (ram_sz < GB) break :value 'M';
        break :value 'G';
    };

    const amount = switch (unit) {
        'K' => @as(f64, @floatFromInt(ram_sz)) / KB,
        'M' => @as(f64, @floatFromInt(ram_sz)) / MB,
        'G' => @as(f64, @floatFromInt(ram_sz)) / GB,
        else => {
            try efiprint("RAM size: {} B\r\n", .{ram_sz});
            return;
        },
    };

    try efiprint("RAM size: {d:.1} {c}B\r\n", .{ amount, unit });

    try efifwrite(stdout, "Reading file hello.txt:\r\n");
    cat(root_dir, "hello.txt") catch |err| {
        try efiprint("Failed to read file: {}\r\n", .{err});
    };
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
