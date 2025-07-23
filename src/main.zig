const std = @import("std");
const lua = @import("lua_lib");
const Game = @import("game.zig").Game;

const luac = lua.clib;
const commands = @import("commands.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{
        .safety = true,
        .retain_metadata = true,
    }).init;
    defer {
        switch (gpa.deinit()) {
            .leak => {
                std.debug.print("Leaks found!\n", .{});
            },
            else => {
                std.debug.print("no leaks found\n", .{});
            },
        }
    }
    // runGame(gpa.allocator());
    //try testLua(gpa.allocator());
    try testCommands(gpa.allocator());
    //try testLoad(gpa.allocator());
}

fn runGame(alloactor: std.mem.Allocator) !void {
    var game = try Game.init(alloactor, .{ .window = .{ .targetFps = 60, .title = "Hello?", .size = .{
        .width = 1080,
        .height = 720,
    } } });
    defer game.deinit();
    try game.run();
}

fn testLoad(allocator: std.mem.Allocator) !void {
    var state = try lua.State.init(allocator);
    defer state.deinit();
    try state.load(
        \\ return {"err", {"hello", size = {1, 2}}};
    );
    try state.pop();
}

fn testLua(allocator: std.mem.Allocator) !void {
    var state = try lua.State.init(allocator);
    defer state.deinit();
    try state.load("return \"12345\"");
    var len: usize = 0;
    const string = luac.lua_tolstring(state.state, -1, &len);
    const rawlen = luac.lua_rawlen(state.state, -1);
    std.debug.print("string is {s}\n", .{string});
    std.debug.print("size of the string is {}\n, rawlen is {}\n", .{ len, rawlen });
}

fn testCommands(allocator: std.mem.Allocator) !void {
    var state = try lua.State.init(allocator);
    defer state.deinit();
    try state.load(
        \\ return {
        \\    { "spawn", {
        \\         "raygui:button", 
        \\          title = "hello",  
        \\          size = {100, 200},
        \\          pos = {1, 2},
        \\          callback = function() end,
        \\      } },
        \\    { "app:log", "hello" }
        \\  };
    );
    const ref = try state.makeRef();
    defer ref.release();
    const parsed = try commands.getCommands(ref, state, allocator);
    // free commands
    defer commands.deinitSlice(parsed, allocator);

    std.debug.print("Commands len is {}\n", .{parsed.len});
    const stackSize = state.stackSize();
    std.debug.print("Stack size is {}\n", .{stackSize});
    switch (parsed[0]) {
        .Spawn => |spw| switch (spw) {
            .RayGui => |rg| switch (rg) {
                .Button => |args| {
                    std.debug.print("got spawn raygui:button with {any}\n", .{args});
                },
            },
        },
        else => @panic("oh well\n"),
    }
    std.debug.print("All {any}\n", .{parsed});
}
