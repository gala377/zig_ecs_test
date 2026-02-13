const ecs = @import("../prelude.zig");

pub const events = @import("events.zig");
pub const commands = @import("commands.zig");
pub const commands_system = @import("commands_system.zig");
pub const allocators = @import("allocators.zig");
pub const game_actions = @import("game_actions.zig");
pub const lua_runtime = @import("lua_runtime.zig");
pub const one_shot = @import("oneshot_scheduler.zig");
pub const wrappers = @import("wrappers.zig");
pub const GlobalTimer = @import("global_timer.zig");
pub const PhaseExecutionTimer = @import("phase_execution_time.zig");
pub const SystemExecutionTime = @import("system_execution_time.zig");

pub fn install(game: *ecs.Game) !void {
    try game.addResource(allocators.GlobalAllocator{
        .allocator = game.allocator,
    });
    try game.addResource(allocators.FrameAllocator{
        .allocator = game.frame_allocator.allocator(),
        .arena = &game.frame_allocator,
    });
    try game.type_registry.registerType(allocators.GlobalAllocator);
    try game.type_registry.registerType(allocators.FrameAllocator);
    try game.addSystems(.tear_down, &.{
        ecs.system.labeledSystem("runtime.allocators.freeFrameAllocator", allocators.freeFrameAllocator),
    });
    try one_shot.install(game);
    try game.type_registry.registerType(wrappers.TypeRegistry);
    try game.type_registry.registerType(wrappers.SystemRegistry);
    try game.addResource(wrappers.TypeRegistry{
        .registry = &game.type_registry,
    });
    try game.addResource(wrappers.SystemRegistry{
        .registry = &game.systems_registry,
    });
    try game.type_registry.registerType(GlobalTimer);
    try game.addResource(GlobalTimer.init());
    try game.addSystems(.pre_update, &.{ecs.system.labeledSystem(
        "ecs.runtime.GlobalTimer.updateTimer",
        GlobalTimer.updateTimer,
    )});
    try PhaseExecutionTimer.install(game);
}
