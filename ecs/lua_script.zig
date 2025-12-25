const std = @import("std");

const lua = @import("lua_lib");
const ecs = @import("root.zig");
const clua = lua.clib;

const Component = @import("component.zig").Component;
const Query = @import("game.zig").Query;
const Without = @import("game.zig").Without;
const Resource = @import("resource.zig").Resource;
const LuaRuntime = ecs.runtime.components.LuaRuntime;
const Commands = ecs.Commands;
const EntityId = ecs.EntityId;

pub const Initialized = struct {
    pub const component_info = Component(Initialized);
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

    pub fn runScriptInit(self: *LuaScript) void {
        _ = clua.lua_rawgeti(self.thread, clua.LUA_REGISTRYINDEX, self.object.ref);
        _ = clua.lua_getfield(self.thread, -1, "Init");
        clua.lua_pushvalue(self.thread, -2);

        var n_results: i32 = 0;
        const status = clua.lua_resume(self.thread, null, 1, &n_results);
        switch (status) {
            clua.LUA_YIELD => {
                std.debug.print("got lua yield", .{});
            },
            clua.LUA_OK => {
                std.debug.print("executed no problems\n", .{});
            },
            else => {
                @panic("unexpected lua status");
            },
        }
    }

    pub fn deinit(self: *LuaScript) void {
        self.object.release();
        self.thread_ref.release();
    }
};

fn zig_yield(L: ?*clua.lua_State) callconv(.c) i32 {
    _ = clua.lua_yieldk(L, 0, 0, null);

    // 4. Return the number of results pushed
    return 0;
}

pub fn runInitScripts(
    commands: Commands,
    runtime: Resource(LuaRuntime),
    scripts: *Query(.{ EntityId, LuaScript, Without(.{Initialized}) }),
) void {
    const state = runtime.get().lua.state;
    clua.lua_pushcfunction(@as(*clua.lua_State, @ptrCast(state)), zig_yield);
    clua.lua_setglobal(@ptrCast(state), "zig_yield");
    const cmd: *ecs.commands = commands.get();

    while (scripts.next()) |components| {
        const entity_id, const script = components;
        script.runScriptInit();
        cmd.addComponents(entity_id.*, .{Initialized{}}) catch @panic("could not add component");
    }
}
