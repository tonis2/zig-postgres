const std = @import("std");

const print = std.debug.print;
const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;

const Error = @import("./definitions.zig").Error;

pub const SQL = enum { Insert, Select, Delete, Update };

pub const Builder = struct {
    table_name: []const u8,
    buffer: ArrayList(u8),
    columns: ArrayList([]const u8),
    values: ArrayList([]const u8),
    allocator: *Allocator,
    build_type: SQL,

    pub fn new(build_type: SQL, allocator: *Allocator) Error!Builder {
        return Builder{
            .table_name = "",
            .buffer = ArrayList(u8).init(allocator),
            .columns = ArrayList([]const u8).init(allocator),
            .values = ArrayList([]const u8).init(allocator),
            .allocator = allocator,
            .build_type = build_type,
        };
    }

    pub fn table(self: *Builder, table_name: []const u8) !void {
        self.table_name = table_name;
    }

    pub fn addColumn(self: *Builder, column_name: []const u8) !void {
        try self.columns.append(column_name);
    }

    pub fn addStringValue(self: *Builder, value: []const u8) !void {
        try self.values.append(try std.fmt.allocPrint(self.allocator, "'{s}'", .{value}));
    }

    pub fn addNumValue(self: *Builder, value: anytype) !void {
        try self.values.append(try std.fmt.allocPrint(self.allocator, "{d}", .{value}));
    }

    pub fn addValue(self: *Builder, value: []const u8) !void {
        try self.values.append(value);
    }

    pub fn addStringArray(self: *Builder, values: ArrayList([]const u8)) !void {
        _ = try self.buffer.writer().write("ARRAY[");
        for (values.items) |value, i| _ = {
            _ = try self.buffer.writer().write(try std.fmt.allocPrint(self.allocator, "'{s}'", .{value}));
            if (i < values.items.len - 1)
                _ = try self.buffer.writer().write(",");
        };
        _ = try self.buffer.writer().write("]");

        try self.values.append(self.buffer.toOwnedSlice());
        self.buffer.shrinkAndFree(0);
    }

    pub fn autoAdd(self: *Builder, comptime field_type: type, field_value: anytype) !void {
        switch (field_type) {
            i16, i32, u8, u16, u32, usize => {
                try self.addNumValue(field_value);
            },
            []const u8 => {
                try self.addStringValue(field_value);
            },
            ?[]const u8 => {
                if (field_value != null)
                    try self.addStringValue(field_value.?);
            },
            ArrayList([]const u8) => {
                try self.addStringArray(field_value);
            },
            else => {},
        }
    }

    pub fn end(self: *Builder) !void {
        switch (self.build_type) {
            .Insert => {
                _ = try self.buffer.writer().write("INSERT INTO ");
                _ = try self.buffer.writer().write(self.table_name);

                for (self.columns.items) |column, index| {
                    if (index == 0) _ = try self.buffer.writer().write(" (");
                    if (index == self.columns.items.len - 1) {
                        _ = try self.buffer.writer().write(column);
                        _ = try self.buffer.writer().write(") ");
                    } else {
                        _ = try self.buffer.writer().write(column);
                        _ = try self.buffer.writer().write(",");
                    }
                }
                _ = try self.buffer.writer().write("VALUES");

                for (self.values.items) |value, index| {
                    const columns_mod = index % self.columns.items.len;
                    const final_value = index == self.values.items.len - 1;

                    if (index == 0) _ = try self.buffer.writer().write(" (");
                    if (columns_mod == 0 and index != 0) {
                        _ = try self.buffer.writer().write(")");
                        _ = try self.buffer.writer().write(",");
                        _ = try self.buffer.writer().write("(");
                    }

                    _ = try self.buffer.writer().write(value);

                    if (!final_value and columns_mod != self.columns.items.len - 1) {
                        _ = try self.buffer.writer().write(",");
                    }

                    if (final_value) {
                        _ = try self.buffer.writer().write(")");
                        _ = try self.buffer.writer().write(";");
                    }
                }
            },
            else => {
                return Error.NotImplemented;
            },
        }
    }

    pub fn command(self: *Builder) []const u8 {
        return self.buffer.items;
    }

    pub fn deinit(self: *Builder) void {
        self.columns.deinit();
        self.values.deinit();
        self.buffer.deinit();
    }
};

const testing = std.testing;

test "database" {
    var temp_memory = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const allocator = &temp_memory.allocator;
    defer temp_memory.deinit();

    var builder = try Builder.new(.Insert, allocator);

    try builder.table("test");
    try builder.addColumn("id");
    try builder.addColumn("name");
    try builder.addColumn("age");

    try builder.addValue("5");
    try builder.addStringValue("Test");
    try builder.addValue("3");
    try builder.end();

    testing.expectEqualStrings("INSERT INTO test (id,name,age) VALUES (5,'Test',3);", builder.command());

    builder.deinit();

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
    builder2.deinit();

    var builder3 = try Builder.new(.Insert, allocator);
    const array = &[_][]const u8{ "child1", "child2", "child3" };
    try builder3.table("test");
    try builder3.addColumn("id");
    try builder3.addColumn("name");
    try builder3.addColumn("children");

    try builder3.addValue("5");
    try builder3.addStringValue("Test");
    try builder3.addStringArray(array);

    try builder3.addValue("1");
    try builder3.addStringValue("Test2");
    try builder3.addStringArray(array);
    try builder3.end();

    testing.expectEqualStrings("INSERT INTO test (id,name,children) VALUES (5,'Test',ARRAY['child1','child2','child3']),(1,'Test2',ARRAY['child1','child2','child3']);", builder3.command());

    builder3.deinit();
}
