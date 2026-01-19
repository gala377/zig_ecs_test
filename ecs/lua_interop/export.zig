const std = @import("std");

const lua = @import("lua_lib");
const clua = lua.clib;

const utils = @import("../utils.zig");
const entity_storage = @import("../entity_storage.zig");
const ComponentWrapper = entity_storage.ComponentWrapper;

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
            const self = @as(*Self, @ptrCast(@alignCast(allocated)));
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
            const self: *Self = @ptrCast(@alignCast(clua.lua_touserdata(state, 1) orelse @panic("pointer is null")));
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
            const self: *Self = @ptrCast(@alignCast(clua.lua_touserdata(state, 1) orelse @panic("pointer is null")));
            clua.lua_pushinteger(state, @intCast(self.slice.len));
            return 1;
        }

        pub fn to_table(state: *clua.lua_State) callconv(.c) c_int {
            const self: *Self = @ptrCast(@alignCast(clua.lua_touserdata(state, 1) orelse @panic("pointer is null")));
            clua.lua_newtable(state);
            for (0..self.slice.len) |index| {
                luaPushValue(Element, state, &self.slice.*[@intCast(index)], self.allocator) catch @panic("could not push the value");
                clua.lua_seti(state, 2, @intCast(index + 1));
            }
            return 1;
        }

        pub fn getIndex(state: *lua.CLuaState) callconv(.c) c_int {
            const self: *Self = @ptrCast(@alignCast(clua.lua_touserdata(state, 1) orelse @panic("pointer is null")));
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

        const field_map = blk: {
            const fields = std.meta.fields(T);
            // We create an array of tuples { field_name, field_index }
            var kvs: [fields.len]struct { []const u8, usize } = undefined;
            for (fields, 0..) |f, i| {
                kvs[i] = .{ f.name, i };
            }
            break :blk std.StaticStringMap(usize).initComptime(kvs);
        };

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

        /// Passes this component to lua as userdata.
        ///
        /// This component is wrapped into a pointer which means that lua does
        /// not create a copy like it would do in a general case.
        ///
        /// That means that any changes to this component in lua will be reflected
        /// and visible in zig.
        pub fn luaPush(self: *T, state: *clua.lua_State, allocator: std.mem.Allocator) void {
            // std.debug.print("Pushing value of t={s}\n", .{@typeName(T)});
            const allocated = clua.lua_newuserdata(state, @sizeOf(utils.ZigPointer(T))) orelse @panic("lua could not allocate");
            const udata = @as(*utils.ZigPointer(T), @ptrCast(@alignCast(allocated)));
            udata.* = utils.ZigPointer(T){ .ptr = self, .allocator = allocator };
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
            const fields = std.meta.fields(T);
            const udata: *utils.ZigPointer(T) = @ptrCast(@alignCast(clua.lua_touserdata(state, 1)));
            const ptr: *T = @ptrCast(@alignCast(udata.ptr));
            var str_len: usize = 0;
            const from_lua_field_name = clua.lua_tolstring(state, 2, &str_len);
            const lua_field_name = from_lua_field_name[0..str_len];

            const allocator: std.mem.Allocator = if (comptime @hasField(T, "allocator"))
                ptr.allocator
            else
                udata.allocator;
            // fields take priority
            if (field_map.get(lua_field_name)) |lookup_index| {
                switch (lookup_index) {
                    inline 0...fields.len - 1 => |field_index| {
                        const f = fields[field_index];
                        if (comptime isLuaSupported(f.type) and !isIgnoredField(f.name)) {
                            luaPushValue(
                                f.type,
                                state,
                                &@field(ptr, f.name),
                                allocator,
                            ) catch {
                                unreachable;
                            };
                            return 1;
                        } else {
                            std.debug.panic("trying to read field {s} which is not supported from lua", .{f.name});
                        }
                    },
                    else => @panic("not possible"),
                }
            }
            // did not found the field, we return nothing
            return 0;
        }

        /// Called from lua when setting a field.
        pub fn luaNewIndex(state: *clua.lua_State) callconv(.c) c_int {
            const fields = std.meta.fields(T);
            const udata: *utils.ZigPointer(T) = @ptrCast(@alignCast(clua.lua_touserdata(state, 1)));
            const ptr: *T = @ptrCast(@alignCast(udata.ptr));
            var str_len: usize = 0;
            const from_lua_string = clua.lua_tolstring(state, 2, &str_len);
            const lua_field = from_lua_string[0..str_len];

            // use type allocator if possible if not use generic one
            const allocator = if (comptime @hasField(T, "allocator"))
                ptr.allocator
            else
                udata.allocator;
            if (field_map.get(lua_field)) |lookup_index| {
                switch (lookup_index) {
                    inline 0...fields.len - 1 => |field_index| {
                        const f = fields[field_index];
                        freeRecursive(
                            f.type,
                            &@field(ptr, f.name),
                            allocator,
                        );
                        // TODO: doesn't handle a case where we assing userdata
                        // there are 2 cases to consider:
                        // 1. we assing to pointer => we just copy userdata pointer
                        // 2. we assing to value => we need to do shallow copy
                        //
                        // in other cases we do the thing here which is we just
                        // read the value as deserialized.
                        @field(ptr, f.name) = fromLua(
                            f.type,
                            state,
                            3,
                            allocator,
                        ) catch {
                            @panic("could not read value from lua");
                        };
                        return 0;
                    },
                    else => @panic("not possible"),
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
            const state: *lua.CLuaState = lstate.state;
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
        pub fn exportId(state: *lua.CLuaState, allocator: std.mem.Allocator) !void {
            const comp_name: []const u8 = @TypeOf(T.component_info).comp_name;
            std.debug.print("Exporting component {s}\n", .{comp_name});
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
                const id = utils.typeId(T);
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

fn freeRecursive(comptime T: type, val: *const T, allocator: std.mem.Allocator) void {
    const info = @typeInfo(T);
    switch (info) {
        .@"opaque" => {
            @panic("dont know how to free opaque types");
        },
        .@"anyframe", .frame => {
            @panic("dont know how to free frame types");
        },
        .@"struct" => |str| {
            inline for (str.fields) |field| {
                const payload = &@field(val.*, field.name);
                freeRecursive(field.type, payload, allocator);
            }
        },
        .@"union" => |un| {
            if (un.tag_type == null) {
                @panic("only unions with tags are supported");
            }
            const active_tag = std.meta.activeTag(val.*);
            inline for (un.fields) |field| {
                if (active_tag == @field(std.meta.Tag(T), field.name)) {
                    const payload = &@field(val.*, field.name);
                    freeRecursive(field.type, payload, allocator);
                }
            }
        },
        .optional => |opt| {
            if (val.*) |*inner| {
                freeRecursive(opt.child, inner, allocator);
            }
        },
        .pointer => |ptr| {
            switch (ptr.size) {
                .one => {
                    freeRecursive(ptr.child, val.*, allocator);
                    allocator.destroy(val.*);
                },
                .slice => {
                    for (val.*) |*inner| {
                        freeRecursive(ptr.child, inner, allocator);
                    }
                    allocator.free(val.*);
                },
                .c => {
                    @panic("c pointers are not supported");
                },
                .many => {
                    @panic("many pointers are not supported");
                },
            }
        },
        .array => |arr| {
            for (val.*) |*item| {
                freeRecursive(arr.child, item, allocator);
            }
        },
        else => {},
    }
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

const luaDeserializeFn = *const fn (
    state: *clua.lua_State,
    index: c_int,
    allocator: std.mem.Allocator,
) *anyopaque;

fn fromLuaAny(comptime T: type) luaDeserializeFn {
    return &struct {
        fn deserialize(state: *clua.lua_State, index: c_int, allocator: std.mem.Allocator) *anyopaque {
            const ret = allocator.create(T) catch {
                @panic("Could not allocate space for a type");
            };
            ret.* = fromLua(T, state, index, allocator) catch |e| {
                std.debug.panic("error while deserializing from lua {any}", e);
            };
            return @ptrCast(@alignCast(ret));
        }
    }.deserialize;
}

fn fromLua(comptime T: type, state: *clua.lua_State, index: c_int, allocator: std.mem.Allocator) !T {
    const info = @typeInfo(T);
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
            return try fromLua(opt.child, state, index, allocator);
        },
        .@"struct" => |s| {
            if (clua.lua_type(state, index) != clua.LUA_TTABLE) {
                return error.expectedTable;
            }
            var ret: T = undefined;
            inline for (s.fields) |f| {
                _ = clua.lua_getfield(state, index, f.name.ptr);
                @field(ret, f.name) = try fromLua(f.type, state, -1, allocator);
            }
            return ret;
        },
        .@"union" => |union_info| {
            if (union_info.tag_type == null) @compileError("Only tagged unions are supported");
            if (clua.lua_type(state, index) == clua.LUA_TTABLE) return error.expectedTable;

            // Push nil to start the table traversal
            clua.lua_pushnil(state);

            // lua_next(L, index) pops the key and pushes the next key-value pair
            // Because we expect { tagName = value }, we only need the first pair
            if (clua.lua_next(state, if (index < 0) index - 1 else index) != 0) {
                // Stack is now: [..., key, value]
                defer clua.lua_pop(state, 2); // Clean up key and value

                // 1. Convert the key (tag name) to a string
                var name_len: usize = 0;
                const name_ptr = clua.lua_tolstring(state, -2, &name_len);
                if (name_ptr == null) return error.InvalidUnionKey;
                const active_tag_name = name_ptr[0..name_len];

                // 2. Iterate comptime fields to find the match
                inline for (union_info.fields) |field| {
                    if (std.mem.eql(u8, field.name, active_tag_name)) {
                        // Recursively parse the value at index -1
                        const payload = try fromLua(field.type, state, -1, allocator);
                        return @unionInit(T, field.name, payload);
                    }
                }
                return error.UnknownUnionTag;
            }
            return error.EmptyUnionTable;
        },
        .pointer => |ptr_info| {
            if (ptr_info.size == .slice and ptr_info.child == u8) {
                // Handle Strings
                var len: usize = 0;
                const ptr = clua.lua_tolstring(state, index, &len);
                if (ptr == null) return error.expectedString;

                if (ptr_info.sentinel()) |sentinel| {
                    if (comptime sentinel != @as(u8, 0)) {
                        @compileError("only 0 sentinels are supported");
                    }
                    return try allocator.dupeZ(u8, ptr[0..len]);
                } else {
                    return try allocator.dupe(u8, ptr[0..len]);
                }
            } else if (ptr_info.size == .slice) {
                // Handle Slices (Lua Arrays)
                if (clua.lua_type(state, index) == clua.LUA_TTABLE) return error.expectedArray;

                const len = clua.lua_rawlen(state, index);
                const slice = try allocator.alloc(ptr_info.child, len);
                errdefer allocator.free(slice);

                var i: usize = 0;
                while (i < len) : (i += 1) {
                    _ = clua.lua_rawgeti(state, index, @intCast(i + 1)); // Lua is 1-indexed
                    defer clua.lua_pop(state, 1);
                    slice[i] = try fromLua(ptr_info.child, state, -1, allocator);
                }
                return slice;
            } else if (ptr_info.size == .one) {
                const ret: *ptr_info.child = try allocator.create(ptr_info.child);
                errdefer allocator.destroy(ret);
                ret.* = try fromLua(ptr_info.child, state, index, allocator);
                return ret;
            }
            @compileError("Unsupported pointer type: " ++ @typeName(T));
        },
        else => @compileError("Type not supported: " ++ @typeName(T)),
    }
}

/// Deserializes value from lua to the type of `field_type`.
///
/// Intended to be used when deserializing values to set to fields.
fn luaReadValue(state: *clua.lua_State, comptime field_type: type, index: c_int, allocator: std.mem.Allocator) !field_type {
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
                const str = try allocator.dupe(u8, lstr[0..size]);
                return @ptrCast(str);
            } else if (ptr.child == u8) {
                // its a string, thats a problem we need to do allocation
                if (clua.lua_type(state, index) != clua.LUA_TSTRING) {
                    return error.expectedString;
                }
                var size: usize = undefined;
                const lstr = clua.lua_tolstring(state, index, &size);
                const str = try allocator.dupeZ(u8, lstr[0..size :0]);
                return @ptrCast(str);
            }
            // now array
            if (clua.lua_type(state, index) != clua.LUA_TTABLE) {
                return error.expectedTable;
            }
            const len = clua.lua_rawlen(state, index);
            const res = try allocator.alloc(ptr.child, len);
            for (0..len) |idx| {
                _ = clua.lua_geti(state, index, @intCast(idx + 1));
                const value = try luaReadValue(state, ptr.child, -1, allocator);
                res[idx] = value;
            }
            return res;
        } else if (ptr.size == .c and ptr.child == u8) {
            return error.cStringsUnsupported;
            // its a string thats a problem, we need to do allocation
        } else if (ptr.size == .one) {
            const value = try luaReadValue(state, ptr.child, index, allocator);
            const obj: *ptr.child = try allocator.create(ptr.child);
            obj.* = value;
            return obj;
        } else {
            return error.unsupportedType;
        },
        .@"struct" => if (isLuaSupported(field_type)) {
            // TODO: allow setting this field from lua
            // we need to check if tehis field is userdata. If so just assing pointer
            // or if it is table we need something like FromLua method for components
            return error.unsupportedType;
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
        .pointer => |ptr| (
            // slices support
            ptr.size == .slice and isLuaSupported(ptr.child)) or (
            // cstrings
            ptr.size == .c and ptr.child == u8) or (
            // pointers to lua supported types
            ptr.size == .one and isLuaSupported(ptr.child)),
        .@"struct" => @hasDecl(t, "lua_info"),
        else => false,
    };
}

/// Push value of type T onto lua stack
fn luaPushValue(T: type, state: *clua.lua_State, val: *T, allocator: std.mem.Allocator) !void {
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
                SliceProxy(T).luaPush(val, allocator, state);
            }
        } else if (ptr.size == .c and ptr.child == u8) {
            _ = clua.lua_pushstring(state, @ptrCast(val.*));
        } else if (ptr.size == .one and isLuaSupported(ptr.child)) {
            try luaPushValue(ptr.child, state, val.*, allocator);
        } else {
            return error.unsupportedType;
        },
        .@"struct" => if (isLuaSupported(T)) {
            @TypeOf(T.lua_info).luaPush(val, state, allocator);
        } else {
            return error.unsupportedType;
        },
        else => {
            // std.debug.print("unsupported type {s} for field", .{@tagName(tag)});
            return error.unsupportedType;
        },
    }
}
