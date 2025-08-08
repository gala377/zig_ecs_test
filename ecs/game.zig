const std = @import("std");
const component_prefix = @import("build_options").components_prefix;

const lua = @import("lua_lib");
const clua = lua.clib;
const rg = @import("raygui");
const rl = @import("raylib");

const commands = @import("commands.zig");
const Component = @import("component.zig").LibComponent;
const component_mod = @import("component.zig");
const ComponentId = @import("component.zig").ComponentId;
const ComponentWrapper = @import("entity_storage.zig").ComponentWrapper;
const DeclarationGenerator = @import("declaration_generator.zig");
const DynamicQueryIter = @import("dynamic_query.zig").DynamicQueryIter;
const DynamicQueryScope = @import("dynamic_query.zig").DynamicQueryScope;
const DynamicScopeOptions = @import("entity_storage.zig").DynamicScopeOptions;
const EntityId = @import("scene.zig").EntityId;
const EntityStorage = @import("entity_storage.zig");
const Entity = @import("entity.zig");
const ExportLua = @import("component.zig").ExportLua;
const LuaAccessibleOpaqueComponent = @import("dynamic_query.zig").LuaAccessibleOpaqueComponent;
const LuaSystem = @import("lua_system.zig");
const make_system = @import("system.zig").system;
const PtrTuple = @import("utils.zig").PtrTuple;
const Resource = @import("resource.zig").Resource;
const Scene = @import("scene.zig").Scene;
const utils = @import("utils.zig");
const mksystem = @import("system.zig").system;
const commands_system = @import("commands_system.zig");

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
    deffered_systems: std.ArrayList(System),
    lua_systems: std.ArrayList(LuaSystem),
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
            .deffered_systems = .init(allocator),
            .current_scene = null,
            .global_entity_storage = try EntityStorage.init(allocator),
            .lua_systems = .init(allocator),
        };
    }

    pub fn run(self: *Self) !void {
        try self.installRuntime();

        rl.setConfigFlags(.{ .window_highdpi = true });
        //rl.setTargetFPS(self.options.window.targetFps);
        rl.initWindow(self.options.window.size.width, self.options.window.size.height, self.options.window.title);
        defer rl.closeWindow();


        var iters: usize = 1;
        var total: usize = 0;
        while (!self.should_close) : (self.should_close = rl.windowShouldClose() or self.should_close) {
            const start = try std.time.Instant.now();
            rl.beginDrawing();

            for (self.systems.items) |sys| {
                sys(self);
            }
            for (self.lua_systems.items) |*sys| {
                sys.run(self, self.lua_state) catch {
                    @panic("could not run lua system");
                };
            }
            for (self.deffered_systems.items) |sys| {
                sys(self);
            }

            rl.clearBackground(.black);
            rl.endDrawing();

            const end = try std.time.Instant.now();
            const elapsed_ns = end.since(start); 
            total += elapsed_ns;
            const avg = total / iters;
            const seconds_per_frame = @as(f64, @floatFromInt(avg)) / 1_000_000_000.0;
            const fps = 1.0 / seconds_per_frame;
            iters += 1;
            std.debug.print("FPS: {d:.2}\n", .{fps});
        }
    }

    fn installRuntime(self: *Self) !void {
        try self.addResource(commands.init(self, self.allocator));
        try self.addDefferedSystem(mksystem(commands_system.create_entities));
    }

    pub fn exportComponent(self: *Self, comptime Comp: type) void {
        Comp.registerMetaTable(self.lua_state);
    }

    pub fn query(self: *Self, comptime components: anytype) Query(components) {
        const global_components = self.global_entity_storage.query(components);
        const scene_components = if (self.current_scene) |*s| s.entity_storage.query(components) else null;
        return Query(components).init(global_components, scene_components);
    }

    pub fn dynamicQueryScope(self: *Self, components: []const ComponentId) !JoinedDynamicScope {
        const global_scope = try self.global_entity_storage.dynamicQueryScope(components, .{});
        const scene_scope = if (self.current_scene) |*s| try s.entity_storage.dynamicQueryScope(components, .{}) else null;
        return JoinedDynamicScope{
            .global_scope = global_scope,
            .scene_scope = scene_scope,
            .allocator = self.allocator,
        };
    }

    pub fn dynamicQueryScopeOpts(self: *Self, components: []const ComponentId, options: DynamicScopeOptions) !JoinedDynamicScope {
        const global_scope = try self.global_entity_storage.dynamicQueryScope(components, options);
        const scene_scope = if (self.current_scene) |*s| try s.entity_storage.dynamicQueryScope(components, options) else null;
        return JoinedDynamicScope{
            .global_scope = global_scope,
            .scene_scope = scene_scope,
            .allocator = options.allocator orelse self.allocator,
        };
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

    pub fn addDefferedSystem(self: *Self, system: System) !void {
        try self.deffered_systems.append(system);
    }

    pub fn addLuaSystem(self: *Self, path: []const u8) !void {
        const cwd = std.fs.cwd();

        var file = try cwd.openFile(path, .{});
        defer file.close();
        const contents = try file.readToEndAlloc(self.allocator, std.math.maxInt(usize));
        defer self.allocator.free(contents);
        try self.lua_state.loadWithName(contents, path);
        const system = try LuaSystem.fromLua(self.lua_state, self.allocator);
        try self.lua_systems.append(system);
    }

    pub fn addLuaSystems(self: *Self, path: []const u8) !void {
        const cwd = std.fs.cwd();

        var file = try cwd.openFile(path, .{});
        defer file.close();
        const contents = try file.readToEndAlloc(self.allocator, std.math.maxInt(usize));
        defer self.allocator.free(contents);
        try self.lua_state.loadWithName(contents, path);
        if (clua.lua_type(self.lua_state.state, -1) != clua.LUA_TTABLE) {
            return error.expectedTable;
        }
        const len = clua.lua_rawlen(self.lua_state.state, -1);
        for (0..len) |idx| {
            _ = clua.lua_geti(self.lua_state.state, -1, @intCast(idx + 1));
            const system = try LuaSystem.fromLua(self.lua_state, self.allocator);
            try self.lua_systems.append(system);
        }
        self.lua_state.popUnchecked();
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

    pub fn insertEntity(self: *Self, id: EntityId, components: std.AutoHashMap(ComponentId, ComponentWrapper)) !void {
        if (id.scene_id == 0) {
            try self.global_entity_storage.insertEntity(id.entity_id, components);
        } else if (self.current_scene) |*scene| {
            if (scene.id == id.scene_id) {
                try scene.entity_storage.insertEntity(id.entity_id, components);
            } else {
                return error.sceneDoesNotExist;
            }
        } else {
            // TODO: Later, maybe look through other scenes, if we will allow for
            // storing scenes for later use
            return error.sceneDoesNotExist;
        }
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
        self.deffered_systems.deinit();
        if (self.current_scene) |*scene| {
            scene.deinit();
        }
        for (self.lua_systems.items) |*system| {
            system.deinit();
        }
        self.lua_systems.deinit();
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
    pub usingnamespace ExportLua(GameActions, .{});
    should_close: bool,
    test_field: ?isize = null,
    test_field_2: ?f64 = null,
    log: [][]const u8,
    allocator: std.mem.Allocator,

    pub fn deinit(self: *GameActions, allocator: std.mem.Allocator) void {
        _ = allocator;
        for (self.log) |log| {
            self.allocator.free(log);
        }
        if (self.log.len > 0) {
            self.allocator.free(self.log);
        }
    }
};

pub const LuaRuntime = struct {
    pub usingnamespace Component(component_prefix, LuaRuntime);
    lua: *lua.State,
};

pub fn addDefaultPlugins(game: *Game, export_lua: bool) !void {
    _ = try game.addResource(GameActions{ .should_close = false, .allocator = game.allocator, .log = &.{} });
    _ = try game.addResource(LuaRuntime{ .lua = &game.lua_state });
    try game.addSystem(&applyGameActions);
    if (export_lua) {
        game.exportComponent(GameActions);
        try DynamicQuery.registerMetaTable(game.lua_state);
    }
    const state = game.lua_state.state;
    lua.clib.lua_pushcclosure(state, &luaHash, 0);
    lua.clib.lua_setglobal(state, "ComponentHash");
}

fn luaHash(state: ?*lua.clib.lua_State) callconv(.c) c_int {
    var string_len: usize = undefined;
    // 1 refers to the first argument, from the bottom of the stack
    const lstr: [*c]const u8 = lua.clib.lua_tolstring(state, 1, &string_len);
    if (lstr == null) {
        @panic("Could not hash, not a string");
    }
    const str: []const u8 = lstr[0..string_len];
    const comp_id = component_mod.newComponentId(str);
    const lua_int: i64 = @bitCast(comp_id);
    lua.clib.lua_pushinteger(state, lua_int);
    return 1;
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

pub const JoinedDynamicScope = struct {
    const Self = @This();
    global_scope: DynamicQueryScope,
    scene_scope: ?DynamicQueryScope,
    allocator: std.mem.Allocator,

    pub fn deinit(self: *Self) void {
        self.global_scope.deinit();
        if (self.scene_scope) |*scope| scope.deinit();
    }

    pub fn iter(self: *Self) DynamicQuery {
        return .init(
            self.global_scope.iter(),
            if (self.scene_scope) |*s| s.iter() else null,
            self.allocator,
        );
    }
};

pub const DynamicQuery = struct {
    const Self = @This();
    const MetaTableName = "ecs." ++ @typeName(Self) ++ "_MetaTable";

    global_components: DynamicQueryIter,
    scene_components: ?DynamicQueryIter,
    allocator: std.mem.Allocator,

    pub fn init(global_components: DynamicQueryIter, scene_components: ?DynamicQueryIter, allocator: std.mem.Allocator) Self {
        return .{
            .global_components = global_components,
            .scene_components = scene_components,
            .allocator = allocator,
        };
    }

    pub fn next(self: *Self) ?[]LuaAccessibleOpaqueComponent {
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

    pub fn luaPush(self: *Self, state: *clua.lua_State) void {
        // std.debug.print("Pushing value of t={s}\n", .{@typeName(Self)});
        const raw = clua.lua_newuserdata(state, @sizeOf(utils.ZigPointer(Self))) orelse @panic("lua could not allocate memory");
        const udata: *utils.ZigPointer(Self) = @alignCast(@ptrCast(raw));
        udata.* = utils.ZigPointer(Self){ .ptr = self };
        if (clua.luaL_getmetatable(state, MetaTableName) == 0) {
            @panic("Metatable " ++ MetaTableName ++ "not found");
        }
        // Assign the metatable to the userdata (stack: userdata, metatable)
        if (clua.lua_setmetatable(state, -2) != 0) {
            // @panic("object " ++ @typeName(T) ++ " already had a metatable");
        }
    }

    pub fn luaNext(state: *clua.lua_State) callconv(.c) c_int {
        // std.debug.print("calling next in zig\n", .{});
        const ptr: *utils.ZigPointer(Self) = @alignCast(@ptrCast(clua.lua_touserdata(state, 1)));
        const self = ptr.ptr;
        const rest = self.next();
        if (rest == null) {
            clua.lua_pushnil(state);
            return 1;
        }
        // get component pointers
        const components = rest.?;

        // create a table on the stack for components
        clua.lua_createtable(state, @intCast(components.len), 0);

        for (components, 1..) |component, idx| {
            component.push(component.pointer, state);
            clua.lua_seti(state, -2, @intCast(idx));
        }

        self.allocator.free(components);
        return 1;
    }

    pub fn registerMetaTable(lstate: lua.State) !void {
        const state = lstate.state;
        if (clua.luaL_newmetatable(state, MetaTableName) != 1) {
            @panic("Could not create metatable");
        }
        clua.lua_pushvalue(state, -1);
        clua.lua_setfield(state, -2, "__index");
        const methods = [_]clua.luaL_Reg{
            .{
                .name = "next",
                .func = @ptrCast(&luaNext),
            },
            .{
                .name = null,
                .func = null,
            },
        };

        clua.luaL_setfuncs(state, &methods[0], 0);
        // Pop metatable
        clua.lua_pop(state, 1);
    }
};
