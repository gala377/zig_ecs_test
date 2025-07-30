const std = @import("std");

const LuaState = @import("state.zig").LuaState;

pub const Pair = struct {
    key: Value,
    value: Value,
};

pub const Value = union(enum) {
    Nil,
    Boolean: bool,
    Number: f64,
    /// This string is owned by the `Value`. This means it has to be freed
    /// by calling LuaState.free on it.
    String: struct { value: []const u8, allocator: std.mem.Allocator },
    /// Caller is responsible for freeing this valye by calling state.free on it.
    Table: struct { value: std.ArrayList(Pair), allocator: std.mem.Allocator },

    pub fn deinit(self: Value) void {
        switch (self) {
            .String => |ptr| {
                ptr.allocator.free(ptr.value);
            },
            .Table => |ptr| {
                const table = ptr.value;
                for (table.items) |pair| {
                    pair.key.deinit();
                    pair.value.deinit();
                }
                table.deinit();
            },
            else => {},
        }
    }
};
