const std = @import("std");
const rg = @import("raygui");
const rl = @import("raylib");
// Import the C glue
const ri = @cImport({
    @cInclude("rlImGui.h");
});
const ecs = @import("../prelude.zig");

const core = ecs.core;
const system = ecs.system;
const shapes = ecs.core.shapes;
const imgui = ecs.imgui;

const Game = ecs.Game;
const Resource = ecs.Resource;
const GameActions = ecs.runtime.game_actions;
const Query = ecs.Query;
const DefaultSchedule = ecs.Schedule.DefaultSchedule;
const WindowOptions = core.window.WindowOptions;

pub const utils = @import("utils.zig");

pub const RaylibSchedule = struct {};

pub fn install(game: *Game, options: WindowOptions, show_fps: bool) !void {
    // define raylib schedules
    try game.schedule.addScheduleAfter(.pre_render, RaylibSchedule{}, .{});
    try game.schedule.addScheduleAfter(.update, RaylibSchedule{}, .{
        DefaultSchedule{},
    });
    try game.schedule.addScheduleAfter(.setup, RaylibSchedule{}, .{});
    try game.schedule.addScheduleAfter(.render, RaylibSchedule{}, .{});
    try game.schedule.addScheduleAfter(.post_render, RaylibSchedule{}, .{});
    try game.schedule.addScheduleAfter(.tear_down, RaylibSchedule{}, .{});

    try game.addResource(options);
    try game.type_registry.registerType(WindowOptions);

    try game.addLabeledSystemToSchedule(.setup, RaylibSchedule{}, "ecs.raylib.initWindow", initWindow);
    try game.addLabeledSystemToSchedule(.update, RaylibSchedule{}, "ecs.raylib.updateClose", updateClose);
    try game.addLabeledSystemToSchedule(.pre_render, RaylibSchedule{}, "ecs.raylib.beginDraw", beginDraw);

    try game.addSystemsToSchedule(.render, RaylibSchedule{}, &.{
        system.labeledSystem("ecs.raylib.draw_circles", draw_circles),
        system.labeledSystem("ecs.raylib.draw_rectangle", draw_rectangle),
        system.labeledSystem("ecs.raylib.imguiButtons", imguiButtons),
    });

    try game.addLabeledSystemToSchedule(.post_render, RaylibSchedule{}, "ecs.raylib.endDraw", endDraw);
    try game.addLabeledSystemToSchedule(.tear_down, RaylibSchedule{}, "ecs.raylib.closeWindow", closeWindow);

    if (show_fps) {
        try game.addLabeledSystemToSchedule(.render, RaylibSchedule{}, "ecs.raylib.showFps", showFps);
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
    rl.clearBackground(.black);
}

fn endDraw() void {
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
            utils.colorToRaylib(color),
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
            utils.colorToRaylib(color),
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
