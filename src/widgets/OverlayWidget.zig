const std = @import("std");
const rui = @import("../rui.zig");

const Event = rui.Event;
const Options = rui.Options;
const Rect = rui.Rect;
const RectScale = rui.RectScale;
const Size = rui.Size;
const Widget = rui.Widget;
const WidgetData = rui.WidgetData;

const OverlayWidget = @This();

wd: WidgetData = undefined,

pub fn init(src: std.builtin.SourceLocation, opts: Options) OverlayWidget {
    const defaults = Options{ .name = "Overlay" };
    return OverlayWidget{ .wd = WidgetData.init(src, .{}, defaults.override(opts)) };
}

pub fn install(self: *OverlayWidget) !void {
    rui.parentSet(self.widget());
    try self.wd.register();
    try self.wd.borderAndBackground(.{});
}

pub fn widget(self: *OverlayWidget) Widget {
    return Widget.init(self, data, rectFor, screenRectScale, minSizeForChild, processEvent);
}

pub fn data(self: *OverlayWidget) *WidgetData {
    return &self.wd;
}

pub fn rectFor(self: *OverlayWidget, id: u32, min_size: Size, e: Options.Expand, g: Options.Gravity) Rect {
    _ = id;
    return rui.placeIn(self.wd.contentRect().justSize(), min_size, e, g);
}

pub fn screenRectScale(self: *OverlayWidget, rect: Rect) RectScale {
    return self.wd.contentRectScale().rectToRectScale(rect);
}

pub fn minSizeForChild(self: *OverlayWidget, s: Size) void {
    self.wd.minSizeMax(self.wd.options.padSize(s));
}

pub fn processEvent(self: *OverlayWidget, e: *Event, bubbling: bool) void {
    _ = bubbling;
    if (e.bubbleable()) {
        self.wd.parent.processEvent(e, true);
    }
}

pub fn deinit(self: *OverlayWidget) void {
    self.wd.minSizeSetAndRefresh();
    self.wd.minSizeReportToParent();
    rui.parentReset(self.wd.id, self.wd.parent);
}

test {
    @import("std").testing.refAllDecls(@This());
}
