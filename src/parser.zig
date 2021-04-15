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

pub fn parseArray(self: *const Self, value: []const u8, break_point: []const u8) ![][]const u8 {
    var buffer = std.ArrayList([]const u8).init(self.allocator);

    var stop_point: usize = try std.math.divCeil(usize, break_point.len, 2);
    for (value) |char, index| {
        const one_step = index + break_point.len;
        if (one_step == value.len and stop_point < index) {
            try buffer.append(value[stop_point..index]);
        }
        if (one_step == value.len) break;
        if (std.mem.eql(u8, value[index..one_step], break_point)) {
            try buffer.append(value[stop_point..index]);
            stop_point = one_step;
        }
    }
    return buffer.toOwnedSlice();
}

// const testing = std.testing;

// test "Parser" {
//     var gpa = std.heap.GeneralPurposeAllocator(.{}){};
//     const allocator = &gpa.allocator;

//     const test_string =
//         \\{Ace,2,Queen}
//     ;
//     const test_string2 =
//         \\{"Test string ?","I am long text!","Finishing words." }
//     ;

//     const parser = Self.init(allocator);
//     var parsed1 = try parser.parseArray(test_string, ",");
//     var parsed2 = try parser.parseArray(test_string2, "\x22,\x22");

//     var results1 = [3][]const u8{
//         "Ace",
//         "2",
//         "Queen",
//     };

//     var results2 = [3][]const u8{
//         "Test string ?",
//         "I am long text!",
//         "Finishing words.",
//     };

//     // Todo finish test
//     for (parsed1) |value, index| {
//         print("{s} \n", .{value});
//     }

//     for (parsed2) |value, index| {
//         print("{s} \n", .{value});
//     }

//     defer {
//         allocator.free(parsed1);
//         allocator.free(parsed2);
//         std.debug.assert(!gpa.deinit());
//     }
// }
