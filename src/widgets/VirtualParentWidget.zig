/// This is a widget that forwards all parent calls to its parent.  Useful
/// where you want to wrap widgets but only to adjust their IDs.
const std = @import("std");
const rui = @import("../rui.zig");

const Event = rui.Event;
const Options = rui.Options;
const Rect = rui.Rect;
const RectScale = rui.RectScale;
const Size = rui.Size;
const Widget = rui.Widget;
const WidgetData = rui.WidgetData;

const VirtualParentWidget = @This();

wd: WidgetData = undefined,
child_rect_union: ?Rect = null,

pub fn init(src: std.builtin.SourceLocation, opts: Options) VirtualParentWidget {
    const id = rui.parentGet().extendId(src, opts.idExtra());
    const rect = rui.dataGet(null, id, "_rect", Rect);
    const defaults = Options{ .name = "Virtual Parent", .rect = rect orelse .{} };
    return VirtualParentWidget{ .wd = WidgetData.init(src, .{}, defaults.override(opts)) };
}

pub fn install(self: *VirtualParentWidget) !void {
    rui.parentSet(self.widget());
    try self.wd.register();
}

pub fn widget(self: *VirtualParentWidget) Widget {
    return Widget.init(self, data, rectFor, screenRectScale, minSizeForChild, processEvent);
}

pub fn data(self: *VirtualParentWidget) *WidgetData {
    return &self.wd;
}

pub fn rectFor(self: *VirtualParentWidget, id: u32, min_size: Size, e: Options.Expand, g: Options.Gravity) Rect {
    const ret = self.wd.parent.rectFor(id, min_size, e, g);
    if (self.child_rect_union) |u| {
        self.child_rect_union = u.unionWith(ret);
    } else {
        self.child_rect_union = ret;
    }
    return ret;
}

pub fn screenRectScale(self: *VirtualParentWidget, rect: Rect) RectScale {
    return self.wd.parent.screenRectScale(rect);
}

pub fn minSizeForChild(self: *VirtualParentWidget, s: Size) void {
    self.wd.parent.minSizeForChild(s);
}

pub fn processEvent(self: *VirtualParentWidget, e: *Event, bubbling: bool) void {
    _ = bubbling;
    if (e.bubbleable()) {
        self.wd.parent.processEvent(e, true);
    }
}

pub fn deinit(self: *VirtualParentWidget) void {
    if (self.child_rect_union) |u| {
        rui.dataSet(null, self.wd.id, "_rect", u);
    }
    rui.parentReset(self.wd.id, self.wd.parent);
}

test {
    @import("std").testing.refAllDecls(@This());
}
