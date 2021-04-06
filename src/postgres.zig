const std = @import("std");
pub const c = @cImport({
    @cInclude("libpq-fe.h");
});

pub const Builder = @import("./sql_builder.zig").Builder;
const helpers = @import("./helpers.zig");
const Error = @import("./definitions.zig").Error;

const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const Result = @import("./result.zig").Result;

const print = std.debug.print;

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
                const pointer_info = @typeInfo(type_info.Pointer.child);
                if (pointer_info == .Array) {
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

                            try builder.autoAdd(child, field_type, field_value);
                        }
                    }
                }
            },
            .Struct => {
                const struct_info = @typeInfo(@TypeOf(data)).Struct;
                const struct_name = @typeName(@TypeOf(data));

                try builder.table(helpers.toLowerCase(struct_name.len, struct_name)[0..]);
                inline for (struct_info.fields) |field, index| {
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

                    try builder.autoAdd(data, field_type, field_value);
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
    var db = try Pg.connect(allocator, "postgresql://root@tonis-xps:26257?sslmode=disable");

    defer {
        std.debug.assert(!gpa.deinit());
        db.deinit();
    }

    const Users = struct {
        id: i16,
        name: []const u8,
        age: i16,
    };

    const schema =
        \\CREATE DATABASE IF NOT EXISTS root;
        \\CREATE TABLE IF NOT EXISTS users (id INT, name TEXT, age INT);
        \\CREATE TABLE IF NOT EXISTS school (pupils TEXT[]);
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

    while (result3.parse(Users)) |data| testing.expectEqual(data.age, 25);

    _ = try db.insert(&[_]Users{
        Users{ .id = 4, .name = "Tony", .age = 33 },
        Users{ .id = 5, .name = "Sara", .age = 33 },
        Users{ .id = 6, .name = "Tony", .age = 33 },
    });

    var result4 = try db.execValues("SELECT * FROM users WHERE age = {d}", .{33});

    testing.expectEqual(result.rows, 1);
    testing.expectEqual(result2.rows, 1);
    testing.expectEqual(result3.rows, 2);

    // testing.expectEqual(user.id, 1);
    // testing.expectEqualStrings(user.name, "Charlie");

    // testing.expectEqual(user2.id, 2);
    // testing.expectEqualStrings(user2.name, "Steve");
    // testing.expectEqual(result4.rows, 3);

    _ = try db.exec("DROP TABLE users");
}
