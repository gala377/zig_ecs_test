const std = @import("std");

const Self = @This();
buff: std.ArrayList(u8),

pub const empty = Self{ .buff = std.ArrayList(u8).empty };

pub fn init(allocator: std.mem.Allocator, value: []const u8) std.mem.Allocator.Error!Self {
    var buff = try std.ArrayList(u8).initCapacity(allocator, value.len);
    buff.appendSliceAssumeCapacity(value);
    return .{
        .buff = buff,
    };
}

pub fn fromOwnedSlice(allocator: std.mem.Allocator, slice: []u8) Self {
    return .{ .buff = std.ArrayList(u8).fromOwnedSlice(allocator, slice) };
}

pub fn deinit(self: Self) void {
    self.buff.deinit();
}

pub fn asBytes(self: Self) []const u8 {
    return self.buff.items;
}

pub inline fn len(self: Self) usize {
    return self.buff.items.len;
}

pub fn concatBytes(self: Self, allocator: std.mem.Allocator, bytes: []const u8) std.mem.Allocator.Error!Self {
    const result = try allocator.alloc(u8, self.len() + bytes.len);
    @memcpy(result[0..self.len()], self.asBytes());
    @memcpy(result[self.len()..], bytes);
    return fromOwnedSlice(allocator, result);
}

pub fn concat(self: Self, allocator: std.mem.Allocator, other: Self) std.mem.Allocator.Error!Self {
    return self.concatBytes(allocator, other.asBytes());
}

pub fn writer(self: *Self) std.ArrayList(u8).Writer {
    return self.buff.writer();
}

pub fn clone(self: Self) std.mem.Allocator.Error!Self {
    return .{ .buff = try self.buff.clone() };
}
