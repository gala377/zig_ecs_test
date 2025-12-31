const std = @import("std");

const rg = @import("raygui");
const rl = @import("raylib");

const Game = @import("../game.zig").Game;
const system = @import("../system.zig").system;
const WindowOptions = @import("../core/core.zig").window.WindowOptions;
const Resource = @import("../root.zig").Resource;
const GameActions = @import("../runtime/game_actions.zig");

pub fn install(game: *Game, options: WindowOptions) !void {
    try game.addResource(options);
    try game.addSystem(.setup, initWindow);
    try game.addSystem(.update, updateClose);
    try game.addSystem(.pre_render, beginDraw);
    try game.addSystem(.post_render, endDraw);
    try game.addSystem(.tear_down, closeWindow);
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
