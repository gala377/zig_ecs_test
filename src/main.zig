const std = @import("std");

const lua = @import("lua_lib");
const luac = lua.clib;

const ecs = @import("ecs");
const Component = ecs.Component;
const Game = ecs.Game;
const GameActions = ecs.game.GameActions;
const imgui = ecs.imgui;
const Scene = ecs.Scene;

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

    try ecs.game.addDefaultPlugins(&game);
    try imgui.addImguiPlugin(&game);

    const text: [:0]const u8 = "hello";
    const title: [:0]u8 = try game.allocator.allocSentinel(u8, text.len, 0);
    @memcpy(title, text);

    const close_text: [:0]const u8 = "Close";
    const close_title: [:0]u8 = try game.allocator.allocSentinel(u8, close_text.len, 0);
    @memcpy(close_title, close_text);

    try game.addSystems(.{
        print_on_button_click,
        close_on_button,
    });

    _ = try game.newGlobalEntity(.{
        imgui.components.Button{
            .pos = .{ .x = 50.0, .y = 50.0 },
            .size = .{ .x = 200.0, .y = 100.0 },
            .title = @ptrCast(title),
        },
        ButtonLog{},
    });
    _ = try game.newGlobalEntity(.{
        imgui.components.Button{
            .pos = .{ .x = 50.0, .y = 150.0 },
            .size = .{ .x = 200.0, .y = 100.0 },
            .title = @ptrCast(close_title),
        },
        ButtonClose{},
    });

    const scene = try Scene.init(game.newId(), allocator);
    try game.setInitialScene(scene);

    try game.run();
}

fn print_on_button_click(game: *Game) void {
    var iter = game.query(.{ imgui.components.Button, ButtonLog });
    const button: *imgui.components.Button, _ = iter.single();
    if (button.clicked) {
        std.debug.print("The button has been clicked\n", .{});
    }
}

fn close_on_button(game: *Game) void {
    var iter = game.query(.{ imgui.components.Button, ButtonClose });
    var game_action_iter = game.query(.{GameActions});
    const button, _ = iter.single();
    var game_actions = game_action_iter.single()[0];
    if (button.clicked) {
        game_actions.should_close = true;
    }
}

const ButtonLog = struct {
    pub usingnamespace Component(ButtonLog);
};

const ButtonClose = struct {
    pub usingnamespace Component(ButtonClose);
};
