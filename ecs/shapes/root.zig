const Component = @import("../component.zig").LibComponent;
const component_prefix = @import("build_options").components_prefix;
const Query = @import("../game.zig").Query;
const Position = @import("../core/position.zig");
const Style = @import("../core/style.zig");
const Color = @import("../core/color.zig");
const rl = @import("raylib");
const Game = @import("../game.zig").Game;
const system = @import("../system.zig").system;
const std = @import("std");

pub const Circle = struct {
    pub const component_info = Component(component_prefix, Circle);
    radius: f32,
};

pub const Rectangle = struct {
    pub const component_info = Component(component_prefix, Rectangle);
    width: f32,
    height: f32,
};

pub fn draw_circles(circles: *Query(.{
    Circle,
    Position,
    Style,
})) void {
    while (circles.next()) |components| {
        const circle: *Circle, const position: *Position, const style: *Style = components;
        const color = if (style.background_color) |c| c else Color.white;
        rl.drawCircleV(
            .init(position.x, position.y),
            circle.radius,
            color.toRaylib(),
        );
    }
}

pub fn draw_rectangle(rectangles: *Query(.{
    Rectangle,
    Position,
    Style,
})) void {
    while (rectangles.next()) |components| {
        const rect: *Rectangle, const position: *Position, const style: *Style = components;
        const color = if (style.background_color) |c| c else Color.white;
        rl.drawRectangleV(
            .init(position.x, position.y),
            .init(rect.width, rect.height),
            color.toRaylib(),
        );
    }
}

pub fn installShapes(
    game: *Game,
) !void {
    try game.addSystems(.{
        system(draw_circles),
        system(draw_rectangle),
    });
}
