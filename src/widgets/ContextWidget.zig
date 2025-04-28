const std = @import("std");
const rui = @import("../rui.zig");

const Event = rui.Event;
const Options = rui.Options;
const Point = rui.Point;
const Rect = rui.Rect;
const RectScale = rui.RectScale;
const Size = rui.Size;
const Widget = rui.Widget;
const WidgetData = rui.WidgetData;

const ContextWidget = @This();

pub const InitOptions = struct {
    /// Screen space pixel rect where right-click triggers the context menu
    rect: Rect,
};

wd: WidgetData = undefined,
init_options: InitOptions = undefined,

winId: u32 = undefined,
focused: bool = false,
activePt: Point = Point{},

pub fn init(src: std.builtin.SourceLocation, init_opts: InitOptions, opts: Options) ContextWidget {
    var self = ContextWidget{};
    const defaults = Options{ .name = "Context" };
    self.wd = WidgetData.init(src, .{}, defaults.override(opts).override(.{ .rect = rui.parentGet().data().rectScale().rectFromScreen(init_opts.rect) }));
    self.init_options = init_opts;
    self.winId = rui.subwindowCurrentId();
    if (rui.focusedWidgetIdInCurrentSubwindow()) |fid| {
        if (fid == self.wd.id) {
            self.focused = true;
        }
    }

    if (rui.dataGet(null, self.wd.id, "_activePt", Point)) |a| {
        self.activePt = a;
    }

    return self;
}

pub fn install(self: *ContextWidget) !void {
    rui.parentSet(self.widget());
    try self.wd.register();
    try self.wd.borderAndBackground(.{});
}

pub fn activePoint(self: *ContextWidget) ?Point {
    if (self.focused) {
        return self.activePt;
    }

    return null;
}

pub fn widget(self: *ContextWidget) Widget {
    return Widget.init(self, data, rectFor, screenRectScale, minSizeForChild, processEvent);
}

pub fn data(self: *ContextWidget) *WidgetData {
    return &self.wd;
}

pub fn rectFor(self: *ContextWidget, id: u32, min_size: Size, e: Options.Expand, g: Options.Gravity) Rect {
    _ = id;
    rui.log.debug("{s}:{d} ContextWidget should not have normal child widgets, only menu stuff", .{ self.wd.src.file, self.wd.src.line });
    return rui.placeIn(self.wd.contentRect().justSize(), min_size, e, g);
}

pub fn screenRectScale(self: *ContextWidget, rect: Rect) RectScale {
    return self.wd.contentRectScale().rectToRectScale(rect);
}

pub fn minSizeForChild(self: *ContextWidget, s: Size) void {
    self.wd.minSizeMax(self.wd.options.padSize(s));
}

pub fn processEvents(self: *ContextWidget) void {
    const evts = rui.events();
    for (evts) |*e| {
        if (!rui.eventMatchSimple(e, self.data()))
            continue;

        self.processEvent(e, false);
    }
}

pub fn processEvent(self: *ContextWidget, e: *Event, bubbling: bool) void {
    _ = bubbling;
    switch (e.evt) {
        .mouse => |me| {
            if (me.action == .focus and me.button == .right) {
                // eat any right button focus events so they don't get
                // caught by the containing window cleanup and cause us
                // to lose the focus we are about to get from the right
                // press below
                e.handled = true;
            } else if (me.action == .press and me.button == .right) {
                e.handled = true;

                rui.focusWidget(self.wd.id, null, e.num);
                self.focused = true;

                // scale the point back to natural so we can use it in Popup
                self.activePt = me.p.scale(1 / rui.windowNaturalScale());

                // offset just enough so when Popup first appears nothing is highlighted
                self.activePt.x += 1;
            }
        },
        .close_popup => {
            if (self.focused) {
                // we are getting a bubbled event, so the window we are in is not the current one
                rui.focusWidget(null, self.winId, null);
            }
        },
        else => {},
    }

    if (e.bubbleable()) {
        self.wd.parent.processEvent(e, true);
    }
}

pub fn deinit(self: *ContextWidget) void {
    if (self.focused) {
        rui.dataSet(null, self.wd.id, "_activePt", self.activePt);
    }

    // we are always given a rect, so we don't do normal layout, don't do these
    //self.wd.minSizeSetAndRefresh();
    //self.wd.minSizeReportToParent();

    rui.parentReset(self.wd.id, self.wd.parent);
}

test {
    @import("std").testing.refAllDecls(@This());
}
