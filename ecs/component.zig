fn simpleHashString(comptime str: []const u8) u64 {
    var hash: u64 = 5381;
    for (str) |c| {
        hash = ((hash << 5) +% hash) +% @as(u64, c); // hash * 33 + c
    }
    return hash;
}

pub const ComponentId = u64;

pub fn Component(comptime T: type) type {
    return struct {
        pub const is_component_marker: void = void{};
        pub const comp_id: ComponentId = simpleHashString(@typeName(T));
        pub const comp_name: []const u8 = @typeName(T);
    };
}
