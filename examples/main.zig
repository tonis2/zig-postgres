const std = @import("std");
const print = std.debug.print;

const Postgres = @import("postgres");
const Pg = Postgres.Pg;
const Result = Postgres.Result;
const Builder = Postgres.Builder;
const FieldInfo = Postgres.FieldInfo;

const ArrayList = std.ArrayList;
const Utf8View = std.unicode.Utf8View;

var gpa = std.heap.GeneralPurposeAllocator(.{}){};
const allocator = &gpa.allocator;

const Users = struct {
    id: u16 = 0,
    name: []const u8 = "",
    age: u16 = 0,
    cards: ArrayList([]const u8),

    pub fn onSave(self: *const Users, comptime field: FieldInfo, builder: *Builder) !void {
        switch (field.type) {
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

    pub fn onLoad(self: *Users, comptime field: FieldInfo, value: []const u8) !void {
        switch (field.type) {
            ArrayList([]const u8) => {
                const parser = try Utf8View.init(value);
                var iterator = parser.iterator();
                var pause: usize = 1;
                while (iterator.nextCodepointSlice()) |char| {
                    if (std.mem.eql(u8, ",", iterator.peek(1))) {
                        try self.cards.append(value[pause..iterator.i]);
                        pause = iterator.i + 1;
                    }
                }
            },
            else => {},
        }
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
        \\CREATE TABLE IF NOT EXISTS users (id INT, name TEXT, age INT, cards STRING[]);
    ;

    _ = try db.exec(schema);

    var cards = [3][]const u8{
        "Ace",
        "2",
        "Queen",
    };

    _ = try db.insert(Users{ .id = 1, .age = 3, .name = "Steve", .cards = ArrayList([]const u8).fromOwnedSlice(allocator, cards[0..]) });
    _ = try db.insert(Users{ .id = 21, .age = 4, .name = "Karl", .cards = ArrayList([]const u8).fromOwnedSlice(allocator, cards[0..]) });

    var user_result = Users{ .cards = ArrayList([]const u8).init(allocator) };
    defer user_result.cards.deinit();

    var result = try db.execValues("SELECT * FROM users WHERE name = {s};", .{"Steve"});

    try result.parseTo(&user_result);

    print("{d} \n", .{user_result.id});

    var result2 = try db.execValues("SELECT * FROM users WHERE name = {s};", .{"Karl"});
    try result2.parseTo(&user_result);

    print("{s} \n", .{user_result.name});

    _ = try db.exec("DROP TABLE users");
}
