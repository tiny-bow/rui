const std = @import("std");
const rui = @import("../rui.zig");

const Event = rui.Event;
const Options = rui.Options;
const Rect = rui.Rect;
const RectScale = rui.RectScale;
const Size = rui.Size;
const Widget = rui.Widget;
const WidgetData = rui.WidgetData;
const MenuWidget = rui.MenuWidget;
const ScrollAreaWidget = rui.ScrollAreaWidget;

const FloatingMenuWidget = @This();

pub const FloatingMenuAvoid = enum {
    none,
    horizontal,
    vertical,

    /// Pick horizontal or vertical based on the direction of the current
    /// parent menu (if any).
    auto,
};

// this lets us maintain a chain of all the nested FloatingMenuWidgets without
// forcing the user to manually do it
var popup_current: ?*FloatingMenuWidget = null;

fn popupSet(p: ?*FloatingMenuWidget) ?*FloatingMenuWidget {
    const ret = popup_current;
    popup_current = p;
    return ret;
}

pub var defaults: Options = .{
    .name = "FloatingMenu",
    .corner_radius = Rect.all(5),
    .border = Rect.all(1),
    .padding = Rect.all(4),
    .background = true,
    .color_fill = .{ .name = .fill_window },
};

pub const InitOptions = struct {
    from: Rect,
    avoid: FloatingMenuAvoid = .auto,
};

prev_rendering: bool = undefined,
wd: WidgetData = undefined,
options: Options = undefined,
prev_windowId: u32 = 0,
parent_popup: ?*FloatingMenuWidget = null,
have_popup_child: bool = false,
menu: MenuWidget = undefined,
init_options: InitOptions = undefined,
prevClip: Rect = Rect{},
scale_val: f32 = undefined,
scaler: rui.ScaleWidget = undefined,
scroll: ScrollAreaWidget = undefined,

pub fn init(src: std.builtin.SourceLocation, init_opts: InitOptions, opts: Options) FloatingMenuWidget {
    var self = FloatingMenuWidget{};

    // options is really for our embedded ScrollAreaWidget, so save them for the
    // end of install()
    self.options = defaults.override(opts);

    // the widget itself doesn't have any styling, it comes from the
    // embedded MenuWidget
    // passing options.rect will stop WidgetData.init from calling
    // rectFor/minSizeForChild which is important because we are outside
    // normal layout
    self.wd = WidgetData.init(src, .{ .subwindow = true }, .{ .id_extra = opts.id_extra, .rect = .{} });

    // get scale from parent
    self.scale_val = self.wd.parent.screenRectScale(Rect{}).s / rui.windowNaturalScale();

    self.init_options = init_opts;
    if (self.init_options.avoid == .auto) {
        if (rui.MenuWidget.current()) |pm| {
            self.init_options.avoid = switch (pm.init_opts.dir) {
                .horizontal => .vertical,
                .vertical => .horizontal,
            };
        } else {
            self.init_options.avoid = .none;
        }
    }
    return self;
}

pub fn install(self: *FloatingMenuWidget) !void {
    self.prev_rendering = rui.renderingSet(false);

    rui.parentSet(self.widget());

    self.prev_windowId = rui.subwindowCurrentSet(self.wd.id, null).id;
    self.parent_popup = popupSet(self);

    const avoid: rui.PlaceOnScreenAvoid = switch (self.init_options.avoid) {
        .none => .none,
        .horizontal => .horizontal,
        .vertical => .vertical,
        .auto => unreachable,
    };

    if (rui.minSizeGet(self.wd.id)) |_| {
        self.wd.rect = Rect.fromPoint(self.init_options.from.topLeft());
        const ms = rui.minSize(self.wd.id, self.options.min_sizeGet());
        self.wd.rect.w = ms.w;
        self.wd.rect.h = ms.h;
        self.wd.rect = rui.placeOnScreen(rui.windowRect(), self.init_options.from, avoid, self.wd.rect);
    } else {
        self.wd.rect = rui.placeOnScreen(rui.windowRect(), self.init_options.from, avoid, Rect.fromPoint(self.init_options.from.topLeft()));
        rui.focusSubwindow(self.wd.id, null);

        // need a second frame to fit contents (FocusWindow calls refresh but
        // here for clarity)
        rui.refresh(null, @src(), self.wd.id);
    }

    const rs = self.wd.rectScale();

    try rui.subwindowAdd(self.wd.id, self.wd.rect, rs.r, false, null);
    rui.captureMouseMaintain(.{ .id = self.wd.id, .rect = rs.r, .subwindow_id = self.wd.id });
    try self.wd.register();

    // clip to just our window (using clipSet since we are not inside our parent)
    self.prevClip = rui.clipGet();
    rui.clipSet(rs.r);

    self.scaler = rui.ScaleWidget.init(@src(), self.scale_val, .{ .margin = .{}, .expand = .both });
    try self.scaler.install();

    // we are using scroll to do border/background but floating windows
    // don't have margin, so turn that off
    self.scroll = ScrollAreaWidget.init(@src(), .{ .horizontal = .none }, self.options.override(.{ .margin = .{}, .expand = .both }));
    try self.scroll.install();

    if (rui.MenuWidget.current()) |pm| {
        pm.child_popup_rect = rs.r;
    }

    self.menu = MenuWidget.init(@src(), .{ .dir = .vertical }, self.options.strip().override(.{ .expand = .horizontal }));
    self.menu.parentSubwindowId = self.prev_windowId;
    try self.menu.install();

    // if no widget in this popup has focus, make the menu have focus to handle keyboard events
    if (rui.focusedWidgetIdInCurrentSubwindow() == null) {
        rui.focusWidget(self.menu.wd.id, null, null);
    }
}

pub fn close(self: *FloatingMenuWidget) void {
    self.menu.close();
}

pub fn widget(self: *FloatingMenuWidget) Widget {
    return Widget.init(self, data, rectFor, screenRectScale, minSizeForChild, processEvent);
}

pub fn data(self: *FloatingMenuWidget) *WidgetData {
    return &self.wd;
}

pub fn rectFor(self: *FloatingMenuWidget, id: u32, min_size: Size, e: Options.Expand, g: Options.Gravity) Rect {
    _ = id;
    return rui.placeIn(self.wd.contentRect().justSize(), min_size, e, g);
}

pub fn screenRectScale(self: *FloatingMenuWidget, rect: Rect) RectScale {
    return self.wd.contentRectScale().rectToRectScale(rect);
}

pub fn minSizeForChild(self: *FloatingMenuWidget, s: Size) void {
    self.wd.minSizeMax(self.wd.options.padSize(s));
}

pub fn processEvent(self: *FloatingMenuWidget, e: *Event, bubbling: bool) void {
    // popup does cleanup events, but not normal events
    switch (e.evt) {
        .close_popup => {
            self.wd.parent.processEvent(e, true);
        },
        else => {},
    }

    // otherwise popups don't bubble events
    _ = bubbling;
}

pub fn chainFocused(self: *FloatingMenuWidget, self_call: bool) bool {
    if (!self_call) {
        // if we got called by someone else, then we have a popup child
        self.have_popup_child = true;
    }

    var ret: bool = false;

    // we have to call chainFocused on our parent if we have one so we
    // can't return early

    if (self.wd.id == rui.focusedSubwindowId()) {
        // we are focused
        ret = true;
    }

    if (self.parent_popup) |pp| {
        // we had a parent popup, is that focused
        if (pp.chainFocused(false)) {
            ret = true;
        }
    } else if (self.prev_windowId == rui.focusedSubwindowId()) {
        // no parent popup, is our parent window focused
        ret = true;
    }

    return ret;
}

pub fn deinit(self: *FloatingMenuWidget) void {
    self.menu.deinit();
    self.scroll.deinit();
    self.scaler.deinit();

    const rs = self.wd.rectScale();
    const evts = rui.events();
    for (evts) |*e| {
        if (!rui.eventMatch(e, .{ .id = self.wd.id, .r = rs.r, .cleanup = true }))
            continue;

        if (e.evt == .mouse) {
            if (e.evt.mouse.action == .focus) {
                // unhandled click, clear focus
                e.handled = true;
                rui.focusWidget(null, null, null);
            }
        } else if (e.evt == .key) {
            // catch any tabs that weren't handled by widgets
            if (e.evt.key.action == .down and e.evt.key.matchBind("next_widget")) {
                e.handled = true;
                rui.tabIndexNext(e.num);
            }

            if (e.evt.key.action == .down and e.evt.key.matchBind("prev_widget")) {
                e.handled = true;
                rui.tabIndexPrev(e.num);
            }
        }
    }

    // check if a focus event is happening outside our window
    for (evts) |e| {
        if (!e.handled and e.evt == .mouse and e.evt.mouse.action == .focus) {
            var closeE = Event{ .evt = .{ .close_popup = .{} } };
            self.processEvent(&closeE, true);
        }
    }

    if (!self.have_popup_child and !self.chainFocused(true)) {
        // if a popup chain is open and the user focuses a different window
        // (not the parent of the popups), then we want to close the popups

        // only the last popup can do the check, you can't query the focus
        // status of children, only parents
        var closeE = Event{ .evt = .{ .close_popup = .{ .intentional = false } } };
        self.processEvent(&closeE, true);
    }

    // in case no children ever show up, this will provide a visual indication
    // that there is an empty floating menu
    self.wd.minSizeMax(self.wd.options.padSize(.{ .w = 20, .h = 20 }));

    self.wd.minSizeSetAndRefresh();

    // outside normal layout, don't call minSizeForChild or self.wd.minSizeReportToParent();

    _ = popupSet(self.parent_popup);
    rui.parentReset(self.wd.id, self.wd.parent);
    _ = rui.subwindowCurrentSet(self.prev_windowId, null);
    rui.clipSet(self.prevClip);
    _ = rui.renderingSet(self.prev_rendering);
}

test {
    @import("std").testing.refAllDecls(@This());
}
