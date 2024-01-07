const std = @import("std");
const assert = std.debug.assert;

const w4 = @import("wasm4.zig");

const str = @import("str.zig");
const RocStr = str.RocStr;
const ALIGN = 2 * @alignOf(usize);

const TRACE_ALLOC = false;

const MEM_BASE = 0x19A0;
const MEM_SIZE = 58976;
const MEM: *[MEM_SIZE]u8 = @ptrFromInt(MEM_BASE);
// We allocate memory to max alignment for simplicity.
const MEM_CHUNK_SIZE = ALIGN;
var free_set = std.bit_set.ArrayBitSet(u64, MEM_SIZE / MEM_CHUNK_SIZE).initFull();

// TODO: other roc_ functions.
export fn roc_alloc(requested_size: usize, alignment: u32) callconv(.C) *anyopaque {
    _ = alignment;
    // Leave extra space to store allocation size.
    if (TRACE_ALLOC) {
        w4.tracef("alloc -> requested size %d", requested_size);
    }
    const size = requested_size + MEM_CHUNK_SIZE;

    var chunk_size: usize = 0;
    var start_index: usize = 0;
    var current_index: usize = 0;
    while (chunk_size < size and current_index < free_set.capacity()) : (current_index += 1) {
        if (free_set.isSet(current_index)) {
            chunk_size += MEM_CHUNK_SIZE;
        } else {
            chunk_size = 0;
            start_index = current_index + 1;
        }
    }
    if (chunk_size < size) {
        @panic("ran out of memory");
    }

    const exclusive_end_index = current_index + 1;
    const range = .{ .start = start_index, .end = exclusive_end_index };
    if (TRACE_ALLOC) {
        w4.tracef("alloc -> start %d, end %d", start_index, exclusive_end_index);
    }
    free_set.setRangeValue(range, false);

    const size_addr = MEM_BASE + start_index * MEM_CHUNK_SIZE;
    const data_addr = size_addr + MEM_CHUNK_SIZE;

    const size_ptr: *usize = @ptrFromInt(size_addr);
    size_ptr.* = chunk_size;

    return @ptrFromInt(data_addr);
}

export fn roc_realloc(old_ptr: *anyopaque, new_size: usize, old_size: usize, alignment: u32) callconv(.C) ?*anyopaque {
    // TODO: a nice implementation that has the chance to just extend an allocation.
    const new_ptr = roc_alloc(new_size, alignment);

    var i: usize = 0;
    const new_byte_ptr: [*]u8 = @ptrCast(new_ptr);
    const old_byte_ptr: [*]u8 = @ptrCast(old_ptr);
    while (i < old_size) : (i += 1) {
        new_byte_ptr[i] = old_byte_ptr[i];
    }
    roc_dealloc(old_ptr, alignment);
    return new_ptr;
}

export fn roc_dealloc(c_ptr: *anyopaque, alignment: u32) callconv(.C) void {
    _ = alignment;
    const data_addr = @intFromPtr(c_ptr);
    const size_addr = data_addr - MEM_CHUNK_SIZE;
    const size_ptr: *usize = @ptrFromInt(size_addr);
    const size = size_ptr.*;

    const start_index = (size_addr - MEM_BASE) / MEM_CHUNK_SIZE;
    const exclusive_end_index = start_index + size / MEM_CHUNK_SIZE + 1;
    if (TRACE_ALLOC) {
        w4.tracef("free -> start %d, end %d", start_index, exclusive_end_index);
    }
    const range = .{ .start = start_index, .end = exclusive_end_index };
    free_set.setRangeValue(range, true);
}

export fn roc_panic(msg: *RocStr, tag_id: u32) callconv(.C) void {
    _ = msg;
    _ = tag_id;
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
    roc__mainForHost_1_caller(&model, undefined, update_captures);
    roc__mainForHost_2_caller(undefined, update_captures, &model);
}

export fn roc_fx_text(text: *RocStr, x: i32, y: i32) callconv(.C) void {
    w4.text(text.asSlice(), x, y);
}

export fn roc_fx_rect(x: i32, y: i32, width: u32, height: u32) callconv(.C) void {
    w4.rect(x, y, width, height);
}

export fn roc_fx_setPallet(a: u32, b: u32, c: u32, d: u32) callconv(.C) void {
    w4.PALETTE.* = .{ a, b, c, d };
}

export fn roc_fx_setDrawColors(draw_color_flags: u16) callconv(.C) void {
    w4.DRAW_COLORS.* = draw_color_flags;
}

export fn roc_fx_readGamepad(gamepad_number: u8) callconv(.C) u8 {
    const gamepad_flags = switch (gamepad_number) {
        1 => w4.GAMEPAD1.*,
        2 => w4.GAMEPAD2.*,
        3 => w4.GAMEPAD3.*,
        4 => w4.GAMEPAD4.*,
        else => unreachable,
    };

    return gamepad_flags;
}
