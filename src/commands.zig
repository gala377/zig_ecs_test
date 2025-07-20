const std = @import("std");
const Ref = @import("lua_lib").Ref;
const State = @import("lua_lib").State;
const luac = @import("lua_lib").clib;
const imgui = @import("imgui/root.zig");

pub const Command = union(enum) {
    Spawn: SpawnCommand,
    App: AppCommand,
};

pub const SpawnCommand = union(enum) {
    RayGui: RayGuiObjects,
};

pub const AppCommand = enum {
    Close,
};

pub const RayGuiObjects = union(enum) {
    Button: imgui.Button.ScriptArgs,
};

pub fn getCommands(table: Ref, state: State, allocator: std.mem.Allocator) ![]Command {
    state.pushRef(table);
    const commands = getCommandsImpl(state, allocator) catch |err| {
        try state.pop();
        return err;
    };
    try state.pop();
    return commands;
}

fn getCommandsImpl(L: State, allocator: std.mem.Allocator) ![]Command {
    luac.lua_pushnil(L.state);
    const tableIndex = -2;
    const valueIndex = -1;
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
    if (luac.lua_type(L.state, valueIndex) != luac.LUA_TSTRING) {
        // pop key and value that have been pushed by lua_next
        luac.lua_pop(L.state, 2);
        return error.commandHasToBeString;
    }
    const command = luac.lua_tolstring(L.state, valueIndex, null);
    const cmd: []const u8 = std.mem.span(command);

    if (std.mem.eql(u8, cmd, "app:close")) {
        luac.lua_pop(L.state, 1);
        // cmd is invalidated
        if (luac.lua_next(L.state, tableIndex) != 0) {
            // pop key and value that have been pushed by lua_next
            luac.lua_pop(L.state, 2);
            return error.moreArgumentsThanExpected;
        }
        return .{
            .App = .Close,
        };
    }
    if (std.mem.eql(u8, cmd, "spawn")) {
        std.debug.print("parsing spawn\n", .{});
        luac.lua_pop(L.state, 1);
        std.debug.print("poping value of spawn\n", .{});
        // cmd is invalidated
        if (luac.lua_next(L.state, tableIndex) == 0) {
            std.debug.print("next value does not exist\n", .{});
            return error.expectedArgument;
        }

        std.debug.print("changed value to next\n", .{});
        // value is now a table of arguments
        if (luac.lua_type(L.state, valueIndex) != luac.LUA_TTABLE) {
            std.debug.print("next value is not a lua table\n", .{});
            // pop key and value that have been pushed by lua_next
            luac.lua_pop(L.state, 2);
            return error.expectedTable;
        }
        // we don't need to pop a value yet, we will use it to
        // recursively iterate over the arguments
        luac.lua_pushnil(L.state);
        std.debug.print("iterating arguments table\n", .{});
        if (luac.lua_next(L.state, tableIndex) == 0) {
            std.debug.print("arguments table is empty\n", .{});
            // pop key and value that have been pushed by lua_next from the previous iteration
            luac.lua_pop(L.state, 2);
            return error.expectedArgument;
        }

        std.debug.print("got first argument\n", .{});

        if (luac.lua_type(L.state, valueIndex) != luac.LUA_TSTRING) {
            std.debug.print("object to spawn is not string\n", .{});
            // pop key and value that have been pushed by lua_next
            // as well as table and key pushed by previous iteration
            luac.lua_pop(L.state, 4);
            return error.expectedString;
        }

        std.debug.print("getting object to spawn\n", .{});
        const objc = luac.lua_tolstring(L.state, valueIndex, null);
        const obj: []const u8 = std.mem.span(objc);
        if (std.mem.eql(u8, obj, "raygui:button")) {
            std.debug.print("object is raygui:button, popping the value to get next pair.\n", .{});
            luac.lua_pop(L.state, 1);

            std.debug.print("moving to next argument\n", .{});
            // obj is now invalid

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
                    var slen: usize = 0;
                    const str = luac.lua_tolstring(L.state, valueIndex, &slen);
                    if (str == null) {
                        luac.lua_pop(L.state, 4);
                        return error.invalidLuaString;
                    }
                    const slice = allocator.dupeZ(u8, str[0..slen]) catch |err| {
                        luac.lua_pop(L.state, 4);
                        return err;
                    };
                    title = slice;
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
            std.debug.print("Parsed all keys, popping table with arguments\n", .{});
            // pop the arguments table from the top
            luac.lua_pop(L.state, 1);
            // sanity checks
            if (luac.lua_next(L.state, tableIndex) != 0) {
                std.debug.print("There are more arguments remaining (after spawn)", .{});
                luac.lua_pop(L.state, 2);
                return error.unexpectedArgument;
            }
            if (title == null or position == null or size == null or callback == null) {
                std.debug.print("Not every key has been filled", .{});
                luac.lua_pop(L.state, 2);
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
        luac.lua_pop(L.state, 4);
        return error.unknownObjectToSpawn;
    }

    // pop key and value that have been pushed by lua_next
    luac.lua_pop(L.state, 2);
    return error.undefinedCommand;
}

fn parseVec2(L: State) !Vec2 {
    const valueIndex = -1;
    const tableIndex = -2;
    if (luac.lua_type(L.state, valueIndex) != luac.LUA_TTABLE) {
        return error.expectedTable;
    }
    // Start iteration
    luac.lua_pushnil(L.state);

    // Extract X
    if (luac.lua_next(L.state, tableIndex) == 0) {
        return error.expectedArgument;
    }
    if (luac.lua_type(L.state, valueIndex) != luac.LUA_TNUMBER) {
        luac.lua_pop(L.state, 2);
        return error.expectedNumber;
    }
    const x = luac.lua_tonumberx(L.state, valueIndex, null);

    // next key
    luac.lua_pop(L.state, 1);

    // Extract Y
    if (luac.lua_next(L.state, tableIndex) == 0) {
        return error.expectedArgument;
    }
    if (luac.lua_type(L.state, valueIndex) != luac.LUA_TNUMBER) {
        luac.lua_pop(L.state, 2);
        return error.expectedNumber;
    }
    const y = luac.lua_tonumberx(L.state, valueIndex, null);

    // sanity check
    luac.lua_pop(L.state, 1);
    if (luac.lua_next(L.state, tableIndex) != 0) {
        luac.lua_pop(L.state, 2);
        return error.unexpectedArgument;
    }
    return .{ .x = @floatCast(x), .y = @floatCast(y) };
}

const Vec2 = struct {
    x: f32,
    y: f32,
};

pub fn deinit(cmd: *Command, allocator: std.mem.Allocator) void {
    switch (cmd.*) {
        .App => |*appcmd| switch (appcmd.*) {
            .Close => {
                //nothing allocated, nothing to do
            },
        },
        .Spawn => |*spwncmd| switch (spwncmd.*) {
            .RayGui => |*rgobj| switch (rgobj.*) {
                .Button => |*button| {
                    allocator.free(button.*.title);
                    button.callback.release();
                },
            },
        },
    }
}

pub fn deinitSlice(cmds: []Command, allocator: std.mem.Allocator) void {
    for (cmds) |*cmd| {
        deinit(cmd, allocator);
    }
    allocator.free(cmds);
}
