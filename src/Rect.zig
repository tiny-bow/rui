const std = @import("std");
const rui = @import("rui.zig");

const Point = rui.Point;
const Size = rui.Size;

const Rect = @This();

x: f32 = 0,
y: f32 = 0,
w: f32 = 0,
h: f32 = 0,

/// Stroke (outline) a rounded rect.
///
/// radius values:
/// - x is top-left corner
/// - y is top-right corner
/// - w is bottom-right corner
/// - h is bottom-left corner
///
/// Only valid between rui.Window.begin() and end().
pub fn stroke(self: Rect, radius: Rect, thickness: f32, color: rui.Color, opts: rui.PathStrokeOptions) !void {
    var path: std.ArrayList(rui.Point) = .init(rui.currentWindow().arena());
    defer path.deinit();

    try rui.pathAddRect(&path, self, radius);
    var options = opts;
    options.closed = true;
    try rui.pathStroke(path.items, thickness, color, options);
}

/// Fill a rounded rect.
///
/// radius values:
/// - x is top-left corner
/// - y is top-right corner
/// - w is bottom-right corner
/// - h is bottom-left corner
///
/// Only valid between rui.Window.begin() and end().
pub fn fill(self: Rect, radius: Rect, color: rui.Color) !void {
    var path: std.ArrayList(rui.Point) = .init(rui.currentWindow().arena());
    defer path.deinit();

    try rui.pathAddRect(&path, self, radius);
    try rui.pathFillConvex(path.items, color);
}

pub fn equals(self: *const Rect, r: Rect) bool {
    return (self.x == r.x and self.y == r.y and self.w == r.w and self.h == r.h);
}

pub fn plus(self: *const Rect, r: Rect) Rect {
    return Rect{ .x = self.x + r.x, .y = self.y + r.y, .w = self.w + r.w, .h = self.h + r.h };
}

pub fn nonZero(self: *const Rect) bool {
    return (self.x != 0 or self.y != 0 or self.w != 0 or self.h != 0);
}

pub fn all(v: f32) Rect {
    return Rect{ .x = v, .y = v, .w = v, .h = v };
}

pub fn fromPoint(p: Point) Rect {
    return Rect{ .x = p.x, .y = p.y };
}

pub fn toPoint(self: *const Rect, p: Point) Rect {
    return Rect{ .x = self.x, .y = self.y, .w = p.x - self.x, .h = p.y - self.y };
}

pub fn toSize(self: *const Rect, s: Size) Rect {
    return Rect{ .x = self.x, .y = self.y, .w = s.w, .h = s.h };
}

pub fn justSize(self: *const Rect) Rect {
    return Rect{ .x = 0, .y = 0, .w = self.w, .h = self.h };
}

pub fn topLeft(self: *const Rect) Point {
    return Point{ .x = self.x, .y = self.y };
}

pub fn topRight(self: *const Rect) Point {
    return Point{ .x = self.x + self.w, .y = self.y };
}

pub fn bottomLeft(self: *const Rect) Point {
    return Point{ .x = self.x, .y = self.y + self.h };
}

pub fn bottomRight(self: *const Rect) Point {
    return Point{ .x = self.x + self.w, .y = self.y + self.h };
}

pub fn center(self: *const Rect) Point {
    return Point{ .x = self.x + self.w / 2, .y = self.y + self.h / 2 };
}

pub fn size(self: *const Rect) Size {
    return Size{ .w = self.w, .h = self.h };
}

pub fn contains(self: *const Rect, p: Point) bool {
    return (p.x >= self.x and p.x <= (self.x + self.w) and p.y >= self.y and p.y <= (self.y + self.h));
}

pub fn empty(self: *const Rect) bool {
    return (self.w == 0 or self.h == 0);
}

/// ![image](Rect-scale.png)
pub fn scale(self: *const Rect, s: f32) Rect {
    return Rect{ .x = self.x * s, .y = self.y * s, .w = self.w * s, .h = self.h * s };
}

/// ![image](Rect-offset.png)
pub fn offset(self: *const Rect, r: Rect) Rect {
    return Rect{ .x = self.x + r.x, .y = self.y + r.y, .w = self.w, .h = self.h };
}

/// Same as `offsetNegPoint` but takes a rect, ignoring the width and height
pub fn offsetNeg(self: *const Rect, r: Rect) Rect {
    return Rect{ .x = self.x - r.x, .y = self.y - r.y, .w = self.w, .h = self.h };
}

/// ![image](Rect-offsetNegPoint.png)
pub fn offsetNegPoint(self: *const Rect, p: Point) Rect {
    return Rect{ .x = self.x - p.x, .y = self.y - p.y, .w = self.w, .h = self.h };
}

/// ![image](Rect-intersect.png)
pub fn intersect(a: Rect, b: Rect) Rect {
    const ax2 = a.x + a.w;
    const ay2 = a.y + a.h;
    const bx2 = b.x + b.w;
    const by2 = b.y + b.h;
    const x = @max(a.x, b.x);
    const y = @max(a.y, b.y);
    const x2 = @min(ax2, bx2);
    const y2 = @min(ay2, by2);
    return Rect{ .x = x, .y = y, .w = @max(0, x2 - x), .h = @max(0, y2 - y) };
}

/// True if self would be modified when clipped by r.
pub fn clippedBy(self: *const Rect, r: Rect) bool {
    return self.x < r.x or self.y < r.y or
        (self.x + self.w > r.x + r.w) or
        (self.y + self.h > r.y + r.h);
}

/// ![image](Rect-unionWith.png)
pub fn unionWith(a: Rect, b: Rect) Rect {
    const ax2 = a.x + a.w;
    const ay2 = a.y + a.h;
    const bx2 = b.x + b.w;
    const by2 = b.y + b.h;
    const x = @min(a.x, b.x);
    const y = @min(a.y, b.y);
    const x2 = @max(ax2, bx2);
    const y2 = @max(ay2, by2);
    return Rect{ .x = x, .y = y, .w = @max(0, x2 - x), .h = @max(0, y2 - y) };
}

pub fn shrinkToSize(self: *const Rect, s: Size) Rect {
    return Rect{ .x = self.x, .y = self.y, .w = @min(self.w, s.w), .h = @min(self.h, s.h) };
}

/// ![image](Rect-inset.png)
pub fn inset(self: *const Rect, r: Rect) Rect {
    return Rect{ .x = self.x + r.x, .y = self.y + r.y, .w = @max(0, self.w - r.x - r.w), .h = @max(0, self.h - r.y - r.h) };
}

/// See `inset`
pub fn insetAll(self: *const Rect, p: f32) Rect {
    return self.inset(Rect.all(p));
}

/// ![image](Rect-outset.png)
pub fn outset(self: *const Rect, r: Rect) Rect {
    return Rect{ .x = self.x - r.x, .y = self.y - r.y, .w = self.w + r.x + r.w, .h = self.h + r.y + r.h };
}

/// See `outset`
pub fn outsetAll(self: *const Rect, p: f32) Rect {
    return self.outset(Rect.all(p));
}

pub fn format(self: *const Rect, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
    try std.fmt.format(writer, "Rect{{ {d} {d} {d} {d} }}", .{ self.x, self.y, self.w, self.h });
}

test {
    @import("std").testing.refAllDecls(@This());
}

test scale {
    const rect = Rect{ .x = 50, .y = 50, .w = 150, .h = 150 };
    const res = rect.scale(0.5);
    try std.testing.expectEqualDeep(Rect{ .x = 25, .y = 25, .w = 75, .h = 75 }, res);
}

test "Rect-scale.png" {
    var t = try rui.testing.init(.{ .window_size = .all(250) });
    defer t.deinit();

    const frame = struct {
        fn frame() !rui.App.Result {
            // NOTE: Should be kept up to date with the doctest
            const rect = Rect{ .x = 50, .y = 50, .w = 150, .h = 150 };
            const res = rect.scale(0.5);
            try std.testing.expectEqualDeep(Rect{ .x = 25, .y = 25, .w = 75, .h = 75 }, res);

            var box = try rui.box(@src(), .horizontal, .{ .background = true, .color_fill = .{ .name = .fill_window }, .expand = .both });
            defer box.deinit();
            try rect.stroke(.{}, 1, rui.Color.black.transparent(0.5), .{ .closed = true });
            try res.stroke(.{}, 1, .{ .r = 0xff, .g = 0, .b = 0 }, .{ .closed = true });
            return .ok;
        }
    }.frame;

    try t.saveDocImage(@src(), .{}, frame);
}

test offset {
    const rect = Rect{ .x = 50, .y = 50, .w = 100, .h = 100 };
    const res = rect.offset(.{ .x = 50, .y = 50 }); // width and height does nothing
    try std.testing.expectEqualDeep(Rect{ .x = 100, .y = 100, .w = 100, .h = 100 }, res);
}

test "Rect-offset.png" {
    var t = try rui.testing.init(.{ .window_size = .all(250) });
    defer t.deinit();

    const frame = struct {
        fn frame() !rui.App.Result {
            // NOTE: Should be kept up to date with the doctest
            const rect = Rect{ .x = 50, .y = 50, .w = 100, .h = 100 };
            const res = rect.offset(.{ .x = 50, .y = 50 }); // width and height does nothing
            try std.testing.expectEqualDeep(Rect{ .x = 100, .y = 100, .w = 100, .h = 100 }, res);

            var box = try rui.box(@src(), .horizontal, .{ .background = true, .color_fill = .{ .name = .fill_window }, .expand = .both });
            defer box.deinit();
            try rect.stroke(.{}, 1, rui.Color.black.transparent(0.5), .{ .closed = true });
            try res.stroke(.{}, 1, .{ .r = 0xff, .g = 0, .b = 0 }, .{ .closed = true });
            return .ok;
        }
    }.frame;

    try t.saveDocImage(@src(), .{}, frame);
}

test offsetNeg {
    const rect = Rect{ .x = 100, .y = 100, .w = 100, .h = 100 };
    const res = rect.offsetNeg(.{ .x = 50, .y = 50 }); // width and height does nothing
    try std.testing.expectEqualDeep(Rect{ .x = 50, .y = 50, .w = 100, .h = 100 }, res);
}

test offsetNegPoint {
    const rect = Rect{ .x = 100, .y = 100, .w = 100, .h = 100 };
    const res = rect.offsetNegPoint(.{ .x = 50, .y = 50 });
    try std.testing.expectEqualDeep(Rect{ .x = 50, .y = 50, .w = 100, .h = 100 }, res);
}

test "Rect-offsetNegPoint.png" {
    var t = try rui.testing.init(.{ .window_size = .all(250) });
    defer t.deinit();

    const frame = struct {
        fn frame() !rui.App.Result {
            // NOTE: Should be kept up to date with the doctest
            const rect = Rect{ .x = 100, .y = 100, .w = 100, .h = 100 };
            const res = rect.offsetNegPoint(.{ .x = 50, .y = 50 });
            try std.testing.expectEqualDeep(Rect{ .x = 50, .y = 50, .w = 100, .h = 100 }, res);

            var box = try rui.box(@src(), .horizontal, .{ .background = true, .color_fill = .{ .name = .fill_window }, .expand = .both });
            defer box.deinit();
            try rect.stroke(.{}, 1, rui.Color.black.transparent(0.5), .{ .closed = true });
            try res.stroke(.{}, 1, .{ .r = 0xff, .g = 0, .b = 0 }, .{ .closed = true });
            return .ok;
        }
    }.frame;

    try t.saveDocImage(@src(), .{}, frame);
}

test intersect {
    const a = Rect{ .x = 50, .y = 50, .w = 100, .h = 100 };
    const b = Rect{ .x = 100, .y = 100, .w = 100, .h = 100 };

    const ab = Rect.intersect(a, b);
    try std.testing.expectEqualDeep(Rect{ .x = 100, .y = 100, .w = 50, .h = 50 }, ab);
}

test "Rect-intersect.png" {
    var t = try rui.testing.init(.{ .window_size = .all(250) });
    defer t.deinit();

    const frame = struct {
        fn frame() !rui.App.Result {
            // NOTE: Should be kept up to date with the doctest
            const a = Rect{ .x = 50, .y = 50, .w = 100, .h = 100 };
            const b = Rect{ .x = 100, .y = 100, .w = 100, .h = 100 };

            const ab = Rect.intersect(a, b);
            try std.testing.expectEqualDeep(Rect{ .x = 100, .y = 100, .w = 50, .h = 50 }, ab);

            var box = try rui.box(@src(), .horizontal, .{ .background = true, .color_fill = .{ .name = .fill_window }, .expand = .both });
            defer box.deinit();
            try a.stroke(.{}, 1, rui.Color.black.transparent(0.5), .{ .closed = true });
            try b.stroke(.{}, 1, rui.Color.black.transparent(0.5), .{ .closed = true });
            try ab.stroke(.{}, 1, .{ .r = 0xff, .g = 0, .b = 0 }, .{ .closed = true });
            return .ok;
        }
    }.frame;

    try t.saveDocImage(@src(), .{}, frame);
}

test unionWith {
    const a = Rect{ .x = 50, .y = 50, .w = 100, .h = 100 };
    const b = Rect{ .x = 100, .y = 100, .w = 100, .h = 100 };

    const ab = Rect.unionWith(a, b);
    try std.testing.expectEqualDeep(Rect{ .x = 50, .y = 50, .w = 150, .h = 150 }, ab);
}

test "Rect-unionWith.png" {
    var t = try rui.testing.init(.{ .window_size = .all(250) });
    defer t.deinit();

    const frame = struct {
        fn frame() !rui.App.Result {
            // NOTE: Should be kept up to date with the doctest
            const a = Rect{ .x = 50, .y = 50, .w = 100, .h = 100 };
            const b = Rect{ .x = 100, .y = 100, .w = 100, .h = 100 };

            const ab = Rect.unionWith(a, b);
            try std.testing.expectEqualDeep(Rect{ .x = 50, .y = 50, .w = 150, .h = 150 }, ab);

            var box = try rui.box(@src(), .horizontal, .{ .background = true, .color_fill = .{ .name = .fill_window }, .expand = .both });
            defer box.deinit();
            try a.stroke(.{}, 1, rui.Color.black.transparent(0.5), .{ .closed = true });
            try b.stroke(.{}, 1, rui.Color.black.transparent(0.5), .{ .closed = true });
            try ab.stroke(.{}, 1, .{ .r = 0xff, .g = 0, .b = 0 }, .{ .closed = true });
            return .ok;
        }
    }.frame;

    try t.saveDocImage(@src(), .{}, frame);
}

test inset {
    const rect = Rect{ .x = 50, .y = 50, .w = 150, .h = 150 };
    const res = rect.inset(.{ .x = 50, .y = 50, .w = 25, .h = 25 });
    try std.testing.expectEqualDeep(Rect{ .x = 100, .y = 100, .w = 75, .h = 75 }, res);
}
test "Rect-inset.png" {
    var t = try rui.testing.init(.{ .window_size = .all(250) });
    defer t.deinit();

    const frame = struct {
        fn frame() !rui.App.Result {
            // NOTE: Should be kept up to date with the doctest
            const rect = Rect{ .x = 50, .y = 50, .w = 150, .h = 150 };
            const res = rect.inset(.{ .x = 50, .y = 50, .w = 25, .h = 25 });
            try std.testing.expectEqualDeep(Rect{ .x = 100, .y = 100, .w = 75, .h = 75 }, res);

            var box = try rui.box(@src(), .horizontal, .{ .background = true, .color_fill = .{ .name = .fill_window }, .expand = .both });
            defer box.deinit();
            try rect.stroke(.{}, 1, rui.Color.black.transparent(0.5), .{ .closed = true });
            try res.stroke(.{}, 1, .{ .r = 0xff, .g = 0, .b = 0 }, .{ .closed = true });
            return .ok;
        }
    }.frame;

    try t.saveDocImage(@src(), .{}, frame);
}

test insetAll {
    const rect = Rect{ .x = 50, .y = 50, .w = 150, .h = 150 };
    const res = rect.insetAll(50);
    try std.testing.expectEqualDeep(Rect{ .x = 100, .y = 100, .w = 50, .h = 50 }, res);
}

test outset {
    const rect = Rect{ .x = 100, .y = 100, .w = 50, .h = 50 };
    const res = rect.outset(.{ .x = 50, .y = 50, .w = 25, .h = 25 });
    try std.testing.expectEqualDeep(Rect{ .x = 50, .y = 50, .w = 125, .h = 125 }, res);
}
test "Rect-outset.png" {
    var t = try rui.testing.init(.{ .window_size = .all(250) });
    defer t.deinit();

    const frame = struct {
        fn frame() !rui.App.Result {
            // NOTE: Should be kept up to date with the doctest
            const rect = Rect{ .x = 100, .y = 100, .w = 50, .h = 50 };
            const res = rect.outset(.{ .x = 50, .y = 50, .w = 25, .h = 25 });
            try std.testing.expectEqualDeep(Rect{ .x = 50, .y = 50, .w = 125, .h = 125 }, res);

            var box = try rui.box(@src(), .horizontal, .{ .background = true, .color_fill = .{ .name = .fill_window }, .expand = .both });
            defer box.deinit();
            try rect.stroke(.{}, 1, rui.Color.black.transparent(0.5), .{ .closed = true });
            try res.stroke(.{}, 1, .{ .r = 0xff, .g = 0, .b = 0 }, .{ .closed = true });
            return .ok;
        }
    }.frame;

    try t.saveDocImage(@src(), .{}, frame);
}

test outsetAll {
    const rect = Rect{ .x = 100, .y = 100, .w = 50, .h = 50 };
    const res = rect.outsetAll(50);
    try std.testing.expectEqualDeep(Rect{ .x = 50, .y = 50, .w = 150, .h = 150 }, res);
}
