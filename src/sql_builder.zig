const std = @import("std");

const print = std.debug.print;
const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;

const Error = @import("./definitions.zig").Error;

pub const SQL = enum { Insert, Select, Delete, Update };

pub const Builder = struct {
    commands: ArrayList(u8),
    columns: ArrayList([]const u8),
    values: ArrayList([]const u8),
    build_type: SQL,

    pub fn new(build_type: SQL, allocator: *Allocator) !Builder {
        var builder = Builder{
            .commands = ArrayList(u8).init(allocator),
            .columns = ArrayList([]const u8).init(allocator),
            .values = ArrayList([]const u8).init(allocator),
            .build_type = build_type,
        };
        switch (build_type) {
            .Insert => {
                _ = try builder.commands.writer().write("INSERT INTO ");
            },
            else => {
                return Error.NotImplemented;
            },
        }
        return builder;
    }

    pub fn table(self: *Builder, table_name: []const u8) !void {
        switch (self.build_type) {
            .Insert => {
                _ = try self.commands.writer().write(table_name);
            },
            else => {
                return Error.NotImplemented;
            },
        }
    }

    pub fn addColumn(self: *Builder, column_name: []const u8) !void {
        try self.columns.append(column_name);
    }

    pub fn addValue(self: *Builder, value: []const u8) !void {
        try self.values.append(value);
    }

    pub fn end(self: *Builder) !void {
        switch (self.build_type) {
            .Insert => {
                for (self.columns.items) |column, index| {
                    if (index == 0) _ = try self.commands.writer().write(" (");
                    if (index == self.columns.items.len - 1) {
                        _ = try self.commands.writer().write(column);
                        _ = try self.commands.writer().write(") ");
                    } else {
                        _ = try self.commands.writer().write(column);
                        _ = try self.commands.writer().write(",");
                    }
                }
                _ = try self.commands.writer().write("VALUES");

                for (self.values.items) |value, index| {
                    const columns_mod = index % self.columns.items.len;
                    const final_value = index == self.values.items.len - 1;
                    if (index == 0) _ = try self.commands.writer().write(" (");
                    if (columns_mod == 0 and index != 0) {
                        _ = try self.commands.writer().write(")");
                        _ = try self.commands.writer().write(",");
                        _ = try self.commands.writer().write("(");
                    }

                    _ = try self.commands.writer().write(value);

                    if (!final_value and columns_mod != self.columns.items.len - 1) {
                        _ = try self.commands.writer().write(",");
                    }

                    if (final_value) {
                        _ = try self.commands.writer().write(")");
                        _ = try self.commands.writer().write(";");
                    }
                }
            },
            else => {
                return Error.NotImplemented;
            },
        }
    }

    pub fn command(self: *Builder) []const u8 {
        return self.commands.items;
    }

    pub fn deinit(self: *Builder) void {
        self.columns.deinit();
        self.commands.deinit();
        self.values.deinit();
    }
};

const testing = std.testing;

test "database" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = &gpa.allocator;

    var builder = try Builder.new(.Insert, allocator);

    try builder.table("test");
    try builder.addColumn("id");
    try builder.addColumn("name");
    try builder.addColumn("age");

    try builder.addValue("5");
    try builder.addValue("Test");
    try builder.addValue("3");
    try builder.end();
    testing.expectEqualStrings("INSERT INTO test (id,name,age) VALUES (5,Test,3);", builder.command());

    var builder2 = try Builder.new(.Insert, allocator);
    try builder2.table("test");
    try builder2.addColumn("id");
    try builder2.addColumn("name");
    try builder2.addColumn("age");

    try builder2.addValue("5");
    try builder2.addValue("Test");
    try builder2.addValue("3");

    try builder2.addValue("1");
    try builder2.addValue("Test2");
    try builder2.addValue("53");

    try builder2.addValue("3");
    try builder2.addValue("Test3");
    try builder2.addValue("53");
    try builder2.end();

    testing.expectEqualStrings("INSERT INTO test (id,name,age) VALUES (5,Test,3),(1,Test2,53),(3,Test3,53);", builder2.command());

    defer {
        builder.deinit();
        builder2.deinit();
        std.debug.assert(!gpa.deinit());
    }
}
