const std = @import("std");
const enums = @import("src/enums.zig");
const Pkg = std.Build.Pkg;
const Compile = std.Build.Step.Compile;

// NOTE: Keep in-sync with raylib's definition
pub const LinuxDisplayBackend = enum {
    X11,
    Wayland,
    Both,
};

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const back_to_build: ?enums.Backend = b.option(enums.Backend, "backend", "Backend to build");

    const test_step = b.step("test", "Test the rui codebase");
    const check_step = b.step("check", "Check that the rui codebase compiles");

    // Setting this to false may fix linking errors
    const use_lld = b.option(bool, "use-lld", "The value of the use_lld executable option");
    const test_filters = b.option([]const []const u8, "test-filter", "Skip tests that do not match any filter") orelse &[0][]const u8{};

    const build_options = b.addOptions();

    const rui_opts = RuiModuleOptions{
        .b = b,
        .target = target,
        .optimize = optimize,
        .test_step = test_step,
        .test_filters = test_filters,
        .check_step = check_step,
        .use_lld = use_lld,
        .build_options = build_options,
    };

    if (back_to_build == .custom) {
        // For export to users who are bringing their own backend.  Use in your build.zig:
        // const rui_mod = rui_dep.module("rui");
        // @import("rui").linkBackend(rui_mod, your_backend_module);
        const rui_mod = addRuiModule("rui", rui_opts);
        rui_opts.addChecksAndTests(rui_mod, "rui");
    }

    // Dx11
    if (back_to_build == null or back_to_build == .dx11) {
        const test_rui_and_app = back_to_build == .dx11;

        if (target.result.os.tag == .windows) {
            const dx11_mod = b.addModule("dx11", .{
                .root_source_file = b.path("src/backends/dx11.zig"),
                .target = target,
                .optimize = optimize,
                .link_libc = true,
            });
            rui_opts.addChecksAndTests(dx11_mod, "dx11-backend");

            if (b.lazyDependency("win32", .{})) |zigwin32| {
                dx11_mod.addImport("win32", zigwin32.module("win32"));
            }

            const rui_dx11 = addRuiModule("rui_dx11", rui_opts);
            if (test_rui_and_app) {
                rui_opts.addChecksAndTests(rui_dx11, "rui_dx11");
            }

            linkBackend(rui_dx11, dx11_mod);
        }
    }

    // Web
    if (back_to_build == null or back_to_build == .web) {
        const test_rui_and_app = back_to_build == .web;

        const export_symbol_names = &[_][]const u8{
            "rui_init",
            "rui_deinit",
            "rui_update",
            "add_event",
            "arena_u8",
            "gpa_u8",
            "gpa_free",
            "new_font",
        };

        const web_mod = b.addModule("web", .{
            .root_source_file = b.path("src/backends/web.zig"),
            .target = target,
            .optimize = optimize,
        });
        web_mod.export_symbol_names = export_symbol_names;

        if (test_rui_and_app) {
            rui_opts.addChecksAndTests(web_mod, "web-backend");
        }

        // NOTE: exported module uses the standard target so it can be overridden by users
        const rui_web = addRuiModule("rui_web", rui_opts);
        // don't add tests here, we test the web backend below in rui_web_wasm

        linkBackend(rui_web, web_mod);
    }
}

pub fn linkBackend(rui_mod: *std.Build.Module, backend_mod: *std.Build.Module) void {
    backend_mod.addImport("rui", rui_mod);
    rui_mod.addImport("backend", backend_mod);
}

const RuiModuleOptions = struct {
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    check_step: ?*std.Build.Step = null,
    test_step: ?*std.Build.Step = null,
    test_filters: []const []const u8,
    add_stb_image: bool = true,
    use_lld: ?bool = null,
    build_options: *std.Build.Step.Options,

    fn addChecksAndTests(self: *const @This(), mod: *std.Build.Module, name: []const u8) void {
        if (self.check_step) |step| {
            const tests = self.b.addTest(.{ .root_module = mod, .name = name, .filters = self.test_filters });
            step.dependOn(&tests.step);
        }
        if (self.test_step) |step| {
            const tests = self.b.addTest(.{ .root_module = mod, .name = name, .filters = self.test_filters });
            step.dependOn(&self.b.addRunArtifact(tests).step);
        }
    }
};

fn addRuiModule(
    comptime name: []const u8,
    opts: RuiModuleOptions,
) *std.Build.Module {
    const b = opts.b;
    const target = opts.target;
    const optimize = opts.optimize;

    const rui_mod = b.addModule(name, .{
        .root_source_file = b.path("src/rui.zig"),
        .target = target,
        .optimize = optimize,
    });
    rui_mod.addOptions("build_options", opts.build_options);

    if (target.result.os.tag == .windows) {
        // tinyfiledialogs needs this
        rui_mod.linkSystemLibrary("comdlg32", .{});
        rui_mod.linkSystemLibrary("ole32", .{});
    }

    rui_mod.addIncludePath(b.path("src/stb"));

    if (target.result.cpu.arch == .wasm32) {
        rui_mod.addCSourceFiles(.{
            .files = &.{
                "src/stb/stb_image_impl.c",
                "src/stb/stb_image_write_impl.c",
                "src/stb/stb_truetype_impl.c",
            },
            .flags = &.{ "-DINCLUDE_CUSTOM_LIBC_FUNCS=1", "-DSTBI_NO_STDLIB=1", "-DSTBIW_NO_STDLIB=1" },
        });
    } else {
        if (opts.add_stb_image) {
            rui_mod.addCSourceFiles(.{ .files = &.{
                "src/stb/stb_image_impl.c",
                "src/stb/stb_image_write_impl.c",
            } });
        }
        rui_mod.addCSourceFiles(.{ .files = &.{"src/stb/stb_truetype_impl.c"} });

        rui_mod.addIncludePath(b.path("src/tfd"));
        rui_mod.addCSourceFiles(.{ .files = &.{"src/tfd/tinyfiledialogs.c"} });

        if (b.systemIntegrationOption("freetype", .{})) {
            rui_mod.linkSystemLibrary("freetype2", .{});
        } else {
            const freetype_dep = b.lazyDependency("freetype", .{
                .target = target,
                .optimize = optimize,
            });
            if (freetype_dep) |fd| {
                rui_mod.linkLibrary(fd.artifact("freetype"));
            }
        }
    }

    return rui_mod;
}
