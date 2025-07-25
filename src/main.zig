const std = @import("std");
const lua = @import("lua_lib");
const Game = @import("game.zig").Game;
const imgui = @import("imgui/root.zig");
const Scene = @import("scene.zig").Scene;

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
    try runGame(gpa.allocator());
    //try testLua(gpa.allocator());
    //try testLoad(gpa.allocator());
}

fn runGame(allocator: std.mem.Allocator) !void {
    var game = try Game.init(allocator, .{ .window = .{ .targetFps = 60, .title = "Hello?", .size = .{
        .width = 1080,
        .height = 720,
    } } });
    defer game.deinit();
    var scene = Scene.init(0, allocator);
    const text: [:0]const u8 = "hello";
    const title: [:0]u8 = try scene.scene_allocator.allocSentinel(u8, text.len, 0);
    @memcpy(title, text);
    try scene.allocComponent("imgui:button", imgui.components.Button{
        .clicked = false,
        .pos = .{ .x = 50.0, .y = 50.0 },
        .size = .{ .x = 200.0, .y = 100.0 },
        .title = @ptrCast(title),
    });
    try game.setInitialScene(scene);
    try game.addSystem(imgui.systems.draw_imgui);
    try game.addSystem(print_on_button_click);

    try game.run();
}

fn print_on_button_click(game: *Game) void {
    for (game.currentScene.?.components.items) |*comp| {
        if (std.mem.eql(u8, comp.name, "imgui:button")) {
            const button: *imgui.components.Button = @alignCast(@ptrCast(comp.pointer));
            if (button.clicked) {
                std.debug.print("The button has been clicked\n", .{});
            }
        }
    }
}
