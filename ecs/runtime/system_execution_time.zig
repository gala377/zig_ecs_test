const std = @import("std");
const ecs = @import("../prelude.zig");

const Self = @This();

const Reading = ecs.runtime.PhaseExecutionTimer.Reading;
const SAMPLE_COUNT = ecs.runtime.PhaseExecutionTimer.SAMPLE_COUNT;
const GlobalNanos = ecs.runtime.PhaseExecutionTimer.GlobalNanos;

const SystemReading = struct {
    reading: Reading,
    name: []const u8,
};

/// Maps @ptrToInt(system.vtable.run) to read for the given system
const ScheduleReadings = struct {
    readings: std.AutoArrayHashMap(usize, SystemReading),

    pub fn init(allocator: std.mem.Allocator) @This() {
        return .{
            .readings = .init(allocator),
        };
    }

    pub fn deinit(self: *@This()) void {
        self.readings.deinit();
    }
};

/// Wihtin a phase maps typeId of a phase to readings of schedules in the phase.
const PhaseReadings = struct {
    schedule_readings: std.AutoArrayHashMap(usize, ScheduleReadings),

    pub fn init(allocator: std.mem.Allocator) @This() {
        return .{
            .schedule_readings = .init(allocator),
        };
    }

    pub fn deinit(self: *@This()) void {
        const values = self.schedule_readings.values();
        for (values) |*v| {
            v.deinit();
        }
        self.schedule_readings.deinit();
    }
};

/// Maps given phase to readings within this phase
phases: std.EnumArray(ecs.Schedule.Phase, PhaseReadings),
allocator: std.mem.Allocator,

pub fn init(allocator: std.mem.Allocator) Self {
    var map: std.EnumArray(ecs.Schedule.Phase, PhaseReadings) = .initUndefined();
    for (std.enums.values(ecs.Schedule.Phase)) |tag| {
        map.set(tag, PhaseReadings.init(allocator));
    }
    return .{
        .phases = map,
        .allocator = allocator,
    };
}

pub fn deinit(self: *Self) void {
    for (&self.phases.values) |*value| {
        value.deinit();
    }
}

pub fn recordSys(
    self: *Self,
    phase: ecs.Schedule.Phase,
    schedule: usize,
    system: ecs.System,
    value: ecs.core.Duration,
) !void {
    return self.record(
        system.name,
        phase,
        schedule,
        @intFromPtr(system.name.ptr),
        value,
    );
}

pub fn record(
    self: *Self,
    name: []const u8,
    phase: ecs.Schedule.Phase,
    schedule: usize,
    system: usize,
    value: ecs.core.Duration,
) !void {
    const pread = self.phases.getPtr(phase);
    const shchedule_read = if (pread.schedule_readings.getPtr(schedule)) |schedule_readings| brk: {
        break :brk schedule_readings;
    } else brk: {
        try pread.schedule_readings.put(schedule, ScheduleReadings.init(self.allocator));
        break :brk pread.schedule_readings.getPtr(schedule).?;
    };

    const system_readings = if (shchedule_read.readings.getPtr(system)) |s| brk: {
        break :brk s;
    } else brk: {
        try shchedule_read.readings.put(system, SystemReading{
            .name = name,
            .reading = Reading{},
        });
        break :brk shchedule_read.readings.getPtr(system).?;
    };
    _ = system_readings.reading.record(value);
}
