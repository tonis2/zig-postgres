const std = @import("std");
const c = @cImport({
    @cInclude("libpq-fe.h");
});

const helpers = @import("./helpers.zig");
const Error = @import("./definitions.zig").Error;
const ColumnType = @import("./definitions.zig").ColumnType;
const Builder = @import("./sql_builder.zig").Builder;

const print = std.debug.print;

pub const Result = struct {
    res: *c.PGresult,
    columns: usize,
    rows: usize,
    active_row: usize = 0,

    pub fn new(result: *c.PGresult) Result {
        const rows = @intCast(usize, c.PQntuples(result));
        const columns = @intCast(usize, c.PQnfields(result));

        return Result{
            .res = result,
            .columns = columns,
            .rows = rows,
        };
    }

    fn columnName(self: Result, column_number: usize) []const u8 {
        const value = c.PQfname(self.res, @intCast(c_int, column_number));
        return @as([*c]const u8, value)[0..std.mem.len(value)];
    }

    fn getType(self: Result, column_number: usize) ColumnType {
        var oid = @intCast(usize, c.PQftype(self.res, @intCast(c_int, column_number)));
        return std.meta.intToEnum(ColumnType, oid) catch return ColumnType.Unknown;
    }

    fn getValue(self: Result, row_number: usize, column_number: usize) []const u8 {
        const value = c.PQgetvalue(self.res, @intCast(c_int, row_number), @intCast(c_int, column_number));
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

        //Lets loop thgrough all the columns and return active_row as a struct
        var col_id: usize = 0;
        while (col_id < self.columns) : (col_id += 1) {
            const column_name = self.columnName(col_id);
            const column_type = self.getType(col_id);
            const value = self.getValue(self.active_row, col_id);

            inline for (struct_fields) |field| {
                if (std.mem.eql(u8, field.name, column_name)) {
                    print("type {d} \n", .{field.field_type});
                    // @field(result, field.name) = column_type.castValue(field.field_type, value) catch unreachable;
                }
            }
        }

        self.active_row = self.active_row + 1;
        if (self.active_row == self.rows) self.deinit();
        return result;
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
        var temp_memory = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        const allocator = &temp_memory.allocator;

        const type_info = @typeInfo(@TypeOf(data));

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
                                u8, u16, u32, usize => {
                                    try builder.addValue(try std.fmt.allocPrint(allocator, "{d}", .{field_value}));
                                },
                                []const u8 => {
                                    try builder.addValue(try std.fmt.allocPrint(allocator, "'{s}'", .{field_value}));
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
                        u8, u16, u32, usize => {
                            try builder.addValue(try std.fmt.allocPrint(allocator, "{d}", .{field_value}));
                        },
                        []const u8 => {
                            try builder.addValue(try std.fmt.allocPrint(allocator, "'{s}'", .{field_value}));
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
  
        //Exec command
        _ = try self.exec(builder.commands.items);
        defer {
            temp_memory.deinit();
            builder.deinit();
        }
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

        //Join values and query with allocPrint and then exec the string
        return self.exec(try std.fmt.allocPrint(allocator, query, values));
    }

    pub fn finish(self: *Self) void {
        c.PQfinish(self.connection);
    }
};

const testing = std.testing;

test "database" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = &gpa.allocator;
    defer std.debug.assert(!gpa.deinit());

    const Users = struct {
        id: u16,
        name: []const u8,
        age: u16,
    };

    var db = try Pg.connect(allocator, "postgresql://root@tonis-xps:26257?sslmode=disable");

    const schema =
        \\CREATE DATABASE IF NOT EXISTS root;
        \\CREATE TABLE IF NOT EXISTS users (id INT, name TEXT, age INT);
    ;

    _ = try db.exec(schema);

    try db.insert(Users{ .id = 1, .name = "Charlie", .age = 20 });

    var result = try db.execValues("SELECT * FROM users WHERE name = {}", .{"Charlie"});

    const user = result.parse(Users).?;

    testing.expectEqual(user.id, 1);

    _ = try db.exec("DROP TABLE users");
}
