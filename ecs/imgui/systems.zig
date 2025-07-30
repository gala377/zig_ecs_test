const Game = @import("../game.zig").Game;
const rg = @import("raygui");
const rl = @import("raylib");
const Button = @import("components.zig").Button;
const std = @import("std");

pub fn draw_imgui(game: *Game) void {
    var iter = game.query(.{Button});
    while (iter.next()) |components| {
        const button: *Button = components[0];
        const bounds: rl.Rectangle = .{
            .x = button.pos.x,
            .y = button.pos.y,
            .width = button.size.x,
            .height = button.size.y,
        };
        if (rg.button(bounds, button.title)) {
            button.clicked = true;
        } else {
            button.clicked = false;
        }
    }
}
