const std = @import("std");

pub fn build(b: *std.Build) !void {
    const optimize = b.standardOptimizeOption(.{});
    const roc_src = b.option([]const u8, "app", "the roc application to build");

    // Full mem size is 58976, but we have to limit due to needing space for other data and code.
    // This has to also leave room for all roc code and constants. That makes it hard to tune.
    // Luckily, end users can set this manually when building.
    const mem_size = b.option(u16, "mem-size", "the amount of space reserved for dynamic memory allocation") orelse 40960;

    // Enable this if you hit any sort of memory corruption.
    // It will cost performance.
    const zero_on_alloc = b.option(bool, "zero-on-alloc", "zeros all newly allocated memory") orelse false;
    const trace_alloc = b.option(bool, "trace-alloc", "debug print on every allocation and deallocation") orelse false;

    const build_roc = b.addExecutable(.{
        .name = "build_roc",
        .root_source_file = .{ .path = "build_roc.zig" },
        // Empty means native.
        .target = .{},
        .optimize = .Debug,
    });
    const run_build_roc = b.addRunArtifact(build_roc);
    // By setting this to true, we ensure zig always rebuilds the roc app since it can't tell if any transitive dependencies have changed.
    run_build_roc.stdio = .inherit;
    run_build_roc.has_side_effects = true;

    if (roc_src) |val| {
        run_build_roc.addFileArg(.{ .path = val });
    } else {
        const default_path = "examples/snake.roc";
        run_build_roc.addFileArg(.{ .path = default_path });
    }

    switch (optimize) {
        .ReleaseFast, .ReleaseSafe => {
            run_build_roc.addArg("--optimize");
        },
        .ReleaseSmall => {
            run_build_roc.addArg("--opt-size");
        },
        else => {},
    }

    // TODO: change to addExecutable with entry disabled when we update to zig 0.12.0.
    const lib = b.addSharedLibrary(.{
        .name = "cart",
        .root_source_file = .{ .path = "platform/host.zig" },
        .target = .{ .cpu_arch = .wasm32, .os_tag = .freestanding },
        .optimize = optimize,
    });
    const options = b.addOptions();
    options.addOption(usize, "mem_size", mem_size);
    options.addOption(bool, "zero_on_alloc", zero_on_alloc);
    options.addOption(bool, "trace_alloc", trace_alloc);
    lib.addOptions("config", options);

    lib.import_memory = true;
    lib.initial_memory = 65536;
    lib.max_memory = 65536;
    lib.stack_size = 14752;

    // Export WASM-4 symbols
    lib.export_symbol_names = &[_][]const u8{ "start", "update" };

    lib.step.dependOn(&run_build_roc.step);
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
