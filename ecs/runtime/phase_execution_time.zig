const std = @import("std");
const ecs = @import("../prelude.zig");
const Self = @This();

pub const component_info = ecs.Component(Self);

pub const SAMPLE_COUNT = 600;

pub const GlobalNanos = struct {
    pub const component_info = ecs.Component(GlobalNanos);
    nanos: u64 = 0,
};

pub const Reading = struct {
    // aproximately 60 seconds as we try to run 60 fps
    readings: [SAMPLE_COUNT]ecs.core.Duration,
    index: usize = 0,
    read_once: bool = false,

    pub fn record(self: *Reading, duration: ecs.core.Duration) bool {
        self.readings[self.index] = duration;
        self.index += 1;
        if (self.index == SAMPLE_COUNT) {
            self.index = 0;
            self.read_once = true;
            return true;
        }
        return self.read_once;
    }

    pub fn average(self: *const Reading) ecs.core.Duration {
        var res: u64 = 0;
        for (self.readings) |read| {
            res += read.toNanos();
        }
        res = res / SAMPLE_COUNT;
        return .{
            .nano = res,
        };
    }
};

readings: std.EnumArray(ecs.Schedule.Phase, Reading),

pub fn init() Self {
    return .{
        .readings = .initFill(.{
            .readings = undefined,
        }),
    };
}

pub fn raport(self: *Self, phase: ecs.Schedule.Phase, duration: ecs.core.Duration) bool {
    const ptr = self.readings.getPtr(phase);
    return ptr.record(duration);
}

fn recordPhase(comptime phase: ecs.Schedule.Phase) ecs.System {
    const f = struct {
        fn run(game: *ecs.Game) anyerror!void {
            const runner = game.getResource(Self).get();
            const timer = game.getResource(GlobalNanos).get();
            const current = @as(u64, @intCast(std.time.nanoTimestamp()));
            const delta = current - timer.nanos;
            timer.nanos = current;
            _ = runner.raport(phase, .{
                .nano = delta,
            });
        }
    }.run;
    return ecs.system.labeledSystem(
        "ecs.runtime.phaseTimeRecorder(" ++ @tagName(phase) ++ ")",
        f,
    );
}

pub const PhaseTimeExecutionSchedule = struct {};

pub fn install(game: *ecs.Game) !void {
    try game.addResource(Self.init());
    try game.addResource(GlobalNanos{});
    try game.type_registry.registerType(Self);
    try game.type_registry.registerType(GlobalNanos);
    try game.addSystems(.setup, &.{ecs.system.labeledSystem(
        "ecs.runtime.phase_execution_time.installSchedule",
        installSchedule,
    )});
}

fn installSchedule(game: *ecs.Game) !void {
    inline for (@typeInfo(ecs.Schedule.Phase).@"enum".fields) |f| {
        try game.schedule.addScheduleAfter(
            @enumFromInt(f.value),
            PhaseTimeExecutionSchedule{},
            .{},
        );
        try game.schedule.addToSchedule(
            @enumFromInt(f.value),
            PhaseTimeExecutionSchedule{},
            recordPhase(@enumFromInt(f.value)),
        );
    }
}
