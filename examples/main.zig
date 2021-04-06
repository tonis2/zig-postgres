const std = @import("std");
const print = std.debug.print;

const Postgres = @import("postgres");
const Pg = Postgres.Pg;
const Result = Postgres.Result;
const Builder = Postgres.Builder;
const ArrayList = std.ArrayList;

var gpa = std.heap.GeneralPurposeAllocator(.{}){};
const allocator = &gpa.allocator;

const Users = struct {
    id: i16,
    name: []const u8,
    age: i16,
    cards: ArrayList([]const u8),

    pub fn onSave(self: *const Users, comptime field: type, builder: *Builder) !void {
        switch (field) {
            ArrayList([]const u8) => {
                _ = try builder.buffer.writer().write("ARRAY[");
                for (self.cards.items) |value, i| _ = {
                    _ = try builder.buffer.writer().write(try std.fmt.allocPrint(builder.allocator, "'{s}'", .{value}));
                    if (i < self.cards.items.len - 1)
                        _ = try builder.buffer.writer().write(",");
                };
                _ = try builder.buffer.writer().write("]");

                try builder.values.append(builder.buffer.toOwnedSlice());
                builder.buffer.shrinkAndFree(0);
            },
            else => {},
        }
    }

    pub fn onParse() !void {

    }
};

pub fn main() !void {
    var db = try Pg.connect(allocator, "postgresql://root@tonis-xps:26257?sslmode=disable");

    defer {
        std.debug.assert(!gpa.deinit());
        db.deinit();
    }

    const schema =
        \\CREATE DATABASE IF NOT EXISTS root;
        \\CREATE TABLE users (id INT, name TEXT, age INT, cards STRING[]);
    ;

    _ = try db.exec(schema);

    var cards = [3][]const u8{
        "Ace",
        "2",
        "Queen",
    };

    var user = Users{ .id = 1, .age = 3, .name = "Steve", .cards = ArrayList([]const u8).fromOwnedSlice(allocator, cards[0..]) };

    _ = try db.insert(user);

    _ = try db.exec("DROP TABLE users");
}
