const std = @import("std");
const Allocator = std.mem.Allocator;

pub fn toLowerCase(comptime size: usize, string: *const [size]u8) [size]u8 {
    var buffer: [size]u8 = undefined;
    for (string) |char, index| {
        buffer[index] = std.ascii.toLower(char);
    }
    return buffer;
}

// Retype comptime_ints and string values
pub fn RetypeValues(values: anytype) type {
    comptime var values_info = @typeInfo(@TypeOf(values));
    comptime var temp_fields: [values_info.Struct.fields.len]std.builtin.TypeInfo.StructField = undefined;

    inline for (values_info.Struct.fields) |field, index| {
        switch (field.field_type) {
            i16, i32, u8, u16, u32, usize, comptime_int => {
                temp_fields[index] = std.builtin.TypeInfo.StructField{
                    .name = field.name,
                    .field_type = i32,
                    .default_value = null,
                    .is_comptime = false,
                    .alignment = if (@sizeOf(field.field_type) > 0) @alignOf(field.field_type) else 0,
                };
            },
            else => {
                temp_fields[index] = std.builtin.TypeInfo.StructField{
                    .name = field.name,
                    .field_type = []const u8,
                    .default_value = null,
                    .is_comptime = false,
                    .alignment = if (@sizeOf(field.field_type) > 0) @alignOf(field.field_type) else 0,
                };
            },
        }
    }
    values_info.Struct.fields = &temp_fields;

    return @Type(values_info);
}

