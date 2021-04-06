const std = @import("std");

pub const Error = error{ ConnectionFailure, QueryFailure, NotConnected, NotImplemented, WrongType, EmptyResult };

pub const ColumnType = enum(usize) {
    Unknown = 0,
    Bool = 16,
    Int2 = 21,
    Int4 = 23,
    Int8 = 20,

    Text = 25,
    Float4 = 700,
    Float8 = 701,
    Char = 18,
    Varchar = 1043,

    Date = 1082,
    Time = 1083,
    Timestamp = 1114,

    Json = 114,
    Jsonb = 3820,
    Uuid = 2950,
};
