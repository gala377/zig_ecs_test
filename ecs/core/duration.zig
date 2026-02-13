const std = @import("std");

const Self = @This();

/// time value in nanoseconds
hours: u64 = 0,
minutes: u64 = 0,
seconds: u64 = 0,
milis: u64 = 0,
micro: u64 = 0,
nano: u64 = 0,

pub const inifinite: Self = .{
    .nano = std.math.maxInt(u64),
};

pub fn toSeconds(self: *const Self) f64 {
    const total = self.toNanos();
    return @as(f64, @floatFromInt(total)) / std.time.ns_per_s;
}

pub fn toHours(self: *const Self) f64 {
    return @as(f64, @floatFromInt(self.toNanos())) / std.time.ns_per_hour;
}

pub fn toMinutes(self: *const Self) f64 {
    return @as(f64, @floatFromInt(self.toNanos())) / std.time.ns_per_min;
}

pub fn toMilis(self: *const Self) f64 {
    return @as(f64, @floatFromInt(self.toNanos())) / std.time.ns_per_ms;
}

pub fn toMicro(self: *const Self) f64 {
    return @as(f64, @floatFromInt(self.toNanos())) / std.time.ns_per_us;
}

pub fn toNanos(self: *const Self) u64 {
    return (self.hours * std.time.ns_per_hour +
        self.minutes * std.time.ns_per_min +
        self.seconds * std.time.ns_per_s +
        self.milis * std.time.ns_per_ms +
        self.micro * std.time.ns_per_us +
        self.nano);
}
