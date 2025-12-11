const lua = @import("lua_lib");
const clua = lua.clib;
const std = @import("std");
const utils = @import("utils.zig");
const entity_storage = @import("entity_storage.zig");
const ComponentWrapper = @import("entity_storage.zig").ComponentWrapper;

pub const ComponentId = u64;

pub fn ComponentInfo(comptime name: []const u8) type {
    return struct {
        pub const comp_name = name;
    };
}

pub fn Component(comptime T: type) ComponentInfo(@typeName(T)) {
    return .{};
}

pub fn LibComponent(comptime name_prefix: []const u8, comptime T: type) ComponentInfo(name_prefix ++ "." ++ @typeName(T)) {
    return .{};
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

        pub fn getIndex(state: *lua.CLUA_T) callconv(.c) c_int {
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

pub fn ExportLuaInfo(comptime T: type, comptime ignore_fields: anytype) type {
    return struct {
        pub const MetaTableName = @TypeOf(T.component_info).comp_name ++ "_MetaTable";

        comptime {
            checkForAllocatorNeededFields();
        }

        /// Check if given field is in `ingored_fields`.
        /// Check happens at compile time.
        fn isIgnoredField(comptime field: []const u8) bool {
            inline for (ignore_fields) |ignored| {
                if (std.mem.eql(u8, field, ignored[0..])) {
                    return true;
                }
            }
            return false;
        }

        /// Check if there is a field that requires allocation within the type T
        ///
        /// If there is check if there is an allocator field that can be used to
        /// allocate memory for this field. If not that is a compile time error.
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

        /// Passes this component to lua as userdata.
        ///
        /// This component is wrapped into a pointer which means that lua does
        /// not create a copy like it would do in a general case.
        ///
        /// That means that any changes to this component in lua will be reflected
        /// and visible in zig.
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

        /// Creates a component wrapper from lua table
        ///
        /// This can be used to add native components created in lua.
        ///
        /// If the component has an allocator field or requires fields that need allocation
        /// it will use storage allocator
        pub fn wrapperFromLua(state: *clua.lua_State, storage: *entity_storage) !ComponentWrapper {
            const tableIndex: c_int = 1;
            const comp: *T = try storage.allocator.create(T);
            if (comptime @typeInfo(T) != .@"struct") {
                @compileError("component has to be a struct");
            }
            const fields: []const std.builtin.Type.StructField = std.meta.fields(T);
            inline for (fields) |f| {
                if (comptime isLuaSupported(f.type) and !isIgnoredField(f.name)) {
                    _ = clua.lua_getfield(state, tableIndex, @ptrCast(f.name));
                    const value = try luaReadValue(state, f.type, -1, storage.allocator);
                    @field(comp, f.name) = value;
                } else {
                    if (comptime std.mem.eql(u8, f.name, "allocator")) {
                        comp.allocator = storage.allocator;
                    } else if (comptime f.default_value_ptr == null) {
                        @compileError("Field " ++ @typeName(T) ++ "." ++ f.name ++ " cannot be created from lua and doesn't have a default value");
                    }
                }
            }
            const wrapper = try storage.createWrapper(T, comp);
            return wrapper;
        }

        /// Called from lua when reading a field
        ///
        /// TODO: we should also use it to handle methods. Would be nice.
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
                // TODO: We need special handling for fields that are struct/pointer to structs that
                // are also lua supported as we can read them by calling their luaPush impl
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

        /// Called from lua when setting a field.
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

        /// Registers meta table within lua so taht it can be assigned when
        /// user data is created.
        ///
        /// This has to be called before trying to pass instances of this component
        /// to lua.
        pub fn registerMetaTable(lstate: lua.State) void {
            const state: *lua.CLUA_T = @ptrCast(lstate.state);
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

        /// Generates type information for lua to be used with LSP.
        pub fn luaGenerateStubFile(writer: std.io.AnyWriter) !void {
            const comp_name = @TypeOf(T.component_info).comp_name;
            const quote = std.mem.indexOfScalar(u8, comp_name, '(') != null;
            try writer.print("---@class {s}\n", .{comp_name});
            const fields = std.meta.fields(T);
            inline for (fields) |f| {
                if (comptime isLuaSupported(f.type) and !isIgnoredField(f.name)) {
                    try writer.print("---@field {s} {s}\n", .{ f.name, getLuaType(f.type) });
                }
            }
            try writer.writeAll("---@field private component_hash integer\n");
            try writer.writeAll("---@field private metatable_name string\n");
            if (quote) {
                const last_dot = std.mem.lastIndexOfScalar(u8, comp_name, '.') orelse {
                    @panic("Expected at least one dot");
                };
                const namespace = comp_name[0..last_dot];
                const queted_name = comp_name[(last_dot + 1)..];
                try writer.print("{s}[\"{s}\"] = {{}}\n\n", .{ namespace, queted_name });
            } else {
                try writer.print("{s} = {{}}\n\n", .{comp_name});
            }
        }

        /// Registers dynamic id of this component in lua.
        ///
        /// Dunamic id is used for reflection. Like when processing
        /// system queries from lua.
        ///
        /// The dynamic id is registered under as a table:
        ///
        /// namespace.path.of.this.component.ComponentTypeName = {
        ///     component_hash = dynamic_id,
        ///     metatable_bame = component_meta_table_name,
        /// }
        pub fn exportId(state: *lua.CLUA_T, idprovider: utils.IdProvider, allocator: std.mem.Allocator) !void {
            const comp_name: []const u8 = @TypeOf(T.component_info).comp_name;
            var segments = std.mem.splitScalar(u8, comp_name, '.');
            var idx: usize = 0;
            while (segments.next()) |segment| {
                const name = try allocator.dupeZ(u8, segment);
                defer allocator.free(name);
                if (idx == 0) {
                    const t = clua.lua_getglobal(state, name.ptr);
                    if (t == clua.LUA_TNIL) {
                        clua.lua_pop(state, 1);
                        clua.lua_newtable(state);
                        clua.lua_setglobal(state, name.ptr);
                        _ = clua.lua_getglobal(state, name.ptr);
                    }
                } else {
                    const t = clua.lua_getfield(state, -1, name.ptr);
                    if (t == clua.LUA_TNIL) {
                        clua.lua_pop(state, 1);
                        clua.lua_newtable(state);
                        clua.lua_setfield(state, -2, name.ptr);
                        _ = clua.lua_getfield(state, -1, name.ptr);
                    }
                }
                idx += 1;
            }
            const th = clua.lua_getfield(state, -1, "component_hash");
            if (th == clua.LUA_TNIL) {
                clua.lua_pop(state, 1);
                const id = utils.dynamicTypeId(T, idprovider);
                const lua_id: c_longlong = @bitCast(id);
                clua.lua_pushinteger(state, lua_id);
                clua.lua_setfield(state, -2, "component_hash");
            }

            const tn = clua.lua_getfield(state, -1, "metatable_name");
            if (tn == clua.LUA_TNIL) {
                clua.lua_pop(state, 1);
                _ = clua.lua_pushlstring(state, MetaTableName.ptr, MetaTableName.len);
                clua.lua_setfield(state, -2, "metatable_name");
            }
            clua.lua_pop(state, @as(c_int, @intCast(idx)));
        }
    };
}
/// Generates code that is used to interoperate with Lua.
///
/// Ignore fields has to be a tuple of strings
pub fn ExportLua(comptime T: type, comptime ignore_fields: anytype) ExportLuaInfo(T, ignore_fields) {
    return .{};
}

/// Given type T returns a name of the corresponding Lua type
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

/// Deserializes value from lua to the type of `field_type`.
///
/// Intended to be used when deserializing values to set to fields.
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

/// Check if type can be read from lua
fn isLuaSupported(comptime t: type) bool {
    return switch (@typeInfo(t)) {
        .bool, .int, .float => true,
        .optional => |opt| isLuaSupported(opt.child),
        .pointer => |ptr| (ptr.size == .slice and isLuaSupported(ptr.child)) or (ptr.size == .c and ptr.child == u8),
        else => false,
    };
}

/// Push value of type T onto lua stack
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
