pub const TabsWidget = @This();

options: Options = undefined,
init_options: InitOptions = undefined,
scroll: ScrollAreaWidget = undefined,
box: BoxWidget = undefined,
tab_index: usize = 0,
tab_button: ButtonWidget = undefined,

pub var defaults: Options = .{
    .background = false,
    .corner_radius = Rect{},
    .name = "Tabs",
};

pub const InitOptions = struct {
    dir: rui.enums.Direction = .horizontal,
};

pub fn init(src: std.builtin.SourceLocation, init_opts: InitOptions, opts: Options) TabsWidget {
    var self = TabsWidget{};
    self.options = defaults.override(opts);
    self.init_options = init_opts;
    var scroll_opts: ScrollAreaWidget.InitOpts = .{};
    switch (self.init_options.dir) {
        .horizontal => scroll_opts = .{ .vertical = .none, .horizontal = .auto, .horizontal_bar = .hide },
        .vertical => scroll_opts = .{ .vertical = .auto, .vertical_bar = .hide },
    }
    self.scroll = ScrollAreaWidget.init(src, scroll_opts, self.options.override(.{ .debug = true }));
    return self;
}

pub fn install(self: *TabsWidget) !void {
    try self.scroll.install();

    const margin: Rect = switch (self.init_options.dir) {
        .horizontal => .{ .y = 2 },
        .vertical => .{ .x = 2 },
    };
    self.box = BoxWidget.init(@src(), self.init_options.dir, false, .{ .margin = margin });
    try self.box.install();

    var r = self.scroll.data().contentRectScale().r;
    switch (self.init_options.dir) {
        .horizontal => {
            if (rui.currentWindow().snap_to_pixels) {
                r.x += 0.5;
                r.w -= 1.0;
                r.y = @floor(r.y) - 0.5;
            }
            try rui.pathStroke(&.{ r.bottomLeft(), r.bottomRight() }, 1, rui.themeGet().color_border, .{});
        },
        .vertical => {
            if (rui.currentWindow().snap_to_pixels) {
                r.y += 0.5;
                r.h -= 1.0;
                r.x = @floor(r.x) - 0.5;
            }
            try rui.pathStroke(&.{ r.topRight(), r.bottomRight() }, 1, rui.themeGet().color_border, .{});
        },
    }
}

pub fn addTabLabel(self: *TabsWidget, selected: bool, text: []const u8) !bool {
    var tab = try self.addTab(selected, .{});
    defer tab.deinit();

    var label_opts = tab.data().options.strip();
    if (rui.captured(tab.data().id)) {
        label_opts.color_text = .{ .name = .text_press };
    }

    try rui.labelNoFmt(@src(), text, label_opts);

    return tab.clicked();
}

pub fn addTab(self: *TabsWidget, selected: bool, opts: Options) !*ButtonWidget {
    var tab_defaults: Options = switch (self.init_options.dir) {
        .horizontal => .{ .id_extra = self.tab_index, .background = true, .corner_radius = .{ .x = 5, .y = 5 }, .margin = .{ .x = 2, .w = 2 } },
        .vertical => .{ .id_extra = self.tab_index, .background = true, .corner_radius = .{ .x = 5, .h = 5 }, .margin = .{ .y = 2, .h = 2 } },
    };

    self.tab_index += 1;

    if (selected) {
        tab_defaults.font_style = .heading;
        tab_defaults.color_fill = .{ .name = .fill_window };
        tab_defaults.border = switch (self.init_options.dir) {
            .horizontal => .{ .x = 1, .y = 1, .w = 1 },
            .vertical => .{ .x = 1, .y = 1, .h = 1 },
        };
    } else {
        tab_defaults.color_fill = .{ .name = .fill_control };
        switch (self.init_options.dir) {
            .horizontal => tab_defaults.margin.?.h = 1,
            .vertical => tab_defaults.margin.?.w = 1,
        }
    }

    switch (self.init_options.dir) {
        .horizontal => tab_defaults.gravity_y = 1.0,
        .vertical => tab_defaults.gravity_x = 1.0,
    }

    const options = tab_defaults.override(opts);

    self.tab_button = ButtonWidget.init(@src(), .{}, options);
    try self.tab_button.install();
    self.tab_button.processEvents();
    try self.tab_button.drawBackground();

    if (self.tab_button.focused() and self.tab_button.data().visible()) {
        const rs = self.tab_button.data().borderRectScale();
        const cr = self.tab_button.data().options.corner_radiusGet();

        switch (self.init_options.dir) {
            .horizontal => {
                var path: std.ArrayList(Point) = .init(rui.currentWindow().arena());
                defer path.deinit();

                try path.append(rs.r.bottomRight());

                const tr = Point{ .x = rs.r.x + rs.r.w - cr.y, .y = rs.r.y + cr.y };
                try rui.pathAddArc(&path, tr, cr.y, math.pi * 2.0, math.pi * 1.5, false);

                const tl = Point{ .x = rs.r.x + cr.x, .y = rs.r.y + cr.x };
                try rui.pathAddArc(&path, tl, cr.x, math.pi * 1.5, math.pi, false);

                try path.append(rs.r.bottomLeft());

                try rui.pathStroke(path.items, 2 * rs.s, self.options.color(.accent), .{ .after = true });
            },
            .vertical => {
                var path: std.ArrayList(Point) = .init(rui.currentWindow().arena());
                defer path.deinit();

                try path.append(rs.r.topRight());

                const tl = Point{ .x = rs.r.x + cr.x, .y = rs.r.y + cr.x };
                try rui.pathAddArc(&path, tl, cr.x, math.pi * 1.5, math.pi, false);

                const bl = Point{ .x = rs.r.x + cr.h, .y = rs.r.y + rs.r.h - cr.h };
                try rui.pathAddArc(&path, bl, cr.h, math.pi, math.pi * 0.5, false);

                try path.append(rs.r.bottomRight());

                try rui.pathStroke(path.items, 2 * rs.s, self.options.color(.accent), .{ .after = true });
            },
        }
    }

    return &self.tab_button;
}

pub fn deinit(self: *TabsWidget) void {
    self.box.deinit();
    self.scroll.deinit();
}

const Options = rui.Options;
const Rect = rui.Rect;
const Point = rui.Point;

const BoxWidget = rui.BoxWidget;
const ButtonWidget = rui.ButtonWidget;
const ScrollAreaWidget = rui.ScrollAreaWidget;

const std = @import("std");
const math = std.math;
const rui = @import("../rui.zig");

test {
    @import("std").testing.refAllDecls(@This());
}
