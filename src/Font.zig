const std = @import("std");
const rui = @import("rui.zig");

const Rect = rui.Rect;
const Size = rui.Size;

const Font = @This();

size: f32,
line_height_factor: f32 = 1.2,
name: []const u8,

pub fn resize(self: *const Font, s: f32) Font {
    return Font{ .size = s, .line_height_factor = self.line_height_factor, .name = self.name };
}

pub fn lineHeightFactor(self: *const Font, factor: f32) Font {
    return Font{ .size = self.size, .line_height_factor = factor, .name = self.name };
}

pub fn textHeight(self: *const Font) f32 {
    return self.sizeM(1, 1).h;
}

pub fn lineHeight(self: *const Font) f32 {
    return self.textHeight() * self.line_height_factor;
}

pub fn sizeM(self: *const Font, wide: f32, tall: f32) Size {
    const msize: Size = self.textSize("M");
    return .{ .w = msize.w * wide, .h = msize.h * tall };
}

// handles multiple lines
pub fn textSize(self: *const Font, text: []const u8) Size {
    if (text.len == 0) {
        // just want the normal text height
        return .{ .w = 0, .h = self.textHeight() };
    }

    var ret = Size{};

    var line_height_adj: f32 = undefined;
    var end: usize = 0;
    while (end < text.len) {
        if (end > 0) {
            ret.h += line_height_adj;
        }

        var end_idx: usize = undefined;
        const s = self.textSizeEx(text[end..], null, &end_idx, .before);
        line_height_adj = s.h * (self.line_height_factor - 1.0);
        ret.h += s.h;
        ret.w = @max(ret.w, s.w);

        end += end_idx;
    }

    return ret;
}

pub const EndMetric = enum {
    before, // end_idx stops before text goes past max_width
    nearest, // end_idx stops at start of character closest to max_width
};

/// textSizeEx always stops at a newline, use textSize to get multiline sizes
pub fn textSizeEx(self: *const Font, text: []const u8, max_width: ?f32, end_idx: ?*usize, end_metric: EndMetric) Size {
    // ask for a font that matches the natural display pixels so we get a more
    // accurate size

    const ss = rui.parentGet().screenRectScale(Rect{}).s;
    const ask_size = self.size * ss;
    const sized_font = self.resize(ask_size);

    // might give us a slightly smaller font
    const fce = rui.fontCacheGet(sized_font) catch |err| {
        rui.log.err("fontCacheGet got {!} for font \"{s}\"", .{ err, self.name });
        return .{ .w = 10, .h = 10 };
    };

    // this must be synced with rui.renderText()
    const target_fraction = if (rui.currentWindow().snap_to_pixels) 1.0 / ss else self.size / fce.height;

    var max_width_sized: ?f32 = null;
    if (max_width) |mwidth| {
        // convert max_width into font units
        max_width_sized = mwidth / target_fraction;
    }

    var s = fce.textSizeRaw(self.name, text, max_width_sized, end_idx, end_metric) catch |err| {
        rui.log.err("textSizeRaw got {!} for font \"{s}\" text \"{s}\"", .{ err, self.name, text });
        return .{ .w = 10, .h = 10 };
    };

    // do this check after calling textSizeRaw so that end_idx is set
    if (ask_size == 0.0) return Size{};

    // convert size back from font units
    return s.scale(target_fraction);
}

// default bytes if font id is not found in database
pub const default_ttf_bytes = TTFBytes.Vera;

// functionality for accessing builtin fonts
pub const TTFBytes = struct {
    pub const Aleo = @embedFile("fonts/Aleo/static/Aleo-Regular.ttf");
    pub const AleoBd = @embedFile("fonts/Aleo/static/Aleo-Bold.ttf");
    pub const Vera = @embedFile("fonts/bitstream-vera/Vera.ttf");
    //pub const VeraBI = @embedFile("fonts/bitstream-vera/VeraBI.ttf");
    pub const VeraBd = @embedFile("fonts/bitstream-vera/VeraBd.ttf");
    //pub const VeraIt = @embedFile("fonts/bitstream-vera/VeraIt.ttf");
    //pub const VeraMoBI = @embedFile("fonts/bitstream-vera/VeraMoBI.ttf");
    //pub const VeraMoBd = @embedFile("fonts/bitstream-vera/VeraMoBd.ttf");
    //pub const VeraMoIt = @embedFile("fonts/bitstream-vera/VeraMoIt.ttf");
    pub const VeraMono = @embedFile("fonts/bitstream-vera/VeraMono.ttf");
    //pub const VeraSe = @embedFile("fonts/bitstream-vera/VeraSe.ttf");
    //pub const VeraSeBd = @embedFile("fonts/bitstream-vera/VeraSeBd.ttf");
    pub const Pixelify = @embedFile("fonts/Pixelify_Sans/static/PixelifySans-Regular.ttf");
    //pub const PixelifyBd = @embedFile("fonts/Pixelify_Sans/static/PixelifySans-Bold.ttf");
    //pub const PixelifyMe = @embedFile("fonts/Pixelify_Sans/static/PixelifySans-Medium.ttf");
    //pub const PixelifySeBd = @embedFile("fonts/Pixelify_Sans/static/PixelifySans-SemiBold.ttf");
    //pub const Hack = @embedFile("fonts/hack/Hack-Regular.ttf");
    //pub const HackBd = @embedFile("fonts/hack/Hack-Bold.ttf");
    //pub const HackIt = @embedFile("fonts/hack/Hack-Italic.ttf");
    //pub const HackBdIt = @embedFile("fonts/hack/Hack-BoldItalic.ttf");
    pub const OpenDyslexic = @embedFile("fonts/OpenDyslexic/compiled/OpenDyslexic-Regular.otf");
    pub const OpenDyslexicBd = @embedFile("fonts/OpenDyslexic/compiled/OpenDyslexic-Bold.otf");
    //pub const OpenDyslexicIt = @embedFile("fonts/OpenDyslexic/compiled/OpenDyslexic-Italic.otf");
    //pub const OpenDyslexicBdIt = @embedFile("fonts/OpenDyslexic/compiled/OpenDyslexic-Bold-Italic.otf");
};

pub fn initTTFBytesDatabase(allocator: std.mem.Allocator) !std.StringHashMap(rui.FontBytesEntry) {
    var result = std.StringHashMap(rui.FontBytesEntry).init(allocator);
    inline for (@typeInfo(TTFBytes).@"struct".decls) |decl| {
        try result.put(decl.name, rui.FontBytesEntry{ .ttf_bytes = @field(TTFBytes, decl.name), .allocator = null });
    }

    if (!rui.wasm) {
        try result.put("Noto", rui.FontBytesEntry{ .ttf_bytes = @embedFile("fonts/NotoSansKR-Regular.ttf"), .allocator = null });
    }

    return result;
}

test {
    @import("std").testing.refAllDecls(@This());
}
