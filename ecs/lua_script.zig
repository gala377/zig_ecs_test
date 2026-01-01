const std = @import("std");

const lua = @import("lua_lib");
const ecs = @import("root.zig");
const clua = lua.clib;

const Component = @import("component.zig").Component;
const Query = @import("game.zig").Query;
const Without = @import("game.zig").Without;
const Resource = @import("resource.zig").Resource;
const LuaRuntime = ecs.runtime.lua_runtime;
const Commands = ecs.Commands;
const EntityId = ecs.EntityId;
const FrameAllocator = ecs.runtime.allocators.FrameAllocator;
const Game = ecs.Game;
const system = ecs.system;

pub const Initialized = struct {
    pub const component_info = Component(Initialized);
    marker: ecs.Marker = .empty,
};

pub const LuaScript = struct {
    pub const component_info = Component(LuaScript);

    object: lua.Ref,
    thread: *clua.lua_State,
    thread_ref: lua.Ref,
    allocator: std.mem.Allocator,

    pub fn fromLua(allocator: std.mem.Allocator, state: lua.State, object: lua.Ref) !LuaScript {
        const thread = clua.lua_newthread(@ptrCast(state.state)) orelse @panic("could not create thread");
        const thread_ref = try state.makeRef();
        return .{
            .object = object,
            .thread = thread,
            .thread_ref = thread_ref,
            .allocator = allocator,
        };
    }

    // Returns true if the function exists.
    // Otherwise returns false and clears the stack.
    pub fn pushScripInitCoroutine(self: *LuaScript) bool {
        _ = clua.lua_rawgeti(self.thread, clua.LUA_REGISTRYINDEX, self.object.ref);
        const t = clua.lua_getfield(self.thread, -1, "Init");
        if (t == clua.LUA_TNIL) {
            clua.lua_pop(self.thread, 2);
            return false;
        }
        clua.lua_rotate(self.thread, -2, 1);
        return true;
    }

    pub fn pushScriptUpdateCoroutine(self: *LuaScript) bool {
        _ = clua.lua_rawgeti(self.thread, clua.LUA_REGISTRYINDEX, self.object.ref);
        const t = clua.lua_getfield(self.thread, -1, "Update");
        if (t == clua.LUA_TNIL) {
            clua.lua_pop(self.thread, 2);
            return false;
        }
        clua.lua_rotate(self.thread, -2, 1);
        return true;
    }

    pub fn runScriptCoroutine(self: *LuaScript, nargs: c_int) ?*ScriptCommand {
        var n_results: i32 = 0;
        const status = clua.lua_resume(self.thread, null, nargs, &n_results);
        switch (status) {
            clua.LUA_YIELD => {
                if (n_results != 1) {
                    @panic("expected 1 value returned on yield");
                }
                const cmd: *ScriptCommand = @ptrCast(@alignCast(clua.lua_touserdata(self.thread, -1) orelse @panic("not userdata")));
                clua.lua_pop(self.thread, 1);
                return cmd;
            },
            clua.LUA_OK => {
                return null;
            },
            else => |x| {
                var strlen: usize = 0;
                const str = clua.lua_tolstring(self.thread, -1, &strlen);

                std.debug.print("STATE GIVEN IS {} msg is {s}\n", .{ x, str[0..strlen] });
                @panic("unexpected lua status");
            },
        }
        @panic("unreachable");
    }

    pub fn deinit(self: *LuaScript) void {
        self.object.release();
        self.thread_ref.release();
    }
};

const ScriptCommand = union(enum) {
    print: []const u8,
};

fn zig_yield(L: ?*clua.lua_State) callconv(.c) i32 {
    if (clua.lua_gettop(L) != 1) {
        @panic("Expected at least one argument which is a string");
    }
    var strlen: usize = 0;
    const argument = clua.lua_tolstring(L, -1, @ptrCast(&strlen));
    const upvalue_idx = clua.lua_upvalueindex(1);
    clua.lua_pushvalue(L, upvalue_idx);
    if (!clua.lua_islightuserdata(L, upvalue_idx)) {
        @panic("Not userdata");
    }
    const allocator: *std.mem.Allocator = @ptrCast(@alignCast(clua.lua_touserdata(L, upvalue_idx) orelse @panic("not userdata")));
    const msg = allocator.dupe(u8, argument[0..strlen]) catch @panic("could not allocate string");
    const cmd = allocator.create(ScriptCommand) catch @panic("could not allocate command");
    cmd.* = ScriptCommand{
        .print = msg,
    };
    clua.lua_pushlightuserdata(L, @ptrCast(cmd));
    return clua.lua_yieldk(L, 1, 0, null);
}

pub fn runInitScripts(
    commands: Commands,
    runtime: Resource(LuaRuntime),
    allocator: Resource(FrameAllocator),
    scripts: *Query(.{ EntityId, LuaScript, Without(.{Initialized}) }),
) void {
    // TODO: Those functions should be set in in a different setup system
    // or in the plugin or something.
    const state = runtime.get().lua.state;
    const lstate = @as(*clua.lua_State, @ptrCast(state));
    const alloc = &allocator.get().allocator;

    // TODO: We can also technically, instead of pushing just allocator
    // also push *ScriptCommand as this will make it so that
    // we don't have to allocate this in every zig funtion just to return
    // it, we can just pass this pointer around and zig functions will overwrite it
    clua.lua_pushlightuserdata(lstate, @ptrCast(alloc));
    clua.lua_pushcclosure(lstate, zig_yield, 1);
    clua.lua_setglobal(lstate, "zig_yield");
    const cmd: *ecs.commands = commands.get();

    while (scripts.next()) |components| {
        const entity_id, const script = components;
        if (script.pushScripInitCoroutine()) {
            var nargs: c_int = 1;
            while (script.runScriptCoroutine(nargs)) |command| {
                switch (command.*) {
                    .print => |msg| {
                        std.debug.print("Made it {s}\n", .{msg});
                        nargs = 0;
                    },
                }
            }
        }
        cmd.addComponents(entity_id.*, .{Initialized{}}) catch @panic("could not add component");
    }
}

pub fn runUpdateScripts(
    runtime: Resource(LuaRuntime),
    allocator: Resource(FrameAllocator),
    scripts: *Query(.{ LuaScript, Initialized }),
) void {
    // TODO: Those functions should be set in in a different setup system
    // or in the plugin or something.
    const state = runtime.get().lua.state;
    const lstate = @as(*clua.lua_State, @ptrCast(state));
    const alloc = &allocator.get().allocator;

    // TODO: We can also technically, instead of pushing just allocator
    // also push *ScriptCommand as this will make it so that
    // we don't have to allocate this in every zig funtion just to return
    // it, we can just pass this pointer around and zig functions will overwrite it
    clua.lua_pushlightuserdata(lstate, @ptrCast(alloc));
    clua.lua_pushcclosure(lstate, zig_yield, 1);
    clua.lua_setglobal(lstate, "zig_yield");

    while (scripts.next()) |components| {
        const script, _ = components;
        if (script.pushScriptUpdateCoroutine()) {
            var nargs: c_int = 1;
            while (script.runScriptCoroutine(nargs)) |command| {
                switch (command.*) {
                    .print => |msg| {
                        std.debug.print("Made it {s}\n", .{msg});
                        nargs = 0;
                    },
                }
            }
        }
    }
}

pub fn install(game: *Game) !void {
    try game.addSystems(.update, &.{
        system(runInitScripts),
        system(runUpdateScripts),
    });
}
