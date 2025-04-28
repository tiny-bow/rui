//! For apps that want rui to provide the mainloop which runs these callbacks.
//!
//! In your root file, have a declaration named "rui_app" of this type:
//! ```
//! pub const rui_app: rui.App = .{ .initFn = AppInit, ...};
//! ```
//!
//! Also must use the App's main, panic and log functions:
//! ```
//! pub const main = rui.App.main;
//! pub const panic = rui.App.panic;
//! pub const std_options: std.Options = .{
//!     .logFn = rui.App.logFn,
//! };
//! ```

pub const App = @This();

/// The configuration options for the app, either directly or a function that
/// is run at startup that returns the options.
config: AppConfig,
/// Runs before the first frame, allowing for configuring the Window.  Window
/// and Backend have run init() already.
initFn: ?fn (*rui.Window) void = null,
/// Runs when the app is exiting, before Window.deinit().
deinitFn: ?fn () void = null,
/// Runs once every frame between `Window.begin` and `Window.end`
///
/// Returns whether the app should continue running or close.
frameFn: frameFunction,

pub const frameFunction = fn () anyerror!Result;

fn nop_main() !void {}
/// The root file needs to expose the App main function:
/// ```
/// pub const main = rui.App.main;
/// ```
pub const main: fn () anyerror!void = if (@hasDecl(rui.backend, "main")) rui.backend.main else nop_main;

/// The root file needs to expose the App panic function:
/// ```
/// pub const panic = rui.App.panic;
/// ```
pub const panic = if (@hasDecl(rui.backend, "panic")) rui.backend.panic else std.debug.FullPanic(std.debug.defaultPanic);

/// Some backends, like web, cannot use stdout and has a custom logFn to be used.
/// rui apps should always prefer to use std.log over stdout to work across all backends.
///
/// The root file needs to use the App logFn function:
/// ```
/// pub const std_options: std.Options = .{
///     .logFn = rui.App.logFn,
/// };
/// ```
pub const logFn: @FieldType(std.Options, "logFn") = if (@hasDecl(rui.backend, "logFn")) rui.backend.logFn else std.log.defaultLog;

pub const AppConfig = union(enum) {
    options: StartOptions,
    /// Runs before anything else. Can be used to programmatically create the `StartOptions`
    startFn: fn () StartOptions,

    pub fn get(self: AppConfig) StartOptions {
        switch (self) {
            .options => |opts| return opts,
            .startFn => |startFn| return startFn(),
        }
    }
};

pub const StartOptions = struct {
    /// The initial size of the application window
    size: rui.Size,
    /// Set the minimum size of the window
    min_size: ?rui.Size = null,
    /// Set the maximum size of the window
    max_size: ?rui.Size = null,
    vsync: bool = true,
    /// The application title to display
    title: [:0]const u8,
    /// content of a PNG image (or any other format stb_image can load)
    /// tip: use @embedFile
    icon: ?[]const u8 = null,
    /// use when running tests
    hidden: bool = false,
};

pub const Result = enum {
    /// App should continue
    ok,
    /// App should close and exit
    close,
};

/// Used internally to get the rui_app if it's defined
pub fn get() ?App {
    const root = @import("root");
    // return error instead of failing compile to allow for reference in tests without rui_app defined
    if (!@hasDecl(root, "rui_app")) return null;

    if (!@hasDecl(root, "main") or @field(root, "main") != main) {
        @compileError(
            \\Using the App interface requires using the App main function
            \\
            \\Add the following line to your root file:
            \\pub const main = rui.App.main;
        );
    }

    return root.rui_app;
}

const std = @import("std");
const rui = @import("rui.zig");

test {
    std.testing.refAllDecls(@This());
}
