const std = @import("std");

/// The roc-wasm4 platform ships a single wasm32-freestanding host object.
/// The Roc compiler links `host.wasm` with the generated app object to produce
/// the final WASM-4 cart (a wasm32 module).
///
/// The cart-level wasm settings (import_memory, initial_memory, max_memory, stack_size,
/// rdynamic exports, entry = .disabled, etc.) are properties of the final wasm module
/// produced by the Roc linker - they are NOT settable on a static library. The Roc
/// compiler handles those when it produces the final `.wasm` output.
pub fn build(b: *std.Build) void {
    const optimize = b.standardOptimizeOption(.{});

    // ---------------------------------------------------------------------
    // Build options exposed as the `config` module to allocator.zig / host.zig.
    // ---------------------------------------------------------------------

    // Full mem size on WASM-4 is 58976, but we have to leave room for code + constants.
    // Was u16 in the old build; widened to u32 for headroom.
    const mem_size = b.option(
        u32,
        "mem-size",
        "the amount of space reserved for dynamic memory allocation",
    ) orelse 40960;

    // Enable this if you hit any sort of memory corruption. Costs performance.
    const zero_on_alloc = b.option(
        bool,
        "zero-on-alloc",
        "zeros all newly allocated memory",
    ) orelse false;

    const trace_allocs = b.option(
        bool,
        "trace-allocs",
        "debug print on every allocation and deallocation",
    ) orelse false;

    const config = b.addOptions();
    config.addOption(u32, "mem_size", mem_size);
    config.addOption(bool, "zero_on_alloc", zero_on_alloc);
    config.addOption(bool, "trace_allocs", trace_allocs);

    // ---------------------------------------------------------------------
    // Cleanup step.
    // ---------------------------------------------------------------------
    const cleanup_step = b.step("clean", "Remove generated host object files");
    cleanup_step.dependOn(&CleanupStep.create(
        b,
        b.path("platform/targets/wasm32/host.wasm"),
    ).step);
    cleanup_step.dependOn(&CleanupStep.create(
        b,
        b.path("platform/targets/wasm32/libhost.a"),
    ).step);

    // ---------------------------------------------------------------------
    // Build the wasm32-freestanding relocatable host object.
    // ---------------------------------------------------------------------
    const wasm_target = b.resolveTargetQuery(.{
        .cpu_arch = .wasm32,
        .os_tag = .freestanding,
        .abi = .none,
    });

    const host_obj = b.addObject(.{
        .name = "host",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/host.zig"),
            .target = wasm_target,
            .optimize = optimize,
            .strip = optimize != .Debug,
            .pic = true,
        }),
    });
    // Expose build options as the `config` module to the host source.
    host_obj.root_module.addOptions("config", config);

    // ---------------------------------------------------------------------
    // Tests.
    // ---------------------------------------------------------------------
    const native_target = b.standardTargetOptions(.{});
    const allocator_tests = b.addTest(.{
        .name = "allocator_test",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/allocator.zig"),
            .target = native_target,
            .optimize = optimize,
        }),
    });
    allocator_tests.root_module.addOptions("config", config);

    const run_allocator_tests = b.addRunArtifact(allocator_tests);
    const test_step = b.step("test", "Run Zig unit tests");
    test_step.dependOn(&run_allocator_tests.step);

    // ---------------------------------------------------------------------
    // Copy the emitted host.wasm to platform/targets/wasm32/host.wasm so that
    // `roc bundle` (via bundle.sh) can pick it up.
    // ---------------------------------------------------------------------
    const copy_step = b.addUpdateSourceFiles();
    copy_step.addCopyFileToSource(
        host_obj.getEmittedBin(),
        "platform/targets/wasm32/host.wasm",
    );

    const install_step = b.getInstallStep();
    install_step.dependOn(&copy_step.step);
}

/// Custom step to remove a single file if it exists.
const CleanupStep = struct {
    step: std.Build.Step,
    path: std.Build.LazyPath,

    fn create(b: *std.Build, path: std.Build.LazyPath) *CleanupStep {
        const self = b.allocator.create(CleanupStep) catch @panic("OOM");
        self.* = .{
            .step = std.Build.Step.init(.{
                .id = .custom,
                .name = "cleanup",
                .owner = b,
                .makeFn = make,
            }),
            .path = path,
        };
        return self;
    }

    fn make(step: *std.Build.Step, options: std.Build.Step.MakeOptions) !void {
        _ = options;
        const self: *CleanupStep = @fieldParentPtr("step", step);
        const path = self.path.getPath2(step.owner, null);
        std.Io.Dir.cwd().deleteFile(step.owner.graph.io, path) catch |err| switch (err) {
            error.FileNotFound => {}, // Already gone, that's fine
            else => return err,
        };
    }
};
