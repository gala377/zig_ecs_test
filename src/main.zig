const std = @import("std");

const lua = @import("lua_lib");
const luac = lua.clib;

const ecs = @import("ecs");
const Component = ecs.Component;
const Game = ecs.Game;
const GameActions = ecs.game.GameActions;
const imgui = ecs.imgui;
const Scene = ecs.Scene;

const logic = @import("logic.zig");

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
    try runGame(gpa.allocator());
}

fn runGame(allocator: std.mem.Allocator) !void {
    var game = try Game.init(allocator, .{});
    defer game.deinit();

    const scene = try game.newScene();
    try game.setInitialScene(scene);

    try ecs.game.addDefaultPlugins(
        &game,
        true,
        .{
            .targetFps = 60,
            .title = "Hello?",
            .size = .{
                .width = 1080,
                .height = 720,
            },
        },
    );
    try imgui.install(&game, .{ .show_fps = true });
    try imgui.exportLua(&game);
    try logic.install(&game);

    try game.run();
}
