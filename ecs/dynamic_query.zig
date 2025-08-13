const Storage = @import("entity_storage.zig");
const ComponentId = @import("component.zig").ComponentId;
const LuaPush = @import("entity_storage.zig").ComponentLuaPush;
const std = @import("std");
const Entity = @import("entity.zig");
const utils = @import("utils.zig");
const lua = @import("lua_lib");
const clua = lua.clib;

// Because dunamic query cannot decide the amount of components at comptime
// the returned components are returned as a slice allocated by the iterator.
//
// This means that after they have been processed the slice has to be freed
// with scope.freeComponentsSlice
//
// Also as there are allocations that Scope needs to do (because of the runtime
// nature of the query) scope has to deinited.
// So the usage actually looks like this.
//
// var scope = storage.dynamicQueryScope(component_ids, .{});
// defer scope.deinit();
//
// var iter = scope.iter();
// while(iter.next()) |components| {
//    defer scope.freeComponentsSlice(components);
//    // do something with component pointers
// }
//
// slices are not freed by deinit in case the caller wants to take ownership of the
// slice, just mind that it uses Storage allocator unless another is passed in options.
//
// var scope = storage.dynamicQueryScope(component_ids, .{ allocator = myAlloc });
pub const DynamicQueryScope = struct {
    component_ids: []const ComponentId,
    sorted_component_ids: []const ComponentId,
    storage: *Storage,
    allocator: std.mem.Allocator,
    cache: []const usize,

    pub fn init(storage: *Storage, component_ids: []const ComponentId, allocator: std.mem.Allocator) !DynamicQueryScope {
        const sorted = try allocator.dupe(ComponentId, component_ids);
        std.sort.heap(ComponentId, sorted, {}, std.sort.asc(ComponentId));
        const cache = try storage.lookupQueryHash(sorted);
        return .{
            .component_ids = component_ids,
            .sorted_component_ids = sorted,
            .storage = storage,
            .allocator = allocator,
            .cache = cache,
        };
    }

    pub fn iter(self: *DynamicQueryScope) DynamicQueryIter {
        return .{
            .component_ids = self.component_ids,
            .sorted_component_ids = self.sorted_component_ids,
            .storage = self.storage,
            .allocator = self.allocator,
            .cache = self.cache,
        };
    }

    pub fn freeComponentsSlice(self: *DynamicQueryScope, slice: []*anyopaque) void {
        self.allocator.free(slice);
    }

    pub fn deinit(self: *DynamicQueryScope) void {
        self.allocator.free(self.sorted_component_ids);
    }
};

pub const DynamicQueryIter = struct {
    const Self = @This();
    const MetaTableName = @typeName(Self) ++ "_MetaTable";

    component_ids: []const ComponentId,
    sorted_component_ids: []const ComponentId,
    storage: *Storage,
    next_archetype: usize = 0,
    current_entity_iterator_pos: usize = 0,
    current_entity_iterator: []Entity = &.{},
    allocator: std.mem.Allocator,
    cache: []const usize,

    pub fn next(self: *Self) ?[]LuaAccessibleOpaqueComponent {
        if (self.current_entity_iterator_pos < self.current_entity_iterator.len) {
            const entity: *Entity = &self.current_entity_iterator[self.current_entity_iterator_pos];
            self.current_entity_iterator_pos += 1;
            return self.getComponentsFromEntity(entity);
        }
        return self.lookupCached(self.cache);
    }

    fn lookupCached(self: *Self, cache: []const usize) ?[]LuaAccessibleOpaqueComponent {
        while (self.next_archetype < cache.len) {
            const archetype_index = cache[self.next_archetype];
            self.current_entity_iterator = self
                .storage
                .archetypes
                .items[archetype_index]
                .entities
                .values();
            self.current_entity_iterator_pos = 0;
            self.next_archetype += 1;
            if (self.current_entity_iterator_pos < self.current_entity_iterator.len) {
                const entity: *Entity = &self.current_entity_iterator[self.current_entity_iterator_pos];
                self.current_entity_iterator_pos += 1;
                return self.getComponentsFromEntity(entity);
            }
        }
        return null;
    }

    fn getComponentsFromEntity(self: *Self, entity: *Entity) []LuaAccessibleOpaqueComponent {
        var res = self.allocator.alloc(LuaAccessibleOpaqueComponent, self.component_ids.len) catch {
            @panic("oom");
        };
        for (self.component_ids, 0..) |id, idx| {
            const comp = entity.components.getPtr(id).?;
            const wrapped = LuaAccessibleOpaqueComponent{
                .pointer = comp.pointer,
                .push = comp.vtable.luaPush.?,
            };
            res[idx] = wrapped;
        }
        return res;
    }

    pub fn luaPush(self: *Self, state: *clua.lua_State) void {
        // std.debug.print("Pushing value of t={s}\n", .{@typeName(Self)});
        const udata: *utils.ZigPointer(Self) = clua.lua_newuserdata(state, @sizeOf(utils.ZigPointer(Self))) orelse @panic("lua could not allocate memory");
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

pub const LuaAccessibleOpaqueComponent = struct {
    pointer: *anyopaque,
    push: LuaPush,
};
