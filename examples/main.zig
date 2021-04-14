const std = @import("std");
const print = std.debug.print;
const build_options = @import("build_options");

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
};

pub fn main() !void {
    var db = try Pg.connect(allocator, build_options.db_uri);

    defer {
        std.debug.assert(!gpa.deinit());
        db.deinit();
    }

    const schema =
        \\CREATE DATABASE IF NOT EXISTS root;
        \\CREATE TABLE IF NOT EXISTS users (id INT, name TEXT, age INT);
    ;

    _ = try db.exec(schema);

    _ = try db.insert(Users{ .id = 1, .name = "Charlie", .age = 20 });
    _ = try db.insert(Users{ .id = 2, .name = "Steve", .age = 25 });
    _ = try db.insert(Users{ .id = 3, .name = "Tom", .age = 25 });

    var result = try db.execValues("SELECT * FROM users WHERE name = {s};", .{"Charlie"});

    var user = result.parse(.{ .type = Users });

    if (user) |value| print("{s} \n", .{value.name});

    var result2 = try db.execValues("SELECT * FROM users WHERE age > {d};", .{20});

    while (result2.parse(.{ .type = Users })) |value| {
        print("{s} \n", .{value.name});
    }

    _ = try db.exec("DROP TABLE users");
}
