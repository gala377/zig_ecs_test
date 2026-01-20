const std = @import("std");
const lua = @import("lua_lib");

const clua = lua.clib;

const utils = @import("utils.zig");
const entity_storage = @import("entity_storage.zig");

pub const ComponentId = u64;
pub const ComponentDeinit = *const fn (*anyopaque, allocator: std.mem.Allocator) void;
pub const ComponentFree = *const fn (*anyopaque, allocator: std.mem.Allocator) void;
pub const ComponentLuaPush = *const fn (*anyopaque, state: *clua.lua_State, allocator: std.mem.Allocator) void;
pub const ComponentFromLua = *const fn (state: *clua.lua_State, storage: *entity_storage) void;

fn emptyDeinit(ptr: *anyopaque, allocator: std.mem.Allocator) void {
    _ = ptr;
    _ = allocator;
}

pub const ComponentWrapper = struct {
    pub const VTable = struct {
        size: usize,
        alignment: usize,
        // Should be static
        name: []const u8,
        deinit: ComponentDeinit,
        luaPush: ?ComponentLuaPush,
        fromLua: ?ComponentFromLua,
    };
    /// opaque pointer to this component
    pointer: *anyopaque,
    /// should have static lifetime
    vtable: *const VTable,
    /// assumed to be utils.typeId(Self)
    component_id: ComponentId,
};

pub fn vtableOf(comptime T: type) *const ComponentWrapper.VTable {
    return @TypeOf(T.component_info).vtable;
}

pub fn wrap(comptime T: type, comp: *T) ComponentWrapper {
    return .{
        .component_id = utils.typeId(T),
        .pointer = @ptrCast(@alignCast(comp)),
        .vtable = vtableOf(T),
    };
}

pub fn ComponentInfo(comptime T: type, comptime name: []const u8) type {
    return struct {
        pub const comp_name = name;

        pub const vtable: *const ComponentWrapper.VTable = brk: {
            const compDeinit: ComponentDeinit = if (std.meta.hasMethod(T, "deinit"))
                @ptrCast(&T.deinit)
            else
                @ptrCast(&emptyDeinit);
            const compLuaPush: ?ComponentLuaPush = if (@hasDecl(T, "lua_info"))
                @ptrCast(&@TypeOf(T.lua_info).luaPush)
            else
                null;
            const wrapperFromLua: ?ComponentFromLua = if (@hasDecl(T, "lua_info"))
                @ptrCast(&@TypeOf(T.lua_info).wrapperFromLua)
            else
                null;
            break :brk &.{
                .alignment = @alignOf(T),
                .size = @sizeOf(T),
                .name = name,
                .deinit = compDeinit,
                .luaPush = compLuaPush,
                .fromLua = wrapperFromLua,
            };
        };

        pub fn wrapper(this: *anyopaque) ComponentWrapper {
            return .{
                .pointer = this,
                .component_id = utils.typeId(T),
                .vtable = vtable,
            };
        }
    };
}

pub fn Component(comptime T: type) ComponentInfo(T, @typeName(T)) {
    return .{};
}

pub fn LibComponent(
    comptime name_prefix: []const u8,
    comptime T: type,
) ComponentInfo(T, name_prefix ++ "." ++ @typeName(T)) {
    return .{};
}
