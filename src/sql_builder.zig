const std = @import("std");

const print = std.debug.print;
const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;

const helpers = @import("./helpers.zig");
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
                    const final_value = index == self.values.items.len - 1;
                    if (index == 0) _ = try self.commands.writer().write(" (");

                    _ = try self.commands.writer().write(value);

                    if (index % self.columns.items.len != 0 and !final_value) {
                        _ = try self.commands.writer().write(")");
                        _ = try self.commands.writer().write(",");
                        _ = try self.commands.writer().write("(");
                    } else if (!final_value) {
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

    pub fn deinit(self: *Builder) void {
        self.columns.deinit();
        self.commands.deinit();
        self.values.deinit();
    }
};
