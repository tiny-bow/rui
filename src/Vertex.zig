const rui = @import("rui.zig");

const Point = rui.Point;
const Color = rui.Color;

pos: Point,
col: Color,
uv: @Vector(2, f32),

test {
    @import("std").testing.refAllDecls(@This());
}
