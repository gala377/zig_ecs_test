const rg = @import("raygui");
const rl = @import("raylib");
const Button = @import("components.zig").Button;
const Query = @import("../root.zig").Query;
const std = @import("std");

pub fn draw_imgui(buttons: *Query(.{Button})) void {
    while (buttons.next()) |pack| {
        const button: *Button = pack[0];
        const bounds: rl.Rectangle = .{
            .x = button.pos.x,
            .y = button.pos.y,
            .width = button.size.x,
            .height = button.size.y,
        };
        if (button.visible and rg.button(bounds, button.title)) {
            button.clicked = true;
        } else {
            button.clicked = false;
        }
    }
}
