const std = @import("std");

pub fn build(b: *std.Build) !void {
    const optimize = b.standardOptimizeOption(.{});
    const roc_src = b.option([]const u8, "app", "the roc application to build");

    const roc_check = b.addSystemCommand(&[_][]const u8{ "roc", "check" });
    const roc_lib = b.addSystemCommand(&[_][]const u8{ "roc", "build", "--target=wasm32", "--no-link" });
    // Note: I don't think this deals with transitive roc dependencies.
    // If a transitive dependency changes, it won't rebuild.
    if (roc_src) |val| {
        roc_lib.addFileArg(.{ .path = val });
        roc_check.addFileArg(.{ .path = val });
    } else {
        roc_lib.addFileArg(.{ .path = "examples/basic.roc" });
        roc_check.addFileArg(.{ .path = "examples/basic.roc" });
    }

    roc_lib.addArg("--output");

    const roc_out = roc_lib.addOutputFileArg("app.o");
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

    const lib = b.addSharedLibrary(.{
        .name = "wasm4",
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

    lib.addObjectFile(roc_out);

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
