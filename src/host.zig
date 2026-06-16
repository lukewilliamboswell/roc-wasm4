//! WASM-4 platform host for Roc, using the new (Zig-ABI) Roc runtime.
//!
//! This file wires the WASM-4 fantasy-console runtime to a Roc app. It:
//!   * Exports `start()` and `update()` for the WASM-4 runtime.
//!   * Builds a `std.mem.Allocator` backed by `umm_malloc` (see allocator.zig).
//!   * Exports the direct Roc runtime and hosted-function symbols.
//!   * Holds the boxed Roc model in a global so it persists across update calls.
//!
//! See `roc_platform_abi.zig` for the ABI shape and ownership rules:
//! refcounted hosted-fn arguments (RocStr, RocList) are owned by the hosted fn
//! and must be `decref`'d before returning.

const std = @import("std");

// `config` (mem_size, zero_on_alloc, trace_allocs) is consumed transitively by
// `allocator.zig`. We don't reference it directly here, but it must be a
// build-time module — see build.zig.
const abi = @import("roc_platform_abi.zig");
const allocator = @import("allocator.zig");
const w4 = @import("wasm4.zig");

// =============================================================================
// std.mem.Allocator wrapper around umm_malloc
//
// `DefaultAllocators` (in roc_platform_abi.zig) drives Roc's allocations
// through a `std.mem.Allocator` and stores its own size metadata in a header
// before the user pointer. We just need the vtable contract:
//   - alloc(len, alignment): return a pointer or null
//   - resize(): return false (umm_malloc has no in-place resize API; the Roc
//     runtime falls back to remap/alloc+copy+free)
//   - remap(): use realloc — umm_malloc copies internally if it has to move
//   - free(memory): drop it
//
// umm_malloc itself ignores alignment beyond 4 bytes. The Roc runtime requests
// at most pointer-width alignment for refcounted allocations, which umm_malloc
// satisfies because its blocks are 4-byte aligned and on wasm32 usize is 4.
// =============================================================================

const ummAllocator = std.mem.Allocator{
    .ptr = undefined, // umm_malloc has no per-instance state
    .vtable = &umm_vtable,
};

const umm_vtable: std.mem.Allocator.VTable = .{
    .alloc = ummAlloc,
    .resize = ummResize,
    .remap = ummRemap,
    .free = ummFree,
};

fn ummAlloc(_: *anyopaque, len: usize, _: std.mem.Alignment, _: usize) ?[*]u8 {
    if (len == 0) return null;
    const maybe_ptr = allocator.malloc(len) catch return null;
    const ptr = maybe_ptr orelse return null;
    return @ptrCast(@alignCast(ptr));
}

fn ummResize(_: *anyopaque, _: []u8, _: std.mem.Alignment, _: usize, _: usize) bool {
    // umm_malloc has no "resize in place without potentially moving" API.
    // Return false so callers fall back to remap.
    return false;
}

fn ummRemap(_: *anyopaque, memory: []u8, _: std.mem.Alignment, new_len: usize, _: usize) ?[*]u8 {
    if (new_len == 0) return null;
    const maybe_ptr = allocator.realloc(@ptrCast(memory.ptr), new_len) catch return null;
    const new_ptr = maybe_ptr orelse return null;
    return @ptrCast(@alignCast(new_ptr));
}

fn ummFree(_: *anyopaque, memory: []u8, _: std.mem.Alignment, _: usize) void {
    allocator.free(@ptrCast(memory.ptr)) catch {
        w4.trace("roc_dealloc: pointer was not in the umm_malloc heap range");
    };
}

// =============================================================================
// Panic handler for wasm32-freestanding
//
// The default zig panic handler tries to capture a stack trace and print it,
// which requires APIs not available on wasm32-freestanding. We replace it with
// a trace + trap.
// =============================================================================

pub const panic = std.debug.FullPanic(wasm4Panic);

fn wasm4Panic(message: []const u8, _: ?usize) noreturn {
    w4.trace("ROC PANIC:");
    w4.trace(message);
    @trap();
}

// =============================================================================
// RocIo backend — route Roc stderr through w4.trace, fatal trap.
// =============================================================================

fn w4WriteStderr(_: ?*anyopaque, data: []const u8) void {
    w4.trace(data);
}

fn w4OnFatal(_: ?*anyopaque) noreturn {
    @trap();
}

const w4_roc_io_vtable: abi.RocIo.VTable = .{
    .writeStderr = &w4WriteStderr,
    .onFatal = &w4OnFatal,
};

fn makeW4RocIo() abi.RocIo {
    return .{ .ctx = null, .vtable = &w4_roc_io_vtable };
}

// =============================================================================
// Stack canary
//
// The canary sits right after the framebuffer; the wasm32 stack grows down and
// will overwrite the framebuffer if it overflows. We zero/refill the canary
// before each `update()` and verify it after.
// =============================================================================

const CANARY_PTR: [*]usize = @ptrFromInt(@intFromPtr(w4.FRAMEBUFFER) + w4.FRAMEBUFFER.len);
const CANARY_SIZE: usize = 8;

fn resetStackCanary() void {
    var i: usize = 0;
    while (i < CANARY_SIZE) : (i += 1) {
        CANARY_PTR[i] = 0xDEAD_BEAF;
    }
}

fn checkStackCanary() void {
    var i: usize = 0;
    while (i < CANARY_SIZE) : (i += 1) {
        if (CANARY_PTR[i] != 0xDEAD_BEAF) {
            w4.trace("Warning: Stack canary damaged! There was likely a stack overflow during roc execution. Overflows write into the screen buffer and other hardware registers.");
            return;
        }
    }
}

// =============================================================================
// Globals: Roc model and runtime state
// =============================================================================

var env: abi.RocEnv = undefined;
var roc_host: abi.RocHost = undefined;

// The Roc `Box(Model)` runtime representation is an opaque pointer. We store it
// between WASM-4 frames.
var boxed_model: abi.RocBox = null;
var boxed_model_initialized: bool = false;

// =============================================================================
// PRNG (used by host_rand / host_rand_range_less_than / host_seed_rand)
// =============================================================================

var prng_state: u32 = 0x6D2B79F5;

fn nextRandomU32() u32 {
    var x = prng_state;
    x ^= x << 13;
    x ^= x >> 17;
    x ^= x << 5;
    prng_state = if (x == 0) 0x6D2B79F5 else x;
    return prng_state;
}

// =============================================================================
// Runtime symbols
//
// Compiled Roc code calls these linker symbols directly. The generated helpers
// use `roc_host` to route them through the WASM-4 allocator and diagnostics.
// =============================================================================

export fn roc_alloc(length: usize, alignment: usize) callconv(.c) ?*anyopaque {
    return abi.DefaultAllocators.rocAlloc(&roc_host, length, alignment);
}

export fn roc_dealloc(ptr: *anyopaque, alignment: usize) callconv(.c) void {
    abi.DefaultAllocators.rocDealloc(&roc_host, ptr, alignment);
}

export fn roc_realloc(ptr: *anyopaque, new_length: usize, alignment: usize) callconv(.c) ?*anyopaque {
    return abi.DefaultAllocators.rocRealloc(&roc_host, ptr, new_length, alignment);
}

export fn roc_dbg(bytes: [*]const u8, len: usize) callconv(.c) void {
    abi.DefaultHandlers.rocDbg(&roc_host, bytes, len);
}

export fn roc_expect_failed(bytes: [*]const u8, len: usize) callconv(.c) void {
    abi.DefaultHandlers.rocExpectFailed(&roc_host, bytes, len);
}

export fn roc_crashed(bytes: [*]const u8, len: usize) callconv(.c) void {
    abi.DefaultHandlers.rocCrashed(&roc_host, bytes, len);
}

// =============================================================================
// Hosted function symbols
//
// These exported symbols correspond to the `hosted` entries in platform/main.roc.
// Refcounted args (RocStr, RocList) are owned by the host and must be decref'd.
// =============================================================================

export fn host_blit(arg0: abi.RocListWith(u8, false), arg1: i32, arg2: i32, arg3: u32, arg4: u32, arg5: u32) callconv(.c) void {
    if (arg0.elements_ptr) |sprite_ptr| {
        w4.blit(sprite_ptr, arg1, arg2, arg3, arg4, arg5);
    }
    arg0.decref(&roc_host);
}

export fn host_blit_sub(arg0: abi.RocListWith(u8, false), arg1: i32, arg2: i32, arg3: u32, arg4: u32, arg5: u32, arg6: u32, arg7: u32, arg8: u32) callconv(.c) void {
    if (arg0.elements_ptr) |sprite_ptr| {
        w4.blitSub(sprite_ptr, arg1, arg2, arg3, arg4, arg5, arg6, arg7, arg8);
    }
    arg0.decref(&roc_host);
}

const MAX_DISK_SIZE: u32 = 1024;

export fn host_disk_read() callconv(.c) abi.RocListWith(u8, false) {
    var out = abi.RocListWith(u8, false).allocate(MAX_DISK_SIZE, &roc_host);
    if (out.elements_ptr) |ptr| {
        const got = w4.diskr(ptr, MAX_DISK_SIZE);
        out.length = got;
    } else {
        out.length = 0;
    }
    return out;
}

export fn host_disk_write(arg0: abi.RocListWith(u8, false)) callconv(.c) bool {
    defer arg0.decref(&roc_host);

    const len = arg0.length;
    if (len > MAX_DISK_SIZE) return false;
    if (arg0.elements_ptr) |ptr| {
        const written = w4.diskw(ptr, @intCast(len));
        return written == len;
    }
    return true;
}

export fn host_get_draw_colors() callconv(.c) u16 {
    return w4.DRAW_COLORS.*;
}

export fn host_get_gamepad(arg0: u8) callconv(.c) u8 {
    return switch (arg0) {
        1 => w4.GAMEPAD1.*,
        2 => w4.GAMEPAD2.*,
        3 => w4.GAMEPAD3.*,
        4 => w4.GAMEPAD4.*,
        else => 0,
    };
}

export fn host_get_mouse_buttons() callconv(.c) u8 {
    return w4.MOUSE_BUTTONS.*;
}

export fn host_get_mouse_x() callconv(.c) i16 {
    return w4.MOUSE_X.*;
}

export fn host_get_mouse_y() callconv(.c) i16 {
    return w4.MOUSE_Y.*;
}

export fn host_get_netplay() callconv(.c) u8 {
    return w4.NETPLAY.*;
}

export fn host_get_palette_color(arg0: u8) callconv(.c) u32 {
    // Palette has 4 colors; clamp/ignore out-of-range indices.
    if (arg0 < 4) return w4.PALETTE[arg0];
    return 0;
}

export fn host_get_pixel(arg0: u8, arg1: u8) callconv(.c) u8 {
    const x = arg0;
    const y = arg1;
    if (x >= w4.SCREEN_SIZE or y >= w4.SCREEN_SIZE) {
        return 0;
    }
    const idx = (w4.SCREEN_SIZE * @as(u32, y) + @as(u32, x)) >> 2;
    const shift: u3 = @intCast((x & 0x3) << 1);
    const mask = @as(u8, 0x3) << shift;
    const stroke_color = (w4.FRAMEBUFFER[idx] & mask) >> shift;
    return stroke_color + 1;
}

export fn host_hline(arg0: i32, arg1: i32, arg2: u32) callconv(.c) void {
    w4.hline(arg0, arg1, arg2);
}

export fn host_line(arg0: i32, arg1: i32, arg2: i32, arg3: i32) callconv(.c) void {
    w4.line(arg0, arg1, arg2, arg3);
}

export fn host_oval(arg0: i32, arg1: i32, arg2: u32, arg3: u32) callconv(.c) void {
    w4.oval(arg0, arg1, arg2, arg3);
}

export fn host_rand() callconv(.c) i32 {
    return @bitCast(nextRandomU32());
}

export fn host_rand_range_less_than(arg0: i32, arg1: i32) callconv(.c) i32 {
    if (arg0 >= arg1) {
        // Invalid range — return the minimum to avoid panicking the cartridge.
        return arg0;
    }
    const min: i64 = arg0;
    const max: i64 = arg1;
    const span: u32 = @intCast(max - min);
    const offset: i64 = nextRandomU32() % span;
    return @intCast(min + offset);
}

export fn host_rect(arg0: i32, arg1: i32, arg2: u32, arg3: u32) callconv(.c) void {
    w4.rect(arg0, arg1, arg2, arg3);
}

export fn host_seed_rand(arg0: u64) callconv(.c) void {
    const seed: u32 = @truncate(arg0);
    prng_state = if (seed == 0) 0x6D2B79F5 else seed;
}

export fn host_set_draw_colors(arg0: u16) callconv(.c) void {
    w4.DRAW_COLORS.* = arg0;
}

export fn host_set_hide_gamepad_overlay(arg0: bool) callconv(.c) void {
    if (arg0) {
        w4.SYSTEM_FLAGS.* |= w4.SYSTEM_HIDE_GAMEPAD_OVERLAY;
    } else {
        w4.SYSTEM_FLAGS.* &= ~w4.SYSTEM_HIDE_GAMEPAD_OVERLAY;
    }
}

export fn host_set_palette(arg0: u32, arg1: u32, arg2: u32, arg3: u32) callconv(.c) void {
    w4.PALETTE.* = .{ arg0, arg1, arg2, arg3 };
}

export fn host_set_pixel(arg0: u8, arg1: u8, arg2: u8) callconv(.c) void {
    const x = arg0;
    const y = arg1;
    const draw_color = arg2;
    if (x < w4.SCREEN_SIZE and y < w4.SCREEN_SIZE and draw_color != 0) {
        const stroke_color = (draw_color - 1) & 0x3;
        const idx = (w4.SCREEN_SIZE * @as(u32, y) + @as(u32, x)) >> 2;
        const shift: u3 = @intCast((x & 0x3) << 1);
        const mask = @as(u8, 0x3) << shift;
        w4.FRAMEBUFFER[idx] = (stroke_color << shift) | (w4.FRAMEBUFFER[idx] & ~mask);
    }
}

export fn host_set_preserve_frame_buffer(arg0: bool) callconv(.c) void {
    if (arg0) {
        w4.SYSTEM_FLAGS.* |= w4.SYSTEM_PRESERVE_FRAMEBUFFER;
    } else {
        w4.SYSTEM_FLAGS.* &= ~w4.SYSTEM_PRESERVE_FRAMEBUFFER;
    }
}

export fn host_text(arg0: abi.RocStr, arg1: i32, arg2: i32) callconv(.c) void {
    w4.text(arg0.asSlice(), arg1, arg2);
    arg0.decref(&roc_host);
}

export fn host_tone(arg0: u32, arg1: u32, arg2: u16, arg3: u8) callconv(.c) void {
    w4.tone(arg0, arg1, arg2, arg3);
}

export fn host_trace(arg0: abi.RocStr) callconv(.c) void {
    w4.trace(arg0.asSlice());
    arg0.decref(&roc_host);
}

export fn host_vline(arg0: i32, arg1: i32, arg2: u32) callconv(.c) void {
    w4.vline(arg0, arg1, arg2);
}

// =============================================================================
// Lifecycle: start() and update()
//
// WASM-4 imports these from the cart. `start` runs once at boot; `update`
// runs at 60Hz. The Roc model is stored as a boxed pointer between calls.
// =============================================================================

export fn start() void {
    allocator.init();

    env = .{
        .allocator = ummAllocator,
        .roc_io = makeW4RocIo(),
    };
    roc_host = abi.makeRocHost(&env);

    boxed_model = abi.init_for_host();
    boxed_model_initialized = true;
}

export fn update() void {
    resetStackCanary();

    if (!boxed_model_initialized) {
        w4.trace("update() called before start() initialized the model");
        @trap();
    }

    boxed_model = abi.update_for_host(boxed_model);

    checkStackCanary();
}
