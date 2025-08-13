const std = @import("std");
const lua = @import("lua_lib");

const component_prefix = @import("build_options").components_prefix;
const component = @import("../component.zig");
const Component = component.LibComponent;
const ExportLua = component.ExportLua;

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
