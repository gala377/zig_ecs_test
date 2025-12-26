const std = @import("std");
const lua = @cImport({
    @cInclude("lua.h");
    @cInclude("lualib.h");
    @cInclude("lauxlib.h");
});
const Value = @import("value.zig").Value;
const Pair = @import("value.zig").Pair;
const Ref = @import("ref.zig").Ref;

/// State of the lua virtual machine.
///
/// Allows interacting with the virtual machine.
///  - Reading values from the stack.
///  - Executing code on the machine.
///  - Sending values to lua.
///
/// Values from lua are wrapped into a Value union which is a type
/// safe wrapper around them.
///
/// Lua state is cheaply copieable, as it is just 2 pointers.
/// Every copy references the same internal lua state and context so think
/// about this struct as a c++ "shared_ptr".
pub const LuaState = struct {
    state: *lua.lua_State,
    context: *Context,

    pub const LuaError = error{
        errSyntax,
        errMem,
        errErr,
        errRun,
        unsupportedType,
        stackEmpty,
        couldNotCreateLuaState,
        invalidLuaString,
        ok,
    };

    /// Passed to C LuaState as an opaque pointer.
    ///
    /// Passed by lua to runtime functions that we implement. For example `alloc` which is used
    /// by lua to manage memory.
    const Context = struct {
        allocator: std.mem.Allocator,

        /// Called from lua to allocate, reallocate and free memory.
        pub fn alloc(self: *Context, ptr: ?*anyopaque, osize: usize, nsize: usize) callconv(.c) ?*anyopaque {
            if (ptr == null) {
                const allocated: []align(8) u8 = self.allocator.alignedAlloc(u8, .@"8", nsize) catch {
                    return null;
                };
                return @as(?*anyopaque, @ptrCast(allocated.ptr));
            }
            const mem: [*]align(8) u8 = @ptrCast(@alignCast(ptr));
            const asSlice: []align(8) u8 = mem[0..osize];
            const ret: []align(8) u8 = self.allocator.realloc(asSlice, nsize) catch {
                return null;
            };
            if (ret.len == 0) {
                return null;
            }
            return @as(?*anyopaque, @ptrCast(ret.ptr));
        }
    };

    const Self = @This();

    /// Initalize lua state.
    ///
    /// allocator - will be used for all of lua allocations so it has to be valid
    ///             for as long as the lua vm is valid.
    pub fn init(allocator: std.mem.Allocator) anyerror!Self {
        const ctx = try allocator.create(Context);
        ctx.* = Context{
            .allocator = allocator,
        };
        const state = lua.lua_newstate(@ptrCast(&Context.alloc), @ptrCast(ctx)) orelse {
            return LuaError.couldNotCreateLuaState;
        };
        lua.luaL_openlibs(state);
        return .{
            .state = state,
            .context = ctx,
        };
    }

    pub fn deinit(self: Self) void {
        lua.lua_close(self.state);
        const allocator = self.context.allocator;
        allocator.destroy(self.context);
    }

    /// Execute lua chunk and return 1 value returned by it.
    ///
    /// If the chunk returns more than one value the rest is ignored.
    pub fn exec(self: Self, code: []const u8, allocator: std.mem.Allocator) !Value {
        try self.load(code);
        return self.popTop(allocator);
    }

    /// Execute the chunk and leave the value on the stack.
    ///
    /// In contrast to `exec` this will just leave the value on the stack.
    /// this is useful when trying to create a reference to value returned by the
    /// chunk.
    pub fn load(self: Self, code: []const u8) !void {
        return self.loadWithName(code, "exec");
    }

    pub fn loadWithName(self: Self, code: []const u8, name: []const u8) !void {
        std.debug.print("4.1\n", .{});
        var reader = ReaderCtx{ .data = code, .last_read = 0 };
        std.debug.print("4.2\n", .{});
        const chunkname = try self.context.allocator.dupeZ(u8, name);
        std.debug.print("4.3\n", .{});
        defer self.context.allocator.free(chunkname);
        std.debug.print("4.4\n", .{});
        try errorFromInt(lua.lua_load(
            self.state,
            @ptrCast(&sliceReader),
            @ptrCast(&reader),
            @ptrCast(chunkname),
            null,
        ));
        std.debug.print("4.5\n", .{});
        luaCall(self.state, 0, 1) catch @panic("call error");
        std.debug.print("4.6\n", .{});
    }

    pub fn call(self: Self, nargs: c_int, nresults: c_int, allocator: std.mem.Allocator) !Value {
        luaCall(self.state, nargs, nresults) catch @panic("call error");
        return self.popTop(allocator);
    }

    pub fn callDontPop(self: Self, nargs: c_int, nresults: c_int) void {
        luaCall(self.state, nargs, nresults) catch @panic("call error");
    }

    pub fn callGetRef(self: Self, nargs: c_int, nresults: c_int) !Ref {
        self.callDontPop(nargs, nresults);
        return self.makeRef();
    }
    /// Pop top of the lua stack.
    ///
    /// Returns error if the stack is empty.
    pub fn pop(self: Self) !void {
        try self.assertStackNotEmpty();
        lua.lua_pop(self.state, 1);
    }

    pub fn popUnchecked(self: Self) void {
        lua.lua_pop(self.state, 1);
    }

    /// Get value from top of the stack and pop it.
    ///
    /// Returns error if the stack is empty.
    pub fn popTop(self: Self, allocator: std.mem.Allocator) !Value {
        const val = try self.peekTop(allocator);
        try self.pop();
        return val;
    }

    /// Get value from the top of the stack and do not pop it.
    ///
    /// Returns error if the stack is empty.
    pub fn peekTop(self: Self, allocator: std.mem.Allocator) !Value {
        try self.assertStackNotEmpty();
        return makeValue(self.state, allocator, -1);
    }

    /// Return number of elements on the stack.
    pub fn stackSize(self: Self) c_int {
        return lua.lua_gettop(self.state);
    }

    /// Make a persistant reference to the object at the top of the stack.
    /// Also pops the value from the top of the stack.
    pub fn makeRef(self: Self) !Ref {
        try self.assertStackNotEmpty();
        const ref = lua.luaL_ref(self.state, lua.LUA_REGISTRYINDEX);
        return Ref{
            .ref = ref,
            .state = self,
        };
    }

    pub fn releaseRef(self: Self, ref: Ref) void {
        lua.luaL_unref(self.state, lua.LUA_REGISTRYINDEX, ref.ref);
    }

    pub fn getRef(self: Self, ref: Ref, allocator: std.mem.Allocator) !Value {
        self.pushRef(ref);
        return self.popTop(allocator);
    }

    pub fn pushRef(self: Self, ref: Ref) void {
        _ = lua.lua_rawgeti(self.state, lua.LUA_REGISTRYINDEX, ref.ref);
    }

    pub fn accessField(self: Self, idx: c_int, field: [:0]const u8) void {
        lua.lua_getfield(self.state, idx, field);
    }

    fn assertStackNotEmpty(self: Self) LuaError!void {
        if (self.stackSize() == 0) {
            return LuaError.stackEmpty;
        }
    }

    pub fn newMetaTable(self: Self, name: [:0]const u8) c_int {
        return lua.luaL_newmetatable(self.state, name);
    }

    pub fn newTable(self: Self) void {
        lua.lua_newtable(self.state);
    }
};

const ReaderCtx = struct {
    data: []const u8,
    last_read: usize,
};

fn sliceReader(state: ?*lua.lua_State, data: *ReaderCtx, size: [*c]usize) callconv(.c) [*c]const u8 {
    _ = state;
    if (data.last_read == data.data.len) {
        return null;
    }
    size.* = data.data.len;
    data.last_read = data.data.len;
    return data.data.ptr;
}

fn luaCall(state: *lua.lua_State, nargs: c_int, nresults: c_int) LuaState.LuaError!void {
    // get traceback and place it under the function
    const func_idx = lua.lua_gettop(state) - nargs;
    _ = lua.lua_getglobal(state, "debug");
    _ = lua.lua_getfield(state, -1, "traceback");
    lua.lua_remove(state, -2); // remove 'debug' table, leave 'traceback' function

    // Move the handler to sit right before the function
    lua.lua_insert(state, func_idx);
    const msgh_idx = func_idx;
    const status = lua.lua_pcallk(state, nargs, nresults, msgh_idx, 0, null);
    if (status != lua.LUA_OK) {
        // The error message + traceback is now at the top of the stack
        var len: usize = 0;
        const err_msg = lua.lua_tolstring(state, -1, &len);
        std.debug.print("LUA ERROR: {s}\n", .{err_msg[0..len]});

        // Remove error message and the handler from stack
        lua.lua_pop(state, 2);
        return LuaState.LuaError.errRun;
    }
    // remove error handler from the stack
    lua.lua_remove(state, msgh_idx);
}

fn luaToNumber(state: *lua.lua_State, idx: c_int) lua.lua_Number {
    return lua.lua_tonumberx(state, idx, null);
}

fn luaToString(state: *lua.lua_State, idx: c_int) [*c]const u8 {
    return lua.lua_tolstring(state, idx, null);
}

fn luaToTable(state: *lua.lua_State, idx: c_int, allocator: std.mem.Allocator) (std.mem.Allocator.Error || LuaState.LuaError)!Value {
    var table = std.ArrayList(Pair).empty;
    lua.lua_pushnil(state);
    while (lua.lua_next(state, idx - 1) != 0) {
        const key = try makeValue(state, allocator, -2);
        const value = try makeValue(state, allocator, -1);
        // only pop the value, leave the key for the next iteration
        lua.lua_pop(state, 1);
        try table.append(allocator, .{ .key = key, .value = value });
    }
    return Value{ .Table = .{
        .value = table,
        .allocator = allocator,
    } };
}

fn errorFromInt(code: c_int) LuaState.LuaError!void {
    return switch (code) {
        lua.LUA_OK => {},
        lua.LUA_ERRMEM => LuaState.LuaError.errMem,
        lua.LUA_ERRERR => LuaState.LuaError.errErr,
        lua.LUA_ERRSYNTAX => LuaState.LuaError.errSyntax,
        lua.LUA_ERRRUN => LuaState.LuaError.errRun,
        else => unreachable,
    };
}

fn makeValue(state: *lua.lua_State, allocator: std.mem.Allocator, idx: c_int) !Value {
    const typ = lua.lua_type(state, idx);
    switch (typ) {
        lua.LUA_TNIL => return Value{ .Nil = {} },
        lua.LUA_TBOOLEAN => return Value{ .Boolean = lua.lua_toboolean(state, idx) != 0 },
        lua.LUA_TNUMBER => return Value{ .Number = luaToNumber(state, idx) },
        lua.LUA_TSTRING => {
            const str = luaToString(state, idx);
            if (str == null) return LuaState.LuaError.invalidLuaString;
            const len: usize = lua.lua_rawlen(state, idx);
            const slice = try allocator.dupe(u8, str[0..len]);
            return Value{ .String = .{ .value = slice, .allocator = allocator } };
        },
        lua.LUA_TTABLE => {
            return luaToTable(state, idx, allocator);
        },
        lua.LUA_TTHREAD => {},
        lua.LUA_TFUNCTION => {},
        lua.LUA_TUSERDATA => {},
        lua.LUA_TLIGHTUSERDATA => {},
        else => return LuaState.LuaError.unsupportedType,
    }
    return LuaState.LuaError.unsupportedType;
}
