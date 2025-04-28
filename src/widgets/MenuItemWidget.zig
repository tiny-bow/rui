const std = @import("std");
const rui = @import("../rui.zig");

const Event = rui.Event;
const Options = rui.Options;
const Rect = rui.Rect;
const RectScale = rui.RectScale;
const Size = rui.Size;
const Widget = rui.Widget;
const WidgetData = rui.WidgetData;

const MenuItemWidget = @This();

pub var defaults: Options = .{
    .name = "MenuItem",
    .corner_radius = Rect.all(5),
    .padding = Rect.all(6),
};

pub const InitOptions = struct {
    submenu: bool = false,
    highlight_only: bool = false,
};

wd: WidgetData = undefined,
focused_last_frame: bool = undefined,
highlight: bool = false,
init_opts: InitOptions = undefined,
activated: bool = false,
show_active: bool = false,
mouse_over: bool = false,

pub fn init(src: std.builtin.SourceLocation, init_opts: InitOptions, opts: Options) MenuItemWidget {
    var self = MenuItemWidget{};
    const options = defaults.override(opts);
    self.wd = WidgetData.init(src, .{}, options);
    self.init_opts = init_opts;
    self.focused_last_frame = rui.dataGet(null, self.wd.id, "_focus_last", bool) orelse false;
    return self;
}

pub fn install(self: *MenuItemWidget) !void {
    try self.wd.register();

    // For most widgets we only tabIndexSet if they are visible, but menu
    // items are often in large dropdowns that are scrollable, plus the
    // up/down arrow keys get used to move between menu items, so you need
    // to be able to move to the next menu item even if it's not visible
    try rui.tabIndexSet(self.wd.id, self.wd.options.tab_index);

    try self.wd.borderAndBackground(.{});

    rui.parentSet(self.widget());
}

pub fn drawBackground(self: *MenuItemWidget, opts: struct { focus_as_outline: bool = false }) !void {
    var focused: bool = false;
    if (self.wd.id == rui.focusedWidgetId()) {
        focused = true;
    }

    if (focused and rui.MenuWidget.current().?.mouse_over and !self.mouse_over) {
        // our menu got a mouse over but we didn't even though we were focused
        focused = false;
        rui.focusWidget(null, null, null);
    }

    if (focused or ((self.wd.id == rui.focusedWidgetIdInCurrentSubwindow()) and self.highlight)) {
        if (!self.init_opts.submenu or !rui.MenuWidget.current().?.submenus_activated) {
            if (!self.init_opts.highlight_only) {
                self.show_active = true;
            }

            if (!self.focused_last_frame) {
                // in case we are in a scrollable dropdown, scroll
                var scrollto = Event{ .evt = .{ .scroll_to = .{ .screen_rect = self.wd.borderRectScale().r } } };
                self.wd.parent.processEvent(&scrollto, true);
            }
        }
    }

    self.focused_last_frame = focused;

    if (self.wd.visible()) {
        if (self.show_active) {
            if (opts.focus_as_outline) {
                try self.wd.focusBorder();
            } else {
                const rs = self.wd.backgroundRectScale();
                try rs.r.fill(self.wd.options.corner_radiusGet().scale(rs.s), self.wd.options.color(.accent));
            }
        } else if ((self.wd.id == rui.focusedWidgetIdInCurrentSubwindow()) or self.highlight) {
            const rs = self.wd.backgroundRectScale();
            try rs.r.fill(self.wd.options.corner_radiusGet().scale(rs.s), self.wd.options.color(.fill_hover));
        } else if (self.wd.options.backgroundGet()) {
            const rs = self.wd.backgroundRectScale();
            try rs.r.fill(self.wd.options.corner_radiusGet().scale(rs.s), self.wd.options.color(.fill));
        }
    }
}

pub fn matchEvent(self: *MenuItemWidget, e: *Event) bool {
    return rui.eventMatchSimple(e, self.data());
}

pub fn processEvents(self: *MenuItemWidget) void {
    const evts = rui.events();
    for (evts) |*e| {
        if (!self.matchEvent(e))
            continue;

        self.processEvent(e, false);
    }
}

pub fn activeRect(self: *const MenuItemWidget) ?Rect {
    var act = false;
    if (self.init_opts.submenu) {
        if (rui.MenuWidget.current().?.submenus_activated and (self.wd.id == rui.focusedWidgetIdInCurrentSubwindow())) {
            act = true;
        }
    } else if (self.activated) {
        act = true;
    }

    if (act) {
        const rs = self.wd.backgroundRectScale();
        return rs.r.scale(1 / rui.windowNaturalScale());
    } else {
        return null;
    }
}

pub fn widget(self: *MenuItemWidget) Widget {
    return Widget.init(self, data, rectFor, screenRectScale, minSizeForChild, processEvent);
}

pub fn data(self: *MenuItemWidget) *WidgetData {
    return &self.wd;
}

pub fn rectFor(self: *MenuItemWidget, id: u32, min_size: Size, e: Options.Expand, g: Options.Gravity) Rect {
    _ = id;
    return rui.placeIn(self.wd.contentRect().justSize(), min_size, e, g);
}

pub fn screenRectScale(self: *MenuItemWidget, rect: Rect) RectScale {
    return self.wd.contentRectScale().rectToRectScale(rect);
}

pub fn minSizeForChild(self: *MenuItemWidget, s: Size) void {
    self.wd.minSizeMax(self.wd.options.padSize(s));
}

pub fn processEvent(self: *MenuItemWidget, e: *Event, bubbling: bool) void {
    _ = bubbling;
    switch (e.evt) {
        .mouse => |me| {
            if (me.action == .focus) {
                rui.MenuWidget.current().?.mouse_mode = true;
                e.handled = true;
                rui.focusWidget(self.wd.id, null, e.num);
            } else if (me.action == .press and me.button.pointer()) {
                // This works differently than normal (like buttons) where we
                // captureMouse on press, to support the mouse
                // click-open-drag-select-release-activate pattern for menus
                // and dropdowns.  However, we still need to do the capture
                // pattern for touch.
                //
                // This is how dropdowns are triggered.
                e.handled = true;
                if (self.init_opts.submenu) {
                    rui.MenuWidget.current().?.submenus_activated = true;
                    rui.MenuWidget.current().?.submenus_in_child = true;
                }

                if (me.button.touch()) {
                    // with touch we have to capture otherwise any motion will
                    // cause scroll to capture
                    rui.captureMouse(self.data());
                    rui.dragPreStart(me.p, .{});
                }
            } else if (me.action == .release) {
                rui.MenuWidget.current().?.mouse_mode = true;
                e.handled = true;
                if (!self.init_opts.submenu and (self.wd.id == rui.focusedWidgetIdInCurrentSubwindow())) {
                    self.activated = true;
                    rui.refresh(null, @src(), self.wd.id);
                }
                if (rui.captured(self.wd.id)) {
                    // should only happen with touch
                    rui.captureMouse(null);
                    rui.dragEnd();
                }
            } else if (me.action == .motion and me.button.touch()) {
                if (rui.captured(self.wd.id)) {
                    if (rui.dragging(me.p)) |_| {
                        // if we overcame the drag threshold, then that
                        // means the person probably didn't want to touch
                        // this, maybe they were trying to scroll
                        rui.captureMouse(null);
                        rui.dragEnd();
                    }
                }
            } else if (me.action == .position) {
                if (rui.MenuWidget.current().?.mouse_mode) {
                    rui.cursorSet(.arrow);
                    self.highlight = true;
                }

                // We get a .position mouse event every frame.  If we
                // focus the menu item under the mouse even if it's not
                // moving then it breaks keyboard navigation.
                if (rui.mouseTotalMotion().nonZero()) {
                    rui.MenuWidget.current().?.mouse_mode = true;
                    self.mouse_over = true;
                    // we shouldn't have gotten this event if the motion
                    // was towards a submenu (caught in MenuWidget)
                    rui.focusSubwindow(null, null); // focuses the window we are in
                    rui.focusWidget(self.wd.id, null, null);

                    if (self.init_opts.submenu) {
                        rui.MenuWidget.current().?.submenus_in_child = true;
                    }
                }
            }
        },
        .key => |ke| {
            if (ke.action == .down and ke.matchBind("activate")) {
                rui.MenuWidget.current().?.mouse_mode = false;
                e.handled = true;
                if (self.init_opts.submenu) {
                    rui.MenuWidget.current().?.submenus_activated = true;
                } else {
                    self.activated = true;
                    rui.refresh(null, @src(), self.wd.id);
                }
            } else if (ke.code == .right and ke.action == .down) {
                if (self.init_opts.submenu and rui.MenuWidget.current().?.init_opts.dir == .vertical) {
                    rui.MenuWidget.current().?.mouse_mode = false;
                    e.handled = true;
                    rui.MenuWidget.current().?.submenus_activated = true;
                }
            } else if (ke.code == .down and ke.action == .down) {
                if (self.init_opts.submenu and rui.MenuWidget.current().?.init_opts.dir == .horizontal) {
                    rui.MenuWidget.current().?.mouse_mode = false;
                    e.handled = true;
                    rui.MenuWidget.current().?.submenus_activated = true;
                }
            }
        },
        else => {},
    }

    if (e.bubbleable()) {
        self.wd.parent.processEvent(e, true);
    }
}

pub fn deinit(self: *MenuItemWidget) void {
    rui.dataSet(null, self.wd.id, "_focus_last", self.focused_last_frame);
    self.wd.minSizeSetAndRefresh();
    self.wd.minSizeReportToParent();
    rui.parentReset(self.wd.id, self.wd.parent);
}

test {
    @import("std").testing.refAllDecls(@This());
}
