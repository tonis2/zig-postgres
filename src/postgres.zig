const std = @import("std");
const c = @cImport({
    @cInclude("libpq-fe.h");
});

pub const Builder = @import("./sql_builder.zig").Builder;

const helpers = @import("./helpers.zig");
const Error = @import("./definitions.zig").Error;
const ColumnType = @import("./definitions.zig").ColumnType;
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

const print = std.debug.print;

pub const Result = struct {
    res: ?*c.PGresult,
    columns: usize,
    rows: usize,
    active_row: usize = 0,

    pub fn new(result: *c.PGresult) Result {
        const rows = @intCast(usize, c.PQntuples(result));
        const columns = @intCast(usize, c.PQnfields(result));

        if (rows == 0) {
            c.PQclear(result);
            return Result{
                .res = null,
                .columns = columns,
                .rows = rows,
            };
        }

        return Result{
            .res = result,
            .columns = columns,
            .rows = rows,
        };
    }

    fn columnName(self: Result, column_number: usize) []const u8 {
        const value = c.PQfname(self.res.?, @intCast(c_int, column_number));
        return @as([*c]const u8, value)[0..std.mem.len(value)];
    }

    fn getType(self: Result, column_number: usize) ColumnType {
        var oid = @intCast(usize, c.PQftype(self.res.?, @intCast(c_int, column_number)));
        return std.meta.intToEnum(ColumnType, oid) catch return ColumnType.Unknown;
    }

    fn getValue(self: Result, row_number: usize, column_number: usize) []const u8 {
        const value = c.PQgetvalue(self.res.?, @intCast(c_int, row_number), @intCast(c_int, column_number));
        return @as([*c]const u8, value)[0..std.mem.len(value)];
    }

    pub fn parse(self: *Result, comptime returnType: type) ?returnType {
        if (self.rows < 1) return null;
        if (self.active_row == self.rows) return null;

        const type_info = @typeInfo(returnType);

        if (type_info != .Struct) {
            @compileError("Need to use struct as parser type");
        }

        const struct_fields = type_info.Struct.fields;

        var result: returnType = undefined;

        var col_id: usize = 0;
        while (col_id < self.columns) : (col_id += 1) {
            const column_name = self.columnName(col_id);
            const column_type = self.getType(col_id);
            const value: []const u8 = self.getValue(self.active_row, col_id);

            inline for (struct_fields) |field| {
                if (std.mem.eql(u8, field.name, column_name)) {
                    switch (field.field_type) {
                        ?u8,
                        ?u16,
                        ?u32,
                        => {
                            @field(result, field.name) = std.fmt.parseUnsigned(@typeInfo(field.field_type).Optional.child, value, 10) catch unreachable;
                        },
                        u8, u16, u32, usize => {
                            @field(result, field.name) = std.fmt.parseUnsigned(field.field_type, value, 10) catch unreachable;
                        },
                        ?i8,
                        ?i16,
                        ?i32,
                        => {
                            @field(result, field.name) = std.fmt.parseInt(@typeInfo(field.field_type).Optional.child, value, 10) catch unreachable;
                        },
                        i8, i16, i32 => {
                            @field(result, field.name) = std.fmt.parseInt(field.field_type, value, 10) catch unreachable;
                        },
                        []const u8, ?[]const u8 => {
                            @field(result, field.name) = value;
                        },
                        else => {},
                    }
                }
            }
        }

        self.active_row = self.active_row + 1;
        if (self.active_row == self.rows) self.deinit();
        return result;
    }

    pub fn deinit(self: Result) void {
        c.PQclear(self.res.?);
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

    pub fn insert(self: Self, data: anytype) !Result {
        var temp_memory = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        const allocator = &temp_memory.allocator;

        var builder = try Builder.new(.Insert, allocator);
        const type_info = @typeInfo(@TypeOf(data));

        defer {
            builder.deinit();
            temp_memory.deinit();
        }

        switch (type_info) {
            .Pointer => {
                const pointer_type = @typeInfo(type_info.Pointer.child);
                if (pointer_type == .Array) {
                    // For each item in inserted array
                    for (data) |child, child_index| {

                        //Set table name as first items struct name.
                        if (child_index == 0) {
                            const struct_name = @typeName(@TypeOf(child));
                            try builder.table(helpers.toLowerCase(struct_name.len, struct_name)[0..]);
                        }

                        const struct_fields = @typeInfo(@TypeOf(child)).Struct.fields;

                        inline for (struct_fields) |field, index| {

                            //Add first child struct keys as column values
                            if (child_index == 0) try builder.addColumn(field.name);

                            const field_value = @field(child, field.name);
                            const field_type: type = field.field_type;

                            //Add the struct values in array
                            switch (field_type) {

                                //Cast int to string
                                i16, i32, u8, u16, u32, usize => {
                                    try builder.addNumValue(field_value);
                                },
                                []const u8 => {
                                    try builder.addStringValue(field_value);
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
                    const field_type_info = @typeInfo(field_type);

                    if (field_type_info == .Optional) {
                        if (field_value != null) {
                            try builder.addColumn(field.name);
                        }
                    } else {
                        try builder.addColumn(field.name);
                    }

                    switch (field_type) {
                        i16, i32, u8, u16, u32, usize => {
                            try builder.addNumValue(field_value);
                        },
                        []const u8 => {
                            try builder.addStringValue(field_value);
                        },
                        ?[]const u8 => {
                            if (field_value != null)
                                try builder.addStringValue(field_value.?);
                        },
                        [][]const u8 => {
                            try builder.addStringArray(field_value);
                        },
                        else => {},
                    }
                }
            },
            else => {},
        }

        try builder.end();
        //Exec command
        return try self.exec(builder.command());
    }

    pub fn exec(self: Self, query: []const u8) !Result {
        var cstr_query = try std.cstr.addNullByte(self.allocator, query);
        defer self.allocator.free(cstr_query);

        var res: ?*c.PGresult = c.PQexec(self.connection, cstr_query);
        var response_code = @enumToInt(c.PQresultStatus(res));

        if (response_code != c.PGRES_TUPLES_OK and response_code != c.PGRES_COMMAND_OK and response_code != c.PGRES_NONFATAL_ERROR) {
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

    pub fn execValues(self: Self, comptime query: []const u8, values: anytype) !Result {
        var temp_memory = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        defer temp_memory.deinit();

        const allocator = &temp_memory.allocator;

        comptime var values_info = @typeInfo(@TypeOf(values));
        comptime var temp_fields: [values_info.Struct.fields.len]std.builtin.TypeInfo.StructField = undefined;

        inline for (values_info.Struct.fields) |field, index| {
            const value = @field(values, field.name);
            const field_type = @TypeOf(value);

            switch (field_type) {
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
        var parsed_values: @Type(values_info) = undefined;
        inline for (values_info.Struct.fields) |field, index| {
            const value = @field(values, field.name);

            switch (field.field_type) {
                comptime_int => {
                    @field(parsed_values, field.name) = @intCast(i32, value);
                    return;
                },
                i16, i32, u8, u16, u32, usize => {
                    @field(parsed_values, field.name) = @as(i32, value);
                },
                else => {
                    @field(parsed_values, field.name) = try std.fmt.allocPrint(allocator, "'{s}'", .{value});
                },
            }
        }

        return try self.exec(try std.fmt.allocPrint(allocator, query, parsed_values));
    }

    pub fn deinit(self: *Self) void {
        c.PQfinish(self.connection);
    }
};

const testing = std.testing;

test "database" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = &gpa.allocator;

    const Users = struct {
        id: i16,
        name: []const u8,
        age: i16,
    };

    var db = try Pg.connect(allocator, "postgresql://root@tonis-xps:26257?sslmode=disable");

    const schema =
        \\CREATE DATABASE IF NOT EXISTS root;
        \\CREATE TABLE IF NOT EXISTS users (id INT, name TEXT, age INT);
    ;

    _ = try db.exec(schema);

    _ = try db.insert(Users{ .id = 1, .name = "Charlie", .age = 20 });
    _ = try db.insert(Users{ .id = 2, .name = "Steve", .age = 25 });
    _ = try db.insert(Users{ .id = 3, .name = "Tom", .age = 25 });

    var result = try db.execValues("SELECT * FROM users WHERE name = {s}", .{"Charlie"});
    var result2 = try db.execValues("SELECT * FROM users WHERE id = {d}", .{2});
    var result3 = try db.execValues("SELECT * FROM users WHERE age = {d}", .{25});

    var user = result.parse(Users).?;
    var user2 = result2.parse(Users).?;

    testing.expectEqual(result.rows, 1);
    testing.expectEqual(result2.rows, 1);
    testing.expectEqual(result3.rows, 2);

    testing.expectEqual(user.id, 1);
    testing.expectEqualStrings(user.name, "Charlie");

    testing.expectEqual(user2.id, 2);
    testing.expectEqualStrings(user2.name, "Steve");

    while (result3.parse(Users)) |data| testing.expectEqual(data.age, 25);

    _ = try db.insert(&[_]Users{
        Users{ .id = 4, .name = "Tony", .age = 33 },
        Users{ .id = 5, .name = "Sara", .age = 33 },
        Users{ .id = 6, .name = "Tony", .age = 33 },
    });

    var result4 = try db.execValues("SELECT * FROM users WHERE age = {d}", .{33});

    testing.expectEqual(result4.rows, 3);

    _ = try db.exec("DROP TABLE users");

    defer {
        std.debug.assert(!gpa.deinit());
        db.deinit();
    }
}
