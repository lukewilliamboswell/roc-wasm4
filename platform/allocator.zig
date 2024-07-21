//! This is an allocator optimized for low memory systems.
//! In the case of wasm32, there are definitely hard memory limits.
//! The implementation is based off of [umm_malloc](https://github.com/rhempel/umm_malloc)
//! That said, umm_malloc does not deal with alignment constraints instead opting for everything to be 4 byte align.
//! In wasm32, u64 and u128 are 8 byte aligned and must be dealt with.
const std = @import("std");
const builtin = @import("builtin");

const config = @import("config");

const w4 = @import("vendored/wasm4.zig");

const ALIGN = @alignOf(u128);
comptime {
    if (config.mem_size % ALIGN != 0) {
        @compileLog("The expected alignment is ", ALIGN);
        @compileError("-Dmem-size must multiple of the alignment");
    }
}

const TRACE_ALLOCS = config.trace_allocs;

const MEM_SIZE = config.mem_size;
const BLOCK_COUNT = MEM_SIZE / @sizeOf(Block);
var MEM: [MEM_SIZE]u8 align(ALIGN) = undefined;
var BLOCKS: []Block align(ALIGN) = @as([*]Block, @ptrCast(&MEM))[0..BLOCK_COUNT];

const Tag = enum(u1) {
    alloc = 0,
    freed = 1,
};
const Block = packed struct {
    tag: Tag,
    next_block: u15,
    _p0: u1 = 0,
    prev_block: u15,
    body: BlockBody,
};
const BlockBody = packed union {
    data: u32,
    free: packed struct {
        _p1: u1 = 0,
        next: u15,
        _p2: u1 = 0,
        prev: u15,
    },
};

pub fn init() void {
    @memset(MEM[0..], 0);

    // The zeroth block is special.
    // Labelled as allocated, but is really just the head of the free list.
    BLOCKS[0] = .{
        .tag = Tag.alloc,
        .next_block = 1,
        .prev_block = 0,
        .body = .{
            .free = .{
                .next = 1,
                .prev = 1,
            },
        },
    };

    // The first block is the free list.
    // Just one giant free element for the entire heap.
    BLOCKS[1] = .{
        .tag = Tag.freed,
        .next_block = @as(u15, @intCast(BLOCKS.len)) - 1,
        .prev_block = 0,
        .body = .{
            .free = .{
                .next = 0,
                .prev = 0,
            },
        },
    };

    // The last block is also special.
    // Labelled as allocated, but is really just the tail of the block list.
    BLOCKS[BLOCKS.len - 1] = Block{
        .tag = Tag.alloc,
        .next_block = 0,
        .prev_block = 1,
        .body = .{
            .free = .{
                .next = 0,
                .prev = 0,
            },
        },
    };
}

/// Allocates a block of `size` and returns a pointer to it.
pub fn malloc(size: usize) !?*anyopaque {
    if (size == 0) {
        if (TRACE_ALLOCS) {
            w4.trace("Allocating zero bytes -> null pointer");
        }
        return null;
    }

    const blocks = num_blocks(size);

    // First scan through the free list for a space with enough blocks.
    var current_free = BLOCKS[0].body.free.next;
    var block_size: u15 = 0;

    // This is using the slower, but more memory effecient best fit algorithm.
    // First fit is a faster but more fragmentation heavy alternative.
    var best_block: u15 = 0;
    var best_size: u15 = std.math.maxInt(u15);
    while (current_free != 0) : (current_free = BLOCKS[current_free].body.free.next) {
        block_size = BLOCKS[current_free].next_block - current_free;

        if (block_size >= blocks and block_size < best_size) {
            best_block = current_free;
            best_size = block_size;
        }
    }

    if (best_size != std.math.maxInt(u15)) {
        current_free = best_block;
        block_size = best_size;
    }

    if (BLOCKS[current_free].next_block != 0 and block_size >= blocks) {
        // We found an existing block in the heap free list to reuse.
        // Need to remove it from the free list, build an allocated block,
        // and then put any extra space back on the free list.
        if (block_size == blocks) {
            // No extra space, just remove the block from the free list.
            if (TRACE_ALLOCS) {
                w4.tracef("Allocating %d blocks starting at %d - exact", @as(u32, @intCast(blocks)), @as(u32, @intCast(current_free)));
            }
            disconnect_from_free_list(current_free);
        } else {
            // Current free will be allocated.
            if (TRACE_ALLOCS) {
                w4.tracef("Allocating %d blocks starting at %d - existing", @as(u32, @intCast(blocks)), @as(u32, @intCast(current_free)));
            }
            // The split off chunk will be added to the free list.
            split_block(current_free, blocks, Tag.freed);

            const current = &BLOCKS[current_free];
            // Link to prev block in free list.
            BLOCKS[current.body.free.prev].body.free.next = current_free + blocks;
            BLOCKS[current_free + blocks].body.free.prev = current.body.free.prev;

            // Link to next block in free list.
            BLOCKS[current.body.free.next].body.free.prev = current_free + blocks;
            BLOCKS[current_free + blocks].body.free.next = current.body.free.next;
        }
    } else {
        return error.OutOfMemory;
    }

    std.debug.assert(BLOCKS[current_free].tag == Tag.alloc);
    return @ptrCast(&BLOCKS[current_free].body.data);
}

test "max small mallocs" {
    init();

    var i: usize = 0;
    while (i < BLOCK_COUNT - 2) : (i += 1) {
        _ = try malloc(@sizeOf(BlockBody));
    }
    // Too far, should error!
    try std.testing.expectError(error.OutOfMemory, malloc(1));
}

test "single large malloc" {
    init();

    _ = try malloc(MEM_SIZE - 2 * @sizeOf(Block) - @sizeOf(BlockBody));

    // Too far, should error!
    try std.testing.expectError(error.OutOfMemory, malloc(1));
}

test "oversized malloc" {
    init();
    try std.testing.expectError(error.OutOfMemory, malloc(MEM_SIZE));
}

/// Merges the next block with the current block if it is free.
fn assimilate_up(c: u15) void {
    const current = &BLOCKS[c];
    const next = &BLOCKS[current.next_block];

    if (next.tag == Tag.freed) {
        if (TRACE_ALLOCS) {
            w4.trace("Assimilating up to next block, which is FREE");
        }

        disconnect_from_free_list(current.next_block);

        BLOCKS[next.next_block].prev_block = c;
        current.next_block = next.next_block;
    }
}

/// Merges the previous block with the current block.
/// Assumes the next block does not have the free bit set.
/// Always assimilate up before down.
fn assimilate_down(c: u15, tag: Tag) u15 {
    const current = &BLOCKS[c];
    const next = &BLOCKS[current.next_block];
    const prev = &BLOCKS[current.prev_block];

    prev.tag = tag;
    prev.next_block = current.next_block;
    next.prev_block = current.prev_block;

    return current.prev_block;
}

/// Frees a block of pointed to by `ptr`.
/// Note, `ptr` should be to the data section. Same as what was returned by `malloc`.
pub fn free(ptr: ?*anyopaque) !void {
    if (ptr == null) {
        if (TRACE_ALLOCS) {
            w4.trace("Freeing null pointer -> do nothing");
        }
        return;
    }

    if (@intFromPtr(ptr) < @intFromPtr(&MEM[0]) or @intFromPtr(ptr) >= @intFromPtr(&MEM[0]) + MEM_SIZE) {
        return error.OutOfRange;
    }

    const c: u15 = @intCast((@intFromPtr(ptr) - @intFromPtr(&MEM[0])) / @sizeOf(Block));
    if (TRACE_ALLOCS) {
        w4.tracef("Freeing block %d", @as(u32, @intCast(c)));
    }

    std.debug.assert(c != 0 and c != BLOCK_COUNT - 1);
    const current = &BLOCKS[c];
    std.debug.assert(current.tag == Tag.alloc);

    // Merge this block with the next if it happens to be free.
    assimilate_up(c);

    // Merge with previous block if possible.
    if (BLOCKS[current.prev_block].tag == Tag.freed) {
        if (TRACE_ALLOCS) {
            w4.trace("Assimilating down to previous block, which is FREE");
        }
        _ = assimilate_down(c, Tag.freed);
    } else {
        // Previous block was not part of the free list.
        // So this block is free but not part of the free list at all.
        // Add it as the head of the free list.
        // base -> next
        // becomes:
        // base -> current -> next
        if (TRACE_ALLOCS) {
            w4.trace("Adding to head of the free list");
        }

        const base = &BLOCKS[0];
        const next = &BLOCKS[base.body.free.next];
        next.body.free.prev = c;
        current.body.free.next = base.body.free.next;
        current.body.free.prev = 0;
        base.body.free.next = c;

        current.tag = Tag.freed;
    }
}

test "free edge cases" {
    try free(null);

    const before: ?*anyopaque = @ptrFromInt(@intFromPtr(&MEM[0]) - 1);
    try std.testing.expectError(error.OutOfRange, free(before));

    const after: ?*anyopaque = @ptrFromInt(@intFromPtr(&MEM[0]) + MEM_SIZE);
    try std.testing.expectError(error.OutOfRange, free(after));
}

test "alloc all, free all" {
    init();

    // Malloc all small.
    var i: usize = 0;
    var ptrs: [BLOCK_COUNT - 2]?*anyopaque = undefined;
    while (i < BLOCK_COUNT - 2) : (i += 1) {
        ptrs[i] = try malloc(@sizeOf(BlockBody));
    }
    try std.testing.expectError(error.OutOfMemory, malloc(1));

    // Free all.
    i = 0;
    while (i < BLOCK_COUNT - 2) : (i += 1) {
        try free(ptrs[i]);
    }
    try std.testing.expectEqual(free_list_size(), 1);

    // Everything merge back correctly and we can alloc the full size.
    _ = try malloc(MEM_SIZE - 2 * @sizeOf(Block) - @sizeOf(BlockBody));
    try std.testing.expectEqual(free_list_size(), 0);
}

test "malloc all, free max fragmentation" {
    init();

    // Malloc all small.
    var i: usize = 0;
    var ptrs: [BLOCK_COUNT - 2]?*anyopaque = undefined;
    while (i < BLOCK_COUNT - 2) : (i += 1) {
        ptrs[i] = try malloc(@sizeOf(BlockBody));
    }
    try std.testing.expectError(error.OutOfMemory, malloc(1));

    // Free every other for max fragmentation.
    i = 0;
    while (i < BLOCK_COUNT - 2) : (i += 2) {
        try free(ptrs[i]);
    }
    try std.testing.expectEqual(free_list_size(), BLOCK_COUNT / 2 - 1);

    // Can't allocate something that needs two blocks.
    try std.testing.expectError(error.OutOfMemory, malloc(9));

    // Free the other half and ensure they merge correctly.
    i = 1;
    while (i < BLOCK_COUNT - 2) : (i += 2) {
        try free(ptrs[i]);
    }
    try std.testing.expectEqual(free_list_size(), 1);

    // Everything merge back correctly and we can alloc the full size.
    _ = try malloc(MEM_SIZE - 2 * @sizeOf(Block) - @sizeOf(BlockBody));
    try std.testing.expectEqual(free_list_size(), 0);
}

/// reallocates a pointer to a new size.
/// Any data is copied over to the new location.
/// Note, `ptr` should be to the data section. Same as what was returned by `malloc`.
pub fn realloc(ptr: ?*anyopaque, size: usize) !?*anyopaque {
    if (ptr == null) {
        if (TRACE_ALLOCS) {
            w4.trace("Reallocating null pointer -> call malloc");
        }
        return malloc(size);
    }

    if (size == 0) {
        if (TRACE_ALLOCS) {
            w4.trace("Reallocating to zero size -> call free");
        }
        try free(ptr);
        return null;
    }

    if (@intFromPtr(ptr) < @intFromPtr(&MEM[0]) or @intFromPtr(ptr) >= @intFromPtr(&MEM[0]) + MEM_SIZE) {
        return error.OutOfRange;
    }

    const blocks = num_blocks(size);
    var c: u15 = @intCast((@intFromPtr(ptr) - @intFromPtr(&MEM[0])) / @sizeOf(Block));
    std.debug.assert(c != 0 and c != BLOCK_COUNT - 1);
    std.debug.assert(BLOCKS[c].tag == Tag.alloc);

    var block_size = BLOCKS[c].next_block - c;

    var current_size = (@as(usize, @intCast(block_size)) * @sizeOf(Block)) - (@sizeOf(Block) - @sizeOf(BlockBody));

    const next_block_size = if (BLOCKS[BLOCKS[c].next_block].tag == Tag.freed)
        BLOCKS[BLOCKS[c].next_block].next_block - BLOCKS[c].next_block
    else
        0;

    const prev_block_size = if (BLOCKS[BLOCKS[c].prev_block].tag == Tag.freed)
        c - BLOCKS[c].prev_block
    else
        0;

    if (TRACE_ALLOCS) {
        w4.tracef("realloc block %d block_size %d next_block_size %d, prev_block_size %d", @as(u32, @intCast(blocks)), @as(u32, @intCast(block_size)), @as(u32, @intCast(next_block_size)), @as(u32, @intCast(prev_block_size)));
    }

    // Doing a good realloc is actually quite complicated with many different cases.
    //
    // 1. Smaller size than current, just do nothing.
    // 2. If next block is free and exact size needed, just merge.
    //    Only do this on exact size to avoid fragmentation.
    //
    // This case might benefit from a copy to reduce fragmentation.
    //
    // 3. Previous block NOT free, but next is free with enough space to reach the required size.
    //    Merge anyway and accept some fragmentation potential.
    //
    // All cases below use copying to reduce fragmentation.
    //
    // 4. Previous is free and has enough space, remove it from the free list and merge.
    //    Requires copying our data over to that block.
    // 5. Both prev and next are free and have enough space,
    //    Merge both removing from free list and copy over to first block.
    // 6. Othewise, alloc a totally new block, copy, and then free.
    //    If the allocation fails, raise an error without changing anything.
    //
    // Finally, if the fit wasn't exact, split the block and add the tail to the free list.

    var out_ptr = ptr;
    if (block_size >= blocks) {
        // 1. block is smaller than current.
        if (TRACE_ALLOCS) {
            w4.tracef("realloc same or smaller size - %d", @as(u32, @intCast(blocks)));
        }
    } else if (block_size + next_block_size == blocks) {
        // 2. current and next are exact fit.
        if (TRACE_ALLOCS) {
            w4.tracef("exact realloc using next - %d", @as(u32, @intCast(blocks)));
        }
        assimilate_up(c);
        block_size += next_block_size;
    } else if (prev_block_size == 0 and block_size + next_block_size >= blocks) {
        // 3. prev NOT free and current and next have enough space.
        if (TRACE_ALLOCS) {
            w4.tracef("realloc using next - %d", @as(u32, @intCast(blocks)));
        }
        assimilate_up(c);
        block_size += next_block_size;
    } else if (prev_block_size + block_size >= blocks) {
        // 4. prev and current have enough space
        if (TRACE_ALLOCS) {
            w4.tracef("realloc using prev - %d", @as(u32, @intCast(blocks)));
        }
        disconnect_from_free_list(BLOCKS[c].prev_block);
        c = assimilate_down(c, Tag.alloc);

        out_ptr = @ptrCast(&BLOCKS[c].body.data);
        std.mem.copyForwards(u8, @as([*]u8, @alignCast(@ptrCast(out_ptr)))[0..current_size], @as([*]u8, @alignCast(@ptrCast(ptr)))[0..current_size]);

        block_size += prev_block_size;
    } else if (prev_block_size + block_size + next_block_size >= blocks) {
        // 5. prev and current and next have enough space
        if (TRACE_ALLOCS) {
            w4.tracef("realloc using prev and next - %d", @as(u32, @intCast(blocks)));
        }
        assimilate_up(c);
        disconnect_from_free_list(BLOCKS[c].prev_block);
        c = assimilate_down(c, Tag.alloc);

        out_ptr = @ptrCast(&BLOCKS[c].body.data);
        std.mem.copyForwards(u8, @as([*]u8, @alignCast(@ptrCast(out_ptr)))[0..current_size], @as([*]u8, @alignCast(@ptrCast(ptr)))[0..current_size]);

        block_size += prev_block_size + next_block_size;
    } else {
        // 6. need to malloc, copy, then free.
        if (TRACE_ALLOCS) {
            w4.tracef("realloc to totally new block - %d", @as(u32, @intCast(blocks)));
        }
        out_ptr = try malloc(size);
        @memcpy(@as([*]u8, @alignCast(@ptrCast(out_ptr)))[0..current_size], @as([*]u8, @alignCast(@ptrCast(ptr)))[0..current_size]);

        try free(ptr);
        block_size = blocks;
    }

    // Add extra blocks at tail back to the free list.
    if (block_size > blocks) {
        if (TRACE_ALLOCS) {
            w4.tracef("split and free %d blocks from %d", @as(u32, @intCast(blocks)), @as(u32, @intCast(block_size)));
        }
        split_block(c, blocks, Tag.alloc);
        try free(@ptrCast(&BLOCKS[c + blocks].body.data));
    }

    return out_ptr;
}

test "realloc to full size and back" {
    init();

    const ptr = try malloc(25);
    const ptr1 = try realloc(ptr, MEM_SIZE - 2 * @sizeOf(Block) - @sizeOf(BlockBody));
    try std.testing.expectEqual(ptr, ptr1);

    const ptr2 = try realloc(ptr1, 32);
    try std.testing.expectEqual(ptr1, ptr2);
}

test "realloc case 1 - smaller" {
    init();

    const ptr = try malloc(100);
    const ptr1 = try malloc(1);

    const ptr2 = try realloc(ptr, 32);
    try std.testing.expectEqual(ptr, ptr2);

    // New allocation should go in gap between ptr and ptr1.
    const ptr3 = try malloc(1);
    try std.testing.expect(@intFromPtr(ptr) < @intFromPtr(ptr3));
    try std.testing.expect(@intFromPtr(ptr3) < @intFromPtr(ptr1));
}

test "realloc case 2 - current + next exact fit" {
    init();

    const ptr = try malloc(1);
    const ptr1 = try malloc(1);
    const ptr2 = try malloc(1);

    try free(ptr1);

    // reallocate exactly to ptr2 and don't move.
    const ptr3 = try realloc(ptr, 2 * @sizeOf(Block) - @sizeOf(BlockBody));
    try std.testing.expectEqual(ptr, ptr3);

    // There should be no space before ptr2 remaining.
    const ptr4 = try malloc(1);

    try std.testing.expect(@intFromPtr(ptr2) < @intFromPtr(ptr4));
}

test "realloc case 3 - current + next extra space" {
    init();

    const ptr = try malloc(1);
    const ptr1 = try malloc(10);
    const ptr2 = try malloc(1);

    try free(ptr1);

    // reallocate exactly to ptr2 and don't move.
    const ptr3 = try realloc(ptr, 2 * @sizeOf(Block) - @sizeOf(BlockBody));
    try std.testing.expectEqual(ptr, ptr3);

    // This should go in the extra space before ptr2
    const ptr4 = try malloc(1);

    try std.testing.expect(@intFromPtr(ptr4) < @intFromPtr(ptr2));
}

test "realloc case 4 - current + prev have enough space" {
    init();

    const ptr = try malloc(1);
    const ptr1 = try malloc(@sizeOf(BlockBody));
    const ptr2 = try malloc(1);
    _ = ptr2;

    var i: u8 = 0;
    while (i < @sizeOf(BlockBody)) : (i += 1) {
        @as([*]u8, @alignCast(@ptrCast(ptr1)))[i] = i;
    }

    try free(ptr);

    // reallocate will merge with `ptr`.
    const ptr3 = try realloc(ptr1, 2 * @sizeOf(Block) - @sizeOf(BlockBody));
    try std.testing.expectEqual(ptr, ptr3);
    i = 0;
    while (i < @sizeOf(BlockBody)) : (i += 1) {
        try std.testing.expectEqual(@as([*]u8, @alignCast(@ptrCast(ptr3)))[i], i);
    }
}

test "realloc case 5 - current + prev + next have enough space" {
    init();

    const ptr = try malloc(1);
    const ptr1 = try malloc(@sizeOf(BlockBody));
    const ptr2 = try malloc(1);
    const ptr3 = try malloc(1);
    _ = ptr3;

    var i: u8 = 0;
    while (i < @sizeOf(BlockBody)) : (i += 1) {
        @as([*]u8, @alignCast(@ptrCast(ptr1)))[i] = i;
    }

    try free(ptr);
    try free(ptr2);

    // reallocate will merge with `ptr` and `ptr2`.
    const ptr4 = try realloc(ptr1, 3 * @sizeOf(Block) - @sizeOf(BlockBody));
    try std.testing.expectEqual(ptr, ptr4);
    i = 0;
    while (i < @sizeOf(BlockBody)) : (i += 1) {
        try std.testing.expectEqual(@as([*]u8, @alignCast(@ptrCast(ptr4)))[i], i);
    }
}

test "realloc case 5 - total move required" {
    init();

    const ptr = try malloc(@sizeOf(BlockBody));
    const ptr1 = try malloc(1);
    const ptr2 = try malloc(1);
    _ = ptr2;

    var i: u8 = 0;
    while (i < @sizeOf(BlockBody)) : (i += 1) {
        @as([*]u8, @alignCast(@ptrCast(ptr)))[i] = i;
    }

    try free(ptr1);

    // This is two large, have to move
    const ptr3 = try realloc(ptr, 3 * @sizeOf(Block) - @sizeOf(BlockBody));
    try std.testing.expect(ptr != ptr3);

    i = 0;
    while (i < @sizeOf(BlockBody)) : (i += 1) {
        try std.testing.expectEqual(@as([*]u8, @alignCast(@ptrCast(ptr3)))[i], i);
    }

    // There should be no space before ptr2 remaining.
    // This should be able to reuse ptr on the other hand.
    const ptr4 = try malloc(2 * @sizeOf(Block) - @sizeOf(BlockBody));
    try std.testing.expectEqual(ptr, ptr4);
}

/// Disconnect a block from the free list.
fn disconnect_from_free_list(c: u15) void {
    const current = &BLOCKS[c];
    std.debug.assert(current.tag == Tag.freed);

    // prev.next = current.next
    const prev = &BLOCKS[current.body.free.prev];
    prev.body.free.next = current.body.free.next;
    // next.prev = current.prev
    const next = &BLOCKS[current.body.free.next];
    next.body.free.prev = current.body.free.prev;

    // Reset tag of current.
    current.tag = Tag.alloc;
}

/// split block `c` into two blocks: `c` and `c + blocks`.
///
/// Note: Does not modify or initialize free pointers.
fn split_block(c: u15, blocks: u15, new_tag: Tag) void {
    const current = &BLOCKS[c];
    const new_block = &BLOCKS[c + blocks];
    new_block.tag = new_tag;
    new_block.prev_block = c;
    new_block.next_block = current.next_block;

    BLOCKS[current.next_block].prev_block = c + blocks;
    current.tag = Tag.alloc;
    current.next_block = c + blocks;
}

/// Returns the number of blocks required to hold an allocation of `size`.
fn num_blocks(size: usize) u15 {
    // Fits inline with the block header.
    if (size <= @sizeOf(BlockBody)) {
        return 1;
    }

    const remaining_size = size - @sizeOf(BlockBody);

    // As documented in the umm code, this expression looks weird but is correct.
    // Bytes (Bytes-Body) (Bytes-Body-1)/BlockSize Blocks
    //     1          n/a                      n/a      1
    //     5            1                        0      2
    //    12            8                        0      2
    //    13            9                        1      3

    const blocks = (2 + ((remaining_size - 1) / @sizeOf(Block)));
    if (blocks > std.math.maxInt(u15)) {
        return std.math.maxInt(u15);
    }
    return @intCast(blocks);
}

test "block sizes" {
    try std.testing.expectEqual(@sizeOf(Block), 8);
    try std.testing.expectEqual(@sizeOf(BlockBody), 4);
    try std.testing.expectEqual(num_blocks(3), 1);
    try std.testing.expectEqual(num_blocks(5), 2);
    try std.testing.expectEqual(num_blocks(12), 2);
    try std.testing.expectEqual(num_blocks(13), 3);
}

test "slice type casting" {
    try std.testing.expectEqual(@as(*u8, @ptrCast(BLOCKS.ptr)), @as(*u8, @ptrCast(&MEM)));
    try std.testing.expectEqual(BLOCKS.len, MEM.len / @sizeOf(Block));
}

/// Returns the current length of the free list.
/// This requires walking the entire free list.
fn free_list_size() u15 {
    var current_free = BLOCKS[0].body.free.next;
    var count: u15 = 0;
    while (current_free != 0) : (current_free = BLOCKS[current_free].body.free.next) {
        count += 1;
    }
    return count;
}
