const std = @import("std");
const print = std.debug.print;

const Pg = @import("postgres").Pg;

var gpa = std.heap.GeneralPurposeAllocator(.{}){};
const allocator = &gpa.allocator;

pub fn main() !void {
    // defer std.debug.assert(!gpa.deinit());

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

    var result = try db.execValues("SELECT * FROM users", .{});

    const user = result.parse(Users).?;

    print("{d} \n", .{user.id});

    _ = try db.exec("DROP TABLE users");
}
