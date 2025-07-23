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
    Log: [:0]const u8,

    pub fn deinit(self: AppCommand, allocator: std.mem.Allocator) void {
        switch (self) {
            .Close => {},
            .MakeCommand => |m| {
                allocator.free(m.command);
                m.callback.release();
            },
            .Log => |l| {
                allocator.free(l);
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
    return getCommandsImpl(state, allocator);
}

fn getCommandsImpl(L: State, allocator: std.mem.Allocator) ![]Command {
    const tableIndex = -2;
    const valueIndex = -1;
    startExpectNext(L, tableIndex) catch {
        return &.{};
    };
    assertType(L, valueIndex, .table) catch {
        const command = try parseSingleCommand(L, allocator);
        var table = try allocator.alloc(Command, 1);
        table[0] = command;
        return table;
    };
    return parseCommands(L, allocator);
}

fn parseCommands(L: State, allocator: std.mem.Allocator) ![]Command {
    std.debug.print("1\n", .{});
    const valueIndex = -1;
    const tableIndex = -2;
    // the stach is [ -1: value | -2: key | -3: table ]
    const len: usize = @intCast(luac.lua_rawlen(L.state, tableIndex - 1));
    std.debug.print("1 size = {}\n", .{len});

    var parsedCommands: usize = 0;
    const commands = allocator.alloc(Command, len) catch |err| {
        popKeyValue(L);
        return err;
    };
    std.debug.print("1\n", .{});
    errdefer {
        // free only parsed commands otherwise its UB
        for (0..parsedCommands) |i| {
            commands[i].deinit(allocator);
        }
        allocator.free(commands);
    }
    //we know that value is a table so we can parse it as a command
    while (true) {
        std.debug.print("2 parsed={}\n", .{parsedCommands});
        startExpectNext(L, tableIndex) catch |err| {
            // empty table, lets skip
            popKeyValue(L);
            return err;
        };
        std.debug.print("2.0\n", .{});
        const command = parseSingleCommand(L, allocator) catch |err| {
            std.debug.print("2.1 {}\n", .{err});
            popKeyValue(L);
            std.debug.print("2.2\n", .{});
            return err;
        };
        std.debug.print("3\n", .{});
        commands[parsedCommands] = command;
        parsedCommands += 1;
        std.debug.print("4\n", .{});
        expectNext(L, tableIndex) catch {
            std.debug.print("empty, breaking parsed={}\n", .{parsedCommands});
            break;
        };

        std.debug.print("5\n", .{});
        assertType(L, valueIndex, .table) catch |err| {
            popKeyValue(L);
            return err;
        };

        std.debug.print("6\n", .{});
    }
    std.debug.print("7\n", .{});
    return commands;
}

fn parseSingleCommand(L: State, allocator: std.mem.Allocator) !Command {
    // assume key and value are already on the stack
    const tableIndex = -2;
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
        // no need to pop, table is empty
        try expectNext(L, tableIndex);
    }

    if (std.mem.eql(u8, cmd, "app:log")) {
        // cmd is invalidated;
        // no need to pop, table is empty
        try expectNext(L, tableIndex);
        assertType(L, valueIndex, .string) catch |err| {
            popKeyValue(L);
            return err;
        };
        const msg = getString(L, valueIndex, allocator) catch |err| {
            popKeyValue(L);
            return err;
        };
        return .{ .App = .{ .Log = msg } };
    }

    if (std.mem.eql(u8, cmd, "spawn")) {
        // cmd is invalidated

        // no need to pop, table is empty
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
            return parseSpawnImguiButton(L, allocator);
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

pub const Vec2 = struct {
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

inline fn parseSpawnImguiButton(L: State, allocator: std.mem.Allocator) !Command {
    const tableIndex = -2;
    const keyIndex = -2;
    const valueIndex = -1;

    popValue(L);
    var title: ?[:0]const u8 = null;
    errdefer {
        if (title) |t| {
            allocator.free(t);
        }
    }
    var position: ?Vec2 = null;
    var size: ?Vec2 = null;
    var callback: ?Ref = null;
    errdefer {
        if (callback) |c| {
            c.release();
        }
    }
    while (luac.lua_next(L.state, tableIndex) != 0) {
        errdefer {
            popKeyValue(L);
            popKeyValue(L);
        }
        try assertType(L, keyIndex, .string);

        const keyspan = stringView(L, keyIndex);
        if (std.mem.eql(u8, keyspan, "title")) {
            try assertType(L, valueIndex, .string);
            title = try getString(L, valueIndex, allocator);
        } else if (std.mem.eql(u8, keyspan, "pos")) {
            position = try parseVec2(L);
        } else if (std.mem.eql(u8, keyspan, "size")) {
            size = try parseVec2(L);
        } else if (std.mem.eql(u8, keyspan, "callback")) {
            // pops the value from the top, in this case it is a value
            try assertType(L, valueIndex, .function);
            callback = try L.makeRef();
            // we need to continue because we alredy popped the value, so we cannot pop again
            continue;
        } else {
            return error.unknownKeyWordArgument;
        }
        popValue(L);
    }

    // we are asserting that {"spawn", {...}, ...} is finished
    // if its not there are now
    assertFinished(L, tableIndex) catch |err| {
        popKeyValue(L);
        return err;
    };
    if (title == null or position == null or size == null or callback == null) {
        // no need to pop, we know that there are no more arguments on the stack
        return error.missingKeyWordArgument;
    }
    // uff everything is okay we can finally pop the actual table;
    // which our caller should do
    return .{ .Spawn = .{ .RayGui = .{
        .Button = .{
            .title = title.?,
            .position = position.?,
            .callback = callback.?,
            .size = size.?,
        },
    } } };
}
