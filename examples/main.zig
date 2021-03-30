const std = @import("std");
const print = std.debug.print;

const Pg = @import("postgres").Pg;

var gpa = std.heap.GeneralPurposeAllocator(.{}){};
const allocator = &gpa.allocator;

pub fn main() !void {
    const Users = struct {
        id: i16,
        name: []const u8,
        age: i16,
    };

    var db = try Pg.connect(allocator, "postgresql://root@tonis-xps:26257?sslmode=disable");

    defer {
        std.debug.assert(!gpa.deinit());
        db.deinit();
    }

    const schema =
        \\CREATE DATABASE IF NOT EXISTS root;
        \\CREATE TABLE IF NOT EXISTS users (id INT, name TEXT, age INT);
    ;

    _ = try db.exec(schema);

    var data = Users{ .id = 1, .name = "Charlie", .age = 20 };

    _ = try db.insert(data);
    _ = try db.insert(Users{ .id = 2, .name = "Steve", .age = 25 });
    _ = try db.insert(Users{ .id = 3, .name = "Karl", .age = 25 });
    _ = try db.insert(&[_]Users{
        Users{ .id = 4, .name = "Tony", .age = 25 },
        Users{ .id = 5, .name = "Sara", .age = 32 },
        Users{ .id = 6, .name = "Fred", .age = 11 },
    });

    var age: u16 = 25;
    var result = try db.execValues("SELECT * FROM users WHERE name = {s}", .{"Charlie"});
    var result2 = try db.execValues("SELECT * FROM users WHERE id = {d}", .{2});
    var result3 = try db.execValues("SELECT * FROM users WHERE age = {d}", .{age});

    while (result3.parse(Users)) |user| {
        print("{s} \n", .{user.name});
    }

    var user = result.parse(Users).?;
    var user2 = result2.parse(Users).?;
    print("{d} \n", .{result.rows});
    print("{d} \n", .{user.id});
    print("{s} \n", .{user.name});

    print("{d} \n", .{user2.id});
    print("{s} \n", .{user2.name});

    _ = try db.exec("DROP TABLE users");
}
