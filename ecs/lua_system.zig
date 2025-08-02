//! This file describes a wrapper around a system defined in lua

const ComponentId = @import("component.zig").ComponentId;
const lua = @import("lua_lib");
const Game = @import("game.zig").Game;
const DynamicScope = @import("game.zig").JoinedDynamicScope;
const DynamicQuery = @import("game.zig").DynamicQuery;

const std = @import("std");

const Self = @This();

components: [][]const ComponentId,
system: lua.Ref,
allocator: std.mem.Allocator,

pub fn fromLua(state: lua.State, allocator: std.mem.Allocator) !Self {
    if (lua.clib.lua_type(state.state, -1) != lua.clib.LUA_TTABLE) {
        @panic("Use system builder for lua systems");
    }
    if (lua.clib.lua_getfield(state.state, -1, "callback") != lua.clib.LUA_TFUNCTION) {
        @panic("expected callback to be a function");
    }
    const system = try state.makeRef();
    if (lua.clib.lua_getfield(state.state, -1, "queries") != lua.clib.LUA_TTABLE) {
        @panic("Expected queries to be a table");
    }
    const queries_len = lua.clib.lua_rawlen(state.state, -1);
    std.debug.print("Got length of queries {}\n", .{queries_len});
    const components = try allocator.alloc([]ComponentId, @intCast(queries_len));
    std.debug.assert(components.len == queries_len);
    for (1..queries_len + 1) |index| {
        std.debug.print("Looking at queries at index {}\n", .{index});
        if (lua.clib.lua_geti(state.state, -1, @intCast(index)) != lua.clib.LUA_TTABLE) {
            @panic("expected query to be a tabel of components\n");
        }
        // top of the stack
        const components_len = lua.clib.lua_rawlen(state.state, -1);
        std.debug.print("Got length of components {}\n", .{components_len});
        components[index - 1] = try allocator.alloc(ComponentId, @intCast(components_len));
        std.debug.assert(components[index - 1].len == components_len);
        for (1..components_len + 1) |cindex| {
            std.debug.print("\tLooking at component at index {}\n", .{cindex});
            if (lua.clib.lua_geti(state.state, -1, @intCast(cindex)) != lua.clib.LUA_TTABLE) {
                @panic("Expected component to be a table");
            }
            // top is the component thing now
            if (lua.clib.lua_getfield(state.state, -1, "component_hash") != lua.clib.LUA_TSTRING) {
                @panic("Expected component_hash to be a string");
            }
            const cstr = lua.clib.lua_tolstring(state.state, -1, null);
            std.debug.assert(cstr != null);
            const str: []const u8 = std.mem.sliceTo(cstr, 0);
            const hash = try std.fmt.parseInt(u64, str, 10);
            // pop the hash
            try state.pop();
            // pop the component
            try state.pop();
            components[index - 1][cindex - 1] = hash;
        }
        // pop the components table
        try state.pop();
    }
    // pop the queries table
    try state.pop();
    // pop the system builder
    try state.pop();
    std.debug.assert(state.stackSize() == 0);
    return .{
        .allocator = allocator,
        .system = system,
        .components = @ptrCast(components),
    };
}

pub fn run(self: *Self, game: *Game, state: lua.State) !void {
    const scopes = try self.allocator.alloc(DynamicScope, self.components.len);
    const iters = try self.allocator.alloc(DynamicQuery, self.components.len);
    defer {
        for (scopes) |*s| {
            s.deinit();
        }
        self.allocator.free(scopes);
        self.allocator.free(iters);
    }
    for (self.components, 0..) |q, i| {
        scopes[i] = try game.dynamicQueryScope(q);
    }
    for (scopes, 0..) |*s, i| {
        iters[i] = s.iter();
    }
    state.pushRef(self.system);
    for (iters) |*iter| {
        iter.luaPush(state.state);
    }
    lua.clib.lua_callk(state.state, @intCast(iters.len), 0, 0, null);
}

pub fn deinit(self: *Self) void {
    self.system.release();
    for (self.components) |comp| {
        self.allocator.free(comp);
    }
    self.allocator.free(self.components);
}
