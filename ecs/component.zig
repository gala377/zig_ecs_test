const lua = @import("lua_lib");
const clua = lua.clib;
const std = @import("std");
const utils = @import("utils.zig");

fn simpleHashString(comptime str: []const u8) u64 {
    var hash: u64 = 5381;
    for (str) |c| {
        hash = ((hash << 5) +% hash) +% @as(u64, c); // hash * 33 + c
    }
    return hash;
}

pub const ComponentId = u64;

pub fn Component(comptime T: type) type {
    return struct {
        pub const is_component_marker: void = void{};
        pub const comp_id: ComponentId = simpleHashString(@typeName(T));
        pub const comp_name: []const u8 = @typeName(T);
    };
}

pub fn LibComponent(comptime name_prefix: []const u8, comptime T: type) type {
    const expanded_name = name_prefix ++ "." ++ @typeName(T);
    return struct {
        pub const is_component_marker: void = void{};
        pub const comp_id: ComponentId = simpleHashString(expanded_name);
        pub const comp_name: []const u8 = expanded_name;
    };
}

pub fn ExportLua(comptime T: type) type {
    return struct {
        const MetaTableName = T.comp_name ++ "_MetaTable";

        pub fn luaPush(self: *T, state: *clua.lua_State) void {
            std.debug.print("Pushing value of t={s}\n", .{@typeName(T)});
            const allocated = clua.lua_newuserdata(state, @sizeOf(utils.ZigPointer(T))) orelse @panic("lua could not allocate");
            const udata = @as(*utils.ZigPointer(T), @alignCast(@ptrCast(allocated)));
            udata.* = utils.ZigPointer(T){ .ptr = self };
            if (clua.luaL_getmetatable(state, MetaTableName) == 0) {
                @panic("Metatable " ++ MetaTableName ++ "not found");
            }
            // Assign the metatable to the userdata (stack: userdata, metatable)
            if (clua.lua_setmetatable(state, -2) != 0) {
                // @panic("object " ++ @typeName(T) ++ " already had a metatable");
            }
        }

        pub fn luaIndex(state: *clua.lua_State) callconv(.c) c_int {
            if (comptime @typeInfo(T) != .@"struct") {
                @compileError("component has to be a struct");
            }
            const fields = std.meta.fields(T);
            const udata: *utils.ZigPointer(T) = @alignCast(@ptrCast(clua.lua_touserdata(state, 1)));
            const ptr: *T = @alignCast(@ptrCast(udata.ptr));
            const luaField = clua.lua_tolstring(state, 2, null);
            inline for (fields) |f| {
                const asSlice = std.mem.sliceTo(luaField, 0);
                if (std.mem.eql(u8, f.name, asSlice)) {
                    const info = @typeInfo(f.type);
                    switch (info) {
                        .bool => {
                            const val = @field(ptr, f.name);
                            clua.lua_pushboolean(state, if (val) 1 else 0);
                        },
                        .int => {
                            const val = @field(ptr, f.name);
                            clua.lua_pushinteger(state, @intCast(val));
                        },
                        else => |tag| {
                            std.debug.print("unsupported type {s} for field {s}", .{ @tagName(tag), f.name });
                            clua.lua_pushnil(state);
                        },
                    }
                }
            }
            return 1;
        }

        pub fn luaNewIndex(state: *clua.lua_State) callconv(.c) c_int {
            if (comptime @typeInfo(T) != .@"struct") {
                @compileError("component has to be a struct");
            }
            const fields = std.meta.fields(T);
            const udata: *utils.ZigPointer(T) = @alignCast(@ptrCast(clua.lua_touserdata(state, 1)));
            const ptr: *T = @alignCast(@ptrCast(udata.ptr));
            const luaField = clua.lua_tolstring(state, 2, null);
            inline for (fields) |f| {
                const asSlice = std.mem.sliceTo(luaField, 0);
                if (std.mem.eql(u8, f.name, asSlice)) {
                    const info = @typeInfo(f.type);
                    switch (info) {
                        .bool => {
                            const value = clua.lua_toboolean(state, 3);
                            @field(ptr, f.name) = if (value == 1) true else false;
                        },
                        .int => {
                            const value = clua.lua_tointegerx(state, 3, null);
                            @field(ptr, f.name) = @intCast(value);
                        },
                        else => |tag| {
                            std.debug.print("unsupported type {s} for field {s}", .{ @tagName(tag), f.name });
                        },
                    }
                }
            }
            return 0;
        }

        pub fn registerMetaTable(lstate: lua.State) void {
            const state = lstate.state;
            if (comptime @typeInfo(T) != .@"struct") {
                @compileError("component has to be a struct");
            }
            if (clua.luaL_newmetatable(state, MetaTableName) != 1) {
                @panic("Could not create metatable");
            }

            clua.lua_pushcclosure(state, @ptrCast(&luaIndex), 0);
            clua.lua_setfield(state, -2, "__index");

            clua.lua_pushcclosure(state, @ptrCast(&luaNewIndex), 0);
            clua.lua_setfield(state, -2, "__newindex");

            clua.lua_pop(state, 1);
        }

        pub fn luaGenerateStubFile(writer: std.io.AnyWriter) !void {
            try writer.print("---@class {s}\n", .{T.comp_name});
            const fields = std.meta.fields(T);
            inline for (fields) |f| {
                const info = @typeInfo(f.type);
                switch (info) {
                    .bool => {
                        try writer.print("---@field {s} {s}\n", .{ f.name, "boolean" });
                    },
                    .int => {
                        try writer.print("---@field {s} {s}\n", .{ f.name, "integer" });
                    },
                    else => {},
                }
            }
            try writer.writeAll("---@field private component_hash string\n");
            try writer.writeAll("---@field private metatable_name string\n");
            const emit_local = std.mem.indexOfScalar(u8, T.comp_name, '.') == null;
            if (emit_local) {
                try writer.writeAll("local ");
            }
            try writer.print("{s} = {{}}\n\n", .{T.comp_name});
        }

        pub fn luaGenerateDataDefinition(writer: std.io.AnyWriter) !void {
            try writer.print("---@type {s}\n", .{T.comp_name});
            const emit_local = std.mem.indexOfScalar(u8, T.comp_name, '.') == null;
            if (emit_local) {
                try writer.writeAll("local ");
            }
            try writer.print(
                \\{s} = {{
                \\  component_hash = "{}",
                \\  metatable_name = "{s}",
                \\}}
            , .{ T.comp_name, T.comp_id, MetaTableName });
            try writer.writeAll("\n");
        }
    };
}
