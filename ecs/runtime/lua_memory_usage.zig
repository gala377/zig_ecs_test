const std = @import("std");
const ecs = @import("../prelude.zig");
const lua = @import("lua_lib");

const Self = @This();

pub const SAMPLE_COUNT = 144 * 5;

pub const component_info = ecs.Component(Self);

samples: [SAMPLE_COUNT]u32 = undefined,
index: usize = 0,
read_once: bool = false,

pub fn init() Self {
    return .{};
}

pub fn record(self: *Self, sample: u32) void {
    self.samples[self.index] = sample;
    self.index = (self.index + 1) % SAMPLE_COUNT;
    if (self.index == 0) {
        self.read_once = true;
    }
}

pub fn samplesOrdered(self: *Self, allocator: std.mem.Allocator) ![]u32 {
    const res = try allocator.alloc(u32, SAMPLE_COUNT);
    var res_index: usize = 0;
    var ptr: usize = self.index;
    while (true) {
        res[res_index] = self.samples[ptr];
        res_index += 1;
        ptr = (ptr + 1) % SAMPLE_COUNT;
        if (ptr == self.index or res_index == SAMPLE_COUNT) {
            break;
        }
    }
    return res;
}

pub fn recordMemoryUsage(self: ecs.Resource(Self), luas: ecs.Resource(ecs.runtime.lua_runtime)) !void {
    const res = lua.clib.lua_gc(luas.get().lua.state, lua.clib.LUA_GCCOUNT);
    self.inner.record(@intCast(res));
}
