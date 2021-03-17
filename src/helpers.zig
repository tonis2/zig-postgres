const std = @import("std");
pub fn toLowerCase(comptime size: usize, string: *const [size]u8) [size]u8 {
    var buffer: [size]u8 = undefined;
    for (string) |char, index| {
        buffer[index] = std.ascii.toLower(char);
    }
    return buffer;
}

pub fn getDigitSize(comptime value: comptime_int) usize {
    if (value == 0)
        return 1;

    if (value < 0) value = value * (-1);
    return std.math.log(comptime_int, 10, value) + 1;
}
