const std = @import("std");
const assert = std.debug.assert;

const w4 = @import("wasm4.zig");

const str = @import("str.zig");
const RocStr = str.RocStr;
const ALIGN = 2 * @alignOf(usize);

const MEM_BASE = 0x19A0;
const MEM_SIZE = 58976;
const MEM: *[MEM_SIZE]u8 = @ptrFromInt(MEM_BASE);
// We allocate memory to max alignment for simplicity.
const MEM_CHUNK_SIZE = ALIGN;
var free_set = std.bit_set.ArrayBitSet(u64, MEM_SIZE / MEM_CHUNK_SIZE).initFull();
const Allocation = struct { start: u16, end: u16 };
const MAX_ALLOCATIONS = 100;
comptime {
    assert(MAX_ALLOCATIONS < MEM_SIZE / MEM_CHUNK_SIZE);
}
// TODO: Wrap all this memory stuff in a nice struct with methods.
var allocations: [MAX_ALLOCATIONS]Allocation = undefined;
var alloc_count: usize = 0;

// TODO: other roc_ functions.
export fn roc_alloc(size: usize, alignment: u32) callconv(.C) *anyopaque {
    _ = alignment;
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

    // TODO: double check this range is correct. I think the end may be off by 1.
    const range = .{ .start = start_index, .end = (current_index + 1) };
    free_set.setRangeValue(range, false);

    const addr = MEM_BASE + start_index * MEM_CHUNK_SIZE;
    if (alloc_count >= MAX_ALLOCATIONS) {
        @panic("Hit the maximum number of allocations");
    }
    allocations[alloc_count] = .{ .start = @intCast(range.start), .end = @intCast(range.end) };
    alloc_count += 1;

    return @ptrFromInt(addr);
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
    const addr = @intFromPtr(c_ptr);
    const start_index = (addr - MEM_BASE) / MEM_CHUNK_SIZE;
    var i: usize = 0;
    while (i < alloc_count) : (i += 1) {
        if (allocations[i].start == start_index) {
            const range = .{ .start = start_index, .end = allocations[i].end };
            free_set.setRangeValue(range, true);

            alloc_count -= 1;
            allocations[i] = allocations[alloc_count];
            return;
        }
    }
    @panic("attempted to free memory that was not allocated");
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
