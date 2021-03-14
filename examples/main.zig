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

    try db.insert(&[_]Accounts{
        .{
            .id = 1,
            .balance = 5,
        },
        .{
            .id = 2,
            .balance = 5,
        },
        .{
            .id = 3,
            .balance = 7,
        },
    });
    try db.insert(Accounts{
        .id = 4,
        .balance = 5,
    });

    // _ = try db.execValues("INSERT INTO accounts (id, balance) VALUES ({}, {})", .{ 1, 2 });

    var result = try db.exec("SELECT * FROM accounts");

    var retrieved_data = std.ArrayList(Accounts).init(allocator);

    while (result.parse(Accounts)) |data| {
        print("data {d} \n", .{data.balance});
    }

    _ = try db.exec("DROP TABLE accounts");

    defer {
        db.finish();
        result.deinit();
        retrieved_data.deinit();
        std.debug.assert(!gpa.deinit());
    }
}
