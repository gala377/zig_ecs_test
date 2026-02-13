const std = @import("std");
const ecs = @import("../prelude.zig");

const Self = @This();

previous_nanos: u64 = 0,
current_nanos: u64 = 0,
nanos_diff: u64 = 0,

tick_after: u64,
repeat: bool,
ticked: bool = false,

pub fn init(tick_after: ecs.core.Duration) Self {
    return .{
        .tick_after = tick_after.toNanos(),
        .repeat = false,
    };
}

pub fn initRepeated(tick_after: ecs.core.Duration) Self {
    return .{
        .tick_after = tick_after.toNanos(),
        .repeat = true,
    };
}

pub fn tick(self: *Self, duration: ecs.core.Duration) bool {
    const asNanos = duration.toNanos();
    self.previous_nanos = self.current_nanos;
    self.current_nanos += asNanos;
    self.nanos_diff = self.current_nanos - self.previous_nanos;
    if (self.current_nanos > self.tick_after) {
        if (!self.ticked) {
            if (self.repeat) {
                self.current_nanos -= self.tick_after;
                return true;
            }
            self.ticked = true;
            return true;
        }
    }
    return false;
}

pub fn delta(self: *Self) ecs.core.Duration {
    return .{
        .nano = self.nanos_diff,
    };
}

pub fn reset(self: *Self) void {
    self.ticked = false;
    self.current_nanos = 0;
    self.previous_nanos = 0;
}
