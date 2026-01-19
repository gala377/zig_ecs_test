pub const state = @import("state.zig");
pub const Value = @import("value.zig").Value;
pub const Pair = @import("value.zig").Pair;
pub const Ref = @import("ref.zig").Ref;
pub const State = state.LuaState;
pub const clib = state.lua;
pub const CLuaState = clib.lua_State;

const std = @import("std");

test "getting a table from stack and free" {
    const allocator = std.testing.allocator;
    var s = try state.LuaState.init(allocator);
    defer s.deinit();
    const table = try s.exec(
        \\ return { [1]="hello", [2]="world", key=10 };
    , allocator);
    table.deinit();
}

test "getting a table from stack values make sense" {
    const allocator = std.testing.allocator;
    var s = try state.LuaState.init(allocator);
    defer s.deinit();
    const table = try s.exec(
        \\ return { "hello", "w!", key=10 };
    , allocator);
    defer table.deinit();
    switch (table) {
        .Table => |inner| {
            // std.debug.print("array {any}", .{inner.items});
            try std.testing.expectEqual(3, inner.value.items.len);
        },
        else => try std.testing.expect(false),
    }
}
