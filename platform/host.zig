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

extern fn roc__mainForHost_1_exposed_generic(*RocStr, *RocStr) void;

pub fn main() u8 {
    return 0;
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

export fn start() void {}

export fn update() void {
    var arg = RocStr.fromSlice("MARCO");

    var callresult = RocStr.fromSlice("OUT");
    defer callresult.decref();

    roc__mainForHost_1_exposed_generic(&callresult, &arg);

    w4.DRAW_COLORS.* = 2;
    w4.text(callresult.asSlice(), 5, 10);

    const gamepad = w4.GAMEPAD1.*;
    if (gamepad & w4.BUTTON_1 != 0) {
        w4.DRAW_COLORS.* = 4;
    }

    w4.blit(&smiley, 76, 76, 8, 8, w4.BLIT_1BPP);
    w4.text("Press X to blink", 16, 90);
}
