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
iters_allocator: std.heap.ArenaAllocator,

scopes: []DynamicScope,
iters: []DynamicQuery,

pub fn fromLua(state: lua.State, allocator: std.mem.Allocator) !Self {
    const from_lua = try readComponentsFromLau(state, allocator);

    const iter_allocator = std.heap.ArenaAllocator.init(allocator);
    return .{
        .allocator = allocator,
        .system = from_lua.system,
        .components = @ptrCast(from_lua.components),
        .iters_allocator = iter_allocator,
        .scopes = try allocator.alloc(DynamicScope, from_lua.components.len),
        .iters = try allocator.alloc(DynamicQuery, from_lua.components.len),
    };
}

pub const LuaSystemErrors = error{
    expectedTable,
    expectedFunction,
    expectedInteger,
    unableToMakeCallback,
    outOfMemory,
    stackEmpty,
};

fn readComponentsFromLau(state: lua.State, allocator: std.mem.Allocator) LuaSystemErrors!struct { system: lua.Ref, components: [][]ComponentId } {
    if (lua.clib.lua_type(state.state, 1) != lua.clib.LUA_TTABLE) {
        return LuaSystemErrors.expectedTable;
    }
    if (lua.clib.lua_getfield(state.state, 1, "callback") != lua.clib.LUA_TFUNCTION) {
        return LuaSystemErrors.expectedFunction;
    }
    const system = state.makeRef() catch return LuaSystemErrors.unableToMakeCallback;
    if (lua.clib.lua_getfield(state.state, 1, "queries") != lua.clib.LUA_TTABLE) {
        return LuaSystemErrors.expectedTable;
    }
    const queries_len = lua.clib.lua_rawlen(state.state, -1);
    const components = allocator.alloc([]ComponentId, @intCast(queries_len)) catch return LuaSystemErrors.outOfMemory;
    std.debug.assert(components.len == queries_len);
    for (1..queries_len + 1) |index| {
        if (lua.clib.lua_geti(state.state, -1, @intCast(index)) != lua.clib.LUA_TTABLE) {
            return LuaSystemErrors.expectedTable;
        }
        // top of the stack
        const components_len = lua.clib.lua_rawlen(state.state, -1);
        components[index - 1] = allocator.alloc(ComponentId, @intCast(components_len)) catch return LuaSystemErrors.outOfMemory;
        for (1..components_len + 1) |cindex| {
            if (lua.clib.lua_geti(state.state, -1, @intCast(cindex)) != lua.clib.LUA_TTABLE) {
                return LuaSystemErrors.expectedTable;
            }
            // top is the component thing now
            if (lua.clib.lua_getfield(state.state, -1, "component_hash") != lua.clib.LUA_TNUMBER) {
                return LuaSystemErrors.expectedInteger;
            }
            var is_num: c_int = undefined;
            const int_hash = lua.clib.lua_tointegerx(state.state, -1, &is_num);
            if (is_num == 0) {
                return LuaSystemErrors.expectedInteger;
            }
            const hash: u64 = @bitCast(int_hash);
            // pop the hash
            state.pop() catch return LuaSystemErrors.stackEmpty;
            // pop the component
            state.pop() catch return LuaSystemErrors.stackEmpty;
            components[index - 1][cindex - 1] = hash;
        }
        // pop the components table
        state.pop() catch return LuaSystemErrors.stackEmpty;
    }
    // pop the queries table
    state.pop() catch return LuaSystemErrors.stackEmpty;
    // pop the system builder
    state.pop() catch return LuaSystemErrors.stackEmpty;
    std.debug.assert(state.stackSize() == 0);
    return .{
        .system = system,
        .components = components,
    };
}

pub fn run(self: *Self, game: *Game, state: lua.State) !void {
    for (self.components, 0..) |q, i| {
        self.scopes[i] = try game.dynamicQueryScopeOpts(q, .{ .allocator = self.iters_allocator.allocator() });
    }
    for (self.scopes, 0..) |*s, i| {
        self.iters[i] = s.iter();
    }
    state.pushRef(self.system);
    for (self.iters) |*iter| {
        iter.luaPush(state.state);
    }
    lua.clib.lua_callk(state.state, @intCast(self.iters.len), 0, 0, null);
    if (!self.iters_allocator.reset(.retain_capacity)) {
        return error.couldNotRestAllocator;
    }
}

pub fn deinit(self: *Self) void {
    self.system.release();
    for (self.components) |comp| {
        self.allocator.free(comp);
    }
    self.allocator.free(self.components);
    self.allocator.free(self.scopes);
    self.allocator.free(self.iters);
    self.iters_allocator.deinit();
}
