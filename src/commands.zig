const std = @import("std");

const luac = @import("lua_lib").clib;
const Ref = @import("lua_lib").Ref;
const State = @import("lua_lib").State;

const imgui = @import("imgui/root.zig");

pub const Command = union(enum) {
    Spawn: SpawnCommand,
    App: AppCommand,
    UserDefined: UserDefinedCommand,

    pub fn deinit(self: Command, allocator: std.mem.Allocator) void {
        switch (self) {
            .Spawn => |s| {
                s.deinit(allocator);
            },
            .App => |a| {
                a.deinit(allocator);
            },
            .UserDefined => |u| {
                u.deinit(allocator);
            },
        }
    }
};

pub const SpawnCommand = union(enum) {
    RayGui: RayGuiObjects,

    pub fn deinit(self: SpawnCommand, allocator: std.mem.Allocator) void {
        switch (self) {
            .RayGui => |r| {
                r.deinit(allocator);
            },
        }
    }
};

pub const AppCommand = union(enum) {
    Close,
    MakeCommand: struct {
        command: []const u8,
        callback: Ref,
    },

    pub fn deinit(self: AppCommand, allocator: std.mem.Allocator) void {
        switch (self) {
            .Close => {},
            .MakeCommand => |m| {
                allocator.free(m.command);
                m.callback.release();
            },
        }
    }
};

pub const UserDefinedCommand = struct {
    command: []const u8,
    callback: Ref,

    pub fn deinit(self: UserDefinedCommand, allocator: std.mem.Allocator) void {
        allocator.free(self.command);
        self.callback.release();
    }
};

pub const RayGuiObjects = union(enum) {
    Button: imgui.Button.ScriptArgs,

    pub fn deinit(self: RayGuiObjects, allocator: std.mem.Allocator) void {
        switch (self) {
            .Button => |b| {
                b.deinit(allocator);
            },
        }
    }
};

pub fn getCommands(table: Ref, state: State, allocator: std.mem.Allocator) ![]Command {
    state.pushRef(table);
    defer state.popUnchecked();
    const commands = getCommandsImpl(state, allocator);
    return commands;
}

fn getCommandsImpl(L: State, allocator: std.mem.Allocator) ![]Command {
    const tableIndex = -2;
    const valueIndex = -1;
    luac.lua_pushnil(L.state);
    if (luac.lua_next(L.state, tableIndex) == 0) {
        // empty table, no commands
        return &.{};
    }
    if (luac.lua_type(L.state, valueIndex) != luac.LUA_TTABLE) {
        const command = try parseSingleCommand(L, allocator);
        var table = try allocator.alloc(Command, 1);
        table[0] = command;
        return table;
    }
    return error.MultipleCommandsNotSupported;
    // it is a table of tables
}
fn parseSingleCommand(L: State, allocator: std.mem.Allocator) !Command {
    // assume key and value are already on the stack
    const tableIndex = -2;
    const keyIndex = -2;
    const valueIndex = -1;
    assertType(L, valueIndex, .string) catch |err| {
        // expected command
        popKeyValue(L);
        return err;
    };
    const cmd = stringView(L, valueIndex);

    if (std.mem.eql(u8, cmd, "app:close")) {
        // cmd is invalidated
        assertFinished(L, tableIndex) catch |err| {
            popKeyValue(L);
            return err;
        };
        return .{
            .App = .Close,
        };
    }
    if (std.mem.eql(u8, cmd, "app:makecommand")) {
        // cmd is invalidated;
        popValue(L);
        if (luac.lua_next(L.state, tableIndex) == 0) {
            return error.expectedArgument;
        }
    }

    if (std.mem.eql(u8, cmd, "spawn")) {
        // cmd is invalidated
        try expectNext(L, tableIndex);

        // value is now a table of arguments
        assertType(L, valueIndex, .table) catch |err| {
            popKeyValue(L);
            return err;
        };
        // we don't need to pop a value yet, we will use it to
        // recursively iterate over the arguments
        startExpectNext(L, tableIndex) catch |err| {
            popKeyValue(L);
            return err;
        };

        assertType(L, valueIndex, .string) catch |err| {
            // pop key and value that have been pushed by lua_next
            // as well as table and key pushed by previous iteration
            pop(L, 4);
            return err;
        };

        const obj = stringView(L, valueIndex);
        if (std.mem.eql(u8, obj, "raygui:button")) {
            luac.lua_pop(L.state, 1);

            // TODO: techincally it would be nice to errdeffer this otherwise we have a leak
            // but we would also need to be aware of errdeffering up the stack as we would
            // return those allocations.
            var title: ?[:0]const u8 = null;
            var position: ?struct { x: f32, y: f32 } = null;
            var size: ?struct { x: f32, y: f32 } = null;
            var callback: ?Ref = null;
            std.debug.print("trying to move\n", .{});
            while (luac.lua_next(L.state, tableIndex) != 0) {
                std.debug.print("moved\n", .{});
                if (luac.lua_type(L.state, keyIndex) != luac.LUA_TSTRING) {
                    std.debug.print("the key is not a string\n", .{});
                    luac.lua_pop(L.state, 4);
                    return error.expectedKeyWordArgument;
                }

                std.debug.print("key is a string\n", .{});
                const key = luac.lua_tolstring(L.state, keyIndex, null);
                const keyspan = std.mem.span(key);
                std.debug.print("key is {s}\n", .{keyspan});
                if (std.mem.eql(u8, keyspan, "title")) {
                    if (luac.lua_type(L.state, valueIndex) != luac.LUA_TSTRING) {
                        luac.lua_pop(L.state, 4);
                        return error.expectedString;
                    }
                    title = getString(L, valueIndex, allocator) catch |err| {
                        luac.lua_pop(L.state, 4);
                        return err;
                    };
                } else if (std.mem.eql(u8, keyspan, "pos")) {
                    const parsed = parseVec2(L) catch |err| {
                        luac.lua_pop(L.state, 4);
                        return err;
                    };
                    position = .{ .x = parsed.x, .y = parsed.y };
                } else if (std.mem.eql(u8, keyspan, "size")) {
                    const parsed = parseVec2(L) catch |err| {
                        luac.lua_pop(L.state, 4);
                        return err;
                    };
                    size = .{ .x = parsed.x, .y = parsed.y };
                } else if (std.mem.eql(u8, keyspan, "callback")) {
                    // pops the value from the top, in this case it is a value
                    if (luac.lua_type(L.state, valueIndex) != luac.LUA_TFUNCTION) {
                        luac.lua_pop(L.state, 4);
                        return error.expectedFunction;
                    }
                    const ref = try L.makeRef();
                    callback = ref;
                    // we need to continue because we alredy popped the value, so we cannot pop again
                    continue;
                } else {
                    luac.lua_pop(L.state, 4);
                    return error.unknownKeyWordArgument;
                }

                luac.lua_pop(L.state, 1);
            }
            assertFinished(L, tableIndex) catch |err| {
                popKeyValue(L);
                return err;
            };
            if (title == null or position == null or size == null or callback == null) {
                popKeyValue(L);
                return error.missingKeyWordArgument;
            }
            // uff everythin is okay we can finally pop the actual table;
            // which our caller should do
            const button: imgui.Button.ScriptArgs = .{
                .title = title.?,
                .position = .{ .x = position.?.x, .y = position.?.y },
                .callback = callback.?,
                .size = .{ .x = size.?.x, .y = size.?.y },
            };
            return .{ .Spawn = .{ .RayGui = .{
                .Button = button,
            } } };
        }

        // pop key and value that have been pushed by lua_next
        // as well as table and key pushed by previous iteration
        pop(L, 4);
        return error.unknownObjectToSpawn;
    }

    // pop key and value that have been pushed by lua_next
    popKeyValue(L);
    return error.undefinedCommand;
}

fn parseVec2(L: State) !Vec2 {
    const valueIndex = -1;
    const tableIndex = -2;
    try assertType(L, valueIndex, .table);

    // Extract X
    try startExpectNext(L, tableIndex);
    assertType(L, valueIndex, .number) catch |err| {
        popKeyValue(L);
        return err;
    };
    const x = luac.lua_tonumberx(L.state, valueIndex, null);

    // Extract Y
    try expectNext(L, tableIndex);
    assertType(L, valueIndex, .number) catch |err| {
        popKeyValue(L);
        return err;
    };
    const y = luac.lua_tonumberx(L.state, valueIndex, null);

    // sanity check
    assertFinished(L, tableIndex) catch |err| {
        popKeyValue(L);
        return err;
    };
    return .{ .x = @floatCast(x), .y = @floatCast(y) };
}

const Vec2 = struct {
    x: f32,
    y: f32,
};

pub fn deinitSlice(cmds: []Command, allocator: std.mem.Allocator) void {
    for (cmds) |*cmd| {
        cmd.deinit(allocator);
    }
    allocator.free(cmds);
}

fn getString(L: State, index: c_int, allocator: std.mem.Allocator) ![:0]const u8 {
    var slen: usize = 0;
    const str = luac.lua_tolstring(L.state, index, &slen);
    if (str == null) {
        return error.invalidLuaString;
    }
    return allocator.dupeZ(u8, str[0..slen]) catch |err| {
        return err;
    };
}

inline fn assertType(L: State, index: c_int, t: LuaTypes) !void {
    if (luac.lua_type(L.state, index) != @intFromEnum(t)) {
        return error.luaTypeError;
    }
}

inline fn assertFinished(L: State, index: c_int) !void {
    popValue(L);
    if (luac.lua_next(L.state, index) != 0) {
        return error.unexpectedArgument;
    }
}

inline fn pop(L: State, num: c_int) void {
    luac.lua_pop(L.state, num);
}

inline fn popValue(L: State) void {
    pop(L, 1);
}

inline fn popKeyValue(L: State) void {
    pop(L, 2);
}

inline fn expectNext(L: State, tindex: c_int) !void {
    popValue(L);
    if (luac.lua_next(L.state, tindex) == 0) {
        return error.expectedArgument;
    }
}

inline fn startExpectNext(L: State, tindex: c_int) !void {
    luac.lua_pushnil(L.state);
    if (luac.lua_next(L.state, tindex) == 0) {
        return error.expectedArgument;
    }
}

const LuaTypes = enum(c_int) {
    string = luac.LUA_TSTRING,
    table = luac.LUA_TTABLE,
    number = luac.LUA_TNUMBER,
    function = luac.LUA_TFUNCTION,
};

inline fn stringView(L: State, index: c_int) []const u8 {
    const command = luac.lua_tolstring(L.state, index, null);
    return std.mem.span(command);
}
