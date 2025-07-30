const std = @import("std");

const ecs = @import("ecs");
const Component = ecs.Component;
const Game = ecs.Game;
const GameActions = ecs.game.GameActions;
const Query = ecs.Query;
const system = ecs.system;
const imgui = ecs.imgui;
const Button = imgui.components.Button;

pub fn installMainLogic(game: *Game) !void {
    try game.addSystems(.{
        system(print_on_button),
        system(close_on_button),
    });

    const title: [:0]u8 = try game.allocator.dupeZ(u8, "Click for log");
    const close_title: [:0]u8 = try game.allocator.dupeZ(u8, "Close");

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
            .visible = false,
            .title = @ptrCast(close_title),
        },
        ButtonClose{},
    });
}

fn print_on_button(
    iter: *Query(.{ Button, ButtonLog }),
    close_iter: *Query(.{ Button, ButtonClose }),
) void {
    const button, _ = iter.single();
    if (button.clicked) {
        const close_button, _ = close_iter.single();
        close_button.visible = !close_button.visible;
        std.debug.print("The button has been clicked\n", .{});
    }
}

fn close_on_button(
    iter: *Query(.{ imgui.components.Button, ButtonClose }),
    game_action_iter: *Query(.{GameActions}),
) void {
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
