const std = @import("std");
const print = std.debug.print;
const Allocator = std.mem.Allocator;
const meta = std.meta;
const Utf8View = std.unicode.Utf8View;
const Self = @This();

allocator: *Allocator = allocator,

pub fn init(allocator: *Allocator) Self {
    return Self{
        .allocator = allocator,
    };
}

pub fn parseJson(self: *const Self, comptime T: type, value: []const u8) !T {
    return try std.json.parse(T, &std.json.TokenStream.init(value), .{ .allocator = self.allocator });
}

pub fn parseArray(self: *const Self, value: []const u8) ![][]const u8 {
    var buffer = std.ArrayList([]const u8).init(self.allocator);

    const parser = try Utf8View.init(value);
    var iterator = parser.iterator();
    var pause: usize = 1;
    while (iterator.nextCodepointSlice()) |char| {
        if (std.mem.eql(u8, ",", iterator.peek(1))) {
            try buffer.append(value[pause..iterator.i]);
            pause = iterator.i + 1;
        }
        if (std.mem.eql(u8, "}", iterator.peek(1))) {
            try buffer.append(value[pause..iterator.i]);
            pause = iterator.i + 1;
        }
    }
    return buffer.toOwnedSlice();
}
