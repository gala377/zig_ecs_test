const std = @import("std");
const lua = @import("lua_lib");
const rl = @import("raylib");
const rg = @import("raygui");
const commands = @import("commands.zig");

pub const Size = struct {
    width: i32,
    height: i32,
};

pub const WindowOptions = struct {
    title: [:0]const u8,
    size: Size,
    targetFps: i32,
};

pub const Options = struct {
    window: WindowOptions,
};

pub const Game = struct {
    const Self = @This();

    // config
    options: Options,

    // private
    allocator: std.mem.Allocator,
    luaState: lua.State,

    // internal state
    shouldClose: bool,

    customCommands: std.StringHashMap(commands.UserDefinedCommand),

    pub fn init(allocator: std.mem.Allocator, options: Options) !Self {
        const state = try lua.State.init(allocator);
        return .{
            .allocator = allocator,
            .luaState = state,
            .shouldClose = false,
            .options = options,
            .customCommands = .init(allocator),
        };
    }

    pub fn run(self: *Self) !void {
        rl.setConfigFlags(.{ .window_highdpi = true });
        rl.setTargetFPS(self.options.window.targetFps);
        rl.initWindow(self.options.window.size.width, self.options.window.size.height, self.options.window.title);
        defer rl.closeWindow();

        while (!self.shouldClose) : (self.shouldClose = rl.windowShouldClose() or self.shouldClose) {
            rl.beginDrawing();

            rl.clearBackground(.black);
            rl.endDrawing();
        }
    }

    pub fn deinit(self: *Self) void {
        self.luaState.deinit();
        for (self.customCommands.valueIterator()) |c| {
            c.deinit(self.allocator, self.luaState);
        }
    }
};
