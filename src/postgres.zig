const std = @import("std");
const c = @cImport({
    @cInclude("libpq-fe.h");
});
const helpers = @import("./helpers.zig");

const print = std.debug.print;
const ArrayList = std.ArrayList;
const Builder = @import("./sql_builder.zig").Builder;

pub const Error = error{ ConnectionFailure, QueryFailure, NotConnected };

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
                if (Info == .Int or Info == .ComptimeInt) {
                    // return utility.strToNum(T, str) catch return error.TypesNotCompatible;
                }
                return error.TypesNotCompatible;
            },
            .Float4, .Float8 => {
                // TODO need a function similar to strToNum but can understand the decimal point
                return error.NotImplemented;
            },
            .Bool => {
                if (T == bool and str.len > 0) {
                    return str[0] == 't';
                } else {
                    return error.TypesNotCompatible;
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
                return error.TypesNotCompatible;
            },
            .Date => {
                return error.NotImplemented;
            },
            .Time => {
                return error.NotImplemented;
            },
            .Timestamp => {
                return error.NotImplemented;
            },
            else => {
                return error.TypesNotCompatible;
            },
        }
        unreachable;
    }
};

pub const Result = struct {
    res: *c.PGresult,
    pub fn new(result: *c.PGresult) Result {
        return Result{
            .res = result,
        };
    }

    pub fn numberOfRows(self: Result) usize {
        return @intCast(usize, c.PQntuples(self.res));
    }

    pub fn numberOfColumns(self: Result) usize {
        return @intCast(usize, c.PQnfields(self.res));
    }

    pub fn getType(self: Result, column_number: usize) ColumnType {
        var oid = @intCast(usize, c.PQftype(self.res, @intCast(c_int, column_number)));
        return std.meta.intToEnum(ColumnType, oid) catch return ColumnType.Unknown;
    }

    pub fn deinit(self: Result) void {
        c.PQclear(self.res);
    }
};

pub const Pg = struct {
    const Self = @This();

    connection: *c.PGconn,
    allocator: *std.mem.Allocator,

    pub fn connect(allocator: *std.mem.Allocator, address: []const u8) !Self {
        var conn_info = try std.cstr.addNullByte(allocator, address);
        var connection: *c.PGconn = undefined;

        defer allocator.free(conn_info);

        if (c.PQconnectdb(conn_info)) |conn| {
            connection = conn;
        }

        if (@enumToInt(c.PQstatus(connection)) != c.CONNECTION_OK) {
            return Error.ConnectionFailure;
        }

        return Self{
            .allocator = allocator,
            .connection = connection,
        };
    }

    pub fn insert(self: Self, comptime data: anytype) !void {
        var builder = try Builder.new(.Insert, self.allocator);
        var temporary_memory = std.heap.ArenaAllocator.init(std.heap.page_allocator);

        const allocator = &temporary_memory.allocator;

        const type_info = @typeInfo(@TypeOf(data));

        switch (type_info) {
            .Pointer => {
                const pointer_type = @typeInfo(type_info.Pointer.child);
                if (pointer_type == .Array) {
                    // For each item in inserted array
                    for (data) |child, child_index| {

                        //Set table name as first items struct name.
                        if (child_index == 0) {
                            const table_name = @typeName(@TypeOf(child));
                            try builder.table(helpers.toLowerCase(table_name.len, table_name)[0..]);
                        }

                        const struct_fields = @typeInfo(@TypeOf(child)).Struct.fields;

                        inline for (struct_fields) |field, index| {

                            //Add data column values
                            if (child_index == 0) {
                                try builder.addColumn(field.name);
                            }

                            const field_value = @field(child, field.name);
                            const field_type: type = field.field_type;
                            //Add all values in array
                            switch (field_type) {

                                //Cast int to string
                                u8, u16, u32, usize => {
                                    try builder.addValue(try std.fmt.allocPrint(allocator, "{}", .{field_value}));
                                },
                                []const u8 => {
                                    try builder.addValue(field_value);
                                },
                                else => {
                                    //Todo other types
                                },
                            }
                        }
                    }
                }
            },
            .Struct => {
                const struct_fields = @typeInfo(@TypeOf(data)).Struct.fields;
                const struct_name = @typeName(@TypeOf(data));

                try builder.table(helpers.toLowerCase(struct_name.len, struct_name)[0..]);
                inline for (struct_fields) |field, index| {
                    const field_value = @field(data, field.name);
                    const field_type: type = field.field_type;

                    try builder.addColumn(field.name);

                    switch (field_type) {
                        //Cast int to string
                        u8, u16, u32, usize => {
                            try builder.addValue(try std.fmt.allocPrint(allocator, "{}", .{field_value}));
                        },
                        []const u8 => {
                            try builder.addValue(field_value);
                        },
                        else => {
                            //Todo other types
                        },
                    }
                }
            },
            else => {},
        }

        try builder.end();
        print("command {s} \n", .{builder.commands.items});
        //Exec command
        // _ = try self.exec(command.items);
        defer {
            temporary_memory.deinit();
            builder.deinit();
        }
    }

    pub fn exec(self: Self, query: []const u8) !Result {
        var cstr_query = try std.cstr.addNullByte(self.allocator, query);
        defer self.allocator.free(cstr_query);

        var res: ?*c.PGresult = c.PQexec(self.connection, cstr_query);
        var response_code = @enumToInt(c.PQresultStatus(res));

        if (response_code != c.PGRES_TUPLES_OK and response_code != c.PGRES_COMMAND_OK and response_code != c.PGRES_NONFATAL_ERROR) {
            var msg = c.PQresultErrorMessage(res);
            std.debug.warn("Error {s}\n", .{c.PQresultErrorMessage(res)});
            c.PQclear(res);
            return Error.QueryFailure;
        }

        if (res) |result| {
            return Result.new(result);
        } else {
            return Error.QueryFailure;
        }
    }

    pub fn finish(self: *Self) void {
        c.PQfinish(self.connection);
    }
};
