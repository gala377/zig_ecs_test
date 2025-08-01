const std = @import("std");

const lua = @import("lua_lib");
const rg = @import("raygui");
const rl = @import("raylib");

const commands = @import("commands.zig");
const Component = @import("component.zig").LibComponent;
const ExportLua = @import("component.zig").ExportLua;
const DeclarationGenerator = @import("declaration_generator.zig");
const EntityId = @import("scene.zig").EntityId;
const EntityStorage = @import("entity_storage.zig");
const PtrTuple = @import("utils.zig").PtrTuple;
const Scene = @import("scene.zig").Scene;
const Resource = @import("resource.zig").Resource;
const make_system = @import("system.zig").system;
const DynamicQueryIter = @import("dynamic_query.zig").DynamicQueryIter;

const component_prefix = @import("build_options").components_prefix;

pub const Size = struct {
    width: i32,
    height: i32,
};

pub const WindowOptions = struct {
    title: [:0]const u8,
    size: Size,
    targetFps: i32 = 60,
};

pub const BuildOptions = struct {
    generate_lua_stub_files: bool = false,
    lua_stub_files_output: ?[]const u8 = null,
};

pub const Options = struct {
    window: WindowOptions,
    build_options: BuildOptions = .{},
};

pub const Sentinel = usize;

pub const System = *const fn (game: *Game) void;

pub const Game = struct {
    const Self = @This();

    // config
    options: Options,

    // private
    allocator: std.mem.Allocator,
    lua_state: lua.State,

    // internal state
    should_close: bool,
    current_scene: ?Scene,

    inner_id: usize,
    systems: std.ArrayList(System),
    global_entity_storage: EntityStorage,

    pub fn init(allocator: std.mem.Allocator, options: Options) !Self {
        const state = try lua.State.init(allocator);
        return .{
            .allocator = allocator,
            .lua_state = state,
            .should_close = false,
            .options = options,
            .inner_id = 1,
            .systems = .init(allocator),
            .current_scene = null,
            .global_entity_storage = try EntityStorage.init(allocator),
        };
    }

    pub fn run(self: *Self) !void {
        rl.setConfigFlags(.{ .window_highdpi = true });
        rl.setTargetFPS(self.options.window.targetFps);
        rl.initWindow(self.options.window.size.width, self.options.window.size.height, self.options.window.title);
        defer rl.closeWindow();

        while (!self.should_close) : (self.should_close = rl.windowShouldClose() or self.should_close) {
            rl.beginDrawing();

            for (self.systems.items) |sys| {
                sys(self);
            }

            rl.clearBackground(.black);
            rl.endDrawing();
        }
    }

    pub fn exportComponent(self: *Self, comptime Comp: type) void {
        Comp.registerMetaTable(self.lua_state);
    }

    pub fn query(self: *Self, comptime components: anytype) Query(components) {
        const global_components = self.global_entity_storage.query(components);
        const scene_components = if (self.current_scene) |*s| s.entity_storage.query(components) else null;
        return Query(components).init(global_components, scene_components);
    }

    pub fn getResource(self: *Self, comptime T: type) Resource(T) {
        var q = self.query(.{T});
        return .init(q.single()[0]);
    }

    pub fn addResource(self: *Self, resource: anytype) !void {
        _ = try self.newGlobalEntity(.{resource});
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
        if (self.current_scene != null) {
            return error.sceneAlreadySet;
        }
        self.current_scene = scene;
        self.current_scene.?.id = self.newId();
    }

    pub fn deinit(self: *Self) void {
        self.systems.deinit();
        if (self.current_scene) |*scene| {
            scene.deinit();
        }
        self.global_entity_storage.deinit();
        // INFO: components may hold references to lua so we need to
        // dealloc it last
        self.lua_state.deinit();
    }

    pub fn newId(self: *Self) usize {
        const old = self.inner_id;
        self.inner_id += 1;
        return old;
    }

    pub fn luaLoad(self: *Self, source: []const u8) !lua.Ref {
        try self.lua_state.load(source);
        return self.lua_state.makeRef();
    }
};

pub const GameActions = struct {
    pub usingnamespace Component(component_prefix, GameActions);
    pub usingnamespace ExportLua(GameActions);
    should_close: bool,
};

pub const LuaRuntime = struct {
    pub usingnamespace Component(component_prefix, LuaRuntime);
    lua: *lua.State,
};

pub fn addDefaultPlugins(game: *Game, export_lua: bool) !void {
    _ = try game.addResource(GameActions{ .should_close = false });
    _ = try game.addResource(LuaRuntime{ .lua = &game.lua_state });
    try game.addSystem(&applyGameActions);
    if (export_lua) {
        game.exportComponent(GameActions);
        try DynamicQueryIter.registerMetaTable(game.lua_state);
    }
}

pub fn registerDefaultComponentsForBuild(generator: *DeclarationGenerator) !void {
    try generator.registerComponentForBuild(GameActions);
}

fn applyGameActions(game: *Game) void {
    var actions = game.getResource(GameActions);
    if (actions.get().should_close) {
        game.should_close = true;
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
