const std = @import("std");
const rui = @import("../rui.zig");

const Event = rui.Event;
const Options = rui.Options;
const Rect = rui.Rect;
const RectScale = rui.RectScale;
const Size = rui.Size;
const Widget = rui.Widget;
const WidgetData = rui.WidgetData;
const BoxWidget = rui.BoxWidget;

const ScaleWidget = @This();

wd: WidgetData = undefined,
scale: f32 = undefined,
box: BoxWidget = undefined,

pub fn init(src: std.builtin.SourceLocation, scale_in: f32, opts: Options) ScaleWidget {
    var self = ScaleWidget{};
    const defaults = Options{ .name = "Scale" };
    self.wd = WidgetData.init(src, .{}, defaults.override(opts));
    self.scale = scale_in;
    return self;
}

pub fn install(self: *ScaleWidget) !void {
    rui.parentSet(self.widget());
    try self.wd.register();
    try self.wd.borderAndBackground(.{});

    self.box = BoxWidget.init(@src(), .vertical, false, self.wd.options.strip().override(.{ .expand = .both }));
    try self.box.install();
    try self.box.drawBackground();
}

pub fn widget(self: *ScaleWidget) Widget {
    return Widget.init(self, data, rectFor, screenRectScale, minSizeForChild, processEvent);
}

pub fn data(self: *ScaleWidget) *WidgetData {
    return &self.wd;
}

pub fn rectFor(self: *ScaleWidget, id: u32, min_size: Size, e: Options.Expand, g: Options.Gravity) Rect {
    var s: f32 = undefined;
    if (self.scale > 0) {
        s = 1.0 / self.scale;
    } else {
        // prevent divide by zero
        s = 1_000_000.0;
    }

    _ = id;
    return rui.placeIn(self.wd.contentRect().justSize().scale(s), min_size, e, g);
}

pub fn screenRectScale(self: *ScaleWidget, rect: Rect) RectScale {
    var rs = self.wd.contentRectScale();
    rs.s *= self.scale;
    return rs.rectToRectScale(rect);
}

pub fn minSizeForChild(self: *ScaleWidget, s: Size) void {
    self.wd.minSizeMax(self.wd.options.padSize(s.scale(self.scale)));
}

pub fn processEvent(self: *ScaleWidget, e: *Event, bubbling: bool) void {
    _ = bubbling;
    if (e.bubbleable()) {
        self.wd.parent.processEvent(e, true);
    }
}

pub fn deinit(self: *ScaleWidget) void {
    self.box.deinit();
    self.wd.minSizeSetAndRefresh();
    self.wd.minSizeReportToParent();
    rui.parentReset(self.wd.id, self.wd.parent);
}

test {
    @import("std").testing.refAllDecls(@This());
}
