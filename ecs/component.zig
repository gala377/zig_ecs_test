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

pub fn newComponentId(str: []const u8) u64 {
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

/// Ignore fields has to be a tuple of strings
pub fn ExportLua(comptime T: type, comptime ignore_fields: anytype) type {
    return struct {
        const MetaTableName = T.comp_name ++ "_MetaTable";
        comptime {
            checkForAllocatorNeededFields();
        }

        fn isIgnoredField(comptime field: []const u8) bool {
            inline for (ignore_fields) |ignored| {
                if (std.mem.eql(u8, field, ignored[0..])) {
                    return true;
                }
            }
            return false;
        }

        fn checkForAllocatorNeededFields() void {
            const fields = std.meta.fields(T);
            const has_allocator = @hasField(T, "allocator");
            if (comptime has_allocator) {
                return;
            }
            inline for (fields) |f| {
                const info = @typeInfo(f.type);
                if (comptime isLuaSupported(f.type) and !isIgnoredField(f.name)) {
                    switch (info) {
                        .pointer => |ptr| {
                            if (comptime ptr.size == .slice) {
                                @compileError("type has an exported field " ++ f.name ++ " that requires allocation but is missing an allocator field");
                            }
                            if (comptime ptr.size == .c and ptr.child == u8) {
                                @compileError("type has an exported field " ++ f.name ++ " that requires allocation but is missing an allocator field");
                            }
                        },
                        else => {},
                    }
                }
            }
        }

        pub fn luaPush(self: *T, state: *clua.lua_State) void {
            // std.debug.print("Pushing value of t={s}\n", .{@typeName(T)});
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
                if (isLuaSupported(f.type) and std.mem.eql(u8, f.name, asSlice) and !isIgnoredField(f.name)) {
                    luaPushValue(state, @field(ptr, f.name)) catch {
                        unreachable;
                    };
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
            const asSlice = std.mem.sliceTo(luaField, 0);
            inline for (fields) |f| {
                if (comptime isLuaSupported(f.type) and !isIgnoredField(f.name)) {
                    if (std.mem.eql(u8, f.name, asSlice)) {
                        const val = luaReadValue(state, f.type, 3, if (comptime @hasField(T, "allocator")) ptr.allocator else null) catch {
                            @panic("cought error while reading lua value");
                        };
                        if (comptime @typeInfo(f.type) == .pointer) {
                            ptr.allocator.free(@field(ptr, f.name));
                        }
                        @field(ptr, f.name) = val;
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
                if (comptime isLuaSupported(f.type) and !isIgnoredField(f.name)) {
                    try writer.print("---@field {s} {s}\n", .{ f.name, getLuaType(f.type) });
                }
            }
            try writer.writeAll("---@field private component_hash integer\n");
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
            const hash: i64 = @bitCast(T.comp_id);
            try writer.print(
                \\{s} = {{
                \\  component_hash = {d},
                \\  metatable_name = "{s}",
                \\}}
            , .{ T.comp_name, hash, MetaTableName });
            try writer.writeAll("\n");
        }
    };
}

fn getLuaType(comptime T: type) []const u8 {
    return ret: switch (@typeInfo(T)) {
        .bool => "boolean",
        .int => "integer",
        .float => "number",
        .optional => |opt| comptime {
            break :ret getLuaType(opt.child) ++ "?";
        },
        .pointer => |ptr| if (ptr.size == .slice) {
            if (ptr.child == u8) {
                break :ret "string";
            } else {
                break :ret "{ [integer]: " ++ getLuaType(ptr.child) ++ " }";
            }
        } else if (ptr.size == .c and ptr.child == u8) {
            break :ret "string";
        } else {
            break :ret "any";
        },
        else => "any",
    };
}

fn luaReadValue(state: *clua.lua_State, comptime field_type: type, index: c_int, allocator: ?std.mem.Allocator) !field_type {
    const info = @typeInfo(field_type);
    switch (info) {
        .bool => {
            if (clua.lua_type(state, index) != clua.LUA_TBOOLEAN) {
                return error.expectedBoolean;
            }
            const value = clua.lua_toboolean(state, index);
            return value == 1;
        },
        .int => {
            if (clua.lua_type(state, index) != clua.LUA_TNUMBER) {
                return error.expectedInteger;
            }
            const value = clua.lua_tointegerx(state, index, null);
            return @intCast(value);
        },
        .float => {
            if (clua.lua_type(state, index) != clua.LUA_TNUMBER) {
                return error.expectedNumber;
            }
            const value = clua.lua_tonumberx(state, index, null);
            return @floatCast(value);
        },
        .optional => |opt| {
            if (clua.lua_isnil(state, index)) {
                return null;
            }
            return try luaReadValue(state, opt.child, index, allocator);
        },
        .pointer => |ptr| if (ptr.size == .slice) {
            if (ptr.child == u8) {
                // its a string, thats a problem we need to do allocation
                if (clua.lua_type(state, index) != clua.LUA_TSTRING) {
                    return error.expectedString;
                }
                var size: usize = undefined;
                const lstr = clua.lua_tolstring(state, index, &size);
                const str = try allocator.?.dupe(u8, lstr[0..size]);
                return @ptrCast(str);
            }
            // now array
            if (clua.lua_type(state, index) != clua.LUA_TTABLE) {
                return error.expectedTable;
            }
            const len = clua.lua_rawlen(state, index);
            const res = try allocator.?.alloc(ptr.child, len);
            for (0..len) |idx| {
                clua.lua_geti(state, index, idx + 1);
                const value = try luaReadValue(state, ptr.child, -1, allocator);
                res[idx] = value;
            }
            return res;
        } else if (ptr.size == .c and ptr.child == u8) {
            return error.cStringsUnsupported;
            // its a string thats a problem, we need to do allocation
        } else {
            return error.unsupportedType;
        },
        else => |tag| {
            std.debug.print("unsupported type {s} for field", .{@tagName(tag)});
            return error.unsupportedType;
        },
    }
}

fn isLuaSupported(comptime t: type) bool {
    return switch (@typeInfo(t)) {
        .bool, .int, .float => true,
        .optional => |opt| isLuaSupported(opt.child),
        .pointer => |ptr| (ptr.size == .slice and isLuaSupported(ptr.child)) or (ptr.size == .c and ptr.child == u8),
        else => false,
    };
}

fn luaPushValue(state: *clua.lua_State, val: anytype) !void {
    const info = @typeInfo(@TypeOf(val));
    switch (info) {
        .bool => {
            clua.lua_pushboolean(state, if (val) 1 else 0);
        },
        .int => {
            clua.lua_pushinteger(state, @intCast(val));
        },
        .float => {
            clua.lua_pushnumber(state, @floatCast(val));
        },
        .optional => {
            if (val) |inner| {
                try luaPushValue(state, inner);
            } else {
                clua.lua_pushnil(state);
            }
        },
        .pointer => |ptr| if (ptr.size == .slice) {
            if (ptr.child == u8 and ptr.sentinel_ptr == null) {
                // this is a string
                _ = clua.lua_pushlstring(state, @ptrCast(val), val.len);
            } else if (ptr.child == u8) {
                @panic("sentinel strings not supported yet");
            } else {
                clua.lua_newtable(state);
                for (val, 1..) |el, index| {
                    try luaPushValue(state, el);
                    clua.lua_seti(state, -2, index);
                }
            }
        } else if (ptr.size == .c and ptr.child == u8) {
            _ = clua.lua_pushstring(state, @ptrCast(val));
        } else {
            return error.unsupportedType;
        },
        else => |tag| {
            std.debug.print("unsupported type {s} for field", .{@tagName(tag)});
            return error.unsupportedType;
        },
    }
}
