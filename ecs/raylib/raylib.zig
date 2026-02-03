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
    try game.addSystemToSchedule(.setup, RaylibSchedule{}, initWindow);
    try game.addSystemToSchedule(.update, RaylibSchedule{}, updateClose);
    try game.addSystemToSchedule(.pre_render, RaylibSchedule{}, beginDraw);

    try game.addSystemsToSchedule(.render, RaylibSchedule{}, &.{
        system.func(draw_circles),
        system.func(draw_rectangle),
    });

    try game.addSystemToSchedule(.post_render, RaylibSchedule{}, endDraw);
    try game.addSystemToSchedule(.tear_down, RaylibSchedule{}, closeWindow);

    try game.addSystemToSchedule(.render, RaylibSchedule{}, imguiButtons);

    if (show_fps) {
        try game.addSystemToSchedule(.render, RaylibSchedule{}, showFps);
    }
    try game.addSystemToSchedule(.render, RaylibSchedule{}, allEntities);
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

fn allEntities(game: *Game) void {
    const sw = @as(f32, @floatFromInt(rl.getScreenWidth()));
    const sh = @as(f32, @floatFromInt(rl.getScreenHeight()));

    const panel_width = 200.0;
    const panel_rect = rl.Rectangle{
        .x = sw - panel_width,
        .y = 0,
        .width = panel_width,
        .height = sh,
    };
    _ = rg.panel(panel_rect, "entities");
    const start_x = panel_rect.x + 10.0;
    const start_y = 40.0; // Start below the panel title bar
    const line_height = 25.0;
    const type_registry = &game.type_registry;
    const archetypes = game.current_scene.?.entity_storage.archetypes;
    const padding = 10.0;
    var draw_index: usize = 0;
    for (archetypes.items) |*archetype| {
        for (0..archetype.capacity) |entity_index| {
            if (archetype.freelist.contains(entity_index)) {
                continue;
            }
            const y_pos = start_y + (@as(f32, @floatFromInt(draw_index)) * line_height);
            _ = rg.label(.{
                .x = start_x,
                .y = y_pos,
                .width = panel_width - (padding * 2),
                .height = 20,
            }, "ENTITY:");
            draw_index += 1;
            for (archetype.components.items) |*column| {
                const comp_y_pos = start_y + (@as(f32, @floatFromInt(draw_index)) * line_height);
                const component_id = column.component_id;
                const metadata = type_registry.metadata.get(component_id);
                if (metadata) |meta| {
                    const name = meta.name;
                    const duped = game.allocator.dupeZ(u8, name) catch @panic("could not allocate memory");
                    defer game.allocator.free(duped);
                    _ = rg.label(.{
                        .x = start_x + padding,
                        .y = comp_y_pos,
                        .width = panel_width - (padding * 2),
                        .height = 20,
                    }, duped);
                } else {
                    _ = rg.label(.{
                        .x = start_x + padding,
                        .y = comp_y_pos,
                        .width = panel_width - (padding * 2),
                        .height = 20,
                    }, "Unknown component");
                }
                draw_index += 1;
            }
        }
    }
}
