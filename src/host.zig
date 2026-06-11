//! WASM-4 platform host for Roc, using the new (Zig-ABI) Roc runtime.
//!
//! This file wires the WASM-4 fantasy-console runtime to a Roc app. It:
//!   * Exports `start()` and `update()` for the WASM-4 runtime.
//!   * Builds a `std.mem.Allocator` backed by `umm_malloc` (see allocator.zig).
//!   * Builds a `RocOps` using `DefaultAllocators` + `DefaultHandlers`, and
//!     populates the 28 hosted-function pointers required by `PlatformHostedFns`.
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
var roc_ops: abi.RocOps = undefined;

// The Roc `Box(Model)` runtime representation is a pointer to the boxed data.
// `roc__init_for_host` / `roc__update_for_host` take the return slot as
// `***anyopaque` — i.e. a pointer to where Roc will write a `**anyopaque`
// (the Box pointer). We store that here between frames.
var boxed_model: **anyopaque = undefined;
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
// Hosted function implementations
//
// Ordered alphabetically to match `PlatformHostedFns`. Each function takes
// (*RocOps, *Ret, *const Args) with C calling convention. Refcounted args
// (RocStr, RocList) are owned by the host and must be decref'd.
// =============================================================================

fn hostBlit(ops: *abi.RocOps, _: *anyopaque, args: *const abi.HostBlitArgs) callconv(.c) void {
    if (args.arg0.elements_ptr) |sprite_ptr| {
        w4.blit(sprite_ptr, args.arg1, args.arg2, args.arg3, args.arg4, args.arg5);
    }
    args.arg0.decref(ops);
}

fn hostBlitSub(ops: *abi.RocOps, _: *anyopaque, args: *const abi.HostBlit_subArgs) callconv(.c) void {
    if (args.arg0.elements_ptr) |sprite_ptr| {
        w4.blitSub(sprite_ptr, args.arg1, args.arg2, args.arg3, args.arg4, args.arg5, args.arg6, args.arg7, args.arg8);
    }
    args.arg0.decref(ops);
}

const MAX_DISK_SIZE: u32 = 1024;

fn hostDiskRead(ops: *abi.RocOps, ret: *abi.RocListWith(u8, false), _: *anyopaque) callconv(.c) void {
    var out = abi.RocListWith(u8, false).allocate(MAX_DISK_SIZE, ops);
    if (out.elements_ptr) |ptr| {
        const got = w4.diskr(ptr, MAX_DISK_SIZE);
        out.length = got;
    } else {
        out.length = 0;
    }
    ret.* = out;
}

fn hostDiskWrite(ops: *abi.RocOps, ret: *bool, args: *const abi.HostDisk_writeArgs) callconv(.c) void {
    const len = args.arg0.length;
    if (len > MAX_DISK_SIZE) {
        ret.* = false;
    } else if (args.arg0.elements_ptr) |ptr| {
        const written = w4.diskw(ptr, @intCast(len));
        ret.* = (written == len);
    } else {
        // Empty list — nothing to write, treat as success.
        ret.* = true;
    }
    args.arg0.decref(ops);
}

fn hostGetDrawColors(_: *abi.RocOps, ret: *u16, _: *anyopaque) callconv(.c) void {
    ret.* = w4.DRAW_COLORS.*;
}

fn hostGetGamepad(_: *abi.RocOps, ret: *u8, args: *const abi.HostGet_gamepadArgs) callconv(.c) void {
    ret.* = switch (args.arg0) {
        1 => w4.GAMEPAD1.*,
        2 => w4.GAMEPAD2.*,
        3 => w4.GAMEPAD3.*,
        4 => w4.GAMEPAD4.*,
        else => 0,
    };
}

fn hostGetMouseButtons(_: *abi.RocOps, ret: *u8, _: *anyopaque) callconv(.c) void {
    ret.* = w4.MOUSE_BUTTONS.*;
}

fn hostGetMouseX(_: *abi.RocOps, ret: *i16, _: *anyopaque) callconv(.c) void {
    ret.* = w4.MOUSE_X.*;
}

fn hostGetMouseY(_: *abi.RocOps, ret: *i16, _: *anyopaque) callconv(.c) void {
    ret.* = w4.MOUSE_Y.*;
}

fn hostGetNetplay(_: *abi.RocOps, ret: *u8, _: *anyopaque) callconv(.c) void {
    ret.* = w4.NETPLAY.*;
}

fn hostGetPaletteColor(_: *abi.RocOps, ret: *u32, args: *const abi.HostGet_palette_colorArgs) callconv(.c) void {
    // Palette has 4 colors; clamp/ignore out-of-range indices.
    if (args.arg0 < 4) {
        ret.* = w4.PALETTE[args.arg0];
    } else {
        ret.* = 0;
    }
}

fn hostGetPixel(_: *abi.RocOps, ret: *u8, args: *const abi.HostGet_pixelArgs) callconv(.c) void {
    const x = args.arg0;
    const y = args.arg1;
    if (x >= w4.SCREEN_SIZE or y >= w4.SCREEN_SIZE) {
        ret.* = 0;
        return;
    }
    const idx = (w4.SCREEN_SIZE * @as(u32, y) + @as(u32, x)) >> 2;
    const shift: u3 = @intCast((x & 0x3) << 1);
    const mask = @as(u8, 0x3) << shift;
    const stroke_color = (w4.FRAMEBUFFER[idx] & mask) >> shift;
    ret.* = stroke_color + 1;
}

fn hostHline(_: *abi.RocOps, _: *anyopaque, args: *const abi.HostHlineArgs) callconv(.c) void {
    w4.hline(args.arg0, args.arg1, args.arg2);
}

fn hostLine(_: *abi.RocOps, _: *anyopaque, args: *const abi.HostLineArgs) callconv(.c) void {
    w4.line(args.arg0, args.arg1, args.arg2, args.arg3);
}

fn hostOval(_: *abi.RocOps, _: *anyopaque, args: *const abi.HostOvalArgs) callconv(.c) void {
    w4.oval(args.arg0, args.arg1, args.arg2, args.arg3);
}

fn hostRand(_: *abi.RocOps, ret: *i32, _: *anyopaque) callconv(.c) void {
    ret.* = @bitCast(nextRandomU32());
}

fn hostRandRangeLessThan(_: *abi.RocOps, ret: *i32, args: *const abi.HostRand_range_less_thanArgs) callconv(.c) void {
    if (args.arg0 >= args.arg1) {
        // Invalid range — return the minimum to avoid panicking the cartridge.
        ret.* = args.arg0;
        return;
    }
    const min: i64 = args.arg0;
    const max: i64 = args.arg1;
    const span: u32 = @intCast(max - min);
    const offset: i64 = nextRandomU32() % span;
    ret.* = @intCast(min + offset);
}

fn hostRect(_: *abi.RocOps, _: *anyopaque, args: *const abi.HostRectArgs) callconv(.c) void {
    w4.rect(args.arg0, args.arg1, args.arg2, args.arg3);
}

fn hostSeedRand(_: *abi.RocOps, _: *anyopaque, args: *const abi.HostSeed_randArgs) callconv(.c) void {
    const seed: u32 = @truncate(args.arg0);
    prng_state = if (seed == 0) 0x6D2B79F5 else seed;
}

fn hostSetDrawColors(_: *abi.RocOps, _: *anyopaque, args: *const abi.HostSet_draw_colorsArgs) callconv(.c) void {
    w4.DRAW_COLORS.* = args.arg0;
}

fn hostSetHideGamepadOverlay(_: *abi.RocOps, _: *anyopaque, args: *const abi.HostSet_hide_gamepad_overlayArgs) callconv(.c) void {
    if (args.arg0) {
        w4.SYSTEM_FLAGS.* |= w4.SYSTEM_HIDE_GAMEPAD_OVERLAY;
    } else {
        w4.SYSTEM_FLAGS.* &= ~w4.SYSTEM_HIDE_GAMEPAD_OVERLAY;
    }
}

fn hostSetPalette(_: *abi.RocOps, _: *anyopaque, args: *const abi.HostSet_paletteArgs) callconv(.c) void {
    w4.PALETTE.* = .{ args.arg0, args.arg1, args.arg2, args.arg3 };
}

fn hostSetPixel(_: *abi.RocOps, _: *anyopaque, args: *const abi.HostSet_pixelArgs) callconv(.c) void {
    const x = args.arg0;
    const y = args.arg1;
    const draw_color = args.arg2;
    if (x < w4.SCREEN_SIZE and y < w4.SCREEN_SIZE and draw_color != 0) {
        const stroke_color = (draw_color - 1) & 0x3;
        const idx = (w4.SCREEN_SIZE * @as(u32, y) + @as(u32, x)) >> 2;
        const shift: u3 = @intCast((x & 0x3) << 1);
        const mask = @as(u8, 0x3) << shift;
        w4.FRAMEBUFFER[idx] = (stroke_color << shift) | (w4.FRAMEBUFFER[idx] & ~mask);
    }
}

fn hostSetPreserveFrameBuffer(_: *abi.RocOps, _: *anyopaque, args: *const abi.HostSet_preserve_frame_bufferArgs) callconv(.c) void {
    if (args.arg0) {
        w4.SYSTEM_FLAGS.* |= w4.SYSTEM_PRESERVE_FRAMEBUFFER;
    } else {
        w4.SYSTEM_FLAGS.* &= ~w4.SYSTEM_PRESERVE_FRAMEBUFFER;
    }
}

fn hostText(ops: *abi.RocOps, _: *anyopaque, args: *const abi.HostTextArgs) callconv(.c) void {
    w4.text(args.arg0.asSlice(), args.arg1, args.arg2);
    args.arg0.decref(ops);
}

fn hostTone(_: *abi.RocOps, _: *anyopaque, args: *const abi.HostToneArgs) callconv(.c) void {
    w4.tone(args.arg0, args.arg1, args.arg2, args.arg3);
}

fn hostTrace(ops: *abi.RocOps, _: *anyopaque, args: *const abi.HostTraceArgs) callconv(.c) void {
    w4.trace(args.arg0.asSlice());
    args.arg0.decref(ops);
}

fn hostVline(_: *abi.RocOps, _: *anyopaque, args: *const abi.HostVlineArgs) callconv(.c) void {
    w4.vline(args.arg0, args.arg1, args.arg2);
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

    roc_ops = abi.makeRocOps(&env, abi.hostedFunctions(.{
        .host_blit = &hostBlit,
        .host_blit_sub = &hostBlitSub,
        .host_disk_read = &hostDiskRead,
        .host_disk_write = &hostDiskWrite,
        .host_get_draw_colors = &hostGetDrawColors,
        .host_get_gamepad = &hostGetGamepad,
        .host_get_mouse_buttons = &hostGetMouseButtons,
        .host_get_mouse_x = &hostGetMouseX,
        .host_get_mouse_y = &hostGetMouseY,
        .host_get_netplay = &hostGetNetplay,
        .host_get_palette_color = &hostGetPaletteColor,
        .host_get_pixel = &hostGetPixel,
        .host_hline = &hostHline,
        .host_line = &hostLine,
        .host_oval = &hostOval,
        .host_rand = &hostRand,
        .host_rand_range_less_than = &hostRandRangeLessThan,
        .host_rect = &hostRect,
        .host_seed_rand = &hostSeedRand,
        .host_set_draw_colors = &hostSetDrawColors,
        .host_set_hide_gamepad_overlay = &hostSetHideGamepadOverlay,
        .host_set_palette = &hostSetPalette,
        .host_set_pixel = &hostSetPixel,
        .host_set_preserve_frame_buffer = &hostSetPreserveFrameBuffer,
        .host_text = &hostText,
        .host_tone = &hostTone,
        .host_trace = &hostTrace,
        .host_vline = &hostVline,
    }));

    // init_for_host! returns the initial boxed model into `boxed_model`.
    // Arg is unit ({}) so we pass null.
    abi.roc__init_for_host(&roc_ops, &boxed_model, null);
    boxed_model_initialized = true;
}

export fn update() void {
    resetStackCanary();

    if (!boxed_model_initialized) {
        w4.trace("update() called before start() initialized the model");
        @trap();
    }

    // update_for_host! takes the current boxed model and returns the next one.
    // `arg_ptr` is `?*const **anyopaque` — a pointer to the slot holding the
    // current `**anyopaque` box.
    var current: **anyopaque = boxed_model;
    var next_model: **anyopaque = undefined;
    abi.roc__update_for_host(&roc_ops, &next_model, &current);

    boxed_model = next_model;

    checkStackCanary();
}
