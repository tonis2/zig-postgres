const std = @import("std");
const print = std.debug.print;

const Database = @import("postgres").Database;

var gpa = std.heap.GeneralPurposeAllocator(.{}){};
const allocator = &gpa.allocator;

pub fn main() !void {
    var db = try Database.connect(allocator, "postgresql://root@tonis-xps:26257?sslmode=disable");

    const schema =
        \\CREATE DATABASE IF NOT EXISTS root;
        \\CREATE TABLE IF NOT EXISTS accounts (id INT PRIMARY KEY, balance INT);
    ;

    try db.insert(schema);

    // try db.exec("INSERT INTO accounts (id, balance) VALUES (1, 1000), (2, 250);");

    var result = try db.exec("SELECT * FROM accounts");
    print("type {s} \n", .{result.getType(1)});

    defer {
        db.finish();
        std.debug.assert(!gpa.deinit());
    }
}
