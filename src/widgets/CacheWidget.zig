const std = @import("std");
const rui = @import("../rui.zig");

const Widget = rui.Widget;
const WidgetData = rui.WidgetData;
const Options = rui.Options;
const Size = rui.Size;
const Rect = rui.Rect;
const RectScale = rui.RectScale;

const CacheWidget = @This();

pub const InitOptions = struct {
    invalidate: bool = false,
};

wd: WidgetData = undefined,
hash: u32 = undefined,
refresh_prev_value: u8 = undefined,
caching: bool = false,
caching_tex: rui.TextureTarget = undefined,
texture_create_error: bool = false,
tex_uv: Size = undefined,
old_target: rui.RenderTarget = undefined,
old_clip: ?Rect = null,

pub fn init(src: std.builtin.SourceLocation, init_opts: InitOptions, opts: Options) CacheWidget {
    _ = init_opts;
    var self = CacheWidget{};
    const defaults = Options{ .name = "Cache" };
    self.wd = WidgetData.init(src, .{}, defaults.override(opts));

    self.hash = rui.hashIdKey(self.wd.id, "_tex");
    self.tex_uv = rui.dataGet(null, self.wd.id, "_tex_uv", Size) orelse .{};
    self.refresh_prev_value = rui.currentWindow().extra_frames_needed;
    rui.currentWindow().extra_frames_needed = 0;
    return self;
}

fn tce(self: *CacheWidget) ?*rui.TextureCacheEntry {
    const cw = rui.currentWindow();
    if (cw.texture_cache.getPtr(self.hash)) |t| {
        t.used = true;
        return t;
    }

    return null;
}

fn drawTce(self: *CacheWidget, t: *const rui.TextureCacheEntry) !void {
    const rs = self.wd.contentRectScale();

    try rui.renderTexture(t.texture, rs, .{ .uv = (Rect{}).toSize(self.tex_uv), .debug = self.wd.options.debugGet() });
    //if (self.wd.options.debugGet()) {
    //    rui.log.debug("drawing {d} {d} {d}x{d} {d}x{d} {d} {d}", .{ rs.r.x, rs.r.y, rs.r.w, rs.r.h, t.texture.width, t.texture.height, self.tex_uv.w, self.tex_uv.h });
    //}
}

/// Must be called before install().
pub fn invalidate(self: *CacheWidget) !void {
    if (self.tce()) |t| {
        // if we had a texture, show it this frame because our contents needs a frame to get sizing
        try self.drawTce(t);

        rui.textureDestroyLater(t.texture);
        _ = rui.currentWindow().texture_cache.remove(self.hash);

        // now we've shown the texture, so prevent any widgets from drawing on top of it this frame
        // - can happen if some widgets precalculate their size (like label)
        self.old_clip = rui.clip(.{});
    }
}

pub fn install(self: *CacheWidget) !void {
    rui.parentSet(self.widget());
    try self.wd.register();
    try self.wd.borderAndBackground(.{});

    if (self.tce()) |t| {
        // successful cache, draw texture and enforce min size
        try self.drawTce(t);
        self.wd.minSizeMax(self.wd.rect.size());
    } else {

        // we need to cache, but only do it if we didn't have any refreshes from last frame
        if (rui.dataGet(null, self.wd.id, "_cache_now", bool) orelse false) {
            self.caching = true;
        }

        if (self.caching) {
            const rs = self.wd.contentRectScale();
            const w: u32 = @intFromFloat(@ceil(rs.r.w));
            const h: u32 = @intFromFloat(@ceil(rs.r.h));
            self.tex_uv = .{ .w = rs.r.w / @ceil(rs.r.w), .h = rs.r.h / @ceil(rs.r.h) };

            if (self.caching) {
                self.caching_tex = rui.textureCreateTarget(w, h, .linear) catch |err| blk: {
                    if (err == error.TextureCreate) {
                        self.texture_create_error = rui.dataGet(null, self.wd.id, "_texture_create_error", bool) orelse false;
                        if (!self.texture_create_error) {
                            // indicate that texture failed last frame to prevent backends that always return errors from forever refreshing
                            rui.dataSet(null, self.wd.id, "_texture_create_error", true);
                        }
                    }
                    self.caching = false;
                    break :blk undefined;
                };
            }

            if (self.caching) {
                var offset = rs.r.topLeft();
                if (rui.snapToPixels()) {
                    offset.x = @round(offset.x);
                    offset.y = @round(offset.y);
                }
                self.old_target = rui.renderTarget(.{ .texture = self.caching_tex, .offset = offset });

                // clip to just us, even if we are off screen
                self.old_clip = rui.clipGet();
                rui.clipSet(rs.r);
            }
        }
    }
}

/// Must be called after install().
pub fn uncached(self: *CacheWidget) bool {
    return (self.caching or self.tce() == null);
}

pub fn widget(self: *CacheWidget) Widget {
    return Widget.init(self, data, rectFor, screenRectScale, minSizeForChild, processEvent);
}

pub fn data(self: *CacheWidget) *WidgetData {
    return &self.wd;
}

pub fn rectFor(self: *CacheWidget, id: u32, min_size: Size, e: Options.Expand, g: Options.Gravity) Rect {
    _ = id;
    return rui.placeIn(self.wd.contentRect().justSize(), min_size, e, g);
}

pub fn screenRectScale(self: *CacheWidget, rect: Rect) RectScale {
    return self.wd.contentRectScale().rectToRectScale(rect);
}

pub fn minSizeForChild(self: *CacheWidget, s: Size) void {
    self.wd.minSizeMax(self.wd.options.padSize(s));
}

pub fn processEvent(self: *CacheWidget, e: *rui.Event, bubbling: bool) void {
    _ = bubbling;
    if (e.bubbleable()) {
        self.wd.parent.processEvent(e, true);
    }
}

pub fn deinit(self: *CacheWidget) void {
    if (!self.texture_create_error and self.uncached()) {
        if (rui.currentWindow().extra_frames_needed == 0) {
            rui.dataSet(null, self.wd.id, "_cache_now", true);
            rui.refresh(null, @src(), self.wd.id);
        }
    }
    rui.currentWindow().extra_frames_needed = @max(rui.currentWindow().extra_frames_needed, self.refresh_prev_value);

    if (self.old_clip) |clip| {
        rui.clipSet(clip);
    }
    if (self.caching) {
        _ = rui.renderTarget(self.old_target);

        // convert texture target to normal texture
        const entry = rui.TextureCacheEntry{ .texture = rui.textureFromTarget(self.caching_tex) }; // destroys self.caching_tex
        rui.currentWindow().texture_cache.put(self.hash, entry) catch @panic("OOM");

        // draw texture so we see it this frame
        self.drawTce(&entry) catch {
            rui.log.debug("{x} CacheWidget.deinit failed to render texture\n", .{self.wd.id});
        };

        rui.dataSet(null, self.wd.id, "_tex_uv", self.tex_uv);
        rui.dataRemove(null, self.wd.id, "_cache_now");
    }
    self.wd.minSizeSetAndRefresh();
    self.wd.minSizeReportToParent();
    rui.parentReset(self.wd.id, self.wd.parent);
}

test {
    @import("std").testing.refAllDecls(@This());
}
