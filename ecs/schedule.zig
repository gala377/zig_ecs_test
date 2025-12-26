const std = @import("std");

const system = @import("system.zig");
const System = system.System;

const Self = @This();

setup_systems: std.ArrayList(System),
update_systems: std.ArrayList(System),
lua_systems: std.ArrayList(LuaSystem),
render_systems: std.ArrayList(System),
deffered_systems: std.ArrayList(System),
tear_down_system: std.ArrayList(System),

allocator: std.mem.Allocator,
