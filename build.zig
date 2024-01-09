const std = @import("std");

pub fn build(b: *std.Build) !void {
    const optimize = b.standardOptimizeOption(.{});
    const roc_src = b.option([]const u8, "app", "the roc application to build");

    const roc_check = b.addSystemCommand(&[_][]const u8{ "roc", "check" });
    const roc_lib = b.addSystemCommand(&[_][]const u8{ "roc", "build", "--target=wasm32", "--no-link", "--output", "zig-cache/app.o" });
    // By setting this to true, we ensure zig always rebuilds the roc app since it can't tell if any transitive dependencies have changed.
    roc_check.has_side_effects = true;
    roc_lib.has_side_effects = true;

    if (roc_src) |val| {
        roc_lib.addFileArg(.{ .path = val });
        roc_check.addFileArg(.{ .path = val });
    } else {
        const default_path = "examples/snake.roc";
        roc_lib.addFileArg(.{ .path = default_path });
        roc_check.addFileArg(.{ .path = default_path });
    }

    switch (optimize) {
        .ReleaseFast, .ReleaseSafe => {
            roc_lib.addArg("--optimize");
        },
        .ReleaseSmall => {
            roc_lib.addArg("--opt-size");
        },
        else => {},
    }

    // Run roc check before building
    roc_lib.step.dependOn(&roc_check.step);

    // TODO: change to addExecutable with entry disabled when we update to zig 0.12.0.
    const lib = b.addSharedLibrary(.{
        .name = "cart",
        .root_source_file = .{ .path = "platform/host.zig" },
        .target = .{ .cpu_arch = .wasm32, .os_tag = .freestanding },
        .optimize = optimize,
    });

    lib.import_memory = true;
    lib.initial_memory = 65536;
    lib.max_memory = 65536;
    lib.stack_size = 14752;

    // Export WASM-4 symbols
    lib.export_symbol_names = &[_][]const u8{ "start", "update" };

    lib.step.dependOn(&roc_lib.step);
    lib.addObjectFile(.{ .path = "zig-cache/app.o" });

    b.installArtifact(lib);

    const w4 = b.addSystemCommand(&[_][]const u8{ "w4", "run" });
    w4.addArtifactArg(lib);

    const run = b.step("run", "compile and run the game in the browsers");
    run.dependOn(&w4.step);

    const w4_native = b.addSystemCommand(&[_][]const u8{ "w4", "run-native" });
    w4_native.addArtifactArg(lib);

    const run_native = b.step("run-native", "compile and run the game in a native app");
    run_native.dependOn(&w4_native.step);
}
