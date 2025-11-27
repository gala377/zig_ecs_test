// In general we want something like so
// fn EventReader(comptime T: type) {
//      return struct {
//          const Self = @This();
//          using namespace MappedComponent(Self, Event(T)),
//
//          ^ this would expand to something like this
//          const MapsComponent: type = Event(T)
//
//          pub fn fromComponents(comp: *Event(T)) !Self {
//              return .{
//                  .buffer = comp.buffer,
//                  .current = 0,
//              }
//          }
//      };
// }
//
pub fn ResourceProxy(comptime T: type) ResourceProxyInfo(T) {
    return .{};
}

pub fn ResourceProxyInfo(comptime T: type) type {
    return struct {
        pub const MappedResource = T;
    };
}
