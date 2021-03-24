const std = @import("std");
pub fn toLowerCase(comptime size: usize, string: *const [size]u8) [size]u8 {
    var buffer: [size]u8 = undefined;
    for (string) |char, index| {
        buffer[index] = std.ascii.toLower(char);
    }
    return buffer;
}
