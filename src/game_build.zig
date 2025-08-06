const std = @import("std");
const ecs = @import("ecs");
const DecalartionGenerator = @import("ecs").DeclarationGenerator;
const imgui = @import("ecs").imgui;
const Component = @import("ecs").Component;
const ExportLua = @import("ecs").component.ExportLua;
const logic = @import("logic.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{
        .safety = true,
        .retain_metadata = true,
    }).init;
    defer {
        switch (gpa.deinit()) {
            .leak => {
                std.debug.print("Leaks found!\n", .{});
            },
            else => {
                std.debug.print("no leaks found\n", .{});
            },
        }
    }
    try generate(gpa.allocator());
}

const TestComponent = struct {
    pub usingnamespace Component(TestComponent);
    pub usingnamespace ExportLua(TestComponent, .{});

    test_field: bool,
};

fn generate(allocator: std.mem.Allocator) !void {
    var generator = DecalartionGenerator.init("scripts/types/generated.d.lua", "scripts/lib/components.lua", allocator);
    defer generator.deinit();

    try ecs.game.registerDefaultComponentsForBuild(&generator);
    try imgui.exportBuild(&generator);
    try generator.registerComponentForBuild(TestComponent);
    try generator.registerComponentsForBuild(.{
        logic.ButtonClose,
        logic.ButtonOpen,
    });

    try generator.generate();
}
