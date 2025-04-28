const std = @import("std");
const rui = @import("../rui.zig");

const Options = rui.Options;
const Rect = rui.Rect;
const RectScale = rui.RectScale;
const Size = rui.Size;
const Widget = rui.Widget;
const WidgetData = rui.WidgetData;

const FlexBoxWidget = @This();

pub const InitOptions = struct {
    /// Imitates `justify-content` in CSS Flexbox
    justify_content: ContentPosition = .center,
};

pub const ContentPosition = enum { start, center };

wd: WidgetData = undefined,
init_options: InitOptions = undefined,
prevClip: Rect = Rect{},
insert_pt: rui.Point = .{},
row_size: Size = .{},
max_row_width: f32 = 0.0,
max_row_width_prev: f32 = 0.0,
width_nobreak: f32 = 0.0, // width if all children were on one row

pub fn init(src: std.builtin.SourceLocation, init_opts: InitOptions, opts: Options) FlexBoxWidget {
    var self = FlexBoxWidget{};
    const defaults = Options{ .name = "FlexBox" };
    self.wd = WidgetData.init(src, .{}, defaults.override(opts));
    self.init_options = init_opts;
    self.max_row_width_prev = rui.dataGet(null, self.wd.id, "_mrw", f32) orelse 0.0;
    return self;
}

pub fn install(self: *FlexBoxWidget) !void {
    try self.wd.register();
    rui.parentSet(self.widget());

    self.prevClip = rui.clip(self.wd.contentRectScale().r);
}

pub fn drawBackground(self: *FlexBoxWidget) !void {
    const clip = rui.clipGet();
    rui.clipSet(self.prevClip);
    try self.wd.borderAndBackground(.{});
    rui.clipSet(clip);
}

pub fn widget(self: *FlexBoxWidget) Widget {
    return Widget.init(self, data, rectFor, screenRectScale, minSizeForChild, processEvent);
}

pub fn data(self: *FlexBoxWidget) *WidgetData {
    return &self.wd;
}

pub fn rectFor(self: *FlexBoxWidget, id: u32, min_size: Size, e: Options.Expand, g: Options.Gravity) Rect {
    _ = id;
    _ = e;
    _ = g;

    var container_width = self.wd.contentRect().w;
    if (container_width == 0) {
        // if we are not being shown at all, probably this is the first
        // frame for us and we should calculate our min height assuming we
        // get at least our min width

        container_width = self.wd.options.min_size_contentGet().w;
        if (container_width == 0) {
            // wasn't given a min width, assume something
            container_width = 500;
        }
    }

    if (self.insert_pt.x > 0 and self.insert_pt.x + min_size.w > container_width) {
        // we ran off the end and didn't start at the left edge, break
        self.insert_pt.x = 0;
        self.insert_pt.y += self.row_size.h;
        self.row_size = .{ .w = 0, .h = min_size.h };
    } else {
        self.row_size.h = @max(self.row_size.h, min_size.h);
    }

    var ret = Rect.fromPoint(self.insert_pt).toSize(min_size);
    switch (self.init_options.justify_content) {
        .start => {},
        .center => ret.x += (self.wd.contentRect().w - self.max_row_width_prev) / 2,
    }

    self.insert_pt.x += min_size.w;

    return ret;
}

pub fn screenRectScale(self: *FlexBoxWidget, rect: Rect) RectScale {
    return self.wd.contentRectScale().rectToRectScale(rect);
}

pub fn minSizeForChild(self: *FlexBoxWidget, s: Size) void {
    self.row_size.w += s.w;
    self.max_row_width = @max(self.max_row_width, self.row_size.w);
    self.width_nobreak += s.w;
    self.wd.min_size = self.wd.options.padSize(.{ .w = self.width_nobreak, .h = self.insert_pt.y + self.row_size.h });
}

pub fn processEvent(self: *FlexBoxWidget, e: *rui.Event, bubbling: bool) void {
    _ = bubbling;
    if (e.bubbleable()) {
        self.wd.parent.processEvent(e, true);
    }
}

pub fn deinit(self: *FlexBoxWidget) void {
    rui.dataSet(null, self.wd.id, "_mrw", self.max_row_width);
    rui.clipSet(self.prevClip);
    self.wd.minSizeSetAndRefresh();
    self.wd.minSizeReportToParent();
    rui.parentReset(self.wd.id, self.wd.parent);
}

test {
    @import("std").testing.refAllDecls(@This());
}
