const build_options = @import("build_options");

pub const component = @import("component.zig");
pub const game = @import("game.zig");
pub const utils = @import("utils.zig");
pub const query = @import("query.zig");
pub const system = @import("system.zig");
pub const resource = @import("resource.zig");
pub const entity = @import("entity.zig");
pub const dynamic_query = @import("dynamic_query.zig");
pub const runtime = @import("runtime/runtime.zig");
pub const scene = @import("scene.zig");
pub const core = @import("core/core.zig");
pub const imgui = @import("imgui/imgui.zig");
pub const raylib = @import("raylib/raylib.zig");
pub const lua = @import("lua_interop/lua_interop.zig");
pub const type_registry = @import("type_registry.zig");

pub const Schedule = @import("schedule.zig");
pub const EntityStorage = @import("entity_storage.zig");
pub const Marker = @import("marker.zig");
pub const VTableStorage = @import("comp_vtable_storage.zig");
pub const Game = game.Game;
pub const Query = game.Query;
pub const Resource = resource.Resource;
pub const Scene = scene.Scene;
pub const TypeRegistry = type_registry.TypeRegistry;

pub fn Component(comptime T: type) component.MetaData(
    T,
    componentName(T),
) {
    return component.LibComponent(
        build_options.components_prefix,
        T,
    );
}

pub fn ExportLua(
    comptime T: type,
    comptime options: lua.export_component.ExportOptions(T),
) lua.export_component.MetaData(
    T,
    luaExportOptions(T, options),
) {
    return lua.export_component.ExportLua(
        T,
        luaExportOptions(T, options),
    );
}

fn componentName(comptime T: type) []const u8 {
    return build_options.components_prefix ++ "." ++ @typeName(T);
}

fn luaExportOptions(
    comptime T: type,
    comptime options: lua.export_component.ExportOptions(T),
) lua.export_component.ExportOptions(T) {
    comptime {
        if (options.name_prefix.len == 0) {
            var changed = options;
            changed.name_prefix = build_options.components_prefix;
            return changed;
        }
        return options;
    }
}
