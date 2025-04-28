const std = @import("std");
const rui = @import("../rui.zig");

const Event = rui.Event;
const Options = rui.Options;
const Rect = rui.Rect;
const RectScale = rui.RectScale;
const Size = rui.Size;
const Widget = rui.Widget;
const WidgetData = rui.WidgetData;

const FloatingWidget = @This();

pub var defaults: Options = .{
    .name = "Floating",
};

prev_rendering: bool = undefined,
wd: WidgetData = undefined,
prev_windowId: u32 = 0,
prevClip: Rect = Rect{},
scale_val: f32 = undefined,
scaler: rui.ScaleWidget = undefined,

/// FloatingWidget is a subwindow to show any temporary floating thing.
/// It doesn't focus itself (as a subwindow), and whether it is shown or not is
/// entirely up to the calling code.
///
/// Don't put menus or menuItems in a floating widget because those depend on
/// focus to work.  FloatingMenu is made for that.
///
/// Use FloatingWindowWidget for a floating window that the user can change
/// size, move around, and adjust stacking.
pub fn init(src: std.builtin.SourceLocation, opts_in: Options) FloatingWidget {
    var self = FloatingWidget{};

    // get scale from parent
    self.scale_val = rui.parentGet().screenRectScale(Rect{}).s / rui.windowNaturalScale();
    var opts = opts_in;
    if (opts.min_size_content) |msc| {
        opts.min_size_content = msc.scale(self.scale_val);
    }

    // passing options.rect will stop WidgetData.init from calling
    // rectFor/minSizeForChild which is important because we are outside
    // normal layout
    self.wd = WidgetData.init(src, .{ .subwindow = true }, defaults.override(opts).override(.{ .rect = opts.rect orelse .{} }));

    return self;
}

pub fn install(self: *FloatingWidget) !void {
    self.prev_rendering = rui.renderingSet(false);

    rui.parentSet(self.widget());

    self.prev_windowId = rui.subwindowCurrentSet(self.wd.id, null).id;

    const rs = self.wd.rectScale();

    try rui.subwindowAdd(self.wd.id, self.wd.rect, rs.r, false, self.prev_windowId);
    rui.captureMouseMaintain(.{ .id = self.wd.id, .rect = rs.r, .subwindow_id = self.wd.id });
    try self.wd.register();

    // clip to just our window (using clipSet since we are not inside our parent)
    self.prevClip = rui.clipGet();
    rui.clipSet(rs.r);

    self.scaler = rui.ScaleWidget.init(@src(), self.scale_val, .{ .expand = .both });
    try self.scaler.install();
}

pub fn widget(self: *FloatingWidget) Widget {
    return Widget.init(self, data, rectFor, screenRectScale, minSizeForChild, processEvent);
}

pub fn data(self: *FloatingWidget) *WidgetData {
    return &self.wd;
}

pub fn rectFor(self: *FloatingWidget, id: u32, min_size: Size, e: Options.Expand, g: Options.Gravity) Rect {
    _ = id;
    return rui.placeIn(self.wd.contentRect().justSize(), min_size, e, g);
}

pub fn screenRectScale(self: *FloatingWidget, rect: Rect) RectScale {
    return self.wd.contentRectScale().rectToRectScale(rect);
}

pub fn minSizeForChild(self: *FloatingWidget, s: Size) void {
    self.wd.minSizeMax(self.wd.options.padSize(s));
}

pub fn processEvent(self: *FloatingWidget, e: *Event, bubbling: bool) void {
    // no normal events, just forward close_popup
    switch (e.evt) {
        .close_popup => {
            self.wd.parent.processEvent(e, true);
        },
        else => {},
    }

    // otherwise don't bubble events
    _ = bubbling;
}

pub fn deinit(self: *FloatingWidget) void {
    self.scaler.deinit();
    self.wd.minSizeSetAndRefresh();

    // outside normal layout, don't call minSizeForChild or self.wd.minSizeReportToParent();

    rui.parentReset(self.wd.id, self.wd.parent);
    _ = rui.subwindowCurrentSet(self.prev_windowId, null);
    rui.clipSet(self.prevClip);
    _ = rui.renderingSet(self.prev_rendering);
}

test {
    @import("std").testing.refAllDecls(@This());
}
