const std = @import("std");

const print = std.debug.print;
const c = @import("./postgres.zig").c;
const helpers = @import("./helpers.zig");
const Parser = @import("./postgres.zig").Parser;

const ColumnType = @import("./definitions.zig").ColumnType;
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

const Definitions = @import("./definitions.zig");
const Error = Definitions.Error;

pub const FieldInfo = struct {
    name: []const u8,
    type: type,
};

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

    pub fn isEmpty(self: Result) bool {
        return self.rows < 1;
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

    //Parses and returns struct with values
    pub fn parse(self: *Result, comptime return_type: type, allocator: ?*Allocator) ?return_type {
        if (self.rows < 1) return null;
        if (self.active_row == self.rows) return null;

        const type_info = @typeInfo(return_type);

        if (type_info != .Struct) {
            @compileError("Need to use struct as parser type");
        }

        const struct_fields = type_info.Struct.fields;

        var result: return_type = undefined;

        var col_id: usize = 0;
        while (col_id < self.columns) : (col_id += 1) {
            const column_name = self.columnName(col_id);
            const column_type = self.getType(col_id);
            const value: []const u8 = self.getValue(self.active_row, col_id);
            if (value.len == 0) break;

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
                        else => {
                            const is_extended = @hasDecl(return_type, "onLoad");

                            if (is_extended) @field(result, "onLoad")(FieldInfo{ .name = field.name, .type = field.field_type }, value, Parser.init(allocator.?)) catch unreachable;
                        },
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
