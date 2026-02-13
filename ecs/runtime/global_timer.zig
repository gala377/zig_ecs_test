const ecs = @import("../prelude.zig");
const std = @import("std");

const Self = @This();

pub const component_info = ecs.Component(Self);

inner: ecs.core.Timer,

pub fn init() Self {
    const t: ecs.core.Duration = .inifinite;
    var timer: ecs.core.Timer = .init(t);
    timer.previous_nanos = @intCast(std.time.nanoTimestamp());
    timer.current_nanos = @intCast(std.time.nanoTimestamp());
    return .{
        .inner = timer,
    };
}

pub fn tick(self: *Self) ecs.core.Duration {
    const current = std.time.nanoTimestamp();
    const diff = @as(u64, @intCast(current)) - self.inner.current_nanos;
    _ = self.inner.tick(.{
        .nano = diff,
    });
    return self.inner.delta();
}

pub fn delta(self: *Self) ecs.core.Duration {
    return self.inner.delta();
}

pub fn updateTimer(timer: ecs.Resource(Self)) void {
    _ = timer.inner.tick();
}
