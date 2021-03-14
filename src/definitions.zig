const std = @import("std");

pub const Error = error{ ConnectionFailure, QueryFailure, NotConnected, NotImplemented, WrongType };

pub const ColumnType = enum(usize) {
    Unknown = 0,
    Bool = 16,
    Char = 18,
    Int8 = 20,
    Int2 = 21,
    Int4 = 23,
    Text = 25,
    Float4 = 700,
    Float8 = 701,
    Varchar = 1043,
    Date = 1082,
    Time = 1083,
    Timestamp = 1114,

    pub fn castValue(column_type: ColumnType, comptime T: type, str: []const u8) !T {
        const Info = @typeInfo(T);
        switch (column_type) {
            .Int8, .Int4, .Int2 => {
                return std.fmt.parseInt(T, str, 10);
            },
            .Float4, .Float8 => {
                // TODO need a function similar to strToNum but can understand the decimal point
                return Error.NotImplemented;
            },
            .Bool => {
                if (T == bool and str.len > 0) {
                    return str[0] == 't';
                } else {
                    return Error.NotImplemented;
                }
            },
            .Char, .Text, .Varchar => {
                // FIXME Zig compiler says this cannot be done at compile time
                // if (utility.isStringType(T)) {
                //     return str;
                // }
                // Workaround
                if ((Info == .Pointer and Info.Pointer.size == .Slice and Info.Pointer.child == u8) or (Info == .Array and Info.Array.child == u8)) {
                    return str;
                } else if (Info == .Optional) {
                    const ChildInfo = @typeInfo(Info.Optional.child);
                    if (ChildInfo == .Pointer and ChildInfo.Pointer.Size == .Slice and ChildInfo.Pointer.child == u8) {
                        return str;
                    }
                    if (ChildInfo == .Array and ChildInfo.child == u8) {
                        return str;
                    }
                }
                return Error.NotImplemented;
            },
            .Date => {
                return Error.NotImplemented;
            },
            .Time => {
                return Error.NotImplemented;
            },
            .Timestamp => {
                return Error.NotImplemented;
            },
            else => {
                return Error.NotImplemented;
            },
        }
        unreachable;
    }
};
