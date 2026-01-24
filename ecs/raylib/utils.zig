const rl = @import("raylib");
const ecs = @import("../prelude.zig");

const Color = ecs.core.Color;

pub fn colorToRaylib(self: Color) rl.Color {
    return .init(self.r, self.g, self.b, self.a);
}
