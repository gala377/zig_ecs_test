const Game = @import("../game.zig").Game;
const rg = @import("raygui");
const rl = @import("raylib");
const Button = @import("components.zig").Button;
const std = @import("std");

pub fn draw_imgui(game: *Game) void {
    // TODO: do not use current scene components to iterate over components
    for (game.currentScene.?.components.items) |*comp| {
        if (std.mem.eql(u8, comp.name, "imgui:button")) {
            const button: *Button = @alignCast(@ptrCast(comp.pointer));
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
}
