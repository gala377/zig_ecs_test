const lua = @import("lua_lib");
const clua = lua.clib;
const std = @import("std");
const utils = @import("utils.zig");

fn simpleHashString(comptime str: []const u8) u64 {
    var hash: u64 = 0xcbf29ce484222325; // FNV offset basis
    const prime: u64 = 0x100000001b3;

    inline for (str) |b| { // inline so comptime can fully unroll
        hash ^= b;
        hash *%= prime; // wrapping multiply
    }
    return hash;
}

pub fn newComponentId(str: []const u8) u64 {
    var hash: u64 = 0xcbf29ce484222325; // FNV offset basis
    const prime: u64 = 0x100000001b3;
    for (str) |b| { // inline so comptime can fully unroll
        hash ^= b;
        hash *%= prime; // wrapping multiply
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

pub fn SliceProxy(comptime Slice: type) type {
    const info = @typeInfo(Slice);
    if (comptime info != .pointer and info.pointer.size != .slice) {
        @compileError("Expected a slice");
    }
    const slice_info = @typeInfo(Slice).pointer;
    const Element = slice_info.child;
    return struct {
        const MetaTableName = "SliceProxy(" ++ @typeName(Element) ++ ").MetaTable";
        const Self = @This();
        slice: *Slice,
        allocator: std.mem.Allocator,

        pub fn luaPush(slice: *Slice, allocator: std.mem.Allocator, state: *clua.lua_State) void {
            // std.debug.print("Pushing the proxy {s} of size {d} full proxy name {s}\n", .{ @typeName(Slice), @sizeOf(Self), @typeName(Self) });
            const allocated = clua.lua_newuserdata(state, @sizeOf(Self)) orelse @panic("lua could not allocate");
            const self = @as(*Self, @alignCast(@ptrCast(allocated)));
            // std.debug.print("Got address {d}\n", .{@intFromPtr(self)});
            self.* = Self{ .slice = slice, .allocator = allocator };
            if (clua.luaL_getmetatable(state, MetaTableName) == 0) {
                clua.lua_pop(state, 1);
                createMetaTableAndPush(state);
            }
            if (clua.lua_setmetatable(state, -2) != 0) {}
            if (clua.lua_type(state, -1) != clua.LUA_TUSERDATA) {
                std.debug.panic("Not user data byt why? {}\n", .{clua.lua_type(state, -1)});
            }
        }

        pub fn newIndex(state: *clua.lua_State) callconv(.c) c_int {
            // std.debug.print("Calling new index the stack size is {}\n", .{clua.lua_gettop(state)});
            const self: *Self = @alignCast(@ptrCast(clua.lua_touserdata(state, 1) orelse @panic("pointer is null")));
            if (clua.lua_type(state, 2) != clua.LUA_TNUMBER) {
                @panic("expected array index to be integer");
            }
            const lua_index = clua.lua_tointegerx(state, 2, null);
            const value = luaReadValue(state, Element, 3, self.allocator) catch |err| {
                std.debug.panic("Could not read lua value {}", .{err});
            };
            const index = lua_index - 1;
            if (index < self.slice.len) {
                self.slice.*[@intCast(lua_index)] = value;
                return 0;
            }
            // we need to reallocate
            const new_mem = self.allocator.alloc(Element, @intCast(lua_index)) catch @panic("could not allocate");
            @memcpy(new_mem[0..self.slice.len], self.slice.*);
            self.allocator.free(self.slice.*);
            self.slice.* = new_mem;
            self.slice.*[@intCast(index)] = value;
            return 0;
        }

        pub fn slice_length(state: *clua.lua_State) callconv(.c) c_int {
            // std.debug.print("Calling slice length\n", .{});
            const self: *Self = @alignCast(@ptrCast(clua.lua_touserdata(state, 1) orelse @panic("pointer is null")));
            clua.lua_pushinteger(state, @intCast(self.slice.len));
            return 1;
        }

        pub fn to_table(state: *clua.lua_State) callconv(.c) c_int {
            const self: *Self = @alignCast(@ptrCast(clua.lua_touserdata(state, 1) orelse @panic("pointer is null")));
            clua.lua_newtable(state);
            for (0..self.slice.len) |index| {
                luaPushValue(Element, state, &self.slice.*[@intCast(index)], self.allocator) catch @panic("could not push the value");
                clua.lua_seti(state, 2, @intCast(index + 1));
            }
            return 1;
        }

        pub fn getIndex(state: *clua.lua_State) callconv(.c) c_int {
            const self: *Self = @alignCast(@ptrCast(clua.lua_touserdata(state, 1) orelse @panic("pointer is null")));
            if (clua.lua_type(state, 2) == clua.LUA_TNUMBER) {
                const lua_index = clua.lua_tointegerx(state, 2, null);
                const index = lua_index - 1;
                if (index >= self.slice.len) {
                    clua.lua_pushnil(state);
                } else {
                    luaPushValue(Element, state, &self.slice.*[@intCast(index)], self.allocator) catch {
                        @panic("ojoj");
                    };
                }
                return 1;
            }
            clua.lua_pushvalue(state, 2); // push key
            _ = clua.lua_gettable(state, clua.lua_upvalueindex(1)); // lookup in methods table
            return 1; // return whatever was found (nil if not found)
        }

        const methods = [_]clua.luaL_Reg{
            .{ .name = "length", .func = @ptrCast(&slice_length) },
            .{ .name = "totable", .func = @ptrCast(&to_table) },
            .{ .name = null, .func = null },
        };

        pub fn createMetaTableAndPush(state: *clua.lua_State) void {
            if (clua.luaL_newmetatable(state, MetaTableName) == 0) {
                return;
            }

            clua.lua_newtable(state);
            clua.luaL_setfuncs(state, &methods[0], 0);

            clua.lua_pushcclosure(state, @ptrCast(&getIndex), 1);
            clua.lua_setfield(state, -2, "__index");

            clua.lua_pushcclosure(state, @ptrCast(&newIndex), 0);
            clua.lua_setfield(state, -2, "__newindex");

            clua.lua_pushcclosure(state, @ptrCast(&slice_length), 0);
            clua.lua_setfield(state, -2, "__len");
        }
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
                    const allocator: ?std.mem.Allocator = if (comptime @hasField(T, "allocator")) ptr.allocator else null;
                    luaPushValue(
                        f.type,
                        state,
                        &@field(ptr, f.name),
                        allocator,
                    ) catch {
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
                            // TODO: this has to be recusrive, like if elements of the slice need freeing
                            // we should free them too. It could habe arbitrary level of nesting
                            // like a list of stucts that have strings
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
                comptime {
                    break :ret "Slice<" ++ getLuaType(ptr.child) ++ ">";
                }
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
            if (ptr.child == u8 and ptr.sentinel_ptr == null) {
                // its a string, thats a problem we need to do allocation
                if (clua.lua_type(state, index) != clua.LUA_TSTRING) {
                    return error.expectedString;
                }
                var size: usize = undefined;
                const lstr = clua.lua_tolstring(state, index, &size);
                const str = try allocator.?.dupe(u8, lstr[0..size]);
                return @ptrCast(str);
            } else if (ptr.child == u8) {
                // its a string, thats a problem we need to do allocation
                if (clua.lua_type(state, index) != clua.LUA_TSTRING) {
                    return error.expectedString;
                }
                var size: usize = undefined;
                const lstr = clua.lua_tolstring(state, index, &size);
                const str = try allocator.?.dupeZ(u8, lstr[0..size :0]);
                return @ptrCast(str);
            }
            // now array
            if (clua.lua_type(state, index) != clua.LUA_TTABLE) {
                return error.expectedTable;
            }
            const len = clua.lua_rawlen(state, index);
            const res = try allocator.?.alloc(ptr.child, len);
            for (0..len) |idx| {
                _ = clua.lua_geti(state, index, @intCast(idx + 1));
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
        else => {
            // std.debug.print("unsupported type {s} for field", .{@tagName(tag)});
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

fn luaPushValue(T: type, state: *clua.lua_State, val: *T, allocator: ?std.mem.Allocator) !void {
    const info = @typeInfo(T);
    switch (info) {
        .bool => {
            clua.lua_pushboolean(state, if (val.*) 1 else 0);
        },
        .int => {
            clua.lua_pushinteger(state, @intCast(val.*));
        },
        .float => {
            clua.lua_pushnumber(state, @floatCast(val.*));
        },
        .optional => |opt| {
            if (val.*) |*inner| {
                // as_ptr would be a pointer to opional which kinda doesn't work?
                // we need pointer to a slice so we would need to transform *?[] into *[]
                // but that seems impossible
                try luaPushValue(opt.child, state, inner, allocator);
            } else {
                clua.lua_pushnil(state);
            }
        },
        .pointer => |ptr| if (ptr.size == .slice) {
            if (ptr.child == u8 and ptr.sentinel_ptr == null) {
                // this is a string
                _ = clua.lua_pushlstring(state, @ptrCast(val.*), val.len);
            } else if (ptr.child == u8) {
                // TODO: we assume sentinel pointer is null byte might be wrong assumption
                _ = clua.lua_pushstring(state, @ptrCast(val.*));
            } else {
                // std.debug.print("Pushing slice proxy for type {s}\n", .{@typeName(T)});
                SliceProxy(T).luaPush(val, allocator.?, state);
            }
        } else if (ptr.size == .c and ptr.child == u8) {
            _ = clua.lua_pushstring(state, @ptrCast(val.*));
        } else {
            return error.unsupportedType;
        },
        else => {
            // std.debug.print("unsupported type {s} for field", .{@tagName(tag)});
            return error.unsupportedType;
        },
    }
}
