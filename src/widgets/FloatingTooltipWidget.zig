const std = @import("std");
const rui = @import("../rui.zig");

const Event = rui.Event;
const Options = rui.Options;
const Rect = rui.Rect;
const RectScale = rui.RectScale;
const Size = rui.Size;
const Widget = rui.Widget;
const WidgetData = rui.WidgetData;

const FloatingTooltipWidget = @This();

// maintain a chain of all the nested FloatingTooltipWidgets
var tooltip_current: ?*FloatingTooltipWidget = null;

fn tooltipSet(tt: ?*FloatingTooltipWidget) ?*FloatingTooltipWidget {
    const ret = tooltip_current;
    tooltip_current = tt;
    return ret;
}

pub var defaults: Options = .{
    .name = "Tooltip",
    .corner_radius = Rect.all(5),
    .border = Rect.all(1),
    .background = true,
};

pub const Position = enum {
    /// Right of active_rect
    horizontal,
    /// Below active_rect
    vertical,
    /// Starts where mouse is but stays there
    sticky,
};

pub const InitOptions = struct {
    /// Show when mouse enters this rect in screen pixels
    active_rect: Rect,

    position: Position = .horizontal,

    /// Is true if the user should be able to hover the tooltips content without it disappearing
    interactive: bool = false,
};

parent_tooltip: ?*FloatingTooltipWidget = null,
prev_rendering: bool = undefined,
wd: WidgetData = undefined,
prev_windowId: u32 = 0,
prevClip: Rect = Rect{},
scale_val: f32 = undefined,
scaler: rui.ScaleWidget = undefined,
options: Options = undefined,
init_options: InitOptions = undefined,
showing: bool = false,
mouse_good_this_frame: bool = false,
installed: bool = false,
tt_child_shown: bool = false,

/// FloatingTooltipWidget is a subwindow to show temporary floating tooltips,
/// possibly nested. It doesn't focus itself (as a subwindow).
///
/// Will show when the mouse is in the active rect.
///
/// Will stop if the mouse is outside the active rect AND outside
/// FloatingTooltipWidget's rect AND no nested FloatingTooltipWidget is still
/// showing.
///
/// Don't put menus or menuItems in this those depend on focus to work.
/// FloatingMenu is made for that.
///
/// Use FloatingWindowWidget for a floating window that the user can change
/// size, move around, and adjust stacking.
pub fn init(src: std.builtin.SourceLocation, init_opts: InitOptions, opts_in: Options) FloatingTooltipWidget {
    var self = FloatingTooltipWidget{};

    // get scale from parent
    self.scale_val = rui.parentGet().screenRectScale(Rect{}).s / rui.windowNaturalScale();
    self.options = defaults.override(opts_in);
    if (self.options.min_size_content) |msc| {
        self.options.min_size_content = msc.scale(self.scale_val);
    }

    // passing options.rect will stop WidgetData.init from calling
    // rectFor/minSizeForChild which is important because we are outside
    // normal layout
    self.wd = WidgetData.init(src, .{ .subwindow = true }, (Options{ .name = "FloatingTooltip" }).override(.{ .rect = self.options.rect orelse .{} }));

    self.init_options = init_opts;
    self.showing = rui.dataGet(null, self.wd.id, "_showing", bool) orelse false;

    return self;
}

pub fn shown(self: *FloatingTooltipWidget) !bool {
    // protect against this being called multiple times
    if (self.installed) {
        return true;
    }

    // check for mouse position in active_rect
    const evts = rui.events();
    for (evts) |*e| {
        if (!rui.eventMatch(e, .{ .id = self.wd.id, .r = self.init_options.active_rect })) {
            continue;
        }

        if (e.evt == .mouse and e.evt.mouse.action == .position) {
            self.mouse_good_this_frame = true;
            if (!self.showing) {
                self.showing = true;
            }
        }
    }

    if (self.showing) {
        switch (self.init_options.position) {
            .horizontal, .vertical => |o| {
                const ar = self.init_options.active_rect.scale(1 / rui.windowNaturalScale());
                const r: Rect = rui.Rect.fromPoint(ar.topLeft()).toSize(self.wd.rect.size());
                self.wd.rect = rui.placeOnScreen(rui.windowRect(), ar, if (o == .horizontal) .horizontal else .vertical, r);
            },
            .sticky => {
                if (rui.firstFrame(self.wd.id)) {
                    const mp = rui.currentWindow().mouse_pt.scale(1 / rui.windowNaturalScale());
                    rui.dataSet(null, self.wd.id, "_sticky_pt", mp);
                } else {
                    const mp = rui.dataGet(null, self.wd.id, "_sticky_pt", rui.Point) orelse rui.Point{};
                    var r: Rect = rui.Rect.fromPoint(mp).toSize(self.wd.rect.size());
                    r.x += 10;
                    r.y -= r.h + 10;
                    self.wd.rect = rui.placeOnScreen(rui.windowRect(), .{}, .none, r);
                }
            },
        }
        //std.debug.print("rect {}\n", .{self.wd.rect});

        try self.install();

        if (self.init_options.interactive) {
            // check for mouse position in tooltip window rect
            for (evts) |*e| {
                if (!rui.eventMatch(e, .{ .id = self.wd.id, .r = self.wd.borderRectScale().r })) {
                    continue;
                }

                if (e.evt == .mouse and e.evt.mouse.action == .position) {
                    self.mouse_good_this_frame = true;
                }
            }
        }

        return true;
    }

    return false;
}

pub fn install(self: *FloatingTooltipWidget) !void {
    self.installed = true;
    self.prev_rendering = rui.renderingSet(false);

    rui.parentSet(self.widget());

    self.prev_windowId = rui.subwindowCurrentSet(self.wd.id, null).id;
    self.parent_tooltip = tooltipSet(self);

    const rs = self.wd.rectScale();

    try rui.subwindowAdd(self.wd.id, self.wd.rect, rs.r, false, self.prev_windowId);
    rui.captureMouseMaintain(.{ .id = self.wd.id, .rect = rs.r, .subwindow_id = self.wd.id });
    try self.wd.register();

    // clip to just our window (using clipSet since we are not inside our parent)
    self.prevClip = rui.clipGet();
    rui.clipSet(rs.r);

    self.scaler = rui.ScaleWidget.init(@src(), self.scale_val, self.options.override(.{ .expand = .both }));
    try self.scaler.install();
}

pub fn widget(self: *FloatingTooltipWidget) Widget {
    return Widget.init(self, data, rectFor, screenRectScale, minSizeForChild, processEvent);
}

pub fn data(self: *FloatingTooltipWidget) *WidgetData {
    return &self.wd;
}

pub fn rectFor(self: *FloatingTooltipWidget, id: u32, min_size: Size, e: Options.Expand, g: Options.Gravity) Rect {
    _ = id;
    return rui.placeIn(self.wd.contentRect().justSize(), min_size, e, g);
}

pub fn screenRectScale(self: *FloatingTooltipWidget, rect: Rect) RectScale {
    return self.wd.contentRectScale().rectToRectScale(rect);
}

pub fn minSizeForChild(self: *FloatingTooltipWidget, s: Size) void {
    self.wd.minSizeMax(self.wd.options.padSize(s));
}

pub fn processEvent(self: *FloatingTooltipWidget, e: *Event, bubbling: bool) void {
    // no event processing, everything stops
    _ = self;
    _ = e;
    _ = bubbling;
}

pub fn deinit(self: *FloatingTooltipWidget) void {
    if (!self.installed) {
        return;
    }

    // check if we should still be shown
    if (self.mouse_good_this_frame or (self.init_options.interactive and self.tt_child_shown)) {
        rui.dataSet(null, self.wd.id, "_showing", true);
        var parent: ?*FloatingTooltipWidget = self.parent_tooltip;
        while (parent) |p| {
            p.tt_child_shown = true;
            parent = p.parent_tooltip;
        }
    } else {
        // don't store showing if mouse is outside trigger and tooltip which will close it next frame
        rui.dataRemove(null, self.wd.id, "_showing");
        rui.refresh(null, @src(), self.wd.id); // refresh with new hidden state
    }

    self.scaler.deinit();
    self.wd.minSizeSetAndRefresh();

    // outside normal layout, don't call minSizeForChild or self.wd.minSizeReportToParent();

    _ = tooltipSet(self.parent_tooltip);
    rui.parentReset(self.wd.id, self.wd.parent);
    _ = rui.subwindowCurrentSet(self.prev_windowId, null);
    rui.clipSet(self.prevClip);
    _ = rui.renderingSet(self.prev_rendering);
}

test {
    @import("std").testing.refAllDecls(@This());
}
