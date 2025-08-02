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
    lua.clib.lua_getfield(state.state, -1, "callback");
    const system = try state.makeRef();
    lua.clib.lua_getfield(state.state, -1, "queries");
    const queries_len = lua.clib.lua_rawlen(state.state, -1);
    const components = try allocator.alloc([]ComponentId, @intCast(queries_len));
    for (1..queries_len + 1) |index| {
        lua.clib.lua_geti(state.state, -1, @intCast(index));
        // top of the stack
        const components_len = lua.clib.lua_rawlen(state.state, -1);
        components[index - 1] = try allocator.alloc(ComponentId, @intCast(components_len));
        for (1..components_len + 1) |cindex| {
            lua.clib.lua_geti(state.state, -1, @intCast(cindex));
            // top is the component thing now
            lua.clib.lua_getfield(state.state, -1, "component_hash");
            const cstr = lua.clib.lua_tolstring(state.state, 1, null);
            const str = std.mem.cStrToSlice(u8, cstr);
            const hash = try std.fmt.parseInt(u64, str, 10);
            // pop the hash
            try state.pop();
            components[index - 1][cindex - 1] = hash;
        }
    }
    // pop the table
    try state.pop();
    return .{
        .allocator = allocator,
        .system = system,
        .components = components,
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
