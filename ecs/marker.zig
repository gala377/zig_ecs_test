/// Used on empty components.
/// Unfortunately our system does not handle 0 - sized components well.
const Self = @This();

marker: usize = 0,

pub const empty: Self = .{};
