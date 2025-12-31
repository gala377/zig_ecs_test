const rl = @import("raylib");
const Color = @import("../root.zig").core.Color;

pub fn colorToRaylib(self: Color) rl.Color {
    return .init(self.r, self.g, self.b, self.a);
}
