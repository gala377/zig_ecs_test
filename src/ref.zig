const LuaState = @import("state.zig").LuaState;
const Value = @import("value.zig").Value;

pub const Ref = struct {
    const Self = @This();

    ref: c_int,
    state: LuaState,

    pub fn release(self: Self) void {
        self.state.releaseRef(self);
    }

    pub fn get(self: Self) !Value {
        return self.state.getRef(self);
    }
};
