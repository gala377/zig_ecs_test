const std = @import("std");

const lua = @import("lua_lib");
const rg = @import("raygui");
const rl = @import("raylib");

const commands = @import("commands.zig");
const Component = @import("component.zig").Component;
const EntityId = @import("scene.zig").EntityId;
const EntityStorage = @import("entity_storage.zig");
const PtrTuple = @import("utils.zig").PtrTuple;
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
    global_entity_storage: EntityStorage,

    pub fn init(allocator: std.mem.Allocator, options: Options) !Self {
        const state = try lua.State.init(allocator);
        return .{
            .allocator = allocator,
            .luaState = state,
            .shouldClose = false,
            .options = options,
            .inner_id = 1,
            .systems = .init(allocator),
            .currentScene = null,
            .global_entity_storage = try EntityStorage.init(allocator),
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

    pub fn query(self: *Self, comptime components: anytype) Query(components) {
        const global_components = self.global_entity_storage.query(components);
        const scene_components = if (self.currentScene) |*s| s.entity_storage.query(components) else null;
        return Query(components).init(global_components, scene_components);
    }

    pub fn addSystem(self: *Self, system: System) !void {
        try self.systems.append(system);
    }

    pub fn addSystems(self: *Self, comptime systems: anytype) !void {
        inline for (systems) |s| {
            try self.addSystem(s);
        }
    }

    pub fn newGlobalEntity(self: *Self, components: anytype) !EntityId {
        const id = self.newId();
        try self.global_entity_storage.makeEntity(id, components);
        return .{ .scene_id = 0, .entity_id = id };
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
        self.global_entity_storage.deinit();
    }

    pub fn newId(self: *Self) usize {
        const old = self.inner_id;
        self.inner_id += 1;
        return old;
    }
};

pub const GameActions = struct {
    pub usingnamespace Component(GameActions);
    should_close: bool,
};

pub fn addDefaultPlugins(game: *Game) !void {
    _ = try game.newGlobalEntity(.{GameActions{ .should_close = false }});
    try game.addSystem(&applyGameActions);
}

fn applyGameActions(game: *Game) void {
    var iter = game.query(.{GameActions});
    const actions: *GameActions = iter.single().@"0";
    if (actions.should_close) {
        game.shouldClose = true;
    }
}

pub fn Query(comptime components: anytype) type {
    const InnerIter = EntityStorage.QueryIter(components);
    return struct {
        const ThisIter = @This();
        pub const ComponentTypes = components;

        global_components: InnerIter,
        scene_components: ?InnerIter,

        pub fn init(global_components: InnerIter, scene_components: ?InnerIter) ThisIter {
            return .{
                .global_components = global_components,
                .scene_components = scene_components,
            };
        }

        pub fn next(self: *ThisIter) ?PtrTuple(components) {
            while (self.global_components.next()) |c| {
                return c;
            }
            if (self.scene_components) |*s| {
                while (s.next()) |c| {
                    return c;
                }
            }
            return null;
        }

        pub fn single(self: *ThisIter) PtrTuple(components) {
            var ret: ?PtrTuple(components) = null;
            ret = self.global_components.next();
            if (ret != null and self.global_components.next() != null) {
                @panic("expected only one entity but there is more");
            }
            if (self.scene_components) |*s| {
                const scene_next = s.next();
                if (ret != null) {
                    if (scene_next != null) {
                        @panic("expected only one entity but there is more");
                    }
                    return ret.?;
                }
                // ret is null
                if (scene_next == null) {
                    @panic("expected one entity but there is none");
                }
                return scene_next.?;
            }
            // scene iterator is null
            if (ret == null) {
                @panic("expected one entity but there is none");
            }
            return ret.?;
        }
    };
}
