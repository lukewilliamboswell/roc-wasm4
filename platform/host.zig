const std = @import("std");
const assert = std.debug.assert;

const config = @import("config");

const allocator = @import("allocator.zig");
const w4 = @import("vendored/wasm4.zig");

const str = @import("roc/str.zig");
const RocStr = str.RocStr;

const list = @import("roc/list.zig");
const RocList = list.RocList;

const utils = @import("roc/utils.zig");

// Random numbers
var prng = std.rand.DefaultPrng.init(0);
var rnd = prng.random();

// The canary is right after the frame buffer.
// The stack grows down and will run into the frame buffer if it overflows.
const CANARY_PTR: [*]usize = @ptrFromInt(@intFromPtr(w4.FRAMEBUFFER) + w4.FRAMEBUFFER.len);
const CANARY_SIZE = 8;
fn reset_stack_canary() void {
    var i: usize = 0;
    while (i < CANARY_SIZE) : (i += 1) {
        CANARY_PTR[i] = 0xDEAD_BEAF;
    }
}

fn check_stack_canary() void {
    var i: usize = 0;
    while (i < CANARY_SIZE) : (i += 1) {
        if (CANARY_PTR[i] != 0xDEAD_BEAF) {
            w4.trace("Warning: Stack canary damaged! There was likely a stack overflow during roc execution. Overflows write into the screen buffer and other hardware registers.");
            return;
        }
    }
}

export fn roc_alloc(requested_size: usize, alignment: u32) callconv(.C) *anyopaque {
    _ = alignment;
    if (allocator.malloc(requested_size)) |ptr| {
        return @ptrCast(ptr);
    } else |err| switch (err) {
        error.OutOfMemory => {
            w4.tracef("Ran out of memory: try increasing memory size with `-Dmem-size`. Current mem size is %d", config.mem_size);
            @panic("ran out of memory");
        },
    }
}

export fn roc_realloc(old_ptr: *anyopaque, new_size: usize, old_size: usize, alignment: u32) callconv(.C) ?*anyopaque {
    _ = alignment;
    _ = old_size;
    if (allocator.realloc(old_ptr, new_size)) |ptr| {
        return @ptrCast(ptr);
    } else |err| switch (err) {
        error.OutOfMemory => {
            w4.tracef("Ran out of memory: try increasing memory size with `-Dmem-size`. Current mem size is %d", config.mem_size);
            @panic("ran out of memory");
        },
        error.OutOfRange => {
            w4.tracef("Roc attempted to realloc a pointer that wasn't allocated. Something is definitely wrong.");
            return null;
        },
    }
}

export fn roc_dealloc(c_ptr: *anyopaque, alignment: u32) callconv(.C) void {
    _ = alignment;
    if (allocator.free(c_ptr)) {
        return;
    } else |err| switch (err) {
        error.OutOfRange => {
            w4.tracef("Roc attempted to dealloc a pointer that wasn't allocated. Something is definitely wrong.");
        },
    }
}

export fn roc_panic(msg: *RocStr, _: u32) callconv(.C) void {
    w4.tracef("ROC PANICKED: %s", msg.asU8ptr());
    @panic("ROC PANICKED");
}

// Currently roc does not generate debug statements except with `roc dev ...`.
// So this won't actually be called until that is updated.
export fn roc_dbg(loc: *RocStr, msg: *RocStr, src: *RocStr) callconv(.C) void {
    var loc0 = str.strConcatC(loc.*, RocStr.fromSlice(&[1]u8{0}));
    defer loc0.decref();
    var msg0 = str.strConcatC(msg.*, RocStr.fromSlice(&[1]u8{0}));
    defer msg0.decref();
    var src0 = str.strConcatC(src.*, RocStr.fromSlice(&[1]u8{0}));
    defer src0.decref();

    w4.tracef("[%s] %s = %s\n", loc0.asU8ptr(), src0.asU8ptr(), msg0.asU8ptr());
}

const smiley = [8]u8{
    0b11000011,
    0b10000001,
    0b00100100,
    0b00100100,
    0b00000000,
    0b00100100,
    0b10011001,
    0b11000011,
};

var model: *anyopaque = undefined;

fn trace_model() void {
    w4.tracef("%x", @as(u32, @intFromPtr(model)));
}

extern fn roc__mainForHost_1_exposed_generic(*anyopaque) callconv(.C) void;
extern fn roc__mainForHost_1_exposed_size() callconv(.C) i64;
// Init Task
extern fn roc__mainForHost_0_caller(*anyopaque, *anyopaque, **anyopaque) callconv(.C) void;
extern fn roc__mainForHost_0_size() callconv(.C) i64;

// Update Fn
extern fn roc__mainForHost_1_caller(**anyopaque, *anyopaque, *anyopaque) callconv(.C) void;
extern fn roc__mainForHost_1_size() callconv(.C) i64;
// Update Task
extern fn roc__mainForHost_2_caller(*anyopaque, *anyopaque, **anyopaque) callconv(.C) void;
extern fn roc__mainForHost_2_size() callconv(.C) i64;

export fn start() void {
    allocator.init();
    // w4.tracef("size: %d", free_set.capacity());
    const update_size = @as(usize, @intCast(roc__mainForHost_1_size()));
    if (update_size != 0) {
        w4.trace("This platform does not allow for the update function to have captures");
        @panic("Invalid roc app: captures not allowed");
    }

    const size = @as(usize, @intCast(roc__mainForHost_1_exposed_size()));
    const captures = roc_alloc(size, @alignOf(u128));
    defer roc_dealloc(captures, @alignOf(u128));

    roc__mainForHost_1_exposed_generic(captures);
    roc__mainForHost_0_caller(undefined, captures, &model);

    const update_task_size = @as(usize, @intCast(roc__mainForHost_2_size()));
    update_captures = roc_alloc(update_task_size, @alignOf(u128));
}

var update_captures: *anyopaque = undefined;
export fn update() void {
    reset_stack_canary();
    roc__mainForHost_1_caller(&model, undefined, update_captures);
    roc__mainForHost_2_caller(undefined, update_captures, &model);
    check_stack_canary();
}

export fn roc_fx_text(text: *RocStr, x: i32, y: i32) callconv(.C) void {
    w4.text(text.asSlice(), x, y);
}

export fn roc_fx_trace(text: *RocStr) callconv(.C) void {
    w4.trace(text.asSlice());
}

export fn roc_fx_rect(x: i32, y: i32, width: u32, height: u32) callconv(.C) void {
    w4.rect(x, y, width, height);
}

export fn roc_fx_oval(x: i32, y: i32, width: u32, height: u32) callconv(.C) void {
    w4.oval(x, y, width, height);
}

export fn roc_fx_line(x: i32, y: i32, x2: i32, y2: i32) callconv(.C) void {
    w4.line(x, y, x2, y2);
}

export fn roc_fx_hline(x: i32, y: i32, len: u32) callconv(.C) void {
    w4.hline(x, y, len);
}

export fn roc_fx_vline(x: i32, y: i32, len: u32) callconv(.C) void {
    w4.vline(x, y, len);
}

export fn roc_fx_setPalette(a: u32, b: u32, c: u32, d: u32) callconv(.C) void {
    w4.PALETTE.* = .{ a, b, c, d };
}

const RocPalette = extern struct { color1: u32, color2: u32, color3: u32, color4: u32 };
export fn roc_fx_getPalette() callconv(.C) RocPalette {
    return .{ .color1 = w4.PALETTE[0], .color2 = w4.PALETTE[1], .color3 = w4.PALETTE[2], .color4 = w4.PALETTE[3] };
}

export fn roc_fx_setDrawColors(draw_color_flags: u16) callconv(.C) void {
    w4.DRAW_COLORS.* = draw_color_flags;
}

export fn roc_fx_getDrawColors() callconv(.C) u16 {
    return w4.DRAW_COLORS.*;
}

export fn roc_fx_getGamepad(gamepad_number: u8) callconv(.C) u8 {
    const gamepad_flags = switch (gamepad_number) {
        1 => w4.GAMEPAD1.*,
        2 => w4.GAMEPAD2.*,
        3 => w4.GAMEPAD3.*,
        4 => w4.GAMEPAD4.*,
        else => unreachable,
    };

    return gamepad_flags;
}

const RocMouse = extern struct {
    x: i16,
    y: i16,
    buttons: u8,
};

export fn roc_fx_getMouse() callconv(.C) RocMouse {
    return .{ .x = w4.MOUSE_X.*, .y = w4.MOUSE_Y.*, .buttons = w4.MOUSE_BUTTONS.* };
}

export fn roc_fx_getNetplay() callconv(.C) u8 {
    return w4.NETPLAY.*;
}

export fn roc_fx_seedRand(seed: u64) callconv(.C) void {
    prng = std.rand.DefaultPrng.init(seed);
    rnd = prng.random();
}

export fn roc_fx_rand() callconv(.C) i32 {
    return rnd.int(i32);
}

export fn roc_fx_randRangeLessThan(min: i32, max: i32) callconv(.C) i32 {
    return rnd.intRangeLessThan(i32, min, max);
}

export fn roc_fx_blit(bytes: *RocList, x: i32, y: i32, width: u32, height: u32, flags: u32) callconv(.C) void {
    const data: [*]const u8 = bytes.elements(u8).?;

    w4.blit(data, x, y, width, height, flags);
}

export fn roc_fx_blitSub(bytes: *RocList, x: i32, y: i32, width: u32, height: u32, srcX: u32, srcY: u32, stride: u32, flags: u32) callconv(.C) void {
    const data: [*]const u8 = bytes.elements(u8).?;

    w4.blitSub(data, x, y, width, height, srcX, srcY, stride, flags);
}

// Max size according to https://wasm4.org/docs/reference/functions#storage
const MAX_DISK_SIZE = 1024;

export fn roc_fx_diskw(bytes: *RocList) callconv(.C) bool {
    if (bytes.len() > MAX_DISK_SIZE) {
        // Not possible to save all bytes.
        return false;
    }
    const data: [*]const u8 = bytes.elements(u8).?;

    const written = w4.diskw(data, bytes.len());
    return written == bytes.len();
}

export fn roc_fx_diskr() callconv(.C) RocList {
    // This is just gonna always get as many bytes as possible.
    var out = RocList.allocateExact(@alignOf(u8), MAX_DISK_SIZE, @sizeOf(u8), false);

    const data: [*]u8 = out.elements(u8).?;
    const get = w4.diskr(data, MAX_DISK_SIZE);
    out.length = get;

    return out;
}

export fn roc_fx_setPreserveFrameBuffer(preserve: bool) callconv(.C) void {
    if (preserve) {
        w4.SYSTEM_FLAGS.* |= w4.SYSTEM_PRESERVE_FRAMEBUFFER;
    } else {
        w4.SYSTEM_FLAGS.* &= ~w4.SYSTEM_PRESERVE_FRAMEBUFFER;
    }
}

export fn roc_fx_setHideGamepadOverlay(hide: bool) callconv(.C) void {
    if (hide) {
        w4.SYSTEM_FLAGS.* |= w4.SYSTEM_HIDE_GAMEPAD_OVERLAY;
    } else {
        w4.SYSTEM_FLAGS.* &= ~w4.SYSTEM_HIDE_GAMEPAD_OVERLAY;
    }
}

export fn roc_fx_tone(frequency: u32, duration: u32, volume: u16, flags: u8) callconv(.C) void {
    w4.tone(frequency, duration, volume, flags);
}

export fn roc_fx_setPixel(x: u8, y: u8, draw_color: u8) callconv(.C) void {
    // Draw if inbounds and not transparent color.
    if (x < w4.SCREEN_SIZE and y < w4.SCREEN_SIZE and draw_color != 0) {
        const stroke_color = (draw_color - 1) & 0x3;
        const idx = (w4.SCREEN_SIZE * y + x) >> 2;
        const shift: u3 = @intCast((x & 0x3) << 1);
        const mask = @as(u8, 0x3) << shift;
        w4.FRAMEBUFFER[idx] = (stroke_color << shift) | (w4.FRAMEBUFFER[idx] & ~mask);
    }
}

// For this instead of returning a result, just decide we can return the None color.
export fn roc_fx_getPixel(x: u8, y: u8) callconv(.C) u8 {
    if (x >= w4.SCREEN_SIZE or y >= w4.SCREEN_SIZE) {
        return 0;
    }

    const idx = (w4.SCREEN_SIZE * y + x) >> 2;
    const shift: u3 = @intCast((x & 0x3) << 1);
    const mask = @as(u8, 0x3) << shift;
    const stroke_color = (w4.FRAMEBUFFER[idx] & mask) >> shift;
    return stroke_color + 1;
}
