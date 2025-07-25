const std = @import("std");
const lua = @import("lua_lib");
const rl = @import("raylib");
const rg = @import("raygui");
const commands = @import("commands.zig");
const Scene = @import("scene.zig").Scene;

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

pub const Sentinel = usize;

pub const System = *const fn (game: *Game) void;

pub const Game = struct {
    const Self = @This();

    // config
    options: Options,

    // private
    allocator: std.mem.Allocator,
    luaState: lua.State,

    // internal state
    shouldClose: bool,
    currentScene: ?Scene,

    inner_id: usize,
    systems: std.ArrayList(System),

    pub fn init(allocator: std.mem.Allocator, options: Options) !Self {
        const state = try lua.State.init(allocator);
        return .{
            .allocator = allocator,
            .luaState = state,
            .shouldClose = false,
            .options = options,
            .inner_id = 0,
            .systems = .init(allocator),
            .currentScene = null,
        };
    }

    pub fn run(self: *Self) !void {
        rl.setConfigFlags(.{ .window_highdpi = true });
        rl.setTargetFPS(self.options.window.targetFps);
        rl.initWindow(self.options.window.size.width, self.options.window.size.height, self.options.window.title);
        defer rl.closeWindow();

        while (!self.shouldClose) : (self.shouldClose = rl.windowShouldClose() or self.shouldClose) {
            rl.beginDrawing();

            for (self.systems.items) |sys| {
                sys(self);
            }

            rl.clearBackground(.black);
            rl.endDrawing();
        }
    }

    pub fn addSystem(self: *Self, system: System) !void {
        try self.systems.append(system);
    }

    pub fn setInitialScene(self: *Self, scene: Scene) !void {
        if (self.currentScene != null) {
            return error.sceneAlreadySet;
        }
        self.currentScene = scene;
        self.currentScene.?.id = self.newId();
    }

    pub fn deinit(self: *Self) void {
        self.luaState.deinit();
        if (self.currentScene) |*scene| {
            scene.deinit();
        }
        self.systems.deinit();
    }

    pub fn newId(self: *Self) usize {
        const old = self.inner_id;
        self.inner_id += 1;
        return old;
    }
};
