const std = @import("std");
pub const c = @cImport({
    @cInclude("libpq-fe.h");
});

const build_options = @import("build_options");

pub const Builder = @import("./sql_builder.zig").Builder;
pub const Parser = @import("./parser.zig");

const helpers = @import("./helpers.zig");
const Definitions = @import("./definitions.zig");
const Error = Definitions.Error;

const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

pub const Result = @import("./result.zig").Result;
pub const FieldInfo = @import("./result.zig").FieldInfo;

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

        var builder = Builder.new(.Insert, allocator);
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
                            _ = builder.table(helpers.toLowerCase(struct_name.len, struct_name)[0..]);
                        }

                        const struct_fields = @typeInfo(@TypeOf(child)).Struct.fields;
                        const is_extended = @hasDecl(@TypeOf(child), "onSave");

                        inline for (struct_fields) |field, index| {
                            const field_type_info = @typeInfo(field.field_type);
                            const field_value = @field(child, field.name);

                            //Add first child struct keys as column value
                            if (field_type_info == .Optional) {
                                if (field_value != null) try builder.addColumn(field.name);
                            } else if (child_index == 0) {
                                try builder.addColumn(field.name);
                            }
                            builder.autoAdd(child, FieldInfo{ .name = field.name, .type = field.field_type }, field_value, is_extended) catch unreachable;
                        }
                    }
                }
                if (pointer_info == .Struct) {
                    //Struct pointer
                    const struct_info = @typeInfo(type_info.Pointer.child).Struct;
                    const struct_name = @typeName(type_info.Pointer.child);
                    const is_extended = @hasDecl(type_info.Pointer.child, "onSave");

                    _ = builder.table(helpers.toLowerCase(struct_name.len, struct_name)[0..]);

                    inline for (struct_info.fields) |field, index| {
                        const field_type_info = @typeInfo(field.field_type);
                        const field_value = @field(data, field.name);
                        if (field_type_info == .Optional) {
                            if (field_value != null) try builder.addColumn(field.name);
                        } else {
                            try builder.addColumn(field.name);
                        }

                        builder.autoAdd(data, FieldInfo{ .name = field.name, .type = field.field_type }, field_value, is_extended) catch unreachable;
                    }
                }
            },
            .Struct => {
                const struct_info = @typeInfo(@TypeOf(data)).Struct;
                const struct_name = @typeName(@TypeOf(data));
                const is_extended = @hasDecl(@TypeOf(data), "onSave");

                _ = builder.table(helpers.toLowerCase(struct_name.len, struct_name)[0..]);
                inline for (struct_info.fields) |field, index| {
                    const field_type_info = @typeInfo(field.field_type);
                    const field_value = @field(data, field.name);

                    if (field_type_info == .Optional) {
                        if (field_value != null) try builder.addColumn(field.name);
                    } else {
                        try builder.addColumn(field.name);
                    }

                    builder.autoAdd(data, FieldInfo{ .name = field.name, .type = field.field_type }, field_value, is_extended) catch unreachable;
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

        return self.exec(try Builder.buildQuery(query, values, allocator));
    }

    pub fn deinit(self: *Self) void {
        c.PQfinish(self.connection);
    }
};
