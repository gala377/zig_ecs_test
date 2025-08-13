const std = @import("std");
const component_prefix = @import("build_options").components_prefix;

const lua = @import("lua_lib");
const clua = lua.clib;
const rg = @import("raygui");
const rl = @import("raylib");

const runtime = @import("runtime/components.zig");
const Component = @import("component.zig").LibComponent;
const ComponentId = @import("component.zig").ComponentId;
const ComponentWrapper = @import("entity_storage.zig").ComponentWrapper;
const DeclarationGenerator = @import("declaration_generator.zig");
const DynamicQueryIter = @import("dynamic_query.zig").DynamicQueryIter;
const DynamicQueryScope = @import("dynamic_query.zig").DynamicQueryScope;
const DynamicScopeOptions = @import("entity_storage.zig").DynamicScopeOptions;
const Entity = @import("entity.zig");
const EntityId = Entity.EntityId;
const EntityStorage = @import("entity_storage.zig");
const ExportLua = @import("component.zig").ExportLua;
const VTableStorage = @import("comp_vtable_storage.zig");
const LuaAccessibleOpaqueComponent = @import("dynamic_query.zig").LuaAccessibleOpaqueComponent;
const LuaSystem = @import("lua_system.zig");
const PtrTuple = @import("utils.zig").PtrTuple;
const Resource = @import("resource.zig").Resource;
const Scene = @import("scene.zig").Scene;
const commands = @import("runtime/commands.zig");
const commands_system = @import("runtime/commands_system.zig");
const component_mod = @import("component.zig");
const mksystem = @import("system.zig").system;
const utils = @import("utils.zig");
const QueryIter = @import("query.zig").QueryIter;

const GameActions = @import("runtime/components.zig").GameActions;
const LuaRuntime = @import("runtime/components.zig").LuaRuntime;

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
        const self: *SimpleIdProvider = @alignCast(@ptrCast(clua.lua_touserdata(state, clua.lua_upvalueindex(1))));
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
    lua_state: lua.State,

    // internal state
    should_close: bool,
    current_scene: ?Scene,

    inner_id: usize,
    systems: std.ArrayList(System),
    deffered_systems: std.ArrayList(System),
    lua_systems: std.ArrayList(LuaSystem),
    global_entity_storage: EntityStorage,
    seen_components: std.AutoHashMap(u64, []const u8),
    idprovider: *SimpleIdProvider,
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
            .systems = .init(allocator),
            .deffered_systems = .init(allocator),
            .current_scene = null,
            .global_entity_storage = try EntityStorage.init(allocator, id_provider.idprovider(), vtable_storage),
            .lua_systems = .init(allocator),
            .seen_components = .init(allocator),
            .idprovider = id_provider,
            .vtable_storage = vtable_storage,
        };
    }

    pub fn run(self: *Self) !void {
        try self.installRuntime();

        rl.setConfigFlags(.{ .window_highdpi = true });
        rl.setTargetFPS(self.options.window.targetFps);
        rl.initWindow(self.options.window.size.width, self.options.window.size.height, self.options.window.title);
        defer rl.closeWindow();

        // var iters: usize = 1;
        // var total: usize = 0;
        while (!self.should_close) : (self.should_close = rl.windowShouldClose() or self.should_close) {
            // const start = try std.time.Instant.now();
            rl.beginDrawing();
            for (self.systems.items) |sys| {
                sys(self);
            }
            for (self.lua_systems.items) |*sys| {
                sys.run(self, self.lua_state) catch {
                    @panic("could not run lua system");
                };
            }
            const fps = rl.getFPS();
            const frame_time = rl.getFrameTime();
            var buf: [10000]u8 = undefined;
            const numAsString = try std.fmt.bufPrintZ(&buf, "FPS: {:5}, frame time: {:.3}", .{ fps, frame_time });
            rl.drawText(numAsString, 0, 0, 16, rl.Color.white);

            for (self.deffered_systems.items) |sys| {
                sys(self);
            }
            rl.clearBackground(.black);
            rl.endDrawing();

            // const end = try std.time.Instant.now();
            // const elapsed_ns = end.since(start);
            // total += elapsed_ns;
            // const avg = total / iters;
            // const seconds_per_frame = @as(f64, @floatFromInt(avg)) / 1_000_000_000.0;
            // const fps = 1.0 / seconds_per_frame;
            // iters += 1;
            // std.debug.print("FPS: {d:.2}\n", .{fps});
        }
    }

    fn installRuntime(self: *Self) !void {
        try self.addResource(commands.init(self, self.allocator));
        try self.addDefferedSystem(mksystem(commands_system.create_entities));
    }

    pub fn exportComponent(self: *Self, comptime Comp: type) void {
        Comp.registerMetaTable(self.lua_state);
        Comp.exportId(self.lua_state.state, self.idprovider.idprovider(), self.allocator) catch {
            @panic("could not export component to lua");
        };
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

    pub fn newScene(self: *Self) !Scene {
        return .init(self.newId(), self.idprovider.idprovider(), self.allocator, self.vtable_storage);
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

    pub fn addEvent(self: *Self, comptime T: type) !void {
        _ = try self.newGlobalEntity(.{
            runtime.EventBuffer(T){ .allocator = self.allocator, .events = &.{} },
            runtime.EventWriterBuffer(T){ .events = .init(self.allocator) },
        });
        try self.addDefferedSystem(runtime.eventSystem(T));
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
        const with_id = .{EntityId{
            .scene_id = 0,
            .entity_id = id,
        }} ++ components;
        try self.global_entity_storage.makeEntity(id, with_id);

        return .{ .scene_id = 0, .entity_id = id };
    }

    pub fn removeEntities(self: *Self, ids: []EntityId) !void {
        var global_entities = std.ArrayList(usize).init(self.allocator);
        defer global_entities.deinit();
        var scene_entities = std.ArrayList(usize).init(self.allocator);
        defer scene_entities.deinit();
        for (ids) |id| {
            if (id.scene_id == 0) {
                try global_entities.append(id.entity_id);
                continue;
            }
            if (self.current_scene) |*scene| {
                if (scene.id == id.scene_id) {
                    try scene_entities.append(id.entity_id);
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
        var names = self.seen_components.valueIterator();
        while (names.next()) |name| {
            self.allocator.free(name.*);
        }
        self.seen_components.deinit();
        self.allocator.destroy(self.idprovider);
        self.vtable_storage.deinit();
        self.allocator.destroy(self.vtable_storage);
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
    try game.addSystem(&applyGameActions);
    if (export_lua) {
        game.exportComponent(GameActions);
        game.exportComponent(EntityId);
        game.idprovider.exportIdFunction(game.lua_state.state);
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

pub fn Query(comptime components: anytype) type {
    const InnerIter = QueryIter(components);
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

    pub fn registerMetaTable(lstate: lua.State) void {
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
