const std = @import("std");
const ecs = @import("prelude.zig");
const lua = @import("lua_lib");

const clua = lua.clib;
const dynamic_query = ecs.dynamic_query;
const lua_interop = ecs.lua;
const utils = ecs.utils;
const core = ecs.core;
const raylib = ecs.raylib;
const component = ecs.component;
const entity = ecs.entity;
const runtime = ecs.runtime;
const commands_system = runtime.commands_system;

const VTableStorage = ecs.VTableStorage;
const Schedule = ecs.Schedule;
const EntityStorage = ecs.EntityStorage;
const ExportLua = ecs.ExportLua;
const Scene = ecs.scene.Scene;
const System = ecs.system.System;
const LuaSystem = lua_interop.system;
const Component = ecs.Component;
const DynamicQueryIter = dynamic_query.DynamicQueryIter;
const DynamicQueryScope = dynamic_query.DynamicQueryScope;
const LuaAccessibleOpaqueComponent = dynamic_query.LuaAccessibleOpaqueComponent;
const DynamicScopeOptions = EntityStorage.DynamicScopeOptions;
const PtrTuple = utils.PtrTuple;
const QueryIter = ecs.query.QueryIter;
const Resource = ecs.Resource;
const GameActions = runtime.game_actions;
const LuaRuntime = runtime.lua_runtime;
const commands = runtime.commands;
const TypeRegistry = ecs.TypeRegistry;

pub const BuildOptions = struct {
    generate_lua_stub_files: bool = false,
    lua_stub_files_output: ?[]const u8 = null,
};

pub const Options = struct {
    build_options: BuildOptions = .{},
};

pub const Sentinel = usize;

const SimpleIdProvider = struct {
    inner: std.atomic.Value(usize),

    fn next(self: *SimpleIdProvider) usize {
        return self.inner.fetchAdd(1, .monotonic);
    }

    pub fn idprovider(
        self: *SimpleIdProvider,
    ) utils.IdProvider {
        return .{
            .ctx = @ptrCast(self),
            .nextFn = @ptrCast(&next),
        };
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

    idprovider: SimpleIdProvider,

    schedule: Schedule,

    global_entity_storage: EntityStorage,
    vtable_storage: VTableStorage,
    type_registry: TypeRegistry,
    systems_registry: ecs.SystemsRegistry,

    pub fn init(allocator: std.mem.Allocator, options: Options) !Self {
        return .{
            .allocator = allocator,
            .lua_state = try .init(allocator),
            .should_close = false,
            .options = options,
            .current_scene = null,
            .global_entity_storage = try EntityStorage.init(allocator),
            .idprovider = .{
                // skip 0 as this is special id used to
                // indentify persistant entities (global entities)
                .inner = .init(1),
            },
            .vtable_storage = .init(allocator),
            .frame_allocator = .init(std.heap.c_allocator),
            .schedule = Schedule.init(allocator),
            .type_registry = .init(allocator),
            .systems_registry = .init(allocator),
        };
    }

    /// Run one iteration of systems without
    /// graphical window and context, also skips setup
    /// and runtime initialization.
    ///
    /// Useful for testing systems.
    pub fn runHeadlessOnce(self: *Self) !void {
        try self.schedule.runPhase(.pre_update, self);
        try self.schedule.runPhase(.update, self);
        try self.schedule.runPhase(.post_update, self);
        try self.schedule.runPhase(.render, self);
        try self.schedule.runPhase(.post_render, self);
        try self.schedule.runPhase(.tear_down, self);
    }

    pub fn run(self: *Self) !void {
        try self.schedule.runPhase(.setup, self);

        while (!self.should_close) {
            // const start = try std.time.Instant.now();
            try self.schedule.runPhase(.pre_update, self);
            try self.schedule.runPhase(.update, self);
            try self.schedule.runPhase(.post_update, self);

            try self.schedule.runPhase(.pre_render, self);
            try self.schedule.runPhase(.render, self);
            try self.schedule.runPhase(.post_render, self);

            try self.schedule.runPhase(.tear_down, self);
        }
        try self.schedule.runPhase(.close, self);
    }

    /// TODO: Runtime and core split doesn't make much sense honestly.
    /// I think with things like Commands it makes sense but not much more honestly.
    pub fn installRuntime(self: *Self) !void {
        try self.type_registry.registerStdTypes();
        try self.schedule.addDefaultSchedule();
        try runtime.install(self);
        try self.addResource(GameActions{
            .should_close = false,
            .log = &.{},
        });

        try self.type_registry.registerType(GameActions);
        try self.type_registry.registerType(ecs.resource.ResourceMarker);
        try self.type_registry.registerType(commands);
        try self.addResource(commands.init(self));
        try self.addSystems(.post_update, &.{
            ecs.system.labeledSystem("core.applyGameActions", applyGameActions),
            ecs.system.labeledSystem("commands.create_entities", commands_system.create_entities),
        });
        try core.install(self);
    }

    pub fn exportComponent(self: *Self, comptime Comp: type) void {
        std.debug.print("Exporting {s} = {any}\n", .{
            @typeName(Comp),
            utils.typeId(Comp),
        });
        @TypeOf(Comp.lua_info).registerMetaTable(self.lua_state);
        @TypeOf(Comp.lua_info).exportId(
            self.lua_state.state,
            self.allocator,
        ) catch {
            @panic("could not export component to lua");
        };
    }

    pub fn query(
        self: *Self,
        comptime components: anytype,
        comptime exclude: anytype,
    ) Query(components ++ WrapIfNotEmpty(exclude)) {
        const global_components = self.global_entity_storage.query(
            components,
            exclude,
        );
        const scene_components = if (self.current_scene) |*s| brk: {
            break :brk s.entity_storage.query(components, exclude);
        } else null;
        return Query(components ++ WrapIfNotEmpty(exclude)).init(
            global_components,
            scene_components,
        );
    }

    pub fn dynamicQueryScope(
        self: *Self,
        components: []const component.Id,
        exclude: []const component.Id,
    ) !JoinedDynamicScope {
        const global_scope = try self.global_entity_storage.dynamicQueryScope(
            components,
            exclude,
            .{},
        );
        const scene_scope = if (self.current_scene) |*s| brk: {
            break :brk try s.entity_storage.dynamicQueryScope(
                components,
                exclude,
                .{},
            );
        } else null;
        return JoinedDynamicScope{
            .global_scope = global_scope,
            .scene_scope = scene_scope,
            .allocator = self.allocator,
        };
    }

    pub fn dynamicQueryScopeOpts(
        self: *Self,
        components: []const component.Id,
        exclude: []const component.Id,
        options: DynamicScopeOptions,
    ) !JoinedDynamicScope {
        const global_scope = try self.global_entity_storage.dynamicQueryScope(
            components,
            exclude,
            options,
        );
        const scene_scope = if (self.current_scene) |*s| brk: {
            break :brk try s.entity_storage.dynamicQueryScope(
                components,
                exclude,
                options,
            );
        } else null;
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
        const tname = @typeName(@TypeOf(resource));
        _ = try self.newGlobalEntity(.{
            resource,
            ecs.resource.ResourceMarker{},
            ecs.core.Name.init(tname),
        });
    }

    pub fn addEvent(self: *Self, comptime T: type) !void {
        _ = try self.newGlobalEntity(.{
            runtime.events.EventBuffer(T){
                .allocator = self.allocator,
                .events = &.{},
            },
            runtime.events.EventWriterBuffer(T){
                .allocator = self.allocator,
                .events = .empty,
            },
        });
        try self.type_registry.registerType(runtime.events.EventBuffer(T));
        try self.type_registry.registerType(runtime.events.EventWriterBuffer(T));
        try self.addSystems(
            .tear_down,
            &.{runtime.events.eventSystem(T)},
        );
    }

    /// Add a system defined in lua.
    ///
    /// The lua file should return a system built with system builder
    pub fn addLuaSystem(self: *Self, phase: Schedule.Phase, path: []const u8) !void {
        const cwd = std.fs.cwd();
        var file = try cwd.openFile(path, .{});
        defer file.close();
        const contents = try file.readToEndAlloc(
            self.allocator,
            std.math.maxInt(usize),
        );
        defer self.allocator.free(contents);
        try self.lua_state.loadWithName(contents, path);
        const system = try LuaSystem.fromLua(
            self.lua_state,
            self.allocator,
        );
        try self.schedule.add(
            phase,
            try system.intoSystem(),
        );
    }

    /// Add multiple systems from lua.
    ///
    /// The lua file should return an array of systems built wiht system builder.
    pub fn addLuaSystems(self: *Self, phase: Schedule.Phase, path: []const u8) !void {
        const cwd = std.fs.cwd();
        var file = try cwd.openFile(path, .{});
        defer file.close();
        const contents = try file.readToEndAlloc(
            self.allocator,
            std.math.maxInt(usize),
        );
        defer self.allocator.free(contents);
        self.lua_state.loadWithName(contents, path) catch |err| {
            std.debug.print(
                "got arror when loading lua thing {any}\n",
                .{err},
            );
            return err;
        };
        if (clua.lua_type(@ptrCast(self.lua_state.state), -1) != clua.LUA_TTABLE) {
            return error.expectedTable;
        }
        const len = clua.lua_rawlen(
            @ptrCast(self.lua_state.state),
            -1,
        );
        for (0..len) |idx| {
            _ = clua.lua_geti(@ptrCast(self.lua_state.state), -1, @intCast(idx + 1));
            const system = try LuaSystem.fromLua(
                self.lua_state,
                self.allocator,
            );
            try self.schedule.add(
                phase,
                try system.intoSystem(),
            );
        }
        try self.lua_state.pop();
    }

    /// Add a zig functionas a system to a specific phase.
    pub fn addSystem(self: *Self, phase: Schedule.Phase, comptime sys: anytype) !void {
        try self.schedule.add(
            phase,
            ecs.system.func(sys),
        );
    }

    pub fn addLabeledSystemToSchedule(
        self: *Self,
        phase: Schedule.Phase,
        label: anytype,
        name: []const u8,
        comptime sys: anytype,
    ) !void {
        try self.schedule.addToSchedule(
            phase,
            label,
            ecs.system.labeledSystem(name, sys),
        );
    }

    pub fn addSystemToSchedule(
        self: *Self,
        phase: Schedule.Phase,
        label: anytype,
        comptime sys: anytype,
    ) !void {
        try self.schedule.addToSchedule(
            phase,
            label,
            ecs.system.func(sys),
        );
    }

    /// Add multiple systems to specific phase.
    ///
    /// Those systems have to be already wrapped into a System interface
    /// TODO: We need to think about what interface we want to expose as addSystem and addSystems have different api
    pub fn addSystems(
        self: *Self,
        phase: Schedule.Phase,
        systems: []const System,
    ) !void {
        for (systems) |s| {
            try self.schedule.add(phase, s);
        }
    }

    pub fn addSystemsToSchedule(
        self: *Self,
        phase: Schedule.Phase,
        schedule: anytype,
        systems: []const System,
    ) !void {
        for (systems) |s| {
            try self.schedule.addToSchedule(
                phase,
                schedule,
                s,
            );
        }
    }

    pub fn newGlobalEntity(self: *Self, components: anytype) !entity.Id {
        const id = self.newId();
        const entity_id = entity.Id{
            .scene_id = 0,
            .entity_id = id,
        };
        const with_id = .{entity_id} ++ components;
        try self.global_entity_storage.add(
            entity_id,
            with_id,
        );
        return entity_id;
    }

    pub fn removeEntities(self: *Self, ids: []entity.Id) !void {
        var global_entities = std.ArrayList(entity.Id).empty;
        defer global_entities.deinit(self.allocator);
        var scene_entities = std.ArrayList(entity.Id).empty;
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
            try self.global_entity_storage.remove(global_entities.items);
        }
        if (scene_entities.items.len > 0) {
            try self.current_scene.?.entity_storage.remove(scene_entities.items);
        }
    }

    // Adds components to a given entity.
    //
    // Does not take ownership over a slice of components.
    pub fn addComponents(self: *Self, id: entity.Id, components: []component.Opaque) !void {
        if (id.scene_id == 0) {
            try self.global_entity_storage.addComponents(
                id,
                components,
            );
            return;
        } else if (self.current_scene) |*scene| {
            if (scene.id == id.scene_id) {
                try scene.entity_storage.addComponents(
                    id,
                    components,
                );
                return;
            }
        }
        // TODO: Later, maybe look through other scenes, if we will allow for
        // storing scenes for later use
        return error.sceneDoesNotExist;
    }

    pub fn newEntityWrapped(self: *Self, id: entity.Id, components: []const component.Opaque) !void {
        if (id.scene_id == 0) {
            try self.global_entity_storage.addWrapped(
                id,
                components,
            );
            return;
        } else if (self.current_scene) |*scene| {
            if (scene.id == id.scene_id) {
                try scene.entity_storage.addWrapped(
                    id,
                    components,
                );
                return;
            }
        }
        // TODO: Later, maybe look through other scenes, if we will allow for
        // storing scenes for later use
        return error.sceneDoesNotExist;
    }

    pub fn newScene(self: *Self) !Scene {
        return .init(
            self.newId(),
            self.idprovider.idprovider(),
            self.allocator,
        );
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
        self.global_entity_storage.deinit();
        // components may hold references to lua so we need to
        // dealloc lua runtime after components
        self.lua_state.deinit();

        self.vtable_storage.deinit();
        self.frame_allocator.deinit();
        self.type_registry.deinit();
        self.systems_registry.deinit();
    }

    pub fn newId(self: *Self) usize {
        return self.idprovider.next();
    }

    pub fn luaLoad(self: *Self, source: []const u8) !lua.Ref {
        try self.lua_state.load(source);
        return self.lua_state.makeRef();
    }
};

/// Convienience function that adds the most important plugins.
pub fn addDefaultPlugins(game: *Game, export_lua: bool, window_options: core.window.WindowOptions) !void {
    try raylib.install(game, window_options, true);
    try ecs.zgui.install(game);
    try game.addResource(LuaRuntime{ .lua = &game.lua_state });
    try ecs.lua.install(game);
    try ecs.imgui.install(game);
    if (export_lua) {
        // TODO: this one is weird as we add game actions in the runtime
        // but we expose them to lua here
        game.exportComponent(GameActions);
        game.exportComponent(entity.Id);
        game.exportComponent(core.Vec2);
        game.exportComponent(core.Position);
        game.exportComponent(core.Style);
        game.exportComponent(core.Color);
        DynamicQuery.registerMetaTable(game.lua_state);
    }
    try game.type_registry.registerStruct(entity.Id);
    try game.type_registry.registerStruct(LuaRuntime);
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
    lua_components_table: c_int = 0,

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

    pub fn luaPush(self: *Self, state: *clua.lua_State, allocator: std.mem.Allocator) void {
        // std.debug.print("Pushing value of t={s}\n", .{@typeName(Self)});
        const raw = clua.lua_newuserdata(
            state,
            @sizeOf(utils.ZigPointer(Self)),
        ) orelse @panic("lua could not allocate memory");
        const udata: *utils.ZigPointer(Self) = @ptrCast(@alignCast(raw));
        udata.* = utils.ZigPointer(Self){
            .ptr = self,
            .allocator = allocator,
        };
        if (clua.luaL_getmetatable(state, MetaTableName) == 0) {
            @panic("Metatable " ++ MetaTableName ++ "not found");
        }
        // Assign the metatable to the userdata (stack: userdata, metatable)
        if (clua.lua_setmetatable(state, -2) != 0) {
            // @panic("object " ++ @typeName(T) ++ " already had a metatable");
        }
        clua.lua_createtable(
            state,
            @intCast(self.global_components.component_ids.len),
            0,
        );
        self.lua_components_table = clua.luaL_ref(state, clua.LUA_REGISTRYINDEX);
    }

    pub fn luaNext(state: *clua.lua_State) callconv(.c) c_int {
        // std.debug.print("calling next in zig\n", .{});
        const ptr: *utils.ZigPointer(Self) = @ptrCast(@alignCast(clua.lua_touserdata(
            state,
            1,
        )));
        const self = ptr.ptr;
        const rest = self.next();
        if (rest == null) {
            clua.lua_pushnil(state);
            return 1;
        }
        // get component pointers
        const components = rest.?;

        _ = clua.lua_rawgeti(state, clua.LUA_REGISTRYINDEX, self.lua_components_table);

        for (components, 1..) |comp, idx| {
            comp.push(
                comp.pointer,
                state,
                self.allocator,
            );
            clua.lua_seti(state, -2, @intCast(idx));
        }
        self.allocator.free(components);
        return 1;
    }

    pub fn registerMetaTable(lstate: lua.State) void {
        const state: *clua.lua_State = lstate.state;
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

    pub fn deinit(self: *Self, state: lua.State) void {
        if (self.lua_components_table != 0) {
            lua.clib.luaL_unref(
                state.state,
                lua.clib.LUA_REGISTRYINDEX,
                self.lua_components_table,
            );
        }
    }
};
