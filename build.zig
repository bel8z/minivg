const std = @import("std");

pub fn build(b: *std.build.Builder) void {
    // Standard target options allows the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    const target = b.standardTargetOptions(.{});

    // Standard optimization options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall. Here we do not
    // set a preferred release mode, allowing the user to decide how to optimize.
    const optimize = b.standardOptimizeOption(.{});

    // Build options
    const console = b.option(bool, "console", "Enable debug console") orelse (optimize == .Debug);
    const build_options = b.addOptions();
    build_options.addOption(bool, "console", console);

    const nvg_path = "deps/nanovg";
    const nvg = b.addModule("nanovg", .{ .source_file = .{ .path = nvg_path ++ "/src/nanovg.zig" } });

    const demo = b.addModule("demo", .{
        .source_file = .{ .path = nvg_path ++ "/examples/demo.zig" },
        .dependencies = &.{.{ .module = nvg, .name = "nanovg" }},
    });
    const perf = b.addModule("perf", .{
        .source_file = .{ .path = nvg_path ++ "/examples/perf.zig" },
        .dependencies = &.{.{ .module = nvg, .name = "nanovg" }},
    });

    const exe = b.addExecutable(.{
        .name = "minivg",
        // In this case the main source file is merely a path, however, in more
        // complicated build scripts, this could be a generated file.
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });

    // This declares intent for the executable to be installed into the
    // standard location when the user invokes the "install" step (the default
    // step when running `zig build`).
    b.installArtifact(exe);

    exe.subsystem = .Windows;
    exe.addOptions("build_options", build_options);
    exe.addModule("nanovg", nvg);
    exe.addModule("demo", demo);
    exe.addModule("perf", perf);
    exe.linkSystemLibrary("opengl32");
    exe.linkLibC();
    exe.addIncludePath(.{ .path = nvg_path ++ "/src" });
    exe.addCSourceFile(.{ .file = .{ .path = nvg_path ++ "/src/fontstash.c" }, .flags = &.{ "-DFONS_NO_STDIO", "-fno-stack-protector" } });
    exe.addCSourceFile(.{ .file = .{ .path = nvg_path ++ "/src/stb_image.c" }, .flags = &.{ "-DSTBI_NO_STDIO", "-fno-stack-protector" } });
    exe.installHeader(nvg_path ++ "/src/fontstash.h", "fontstash.h");
    exe.installHeader(nvg_path ++ "/src/stb_image.h", "stb_image.h");
    exe.installHeader(nvg_path ++ "/src/stb_truetype.h", "stb_truetype.h");
    exe.addIncludePath(.{ .path = nvg_path ++ "/lib/gl2/include" });
    exe.addCSourceFile(.{ .file = .{ .path = nvg_path ++ "/lib/gl2/src/glad.c" }, .flags = &.{} });

    // This *creates* a RunStep in the build graph, to be executed when another
    // step is evaluated that depends on it. The next line below will establish
    // such a dependency.
    const run_cmd = b.addRunArtifact(exe);

    // By making the run step depend on the install step, it will be run from the
    // installation directory rather than directly from within the cache directory.
    // This is not necessary, however, if the application depends on other installed
    // files, this ensures they will be present and in the expected location.
    run_cmd.step.dependOn(b.getInstallStep());

    // This allows the user to pass arguments to the application in the build
    // command itself, like this: `zig build run -- arg1 arg2 etc`
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    // This creates a build step. It will be visible in the `zig build --help` menu,
    // and can be selected like this: `zig build run`
    // This will evaluate the `run` step rather than the default, which is "install".
    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    // Creates a step for unit testing.
    const exe_tests = b.addTest(.{
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });

    // Similar to creating the run step earlier, this exposes a `test` step to
    // the `zig build --help` menu, providing a way for the user to request
    // running the unit tests.
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&exe_tests.step);
}
