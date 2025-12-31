const std = @import("std");

const rg = @import("raygui");
const rl = @import("raylib");
const ecs = @import("../root.zig");

const Game = ecs.Game;
const system = ecs.system;
const WindowOptions = ecs.core.window.WindowOptions;
const Resource = ecs.Resource;
const GameActions = ecs.runtime.game_actions;
const Query = ecs.Query;
const core = ecs.core;
const shapes = ecs.core.shapes;
const imgui = ecs.imgui;

pub fn install(game: *Game, options: WindowOptions, show_fps: bool) !void {
    try game.addResource(options);
    try game.addSystem(.setup, initWindow);
    try game.addSystem(.update, updateClose);
    try game.addSystem(.pre_render, beginDraw);

    try game.addSystems(.render, &.{
        system(draw_circles),
        system(draw_rectangle),
    });

    try game.addSystem(.post_render, endDraw);
    try game.addSystem(.tear_down, closeWindow);

    try game.addSystem(.render, imguiButtons);

    if (show_fps) {
        try game.addSystem(.render, showFps);
    }
}

fn initWindow(window_options: Resource(WindowOptions)) void {
    const options = window_options.get();
    rl.setConfigFlags(.{ .window_highdpi = true });
    rl.setTargetFPS(options.targetFps);
    rl.initWindow(
        options.size.width,
        options.size.height,
        options.title,
    );
}

// lifecycle managment

fn beginDraw() void {
    rl.beginDrawing();
}

fn endDraw() void {
    rl.clearBackground(.black);
    rl.endDrawing();
}

fn updateClose(game_actions: Resource(GameActions)) void {
    if (rl.windowShouldClose()) {
        game_actions.get().should_close = true;
    }
}

fn closeWindow(game_actions: Resource(GameActions)) void {
    const actions = game_actions.get();
    if (actions.should_close) {
        rl.closeWindow();
    }
}

// drawing shapes

pub fn draw_circles(circles: *Query(.{
    shapes.Circle,
    core.Position,
    core.Style,
})) void {
    while (circles.next()) |components| {
        const circle: *shapes.Circle, const position: *core.Position, const style: *core.Style = components;
        const color = if (style.background_color) |c| c else core.Color.white;
        rl.drawCircleV(
            .init(position.x, position.y),
            circle.radius,
            color.toRaylib(),
        );
    }
}

pub fn draw_rectangle(rectangles: *Query(.{
    shapes.Rectangle,
    core.Position,
    core.Style,
})) void {
    while (rectangles.next()) |components| {
        const rect: *shapes.Rectangle, const position: *core.Position, const style: *core.Style = components;
        const color = if (style.background_color) |c| c else core.Color.white;
        rl.drawRectangleV(
            .init(position.x, position.y),
            .init(rect.width, rect.height),
            color.toRaylib(),
        );
    }
}

// show fps

fn showFps() void {
    const fps = rl.getFPS();
    const frame_time = rl.getFrameTime();
    var buf: [10000]u8 = undefined;
    const numAsString = std.fmt.bufPrintZ(&buf, "FPS: {:5}, frame time: {:.10}", .{ fps, frame_time }) catch {
        @panic("could not create fps text");
    };
    rl.drawText(numAsString, 0, 0, 16, rl.Color.white);
}

// imgui

pub fn imguiButtons(buttons: *Query(.{imgui.components.Button})) void {
    while (buttons.next()) |pack| {
        const button = pack[0];
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
