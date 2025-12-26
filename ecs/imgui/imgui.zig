const std = @import("std");

const rl = @import("raylib");

const DeclarationGenerator = @import("../declaration_generator.zig");
const Game = @import("../root.zig").Game;
const system = @import("../root.zig").system;
pub const components = @import("components.zig");
pub const systems = @import("systems.zig");

pub const Options = struct {
    show_fps: bool = false,
};

pub fn addImguiPlugin(game: *Game, options: Options) !void {
    try game.addSystem(.render, systems.draw_imgui);
    if (options.show_fps) {
        try game.addSystem(.render, showFps);
    }
}

fn showFps() void {
    const fps = rl.getFPS();
    const frame_time = rl.getFrameTime();
    var buf: [10000]u8 = undefined;
    const numAsString = std.fmt.bufPrintZ(&buf, "FPS: {:5}, frame time: {:.10}", .{ fps, frame_time }) catch {
        @panic("could not create fps text");
    };
    rl.drawText(numAsString, 0, 0, 16, rl.Color.white);
}

pub fn exportLua(game: *Game) !void {
    game.exportComponent(components.Button);
}

pub fn exportBuild(generator: *DeclarationGenerator) !void {
    try generator.registerComponentForBuild(components.Button);
}
