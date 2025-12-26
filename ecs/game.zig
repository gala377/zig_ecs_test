const std = @import("std");
const component_prefix = @import("build_options").components_prefix;
const ecs = @import("root.zig");

const lua = @import("lua_lib");
const clua = lua.clib;
const rg = @import("raygui");
const rl = @import("raylib");

const component_mod = ecs.component;
const Component = component_mod.LibComponent;
const ComponentId = component_mod.ComponentId;
const DeclarationGenerator = @import("declaration_generator.zig");
const dynamic_query = @import("dynamic_query.zig");
const DynamicQueryIter = dynamic_query.DynamicQueryIter;
const DynamicQueryScope = dynamic_query.DynamicQueryScope;
const LuaAccessibleOpaqueComponent = dynamic_query.LuaAccessibleOpaqueComponent;
const Entity = ecs.entity;
const EntityId = Entity.EntityId;
const entity_storage = @import("entity_storage.zig");
const ComponentWrapper = entity_storage.ComponentWrapper;
const DynamicScopeOptions = entity_storage.DynamicScopeOptions;
const ExportLua = component_mod.ExportLua;
const LuaSystem = @import("lua_system.zig");
const PtrTuple = @import("utils.zig").PtrTuple;
const QueryIter = @import("query.zig").QueryIter;
const Resource = @import("resource.zig").Resource;
const runtime = ecs.runtime;
const GameActions = runtime.game_actions;
const LuaRuntime = runtime.lua_runtime;
const commands = runtime.commands;
const commands_system = runtime.commands_system;
const Scene = @import("scene.zig").Scene;
const System = @import("system.zig").System;
const utils = @import("utils.zig");
const VTableStorage = @import("comp_vtable_storage.zig");
const Schedule = @import("schedule.zig");

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

const SimpleIdProvider = struct {
    inner: usize = 0,

    fn next(self: *SimpleIdProvider) usize {
        self.inner += 1;
        return self.inner;
    }

    pub fn idprovider(
        self: *SimpleIdProvider,
    ) utils.IdProvider {
        return .{
            .ctx = @ptrCast(self),
            .nextFn = @ptrCast(&next),
        };
    }

    pub fn luaNext(state: *clua.lua_State) callconv(.c) c_int {
        const self: *SimpleIdProvider = @ptrCast(@alignCast(clua.lua_touserdata(state, clua.lua_upvalueindex(1))));
        clua.lua_pushinteger(state, @intCast(self.next()));
        return 1;
    }

    pub fn exportIdFunction(self: *SimpleIdProvider, state: *clua.lua_State) void {
        clua.lua_pushlightuserdata(state, @ptrCast(self));
        clua.lua_pushcclosure(state, @ptrCast(&luaNext), 1);
        clua.lua_setglobal(state, "newUniqueInteger");
    }
};

pub const Game = struct {
    const Self = @This();

    // config
    options: Options,

    // private
    allocator: std.mem.Allocator,
    frame_allocator: std.heap.ArenaAllocator,

    lua_state: lua.State,

    // internal state
    should_close: bool,
    current_scene: ?Scene,

    inner_id: usize,
    idprovider: *SimpleIdProvider,

    lua_systems: std.ArrayList(LuaSystem),
    schedule: Schedule,

    global_entity_storage: entity_storage,
    vtable_storage: *VTableStorage,

    pub fn init(allocator: std.mem.Allocator, options: Options) !Self {
        const state = try lua.State.init(allocator);
        const id_provider = try allocator.create(SimpleIdProvider);
        id_provider.* = SimpleIdProvider{};
        const vtable_storage = try allocator.create(VTableStorage);
        vtable_storage.* = VTableStorage.init(allocator);
        return .{
            .allocator = allocator,
            .lua_state = state,
            .should_close = false,
            .options = options,
            .inner_id = 1,
            .current_scene = null,
            .global_entity_storage = try entity_storage.init(allocator, id_provider.idprovider(), vtable_storage),
            .lua_systems = .empty,
            .idprovider = id_provider,
            .vtable_storage = vtable_storage,
            .frame_allocator = .init(std.heap.c_allocator),
            .schedule = Schedule.init(allocator),
        };
    }

    pub fn run(self: *Self) !void {
        try self.installRuntime();

        rl.setConfigFlags(.{ .window_highdpi = true });
        rl.setTargetFPS(self.options.window.targetFps);
        rl.initWindow(self.options.window.size.width, self.options.window.size.height, self.options.window.title);
        defer rl.closeWindow();

        self.schedule.runPhase(.setup, self);

        // var iters: usize = 1;
        // var total: usize = 0;
        while (!self.should_close) : (self.should_close = rl.windowShouldClose() or self.should_close) {
            // const start = try std.time.Instant.now();
            self.schedule.runPhase(.update, self);
            for (self.lua_systems.items) |*sys| {
                sys.run(self) catch {
                    @panic("could not run lua system");
                };
            }
            self.schedule.runPhase(.post_update, self);

            rl.beginDrawing();

            self.schedule.runPhase(.render, self);
            self.schedule.runPhase(.post_render, self);

            rl.clearBackground(.black);
            rl.endDrawing();

            self.schedule.runPhase(.tear_down, self);
        }
    }

    fn installRuntime(self: *Self) !void {
        try self.addResource(commands.init(self, self.allocator));
        try self.addResource(runtime.allocators.GlobalAllocator{ .allocator = self.allocator });
        try self.addResource(runtime.allocators.FrameAllocator{
            .allocator = self.frame_allocator.allocator(),
            .arena = &self.frame_allocator,
        });
        try self.addSystem(.post_update, commands_system.create_entities);
        try self.addSystem(.tear_down, runtime.allocators.freeFrameAllocator);
    }

    pub fn exportComponent(self: *Self, comptime Comp: type) void {
        @TypeOf(Comp.lua_info).registerMetaTable(self.lua_state);
        @TypeOf(Comp.lua_info).exportId(@ptrCast(self.lua_state.state), self.idprovider.idprovider(), self.allocator) catch {
            @panic("could not export component to lua");
        };
    }

    pub fn query(self: *Self, comptime components: anytype, comptime exclude: anytype) Query(components ++ WrapIfNotEmpty(exclude)) {
        const global_components = self.global_entity_storage.query(components, exclude);
        const scene_components = if (self.current_scene) |*s| s.entity_storage.query(components, exclude) else null;
        return Query(components ++ WrapIfNotEmpty(exclude)).init(global_components, scene_components);
    }

    pub fn dynamicQueryScope(self: *Self, components: []const ComponentId, exclude: []const ComponentId) !JoinedDynamicScope {
        const global_scope = try self.global_entity_storage.dynamicQueryScope(components, exclude, .{});
        const scene_scope = if (self.current_scene) |*s| try s.entity_storage.dynamicQueryScope(components, exclude, .{}) else null;
        return JoinedDynamicScope{
            .global_scope = global_scope,
            .scene_scope = scene_scope,
            .allocator = self.allocator,
        };
    }

    pub fn newScene(self: *Self) !Scene {
        return .init(self.newId(), self.idprovider.idprovider(), self.allocator, self.vtable_storage);
    }

    pub fn dynamicQueryScopeOpts(self: *Self, components: []const ComponentId, exclude: []const ComponentId, options: DynamicScopeOptions) !JoinedDynamicScope {
        const global_scope = try self.global_entity_storage.dynamicQueryScope(components, exclude, options);
        const scene_scope = if (self.current_scene) |*s| try s.entity_storage.dynamicQueryScope(components, exclude, options) else null;
        return JoinedDynamicScope{
            .global_scope = global_scope,
            .scene_scope = scene_scope,
            .allocator = options.allocator orelse self.allocator,
        };
    }

    pub fn getResource(self: *Self, comptime T: type) Resource(T) {
        var q = self.query(.{T}, .{});
        return .init(q.single()[0]);
    }

    pub fn addResource(self: *Self, resource: anytype) !void {
        _ = try self.newGlobalEntity(.{resource});
    }

    pub fn addEvent(self: *Self, comptime T: type) !void {
        _ = try self.newGlobalEntity(.{
            runtime.events.EventBuffer(T){ .allocator = self.allocator, .events = &.{} },
            runtime.events.EventWriterBuffer(T){ .allocator = self.allocator, .events = .empty },
        });
        try self.addSystems(.tear_down, .{runtime.events.eventSystem(T)});
    }

    pub fn addLuaSystem(self: *Self, path: []const u8) !void {
        const cwd = std.fs.cwd();

        var file = try cwd.openFile(path, .{});
        defer file.close();
        const contents = try file.readToEndAlloc(self.allocator, std.math.maxInt(usize));
        defer self.allocator.free(contents);
        try self.lua_state.loadWithName(contents, path);
        const system = try LuaSystem.fromLua(self.lua_state, self.allocator);
        try self.lua_systems.append(self.allocator, system);
    }

    pub fn addLuaSystems(self: *Self, path: []const u8) !void {
        std.debug.print("1\n", .{});
        const cwd = std.fs.cwd();

        std.debug.print("2\n", .{});
        var file = try cwd.openFile(path, .{});
        std.debug.print("3\n", .{});
        defer file.close();
        const contents = try file.readToEndAlloc(self.allocator, std.math.maxInt(usize));
        std.debug.print("4\n", .{});
        defer self.allocator.free(contents);
        self.lua_state.loadWithName(contents, path) catch |err| {
            std.debug.print("got arror when loading lua thing {any}\n", .{err});
            return err;
        };
        std.debug.print("5\n", .{});
        if (clua.lua_type(@ptrCast(self.lua_state.state), -1) != clua.LUA_TTABLE) {
            std.debug.print("6\n", .{});
            return error.expectedTable;
        }
        std.debug.print("7\n", .{});
        const len = clua.lua_rawlen(@ptrCast(self.lua_state.state), -1);
        std.debug.print("8\n", .{});
        for (0..len) |idx| {
            std.debug.print("9\n", .{});
            _ = clua.lua_geti(@ptrCast(self.lua_state.state), -1, @intCast(idx + 1));
            const system = try LuaSystem.fromLua(self.lua_state, self.allocator);
            try self.lua_systems.append(self.allocator, system);
        }
        std.debug.print("10\n", .{});
        try self.lua_state.pop();
        std.debug.print("11\n", .{});
    }

    pub fn addSystem(self: *Self, phase: Schedule.Phase, comptime sys: anytype) !void {
        try self.schedule.add(phase, ecs.system(sys));
    }

    pub fn addSystems(self: *Self, phase: Schedule.Phase, comptime systems: anytype) !void {
        inline for (systems) |s| {
            try self.schedule.add(phase, s);
        }
    }

    pub fn newGlobalEntity(self: *Self, components: anytype) !EntityId {
        const id = self.newId();
        const entity_id = EntityId{
            .scene_id = 0,
            .entity_id = id,
            .archetype_id = try self.allocator.create(usize),
        };
        if (entity_id.archetype_id) |aid| {
            aid.* = 0;
        }
        const with_id = .{entity_id} ++ components;
        return self.global_entity_storage.makeEntity(id, with_id);
    }

    pub fn removeEntities(self: *Self, ids: []EntityId) !void {
        var global_entities = std.ArrayList(EntityId).empty;
        defer global_entities.deinit(self.allocator);
        var scene_entities = std.ArrayList(EntityId).empty;
        defer scene_entities.deinit(self.allocator);
        for (ids) |id| {
            if (id.scene_id == 0) {
                try global_entities.append(self.allocator, id);
                continue;
            }
            if (self.current_scene) |*scene| {
                if (scene.id == id.scene_id) {
                    try scene_entities.append(self.allocator, id);
                    continue;
                }
            }
            return error.sceneDoesNotExists;
        }
        if (global_entities.items.len > 0) {
            self.global_entity_storage.removeEntities(global_entities.items);
        }
        if (scene_entities.items.len > 0) {
            self.current_scene.?.entity_storage.removeEntities(scene_entities.items);
        }
    }

    // Adds components to a given entity.
    //
    // Does not take ownership over a slice of components.
    pub fn addComponents(self: *Self, id: EntityId, components: []ComponentWrapper) !void {
        const archetype_id = id.archetype_id orelse @panic("archetype id is null");
        if (id.scene_id == 0) {
            try self.global_entity_storage.addComponents(id.entity_id, archetype_id.*, components);
            return;
        } else if (self.current_scene) |*scene| {
            if (scene.id == id.scene_id) {
                try scene.entity_storage.addComponents(id.entity_id, archetype_id.*, components);
                return;
            }
        }
        // TODO: Later, maybe look through other scenes, if we will allow for
        // storing scenes for later use
        return error.sceneDoesNotExist;
    }

    pub fn insertEntity(self: *Self, id: EntityId, components: std.AutoHashMap(ComponentId, ComponentWrapper)) !void {
        if (id.scene_id == 0) {
            try self.global_entity_storage.insertEntity(id.entity_id, components);
            return;
        } else if (self.current_scene) |*scene| {
            if (scene.id == id.scene_id) {
                try scene.entity_storage.insertEntity(id.entity_id, components);
                return;
            }
        }
        // TODO: Later, maybe look through other scenes, if we will allow for
        // storing scenes for later use
        return error.sceneDoesNotExist;
    }

    pub fn setInitialScene(self: *Self, scene: Scene) !void {
        if (self.current_scene != null) {
            return error.sceneAlreadySet;
        }
        self.current_scene = scene;
        self.current_scene.?.id = self.newId();
    }

    pub fn deinit(self: *Self) void {
        self.schedule.deinit();
        if (self.current_scene) |*scene| {
            scene.deinit();
        }
        for (self.lua_systems.items) |*system| {
            system.deinit();
        }
        self.lua_systems.deinit(self.allocator);
        self.global_entity_storage.deinit();
        // INFO: components may hold references to lua so we need to
        // dealloc it last
        self.lua_state.deinit();
        self.allocator.destroy(self.idprovider);
        self.vtable_storage.deinit();
        self.allocator.destroy(self.vtable_storage);
        self.frame_allocator.deinit();
    }

    pub fn newId(self: *Self) usize {
        return self.idprovider.next();
    }

    pub fn luaLoad(self: *Self, source: []const u8) !lua.Ref {
        try self.lua_state.load(source);
        return self.lua_state.makeRef();
    }
};

pub fn addDefaultPlugins(game: *Game, export_lua: bool) !void {
    _ = try game.addResource(GameActions{ .should_close = false, .allocator = game.allocator, .log = &.{} });
    _ = try game.addResource(LuaRuntime{ .lua = &game.lua_state });
    try game.addSystem(.update, applyGameActions);
    if (export_lua) {
        game.exportComponent(GameActions);
        game.exportComponent(EntityId);
        game.idprovider.exportIdFunction(@ptrCast(game.lua_state.state));
        DynamicQuery.registerMetaTable(game.lua_state);
    }
}

pub fn registerDefaultComponentsForBuild(generator: *DeclarationGenerator) !void {
    try generator.registerComponentForBuild(GameActions);
    try generator.registerComponentForBuild(EntityId);
}

fn applyGameActions(game: *Game) void {
    var actions = game.getResource(GameActions);
    if (actions.get().should_close) {
        game.should_close = true;
    }
}

pub fn Without(comptime components: anytype) type {
    return struct {
        pub const is_query_filter: bool = true;
        pub const ComponentTypes = components;
    };
}

pub fn WrapIfNotEmpty(comptime components: anytype) if (@typeInfo(@TypeOf(components)).@"struct".fields.len == 0)
    @TypeOf(.{})
else
    @TypeOf(.{Without(components)}) {
    const field_count = @typeInfo(@TypeOf(components)).@"struct".fields.len;
    if (comptime field_count == 0) {
        return .{};
    } else {
        return .{Without(components)};
    }
}

pub fn Query(comptime components: anytype) type {
    const Filtered = utils.RemoveTypeByDecl(components, "is_query_filter");
    const InnerIter = QueryIter(Filtered);
    return struct {
        const ThisIter = @This();
        pub const ComponentTypes = utils.RemoveTypeByDecl(components, "is_query_filter");
        pub const FilterTypes = utils.ExtractTypeByDecl(components, "is_query_filter");

        global_components: InnerIter,
        scene_components: ?InnerIter,

        pub fn init(global_components: InnerIter, scene_components: ?InnerIter) ThisIter {
            return .{
                .global_components = global_components,
                .scene_components = scene_components,
            };
        }

        pub fn next(self: *ThisIter) ?PtrTuple(ComponentTypes) {
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

        pub fn single(self: *ThisIter) PtrTuple(ComponentTypes) {
            var ret: ?PtrTuple(ComponentTypes) = null;
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
        const udata: *utils.ZigPointer(Self) = @ptrCast(@alignCast(raw));
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
        const ptr: *utils.ZigPointer(Self) = @ptrCast(@alignCast(clua.lua_touserdata(state, 1)));
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

    pub fn registerMetaTable(lstate: lua.State) void {
        const state: *clua.lua_State = @ptrCast(lstate.state);
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
