const std = @import("std");

pub fn build(b: *std.Build) !void {
    const optimize = b.standardOptimizeOption(.{});
    const roc_src = b.option([]const u8, "app", "the roc application to build");

    const roc_lib = b.addSystemCommand(&[_][]const u8{ "roc", "build", "--target=wasm32", "--no-link" });
    // Note: I don't think this deals with transitive roc dependencies.
    // If a transitive dependency changes, it won't rebuild.
    if (roc_src) |val| {
        roc_lib.addFileArg(.{ .path = val });
    } else {
        roc_lib.addFileArg(.{ .path = "examples/basic.roc" });
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

    const run = b.step("run", "run the file w4 game");
    run.dependOn(&w4.step);
}
