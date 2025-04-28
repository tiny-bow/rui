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
const BoxWidget = rui.BoxWidget;

const enums = rui.enums;

const MenuWidget = @This();

var menu_current: ?*MenuWidget = null;

pub fn current() ?*MenuWidget {
    return menu_current;
}

fn menuSet(m: ?*MenuWidget) ?*MenuWidget {
    const ret = menu_current;
    menu_current = m;
    return ret;
}

pub var defaults: Options = .{
    .name = "Menu",
    .color_fill = .{ .name = .fill_window },
};

pub const InitOptions = struct {
    dir: enums.Direction = undefined,
};

wd: WidgetData = undefined,

init_opts: InitOptions = undefined,
winId: u32 = undefined,
parentMenu: ?*MenuWidget = null,
parentSubwindowId: ?u32 = null,
box: BoxWidget = undefined,

// whether submenus should be open
submenus_activated: bool = false,

// whether submenus in a child menu should default to open (for mouse interactions, not for keyboard)
submenus_in_child: bool = false,
mouse_over: bool = false,

// if we have a child popup menu, save it's rect for next frame
// supports mouse skipping over menu items if towards the submenu
child_popup_rect: ?Rect = null,

// false means the last interaction we got was keyboard, so don't highlight the
// entry that happens to be under the mouse
mouse_mode: bool = false,

pub fn init(src: std.builtin.SourceLocation, init_opts: InitOptions, opts: Options) MenuWidget {
    var self = MenuWidget{};
    const options = defaults.override(opts);
    self.wd = WidgetData.init(src, .{}, options);
    self.init_opts = init_opts;

    self.winId = rui.subwindowCurrentId();
    if (rui.dataGet(null, self.wd.id, "_sub_act", bool)) |a| {
        self.submenus_activated = a;
    } else if (current()) |pm| {
        self.submenus_activated = pm.submenus_in_child;
    }

    self.mouse_mode = rui.dataGet(null, self.wd.id, "_mouse_mode", bool) orelse false;

    return self;
}

pub fn install(self: *MenuWidget) !void {
    rui.parentSet(self.widget());
    self.parentMenu = menuSet(self);
    try self.wd.register();
    try self.wd.borderAndBackground(.{});

    const evts = rui.events();
    for (evts) |*e| {
        if (!rui.eventMatchSimple(e, self.data()))
            continue;

        self.processEvent(e, false);
    }

    self.box = BoxWidget.init(@src(), self.init_opts.dir, false, self.wd.options.strip().override(.{ .expand = .both }));
    try self.box.install();
    try self.box.drawBackground();
}

pub fn close(self: *MenuWidget) void {
    // bubble this event to close all popups that had submenus leading to this
    var e = Event{ .evt = .{ .close_popup = .{} } };
    self.processEvent(&e, true);
    rui.refresh(null, @src(), self.wd.id);
}

pub fn widget(self: *MenuWidget) Widget {
    return Widget.init(self, data, rectFor, screenRectScale, minSizeForChild, processEvent);
}

pub fn data(self: *MenuWidget) *WidgetData {
    return &self.wd;
}

pub fn rectFor(self: *MenuWidget, id: u32, min_size: Size, e: Options.Expand, g: Options.Gravity) Rect {
    _ = id;
    return rui.placeIn(self.wd.contentRect().justSize(), min_size, e, g);
}

pub fn screenRectScale(self: *MenuWidget, rect: Rect) RectScale {
    return self.wd.contentRectScale().rectToRectScale(rect);
}

pub fn minSizeForChild(self: *MenuWidget, s: Size) void {
    self.wd.minSizeMax(self.wd.options.padSize(s));
}

pub fn processEvent(self: *MenuWidget, e: *Event, bubbling: bool) void {
    _ = bubbling;
    switch (e.evt) {
        .mouse => |me| {
            if (me.action == .position) {
                if (rui.mouseTotalMotion().nonZero()) {
                    self.mouse_mode = true;
                    if (rui.dataGet(null, self.wd.id, "_child_popup", Rect)) |r| {
                        const center = Point{ .x = r.x + r.w / 2, .y = r.y + r.h / 2 };
                        const cw = rui.currentWindow();
                        const to_center = Point.diff(center, cw.mouse_pt_prev);
                        const movement = Point.diff(cw.mouse_pt, cw.mouse_pt_prev);
                        const dot_prod = movement.x * to_center.x + movement.y * to_center.y;
                        const cos = dot_prod / (to_center.length() * movement.length());
                        if (std.math.acos(cos) < std.math.pi / 3.0) {
                            // there is an existing submenu and motion is
                            // towards the popup, so eat this event to
                            // prevent any menu items from focusing
                            e.handled = true;
                        }
                    }

                    if (!e.handled) {
                        self.mouse_over = true;
                    }
                }
            }
        },
        .key => |ke| {
            if (ke.action == .down or ke.action == .repeat) {
                switch (ke.code) {
                    .escape => {
                        self.mouse_mode = false;
                        e.handled = true;
                        var closeE = Event{ .evt = .{ .close_popup = .{} } };
                        self.processEvent(&closeE, true);
                    },
                    .up => {
                        self.mouse_mode = false;
                        if (self.init_opts.dir == .vertical) {
                            e.handled = true;
                            // TODO: don't do this if focus would move outside the menu
                            rui.tabIndexPrev(e.num);
                        }
                    },
                    .down => {
                        self.mouse_mode = false;
                        if (self.init_opts.dir == .vertical) {
                            e.handled = true;
                            // TODO: don't do this if focus would move outside the menu
                            rui.tabIndexNext(e.num);
                        }
                    },
                    .left => {
                        self.mouse_mode = false;
                        if (self.init_opts.dir == .vertical) {
                            e.handled = true;
                            if (self.parentMenu) |pm| {
                                pm.submenus_activated = false;
                                if (self.parentSubwindowId) |sid| {
                                    rui.focusSubwindow(sid, null);
                                }
                            }
                        } else {
                            e.handled = true;
                            // TODO: don't do this if focus would move outside the menu
                            rui.tabIndexPrev(e.num);
                        }
                    },
                    .right => {
                        self.mouse_mode = false;
                        if (self.init_opts.dir == .horizontal) {
                            e.handled = true;
                            // TODO: don't do this if focus would move outside the menu
                            rui.tabIndexNext(e.num);
                        }
                    },
                    else => {},
                }
            }
        },
        .close_popup => {
            self.submenus_activated = false;
        },
        else => {},
    }

    if (e.bubbleable()) {
        self.wd.parent.processEvent(e, true);
    }
}

pub fn deinit(self: *MenuWidget) void {
    self.box.deinit();
    rui.dataSet(null, self.wd.id, "_mouse_mode", self.mouse_mode);
    rui.dataSet(null, self.wd.id, "_sub_act", self.submenus_activated);
    if (self.child_popup_rect) |r| {
        rui.dataSet(null, self.wd.id, "_child_popup", r);
    }
    self.wd.minSizeSetAndRefresh();
    self.wd.minSizeReportToParent();
    _ = menuSet(self.parentMenu);
    rui.parentReset(self.wd.id, self.wd.parent);
}

test {
    @import("std").testing.refAllDecls(@This());
}
