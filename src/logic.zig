const std = @import("std");

const ecs = @import("ecs");
const Component = ecs.Component;
const Game = ecs.Game;
const GameActions = ecs.game.GameActions;
const Query = ecs.Query;
const system = ecs.system;
const imgui = ecs.imgui;
const Button = imgui.components.Button;
const Vec2 = ecs.utils.Vec2;

pub fn installMainLogic(game: *Game) !void {
    try game.addSystems(.{
        system(print_on_button),
        system(close_on_button),
    });

    const open_title: [:0]u8 = try game.allocator.dupeZ(u8, "Open");
    const close_title: [:0]u8 = try game.allocator.dupeZ(u8, "Close");

    const buttons_size = Vec2{ .x = 50.0, .y = 25.0 };
    const position = Vec2{ .x = 50.0, .y = 50.0 };

    _ = try game.newGlobalEntity(.{
        imgui.components.Button{
            .pos = position,
            .size = buttons_size,
            .title = @ptrCast(open_title),
        },
        ButtonOpen{},
    });
    _ = try game.newGlobalEntity(.{
        imgui.components.Button{
            .pos = position.add_y(buttons_size.y),
            .size = buttons_size,
            .title = @ptrCast(close_title),
            .visible = false,
        },
        ButtonClose{},
    });
}

const ButtonOpen = struct {
    pub usingnamespace Component(ButtonOpen);
};

const ButtonClose = struct {
    pub usingnamespace Component(ButtonClose);
};

fn print_on_button(
    iter: *Query(.{ Button, ButtonOpen }),
    close_iter: *Query(.{ Button, ButtonClose }),
) void {
    const button, _ = iter.single();
    if (button.clicked) {
        const close_button, _ = close_iter.single();
        close_button.visible = !close_button.visible;
    }
}

fn close_on_button(
    iter: *Query(.{ Button, ButtonClose }),
    game_action_iter: *Query(.{GameActions}),
) void {
    const button, _ = iter.single();
    var game_actions = game_action_iter.single()[0];
    if (button.clicked) {
        game_actions.should_close = true;
    }
}
