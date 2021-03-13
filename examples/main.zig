const std = @import("std");
const print = std.debug.print;

const Pg = @import("postgres").Pg;

var gpa = std.heap.GeneralPurposeAllocator(.{}){};
const allocator = &gpa.allocator;

const Accounts = struct {
    id: u32,
    balance: u32,
};

pub fn main() !void {
    var db = try Pg.connect(allocator, "postgresql://root@tonis-xps:26257?sslmode=disable");

    const schema =
        \\CREATE DATABASE IF NOT EXISTS root;
        \\CREATE TABLE IF NOT EXISTS accounts (id INT, balance INT);
    ;

    _ = try db.exec(schema);

    const data = &[_]Accounts{
        .{
            .id = 4,
            .balance = 5,
        },
        .{
            .id = 5,
            .balance = 5,
        },
        .{
            .id = 6,
            .balance = 7,
        },
    };

    try db.insert(Accounts{
        .id = 4,
        .balance = 5,
    });

    try db.insert(data);

    // var values = try db.queryBuilder(Accounts, .{ .name = "test" });
    // try db.exec("INSERT INTO accounts (id, balance) VALUES (1, 1000), (2, 250);");

    var result = try db.exec("SELECT * FROM accounts");
    // print("type {s} \n", .{result.getType(1)});

    defer {
        db.finish();
        std.debug.assert(!gpa.deinit());
    }
}
