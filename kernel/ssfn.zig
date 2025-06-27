const std = @import("std");
const testing = std.testing;
const log = std.log;

const logger = log.scoped(.ssfn);
const imax = std.math.maxInt;

pub const version: std.SemanticVersion = .{
    .major = 2,
    .minor = 0,
    .patch = 0,
};

fn magic(comptime T: type, comptime bytes: []const u8) T {
    if (bytes.len != @sizeOf(T))
        @compileError("magic bytes must be the same size as the type");
    return @as(*const T, @ptrCast(@alignCast(bytes))).*;
}

const magics = struct {
    const start: u32 = magic(u32, "SFN2");
    const end: u32 = magic(u32, "2NFS");
    const collection: u32 = magic(u32, "SFNC");
    const gzip: u16 = 0x8b1f;
};

const ligatures = struct {
    const first = 0xf000;
    const end = 0xf8ff;
};

const Family = enum(u4) {
    const Length = @intFromEnum(Family.handwriting) + 1;

    serif = 0,
    sans_serif,
    decorative,
    monospace,
    handwriting,
    _,

    const Query = union(enum) {
        simple: Family,
        /// By unique name
        name: []const u8,
        /// First loaded font
        any: void,
    };

    fn valid(self: Family) bool {
        return @intFromEnum(self) < Length;
    }
};

const Style = packed struct(u4) {
    bold: bool = false,
    italic: bool = false,
    user_defined1: bool = false,
    user_defined2: bool = false,

    const All = packed struct {
        bold: bool = false,
        italic: bool = false,
        user_defined1: bool = false,
        user_defined2: bool = false,
        // Additional flags
        underline: bool = false,
        striketrough: bool = false,
        no_antialiasing: bool = false,
        no_kerning: bool = false,
        no_default_glyph: bool = false,
        no_cache: bool = false,
        no_hinting: bool = false,
        right_to_left: bool = false,
        absolute_size: bool = false,
        no_smooth: bool = false,
    };

    fn unmask(self: Style) u4 {
        const u4ptr: *const u4 = @ptrCast(&self);
        return u4ptr.*;
    }
};

const Contour = enum(u8) {
    move = 0,
    line,
    quad,
    cubic,
};

const Fragment = enum(u8) {
    contour = 0,
    bitmap,
    pixmap,
    kerning,
    hinting,
};

/// Main SSFN header (32 bytes)
const Font = packed struct {
    const Offsets = packed struct {
        fragments: u16,
        characters: u32,
        ligatures: u32,
        kerning: u32,
        color_map: u32,
    };

    /// SSFN magic bytes
    magic: u32,
    /// Total size in bytes
    size: u32,
    /// font family
    family: Family,
    /// font style
    style: Style,
    /// Format features and revision
    features: u8,

    /// Overall width of the font
    width: u8,
    /// Overall height of the font
    height: u8,
    /// Horizontal baseline in grid pixels
    baseline: u8,
    /// Position of the underline in grid pixels
    underline: u8,

    /// Offset of different tables
    offsets: Offsets,

    pub const Pointer = *align(1) const Font;

    pub fn load(data: []const u8) !Pointer {
        if (data.len < @sizeOf(Font))
            return error.BufferTooSmall;

        const font: Pointer = @ptrCast(data);
        if (font.magic != magics.start)
            return error.BadFile;
        if (font.size > data.len)
            return error.BadFile;
        const endpos: usize = @as(usize, @intCast(font.size)) - @sizeOf(@TypeOf(magics.end));
        if (@as(*align(1) const u32, @ptrCast(data[endpos..])).* != magics.end)
            return error.BadFile;
        if (!font.family.valid())
            return error.BadFile;
        inline for (std.meta.fields(Offsets)) |field| {
            if (@field(font.offsets, field.name) >= font.size)
                return error.BadFile;
        }

        return font;
    }

    pub inline fn name(self: Pointer) []const u8 {
        return self.iterator(u8, 0, @sizeOf(Font)).?;
    }

    /// Smallest size we can render
    pub const MinSize = 8;
    /// Biggest size we can render
    pub const MaxSize = 192;

    pub fn iterator(self: Pointer, comptime T: type, comptime sentinel: T, offsets: usize) ?[]align(1) const T {
        if (offsets == 0)
            return null;
        const start_addr: usize = @intFromPtr(@constCast(self)) + offsets;
        const ptr: [*:sentinel]const T = @ptrFromInt(start_addr);
        var i: usize = 0;
        while (ptr[i] != sentinel) : (i += 1) {}
        return ptr[0..i];
    }

    pub inline fn pointer(self: Pointer, comptime T: type, offsets: usize) [*]align(1) const T {
        const start_addr: usize = @intFromPtr(@constCast(self)) + offsets;
        return @ptrFromInt(start_addr);
    }

    const ParseResult = struct {
        maybe_ptr: ?*align(1) const Character,
        processed: u32,
        unicode: u32,
    };

    fn parse(font: Font.Pointer, text: []const u8) !ParseResult {
        var result: ParseResult = .{
            .maybe_ptr = null,
            .processed = 0,
            .unicode = 0,
        };
        if (font.offsets.characters == 0 or text.len == 0)
            return result;

        var u: u32 = imax(u32);
        if (font.iterator(u16, imax(u16), font.offsets.ligatures)) |ls| {
            for (ls, 0..) |l, i| z: {
                const skip_bytes = font.iterator(u8, 0, l) orelse continue;
                for (skip_bytes, 0..) |b, j| {
                    if (b != text[j]) {
                        u = @intCast(ligatures.first + i);
                        break :z;
                    }
                }
            }
        }

        if (u == imax(u32)) {
            const n = try std.unicode.utf8ByteSequenceLength(text[0]);
            const unicode = try std.unicode.utf8Decode(text[0..n]);
            u = @intCast(unicode);

            result.processed = @intCast(n);
            result.unicode = u;
        }

        var ptr: [*]const u8 = @ptrCast(font.iterator(u8, 0, font.offsets.characters));
        var i: usize = 0;
        while (i < 0x110000) : (i += 1) {
            if (ptr[0] == imax(u8)) {
                ptr = ptr[1..];
                i += imax(u16);
                continue;
            }
            switch (ptr[0] & 0xc0) {
                0xc0 => {
                    const j = (@as(u32, @intCast(ptr[0] & 0x3f)) << 8) | ptr[1];
                    ptr = ptr[2..];
                    i += @intCast(j);
                },
                0x80 => {
                    const j = @as(u32, @intCast(ptr[0] & 0x3f));
                    ptr = ptr[1..];
                    i += @intCast(j);
                },
                else => {
                    if (i == u) {
                        result.maybe_ptr = @ptrCast(ptr);
                        break;
                    }
                    const factor: usize = if (ptr[0] & 0x40 == 0) 5 else 6;
                    const pace = 6 + @as(usize, @intCast(ptr[1])) * factor;
                    ptr = ptr[pace..];
                },
            }
        }

        return result;
    }
};

const ITALIC_DIV = 4;
const PRECISION = 4;

test Font {
    testing.log_level = .debug;

    try testing.expectEqual(32, @sizeOf(Font));

    const gohu = try Font.load(@embedFile("Gohu-Nerd.sfn"));
    logger.info("{}", .{gohu});
    try testing.expectEqualStrings("Gohu Nerd", gohu.name());

    const text = "Hello,  ";
    const expected_results: []const std.meta.Tuple(&.{ ?usize, u32, u32 }) = &.{
        .{ 1217959, 1, 72 },
        .{ 1218503, 1, 101 },
        .{ 1218640, 1, 108 },
        .{ 1218640, 1, 108 },
        .{ 1218688, 1, 111 },
        .{ 1217446, 1, 44 },
        .{ 1217229, 1, 32 },
        .{ 1249120, 3, 60036 },
        .{ 1217229, 1, 32 },
    };
    var i: usize = 0;
    for (expected_results) |expected| {
        const result = try gohu.parse(text[i..]);
        const offset: ?usize = if (result.maybe_ptr) |p| @intFromPtr(p) - @intFromPtr(gohu) else null;
        try testing.expectEqual(expected[0], offset);
        try testing.expectEqual(expected[1], result.processed);
        try testing.expectEqual(expected[2], result.unicode);
        i += result.processed;
    }
}

pub const Color = extern union {
    const Size = @sizeOf(u32);

    value: u32,
    argb: ARGB,
    abgr: ABGR,
    raw: [Size]u8,

    const ARGB = packed struct {
        b: u8 = 0,
        g: u8 = 0,
        r: u8 = 0,
        a: u8 = 0,
    };
    const ABGR = packed struct {
        r: u8 = 0,
        g: u8 = 0,
        b: u8 = 0,
        a: u8 = 0,
    };

    fn put(self: *Color, color: Color) void {
        const a: u16 = color.argb.a;
        inline for (0..Size) |i| {
            if (self.raw[i] < color.raw[i]) {
                const d: u16 = color.raw[i] - self.raw[i];
                self.raw[i] += @intCast(d * a >> 8);
            } else {
                const d: u16 = self.raw[i] - color.raw[i];
                self.raw[i] -= @intCast(d * a >> 8);
            }
        }
    }
};

test Color {
    const color: Color = Color{ .value = 0x11223344 };
    const argb: Color.ARGB = color.argb;
    try testing.expectEqual(0x11, argb.a);
    try testing.expectEqual(0x22, argb.r);
    try testing.expectEqual(0x33, argb.g);
    try testing.expectEqual(0x44, argb.b);
}

pub const Buffer = struct {
    /// Pointer to the buffer
    ptr: [*c]Color,
    width: u32,
    height: u32,
    /// Bytes per line
    pitch: u32,

    /// Cursor position x
    x: u32,
    /// Cursor position y
    y: u32,

    /// foreground color
    fg: Color,
    /// background color
    bg: Color,
};

/// Cached bitmap structure
pub const Glyph = struct {
    const DataLength = 65536;
    pitch: u32,
    height: u8,
    overlap: u8,
    x: u8,
    y: u8,
    ascender: u8,
    descender: u8,
    data: [DataLength]u8,
};

/// Character metrics
pub const Character = packed struct {
    /// type and overlap
    type: u8,
    /// number of fragments
    n: u8,
    width: u8,
    height: u8,
    /// advance x
    x: u8,
    /// advance y
    y: u8,
};

const up = u32;
const ip = i32;
const Array = std.ArrayList;
const HashMap = std.AutoHashMap;
const Allocator = std.mem.Allocator;
const Self = @This();

const Cord = struct {
    x: up = 0,
    y: up = 0,
};

allocator: Allocator,
fonts: [Family.Length]Array(Font.Pointer),
maybe_selected: ?Font.Pointer = null,
maybe_owned: ?[]const u8 = null,
paths: Array(Cord),
cache: HashMap(u32, Glyph),
move: Cord = .{},
last: Cord = .{},
overlap: Cord = .{},
/// Requested font
family: Family.Query = .any,
/// Requested style
style: Style.All = .{},
/// Requested size
size: up = 0,
/// calculate line height
line: up = 0,

pub fn init(allocator: Allocator) Self {
    var self: Self = .{
        .fonts = undefined,
        .paths = Array(Cord).init(allocator),
        .cache = HashMap(u32, Glyph).init(allocator),
        .allocator = allocator,
    };
    for (&self.fonts) |*fonts| {
        fonts.* = Array(Font.Pointer).init(allocator);
    }
    return self;
}

fn _load(self: *Self, data: []const u8) !Font.Pointer {
    const font = try Font.load(data);
    const family: usize = @intFromEnum(font.family);
    try self.fonts[family].append(font);
    return font;
}

pub fn load(self: *Self, data: []const u8) !void {
    const raw: []const u8 = if (@as(*align(1) const u16, @ptrCast(data)).* == magics.gzip) gz: {
        var decompressed = Array(u8).init(self.allocator);
        errdefer decompressed.deinit();

        var stream = std.io.fixedBufferStream(data);
        try std.compress.gzip.decompress(stream.reader(), decompressed.writer());

        const owned = try decompressed.toOwnedSlice();
        self.maybe_owned = owned;
        break :gz owned;
    } else data;

    const peek_font: Font.Pointer = @ptrCast(raw);
    if (peek_font.magic == magics.collection) {
        var i: usize = @sizeOf(@TypeOf(peek_font.magic)) + @sizeOf(@TypeOf(peek_font.size));
        while (i < peek_font.size) {
            const font = try self._load(raw[i..]);
            i += font.size;
        }
    } else {
        _ = try self._load(raw);
    }
}

pub fn deinit(self: *Self) void {
    if (self.maybe_owned) |ptr|
        self.allocator.free(ptr);
    self.paths.deinit();
    self.cache.deinit();

    for (&self.fonts) |fonts| {
        fonts.deinit();
    }
}

const Match = enum {
    both,
    size,
    style,
    either_style,
};

fn _match(self: *const Self, comptime match: Match, font: Font.Pointer) bool {
    return switch (match) {
        .both => self.size == font.height and self.style.bold == font.style.bold and self.style.italic == font.style.italic,
        .size => self.size == font.height,
        .style => self.style.bold == font.style.bold and self.style.italic == font.style.italic,
        .either_style => self.style.bold or self.style.italic,
    };
}

inline fn narrow(v: up) up {
    return (v + (1 << (PRECISION - 1))) >> PRECISION;
}

fn lineTo(self: *Self, pitch: up, height: up, pos: Cord) !void {
    if (pos.x >= pitch or pos.y >= height)
        return;
    if (narrow(self.last.x) == narrow(pos.x) and narrow(self.last.y) == narrow(pos.y))
        return;

    try self.paths.append(pos);
    self.last = pos;
}

fn bezierTo(self: *Self, pitch: up, height: up, p0: Cord, p1: Cord, p2: Cord, p3: Cord, length: up) !void {
    if (length < 4 and (p0.x != p3.x or p0.y != p3.y)) {
        const m0: Cord = .{
            .x = (p0.x + p1.x) >> 1,
            .y = (p0.y + p1.y) >> 1,
        };
        const m1: Cord = .{
            .x = (p1.x + p2.x) >> 1,
            .y = (p1.y + p2.y) >> 1,
        };
        const m2: Cord = .{
            .x = (p2.x + p3.x) >> 1,
            .y = (p2.y + p3.y) >> 1,
        };
        const m3: Cord = .{
            .x = (m0.x + m1.x) >> 1,
            .y = (m0.y + m1.y) >> 1,
        };
        const m4: Cord = .{
            .x = (m1.x + m2.x) >> 1,
            .y = (m1.y + m2.y) >> 1,
        };
        const m5: Cord = .{
            .x = (m3.x + m4.x) >> 1,
            .y = (m3.y + m4.y) >> 1,
        };
        try bezierTo(self, pitch, height, p0, m0, m3, m5, length + 1);
        try bezierTo(self, pitch, height, m5, m4, m2, p3, length + 1);
    }

    if (length != 0)
        try self.lineTo(pitch, height, p3);
}

pub fn render(self: *Self, buf: *Buffer, text: []const u8) !u32 {
    if (text.len == 0)
        return 0;
    if (buf.ptr == null)
        return error.NullBuffer;

    var maybe_font: ?Font.Pointer = null;
    var result = if (self.maybe_selected) |f| has: {
        maybe_font = f;
        break :has try f.parse(text);
    } else hasnt: {
        var family_query = self.family;
        var n: up = undefined;
        var m: up = undefined;

        while (true) {
            switch (family_query) {
                .name => return error.AssertionFailed,
                .any => {
                    n = 0;
                    m = Family.Length;
                },
                .simple => |family| {
                    if (!family.valid())
                        return error.InvalidFamily;
                    n = @intFromEnum(family);
                    m = n + 1;
                },
            }

            while (n < m) : (n += 1) {
                const fonts = self.fonts[n];
                if (self.style.bold or self.style.italic) {
                    inline for (.{ .both, .size, .style }) |match| {
                        for (fonts.items) |f| {
                            if (self._match(match, f)) {
                                const result = try f.parse(text);
                                if (result.maybe_ptr) |_| {
                                    maybe_font = f;
                                    break :hasnt result;
                                }
                            }
                        }
                    }
                    if (self.style.bold or self.style.italic) {
                        for (fonts.items) |f| {
                            if (self._match(.either_style, f)) {
                                const result = try f.parse(text);
                                if (result.maybe_ptr) |_| {
                                    maybe_font = f;
                                    break :hasnt result;
                                }
                            }
                        }
                    }
                }
                for (fonts.items) |f| {
                    const result = try f.parse(text);
                    if (result.maybe_ptr) |_| {
                        maybe_font = f;
                        break :hasnt result;
                    }
                }
            }

            if (family_query == .any)
                break;
            family_query = .any;
        }

        break :hasnt Font.ParseResult{
            .maybe_ptr = null,
            .processed = 0,
            .unicode = 0,
        };
    };

    if (result.maybe_ptr == null) {
        if (self.style.no_default_glyph)
            return error.GlyphNotFound;

        var n: up = undefined;
        var m: up = undefined;

        switch (self.family) {
            .name => return error.AssertionFailed,
            .any => {
                n = 0;
                m = Family.Length;
            },
            .simple => |family| {
                if (!family.valid())
                    return error.InvalidFamily;
                n = @intFromEnum(family);
                m = n + 1;
            },
        }

        while (n < m and result.maybe_ptr == null) : (n += 1) {
            const fonts = self.fonts[n];
            if (fonts.items.len == 0)
                continue;
            const f = fonts.items[0];
            const p: [*]const u8 = @ptrCast(f.iterator(u8, 0, f.offsets.characters));

            if (p[0] & 0x80 != 0) {
                maybe_font = f;
                result.maybe_ptr = @ptrCast(p);
            }
        }

        if (result.maybe_ptr == null)
            return error.GlyphNotFound;
    }

    const font = maybe_font orelse return error.FontNotFound;
    const base: [*]const u8 = @ptrCast(font);
    if (font.height == 0)
        return error.InvalidFont;
    if (self.size < Font.MinSize or self.size > Font.MaxSize)
        return error.InvalidSize;

    const rc = result.maybe_ptr.?;
    const sz: up = self.size;
    const fh: up = font.height;
    const fb: up = font.baseline;

    var ptr = @as([*]const u8, @ptrCast(rc))[@sizeOf(Character)..];
    const H: up = if (self.style.absolute_size or font.family == .monospace or fb == 0) sz else sz * fh / fb;
    var h: up = if (self.style.no_antialiasing) H else (if (sz > fh) (sz + 4) & ~@as(up, 3) else fh);
    const ci = self.style.italic and font.style.italic;
    var cb: up = if (self.style.bold and font.style.bold) (fh >> 6) + 1 else 0;
    var w: up = (@as(up, @intCast(rc.width)) * h + fh - 1) / fh;
    if (w > Font.MaxSize) {
        h = (h * Font.MaxSize + w - 1) / w;
        w = Font.MaxSize;
    }
    const p: up = w + cb + if (ci) h / ITALIC_DIV else 0;
    var x: up = if (rc.x > 0 and ci) (fh - fb) * h / ITALIC_DIV / fh else 0;
    var y: up = undefined;

    const cache = try self.cache.getOrPut(result.unicode);
    if (!cache.found_existing) {
        const g = cache.value_ptr;
        var color: u8 = 0xfe;
        g.pitch = p;
        g.height = @intCast(h);
        g.x = z: {
            const sum: up = rc.x + x;
            const value: u8 = if (sum > imax(u8)) imax(u8) else @as(u8, @intCast(sum));
            break :z value;
        };
        g.y = rc.y;
        g.overlap = @intCast(rc.type & 0x3f + x);
        g.ascender = 0;
        g.descender = 0;
        if (p * h > Glyph.DataLength)
            return error.AssertionFailed;
        @memset(g.data[0 .. p * h], 0xff);

        var r: Array(up) = Array(up).init(self.allocator);
        defer r.deinit();

        for (0..rc.n) |_| {
            if (ptr[0] == 0xff and ptr[1] == 0xff) {
                color = ptr[2];
                const pace: u8 = if (rc.type & 0x40 != 0) 6 else 5;
                ptr = ptr[pace..];
                continue;
            }

            x = ((@as(up, ptr[0]) + cb) << PRECISION) * h / fh;
            y = (@as(up, ptr[1]) << PRECISION) * h / fh;
            ptr = ptr[2..];

            const fragments_offset = z: {
                var yield: usize = 0;
                for (0..if (rc.type & 0x40 != 0) 4 else 3) |i| {
                    const v: usize = @intCast(ptr[i]);
                    yield |= v << @as(u6, @intCast(i * 8));
                }
                break :z yield;
            };

            var fragments = base[fragments_offset..];
            if (fragments[0] & 0x80 == 0) {
                // contour
                var j: up = fragments[0] & 0x3f;
                if (fragments[0] & 0x40 != 0) {
                    j = (j << 8) | fragments[1];
                    fragments = fragments[1..];
                }
                fragments = fragments[1..];
                j += 1;

                const now_fragments = fragments;
                const pp = p << PRECISION;
                const hp = h << PRECISION;
                for (0..j) |i| {
                    const z: Cord = .{
                        .x = ((@as(up, fragments[0]) << PRECISION) * h / fh) + x,
                        .y = ((@as(up, fragments[1]) << PRECISION) * h / fh) + y,
                    };
                    const t: u3 = @intCast((i & 3) << 1);
                    const contour = now_fragments[i >> 2] >> t;
                    switch (@as(Contour, @enumFromInt(contour & 3))) {
                        .move => {
                            self.move = z;
                            self.last = z;
                            fragments = fragments[2..];
                        },
                        .line => {
                            try self.lineTo(pp, hp, z);
                            fragments = fragments[2..];
                        },
                        .quad => {
                            const a: Cord = .{
                                .x = ((@as(up, fragments[2]) << PRECISION) * h / fh) + x,
                                .y = ((@as(up, fragments[3]) << PRECISION) * h / fh) + y,
                            };
                            const b: Cord = .{
                                .x = (a.x + self.last.x) >> 1,
                                .y = (a.y + self.last.y) >> 1,
                            };
                            const c: Cord = .{
                                .x = ((z.x + a.x) >> 1),
                                .y = ((z.y + a.y) >> 1),
                            };
                            try self.bezierTo(pp, hp, self.last, b, c, z, 0);
                            fragments = fragments[4..];
                        },
                        .cubic => {
                            const a: Cord = .{
                                .x = ((@as(up, fragments[2]) << PRECISION) * h / fh) + x,
                                .y = ((@as(up, fragments[3]) << PRECISION) * h / fh) + y,
                            };
                            const b: Cord = .{
                                .x = ((@as(up, fragments[4]) << PRECISION) * h / fh) + x,
                                .y = ((@as(up, fragments[5]) << PRECISION) * h / fh) + y,
                            };
                            try self.bezierTo(pp, hp, self.last, a, b, z, 0);
                            fragments = fragments[6..];
                        },
                    }
                }

                // close path
                if (self.move.x != self.last.x or self.move.y != self.last.y) {
                    try self.paths.append(self.move);
                }

                // add rasterized vector layers to cached glyph
                if (self.paths.items.len > 2) {
                    var A: ip = 0;
                    var o: ip = 0;
                    var b: up = 0;
                    var B: up = 0;
                    while (b < h) {
                        defer {
                            b += 1;
                            B += p;
                        }

                        const a = b << PRECISION;

                        var i: up = 0;
                        while (i < self.paths.items.len - 1) : (i += 1) {
                            const p0 = self.paths.items[i];
                            const p1 = self.paths.items[i + 1];
                            if ((p0.y >= a or p1.y < a) and (p1.y >= a or p0.y < a))
                                continue;
                            x = if (p0.y >> PRECISION == p1.y >> PRECISION)
                                (p0.x + p1.x) >> 1
                            else
                                p0.x + (a - p0.y) * (p1.x - p0.x) / (p1.y - p0.y);
                            x >>= PRECISION;
                            if (ci)
                                x += (h - b) / ITALIC_DIV;
                            if (cb != 0 and o != 0) {
                                if (g.data[B + x] != color) {
                                    o = -@as(ip, @intCast(cb));
                                    A = @intCast(cb);
                                } else {
                                    o = @intCast(cb);
                                    A = -@as(ip, @intCast(cb));
                                }
                            }

                            for (r.items, 0..) |ri, k| {
                                if (x <= ri) {
                                    try r.insert(k, x);
                                    break;
                                }
                            }
                        }

                        if (r.items.len % 2 == 1) {
                            const rl = r.items.len;
                            r.items[rl - 2] = r.pop();
                        }

                        if (r.items.len == 0)
                            continue;
                        g.descender = @max(g.descender, @as(u8, @intCast(y + b)));

                        i = 0;
                        while (i < r.items.len - 1) : (i += 2) {
                            var l: ip = @as(ip, @intCast(r.items[i])) + o;
                            var m: ip = @as(ip, @intCast(r.items[i + 1])) + A;
                            l = @max(l, 0);
                            m = @min(m, @as(ip, @intCast(p)));
                            if (i > 0)
                                l = @max(l, @as(ip, @intCast(r.items[i - 1])) + A);
                            while (l < m) : (l += 1) {
                                const d = &g.data[B + @as(up, @intCast(l))];
                                d.* = if (color == 0xff) d.* else color;
                            }
                        }
                    }
                }
            } else if (fragments[0] & 0x60 == 0) {
                // bitmap
                const B: up = @as(up, @intCast((fragments[0] & 0x1f) + 1)) << 3;
                const A: up = @as(up, @intCast(fragments[1])) + 1;
                fragments = fragments[2..];

                x >>= PRECISION;
                y >>= PRECISION;
                const b: up = B * h / fh;
                const a: up = A * h / fh;
                g.descender = @max(g.descender, @as(u8, @intCast(y + a)));

                for (0..a) |j| {
                    const k = @as(up, @intCast(j)) * A / a;
                    const l = (y + @as(up, @intCast(j))) * p + x + (if (ci) (h - y - j) / ITALIC_DIV else 0);
                    for (0..b) |i| {
                        const m = @as(up, @intCast(i)) * B / b;
                        const fi: usize = @intCast((k * B + m) >> 3);
                        const mask: u8 = @as(u8, 1) << @as(u3, @intCast(m & 7));
                        if (fragments[fi] & mask != 0) {
                            for (0..cb + 1) |o| {
                                const di: usize = @intCast(l + i + o);
                                g.data[di] = color;
                            }
                        }
                    }
                }

                if (!self.style.no_antialiasing and !self.style.no_smooth) {
                    const m: u8 = if (color == 0xfd) 0xfc else 0xfd;
                    const o: up = y * p + p + x;

                    var k: ip = @intCast(h);
                    const d: [*]u8 = @ptrCast(&g.data[0]);
                    while (k > @as(ip, @intCast(fh + 4))) : (k -= @intCast(fh * 2)) {
                        for (1..a - 1) |j| {
                            const l: up = o + @as(up, @intCast(j - 1)) * p;
                            for (1..b - 1) |i| {
                                if (d[l + i] == 0xff and (d[l + i - p] == color or d[l + i + p] == color) and (d[l + i - 1] == color or d[l + i + 1] == color))
                                    d[l + i] = m;
                            }
                        }
                        for (1..a - 1) |j| {
                            const l: up = o + @as(up, @intCast(j - 1)) * p;
                            for (1..b - 1) |i| {
                                if (d[l + i] == m)
                                    d[l + i] = color;
                            }
                        }
                    }
                }
            } else if (fragments[0] & 0x60 == 0x20) {
                // pixmap
                const k: up = z: {
                    const high: up = @intCast(fragments[0] & 0x1f);
                    const low: up = @intCast(fragments[1]);
                    break :z ((high << 8) | low) + 1;
                };
                const B: up = @as(up, @intCast(fragments[2])) + 1;
                const A: up = @as(up, @intCast(fragments[3])) + 1;
                fragments = fragments[4..];

                x >>= PRECISION;
                y >>= PRECISION;
                const b: up = B * h / fh;
                const a: up = A * h / fh;

                const ya = y + a;
                if (ya > g.descender)
                    g.descender = @as(u8, @intCast(ya & 0xff));

                var dec = Array(u8).init(self.allocator);
                try dec.ensureTotalCapacity(@max(k << 8, imax(u16)));
                defer dec.deinit();

                var i: up = 0;
                while (i < k) {
                    const l: up = @as(up, @intCast(fragments[i] & 0x7f)) + 1;
                    const adds = try dec.addManyAsSlice(l);
                    if (fragments[i] & 0x80 != 0) {
                        defer i += 2;
                        const v = fragments[i + 1];
                        for (adds) |*add|
                            add.* = v;
                    } else for (adds) |*add| {
                        i += 1;
                        add.* = fragments[i];
                    }
                }

                var j: up = 0;
                while (j < a) : (j += 1) {
                    const kk = j * A / a * B;
                    const ll = (y + j) * p + x + (if (ci) (h - y - j) / ITALIC_DIV else 0);
                    i = 0;
                    while (i < b) : (i += 1) {
                        const m = dec.items[kk + i * B / b];
                        if (m == 0xff)
                            continue;
                        g.data[ll + i] = m;
                    }
                }
            }
            color = 0xfe;
        }

        g.ascender = font.baseline;
        if (g.descender > g.ascender + 1) {
            g.descender -= g.ascender + 1;
        } else {
            g.descender = 0;
        }
    }

    // blit glyph from cache to buffer
    const g: *const Glyph = cache.value_ptr;
    var s: up = undefined;
    var n: up = undefined;
    h = H;
    self.line = @max(self.line, h);
    w = g.pitch * h / g.height;
    s = ((g.x - g.overlap) * h + fh - 1) / fh;
    const N: up = if (self.size > 16) 2 else 1;
    w = @max(w, N);
    s = @max(s, N);
    if (g.x > 0) {
        self.overlap.x = (@as(up, @intCast(g.overlap)) * h + fh - 1) / fh;
        if (self.style.right_to_left)
            self.overlap.x += w;
        self.overlap.y = (@as(up, @intCast(g.ascender)) * h + fh - 1) / fh;
    } else {
        self.overlap.x = w / 2;
        self.overlap.y = 0;
    }

    if (buf.ptr != null) {
        const fg = buf.fg.argb;
        cb = (h >> 6) + 1;
        var uix: up = @max(w, s);
        var uax: up = 0;
        n = (@as(up, @intCast(font.underline)) * h + fh - 1) / fh;

        const pitch = buf.pitch / @sizeOf(Color);
        const Op = @as([*]Color, @ptrCast(buf.ptr));

        var max_x = @min(w, buf.width + self.overlap.x - buf.x);
        var max_y = @min(h, buf.height + self.overlap.y - buf.y);

        y = if (buf.y < self.overlap.y) self.overlap.y - buf.y else 0;
        while (y < max_y) : (y += 1) {
            x = if (buf.x < self.overlap.x) self.overlap.x - buf.x else 0;
            const dy = buf.y + y - self.overlap.y;
            const dx = buf.x + x - self.overlap.x;
            var Ol: [*]Color = Op[dy * pitch + dx ..];

            const y0 = (y << 8) * g.height / h;
            const Y0 = y0 >> 8;
            const y1 = ((y + 1) << 8) * g.height / h;
            const Y1 = y1 >> 8;

            while (x < max_x) : (x += 1) {
                const bg = (if (buf.bg.value == 0) Ol[0] else buf.bg).argb;
                defer Ol = Ol[1..];

                var m: up = 0;
                var sR: up = 0;
                var sG: up = 0;
                var sB: up = 0;
                var sA: up = 0;

                const x0 = (x << 8) * g.pitch / w;
                const X0 = x0 >> 8;
                const x1 = ((x + 1) << 8) * g.pitch / w;
                const X1 = x1 >> 8;

                var ys = y0;
                while (ys < y1) : (ys += 0x100) {
                    const yp: up = z: {
                        if (ys >> 8 == Y0) {
                            const v = 0x100 - (ys & 0xff);
                            ys &= ~@as(up, 0xff);
                            break :z @max(v, y1 - y0);
                        }
                        if (ys >> 8 == Y1)
                            break :z y1 & 0xff;
                        break :z 0x100;
                    };

                    const X2 = (ys >> 8) * g.pitch;
                    var xs = x0;
                    while (xs < x1) : (xs += 0x100) {
                        const pc: up = z: {
                            if (xs >> 8 == X0) {
                                const v = @as(up, 0x100) - (xs & 0xff);
                                xs &= ~@as(up, 0xff);
                                const k = @min(v, x1 - x0);
                                break :z if (k == 0x100) yp else (k * yp) >> 8;
                            }
                            if (xs >> 8 == X1) {
                                const k = x1 & 0xff;
                                break :z if (k == 0x100) yp else (k * yp) >> 8;
                            }
                            break :z yp;
                        };

                        m += pc;
                        const k = g.data[X2 + (xs >> 8)];
                        if (k == 0xff) {
                            sR += @as(up, @intCast(bg.r)) * pc;
                            sG += @as(up, @intCast(bg.g)) * pc;
                            sB += @as(up, @intCast(bg.b)) * pc;
                            sA += 0xff;
                        } else {
                            const d: Color.ARGB = z: {
                                if (k == 0xfe or font.offsets.color_map == 0)
                                    break :z fg;
                                const P = font.pointer(Color.ARGB, font.offsets.color_map);
                                break :z P[k];
                            };
                            sR += @as(up, @intCast(d.r)) * pc;
                            sG += @as(up, @intCast(d.g)) * pc;
                            sB += @as(up, @intCast(d.b)) * pc;
                            sA += @as(up, @intCast(d.a)) * pc;
                        }
                    }

                    if (m != 0) {
                        sR /= m;
                        sG /= m;
                        sB /= m;
                        sA /= m;
                    } else {
                        sR >>= 8;
                        sG >>= 8;
                        sB >>= 8;
                        sA >>= 8;
                    }

                    if (self.style.no_antialiasing)
                        sA = if (sA > 0x7f) 0xff else 0;
                    if (sA > 0xf) {
                        const _a: u8 = @intCast(@min(sA, 0xff));
                        const _r: u8 = @intCast(@min(sR, 0xff));
                        const _g: u8 = @intCast(@min(sG, 0xff));
                        const _b: u8 = @intCast(@min(sB, 0xff));
                        Ol[0].argb = .{
                            .a = @max(_a, bg.a),
                            .r = @max(_r, bg.r),
                            .g = @max(_g, bg.g),
                            .b = @max(_b, bg.b),
                        };
                        if (y == n) {
                            uix = @min(uix, x);
                            uax = @max(uax, x);
                        }
                    }
                }
            }
        }

        if (self.style.underline) {
            uix -= cb + 1;
            uax += cb + 2;
            if (uax < uix)
                uax = uix + 1;
            const k = @max(w, s) + 1;
            max_x = @min(k, buf.width + self.overlap.x - buf.x);
            max_y = @min(n + cb, buf.height + self.overlap.y - buf.y);
            y = if (buf.y < self.overlap.y) self.overlap.y - buf.y else n;
            while (y < max_y) : (y += 1) {
                x = if (buf.x < self.overlap.x) self.overlap.x - buf.x else 0;
                const dy = buf.y + y - self.overlap.y;
                const dx = buf.x + x - self.overlap.x;
                var Ol: [*]Color = Op[dy * pitch + dx ..];
                while (x < max_x) : (x += 1) {
                    defer Ol = Ol[1..];
                    Ol[0].put(Color{ .argb = fg });
                }
            }
        }

        if (self.style.striketrough) {
            n = h >> 1;
            const k = @max(w, s) + 1;
            max_x = @min(k, buf.width + self.overlap.x - buf.x);
            max_y = @min(n + cb, buf.height + self.overlap.y - buf.y);
            y = if (buf.y < self.overlap.y) self.overlap.y - buf.y else n;
            while (y < max_y) : (y += 1) {
                x = if (buf.x < self.overlap.x) self.overlap.x - buf.x else 0;
                const dy = buf.y + y - self.overlap.y;
                const dx = buf.x + x - self.overlap.x;
                var Ol: [*]Color = Op[dy * pitch + dx ..];
                while (x < max_x) : (x += 1) {
                    defer Ol = Ol[1..];
                    Ol[0].put(Color{ .argb = fg });
                }
            }
        }
    }

    if (self.style.right_to_left) {
        buf.x -= s;
    } else {
        buf.x += y;
    }
    buf.y += (g.y * h + fh - 1) / fh;

    if (!self.style.no_kerning and font.offsets.kerning != 0) {
        const peek = try font.parse(text[result.processed..]);
        if (peek.maybe_ptr != null and peek.unicode > 32) {
            ptr = @ptrCast(rc);
            ptr = ptr[@sizeOf(Character)..];
            for (0..rc.n) |_| {
                if (ptr[0] == 0xff and ptr[1] == 0xff) {
                    const pace: u8 = if (rc.type & 0x40 != 0) 6 else 5;
                    ptr = ptr[pace..];
                    continue;
                }

                x = ptr[0];
                ptr = ptr[2..];

                const fragments_offset = z: {
                    var yield: usize = 0;
                    for (0..if (rc.type & 0x40 != 0) 4 else 3) |i| {
                        const v: usize = @intCast(ptr[i]);
                        yield |= v << @as(u6, @intCast(i * 8));
                    }
                    break :z yield;
                };

                var fragments = base[fragments_offset..];
                if ((fragments[0] & 0xe0) == 0xc0) {
                    const k: up = z: {
                        const high: up = fragments[0] & 0x1f;
                        const low: up = fragments[1];
                        break :z ((high << 8) | low) + 1;
                    };
                    fragments = fragments[2..];

                    for (0..k) |_| {
                        const m: up = z: {
                            const high: up = fragments[2] & 0xf;
                            const mid: up = fragments[1];
                            const low: up = fragments[0];
                            break :z (high << 16) | (mid << 8) | low;
                        };
                        const next_m: up = z: {
                            const high: up = fragments[5] & 0xf;
                            const mid: up = fragments[4];
                            const low: up = fragments[3];
                            break :z (high << 16) | (mid << 8) | low;
                        };
                        var P = peek.unicode;
                        if (m <= P and P < next_m) {
                            P -= m;
                            const _m: up = z: {
                                const hh: up = (fragments[2] >> 4) & 0xf;
                                const hl: up = (fragments[5] >> 4) & 0xf;
                                const lh: up = fragments[7];
                                const ll: up = fragments[6];
                                break :z (hh << 24) | (hl << 16) | (lh << 8) | ll;
                            };
                            var i = _m + font.offsets.kerning;
                            const max_i = font.size - 4;
                            while (i < max_i) {
                                const _ptr = font.pointer(u8, i);
                                if ((_ptr[0] & 0x7f) < P) {
                                    P -= (_ptr[0] & 0x7f) + 1;
                                    i += 2;
                                    if (_ptr[0] & 0x80 == 0)
                                        i += _ptr[0] & 0x7f;
                                } else {
                                    y = z: {
                                        const index: up = if (_ptr[0] & 0x80 != 0) 1 else P + 1;
                                        break :z @as(up, @intCast(_ptr[index])) * h / fh;
                                    };
                                    if (x != 0) {
                                        buf.x += y;
                                    } else {
                                        buf.y += y;
                                    }
                                    break;
                                }
                            }
                            break;
                        }
                        fragments = fragments[8..];
                    }
                }
            }
        }
    }

    return result.processed;
}

test Self {
    var context = init(testing.allocator);
    try context.load(@embedFile("Gohu-Nerd.sfn"));
    defer context.deinit();
}
