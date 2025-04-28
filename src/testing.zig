allocator: std.mem.Allocator,
backend: *Backend,
window: *Window,
doc_image_dir: ?[]const u8,
snapshot_dir: []const u8,

snapshot_index: u8 = 0,

/// Moves the mouse to the center of the widget
pub fn moveTo(tag: []const u8) !void {
    const tag_data = rui.tagGet(tag) orelse {
        std.debug.print("tag \"{s}\" not found\n", .{tag});
        return error.TagNotFound;
    };
    if (!tag_data.visible) return error.WidgetNotVisible;
    try moveToPoint(tag_data.rect.center());
}

/// Moves the mouse to the provided absolute position
pub fn moveToPoint(point: rui.Point) !void {
    const cw = rui.currentWindow();
    _ = try cw.addEventMouseMotion(point.x, point.y);
}

/// Presses and releases the button at the current mouse position
pub fn click(b: rui.enums.Button) !void {
    const cw = rui.currentWindow();
    _ = try cw.addEventMouseButton(b, .press);
    _ = try cw.addEventMouseButton(b, .release);
}

pub fn writeText(text: []const u8) !void {
    const cw = rui.currentWindow();
    _ = try cw.addEventText(text);
}

pub fn pressKey(code: rui.enums.Key, mod: rui.enums.Mod) !void {
    const cw = rui.currentWindow();
    _ = try cw.addEventKey(.{ .code = code, .mod = mod, .action = .down });
    _ = try cw.addEventKey(.{ .code = code, .mod = mod, .action = .up });
}

/// Runs frames until `rui.refresh` was not called.
///
/// Assumes we are just after `rui.Window.begin`, and on return will be just
/// after a future `rui.Window.begin`.
pub fn settle(frame: rui.App.frameFunction) !void {
    for (0..100) |_| {
        const wait_time = try step(frame);

        if (wait_time == 0) {
            // need another frame, someone called refresh()
            continue;
        }

        return;
    }

    return error.unsettled;
}

/// Runs exactly one frame, returning the wait_time from `rui.Window.end`.
///
/// Assumes we are just after `rui.Window.begin`, and moves to just after the
/// next `rui.Window.begin`.
///
/// Useful when you know the frame will not settle, but you need the frame
/// to handle events.
pub fn step(frame: rui.App.frameFunction) !?u32 {
    const cw = rui.currentWindow();
    if (try frame() == .close) return error.closed;
    const wait_time = try cw.end(.{});
    try cw.begin(cw.frame_time_ns + 100 * std.time.ns_per_ms);
    return wait_time;
}

pub const InitOptions = struct {
    allocator: std.mem.Allocator = if (@import("builtin").is_test) std.testing.allocator else undefined,
    window_size: rui.Size = .{ .w = 600, .h = 400 },
    doc_image_dir: ?[]const u8 = null,
    snapshot_dir: []const u8 = "snapshots",
};

pub fn init(options: InitOptions) !Self {
    // init SDL backend (creates and owns OS window)
    const backend = try options.allocator.create(Backend);
    errdefer options.allocator.destroy(backend);
    backend.* = switch (Backend.kind) {
        .sdl2, .sdl3 => try Backend.initWindow(.{
            .allocator = options.allocator,
            .size = options.window_size,
            .vsync = false,
            .title = "",
            .hidden = true,
        }),
        .testing => Backend.init(.{
            .allocator = options.allocator,
            .size = options.window_size,
        }),
        inline else => |kind| {
            std.debug.print("rui.testing does not support the {s} backend\n", .{@tagName(kind)});
            return error.SkipZigTest;
        },
    };

    const img_dir = options.doc_image_dir orelse @import("build_options").doc_image_dir;

    if (img_dir) |imgdir| {
        std.fs.cwd().makePath(imgdir) catch |err| switch (err) {
            else => return err,
        };
    }

    if (should_write_snapshots()) {
        // ensure snapshot directory exists
        // NOTE: do fs operation through cwd to handle relative and absolute paths
        std.fs.cwd().makeDir(options.snapshot_dir) catch |err| switch (err) {
            error.PathAlreadyExists => {},
            else => return err,
        };
    }

    const window = try options.allocator.create(Window);
    window.* = try rui.Window.init(@src(), options.allocator, backend.backend(), .{});

    window.begin(0) catch unreachable;

    return .{
        .allocator = options.allocator,
        .backend = backend,
        .window = window,
        .doc_image_dir = img_dir,
        .snapshot_dir = options.snapshot_dir,
    };
}

pub fn deinit(self: *Self) void {
    _ = self.window.end(.{}) catch |err| {
        std.debug.print("window.end() returned {!}\n", .{err});
    };
    self.window.deinit();
    self.backend.deinit();
    self.allocator.destroy(self.window);
    self.allocator.destroy(self.backend);
}

pub fn expectFocused(tag: []const u8) !void {
    if (rui.tagGet(tag)) |data| {
        try std.testing.expectEqual(data.id, rui.focusedWidgetId());
    } else {
        std.debug.print("tag \"{s}\" not found\n", .{tag});
        return error.TagNotFound;
    }
}

pub fn expectVisible(tag: []const u8) !void {
    if (rui.tagGet(tag)) |data| {
        try std.testing.expect(data.visible);
    } else {
        std.debug.print("tag \"{s}\" not found\n", .{tag});
        return error.TagNotFound;
    }
}

pub const SnapshotError = error{
    MissingSnapshotDirectory,
    MissingSnapshotFile,
    SnapshotsDidNotMatch,
};

/// Captures one frame and return the png data for that frame.
///
/// Captures the physical pixels in rect, or if null the entire OS window.
///
/// The returned data is allocated by `Self.allocator` and should be freed by the caller.
pub fn capturePng(self: *Self, frame: rui.App.frameFunction, rect: ?rui.Rect) ![]const u8 {
    var picture = rui.Picture.start(rect orelse rui.windowRectPixels()) orelse {
        std.debug.print("Current backend does not support capturing images\n", .{});
        return error.Unsupported;
    };

    // run the gui code
    if (try frame() == .close) return error.closed;

    // render the retained dialogs and deferred renders
    _ = try rui.currentWindow().endRendering(.{});

    picture.stop();

    // texture will be destroyed in picture.deinit() so grab pixels now
    const png_data = try picture.png(self.allocator);

    // draw texture and destroy
    picture.deinit();

    const cw = rui.currentWindow();

    _ = try cw.end(.{});
    try cw.begin(cw.frame_time_ns + 100 * std.time.ns_per_ms);

    return png_data;
}
const png_extension = ".png";

/// Captures one frame and compares to an earilier captured frame, returning an error if they are not the same
///
/// IMPORTANT: Snapshots are unstable and both backend and platform dependent. Changing any of these might fail the test.
///
/// All snapshot tests can be ignored (without skipping the whole test) by setting the environment variable `rui_SNAPSHOT_IGNORE`
///
/// Set the environment variable `rui_SNAPSHOT_WRITE` to create/overwrite the snapshot files
///
/// rui does not clear out old or unused snapshot files. To clean the snapshot directory follow these steps:
/// 1. Ensure all snapshot test pass
/// 2. Delete the snapshot directory
/// 3. Run all snapshot tests with `rui_SNAPSHOT_WRITE` set to recreate only the used files
pub fn snapshot(self: *Self, src: std.builtin.SourceLocation, frame: rui.App.frameFunction) !void {
    if (should_ignore_snapshots()) return;

    defer self.snapshot_index += 1;
    const filename = try std.fmt.allocPrint(self.allocator, "{s}-{s}-{d}" ++ png_extension, .{ src.file, src.fn_name, self.snapshot_index });
    defer self.allocator.free(filename);
    // NOTE: do fs operation through cwd to handle relative and absolute paths
    var dir = std.fs.cwd().openDir(self.snapshot_dir, .{}) catch |err| switch (err) {
        error.FileNotFound => {
            std.debug.print("{s}:{d}:{d}: Snapshot directory did not exist! Run the test with rui_SNAPSHOT_WRITE to create all snapshot files\n", .{ src.file, src.line, src.column });
            return error.SkipZigTest; // FIXME: Test should fail with missing snapshots, but we don't want to commit snapshots while they are unstable, so skip tests instead
        },
        else => return err,
    };
    defer dir.close();

    const png_data = try self.capturePng(frame, null);
    defer self.allocator.free(png_data);

    const file = dir.openFile(filename, .{}) catch |err| switch (err) {
        std.fs.File.OpenError.FileNotFound => {
            if (should_write_snapshots()) {
                try dir.writeFile(.{ .sub_path = filename, .data = png_data, .flags = .{} });
                std.debug.print("Snapshot: Created file \"{s}\"\n", .{filename});
                return;
            }
            std.debug.print("{s}:{d}:{d}: Snapshot file did not exist! Run the test with `rui_SNAPSHOT_WRITE` to create all snapshot files\n", .{ src.file, src.line, src.column });
            return error.SkipZigTest; // FIXME: Test should fail with missing snapshots, but we don't want to commit snapshots while they are unstable, so skip tests instead
        },
        else => return err,
    };
    const prev_hash = try hash_png(file.reader().any());
    file.close();

    var png_reader = std.io.fixedBufferStream(png_data);
    const new_hash = try hash_png(png_reader.reader().any());

    if (prev_hash != new_hash) {
        if (should_write_snapshots()) {
            try dir.writeFile(.{ .sub_path = filename, .data = png_data, .flags = .{} });
            std.debug.print("Snapshot: Overwrote file \"{s}\"\n", .{filename});
            return;
        }
        const failed_filename = try std.fmt.allocPrint(self.allocator, "{s}-failed" ++ png_extension, .{filename[0 .. filename.len - png_extension.len]});
        defer self.allocator.free(failed_filename);
        try dir.writeFile(.{ .sub_path = failed_filename, .data = png_data, .flags = .{} });

        std.debug.print("Snapshot did not match! See the \"{s}\" for the current output", .{failed_filename});

        return SnapshotError.SnapshotsDidNotMatch;
    }
}

fn hash_png(png_reader: std.io.AnyReader) !u32 {
    var hasher = rui.fnv.init();

    var read_buf: [1024 * 4]u8 = undefined;
    var len: usize = read_buf.len;
    // len < read_buf indicates the end of the data
    while (len == read_buf.len) {
        len = try png_reader.readAll(&read_buf);
        hasher.update(read_buf[0..len]);
    }
    return hasher.final();
}

fn should_ignore_snapshots() bool {
    return Backend.kind == .testing or std.process.hasEnvVarConstant("rui_SNAPSHOT_IGNORE");
}

fn should_write_snapshots() bool {
    return !should_ignore_snapshots() and std.process.hasEnvVarConstant("rui_SNAPSHOT_WRITE");
}

/// If image_dir is not null, run a single frame, capture the physical pixels
/// in rect, and write those as a png file to image_dir/filename_fmt.
///
/// If rect is null, capture the whole OS window.
///
/// The intended use is for automatically generating documentation images.
pub fn saveImage(self: *Self, frame: rui.App.frameFunction, rect: ?rui.Rect, comptime filename_fmt: []const u8, fmt_args: anytype) !void {
    if (self.doc_image_dir) |img_dir| {
        const filename = try std.fmt.allocPrint(self.allocator, "{s}/" ++ filename_fmt, .{img_dir} ++ fmt_args);
        std.debug.print("FILENAME: {s}\n", .{filename});
        defer self.allocator.free(filename);

        const png_data = try self.capturePng(frame, rect);
        defer self.allocator.free(png_data);

        try std.fs.cwd().writeFile(.{
            .data = png_data,
            .sub_path = filename,
            .flags = .{},
        });
    }
}

/// Internal use only!
///
/// Generates and saves images for documentation. The test name is required to end with `.png` and are format strings evaluated at comptime.
pub fn saveDocImage(self: *Self, comptime src: std.builtin.SourceLocation, comptime format_args: anytype, frame: rui.App.frameFunction) !void {
    if (!std.mem.endsWith(u8, src.fn_name, png_extension)) {
        return error.SaveDocImageRequiresPNGExtensionInTestName;
    }

    if (!is_rui_doc_gen) {
        // Do nothing if we are not running with the doc_gen test runner.
        // This means that the rest of the test is still performed and used as a normal rui test.
        return;
    }

    const test_prefix = "test.";
    const filename = std.fmt.comptimePrint(src.fn_name[test_prefix.len..], format_args);

    const png_data = try self.capturePng(frame, null);
    defer self.allocator.free(png_data);

    @import("root").rui_image_doc_gen_dir.writeFile(.{
        .data = png_data,
        .sub_path = filename,
        // set exclusive flag to error if two test generate an image with the same name
        .flags = .{ .exclusive = true },
    }) catch |err| {
        if (err == std.fs.File.OpenError.PathAlreadyExists) {
            std.debug.print("Error generating doc image: duplicated test name '{s}'\n", .{filename});
            return error.DuplicateDocImageName;
        } else {
            return err;
        }
    };
}

/// Used internally for documentation generation
pub const is_rui_doc_gen = @hasDecl(@import("root"), "rui_image_doc_gen_dir");

const Self = @This();

const std = @import("std");
const rui = @import("rui.zig");

const Backend = rui.backend;
const Window = rui.Window;

test {
    @import("std").testing.refAllDecls(@This());
}
