const std = @import("std");
const Postgres = @import("./postgres.zig");
const build_options = @import("build_options");

const Pg = Postgres.Pg;
const Result = Postgres.Result;
const Builder = Postgres.Builder;
const FieldInfo = Postgres.FieldInfo;
const Parser = Postgres.Parser;

const testing = std.testing;
const Allocator = std.mem.Allocator;

var gpa = std.heap.GeneralPurposeAllocator(.{}){};
const allocator = &gpa.allocator;

const Users = struct {
    id: u16,
    name: []const u8,
    age: u16,
};

test "database" {
    var db = try Pg.connect(allocator, build_options.db_uri);
    defer db.deinit();
    const schema =
        \\CREATE DATABASE IF NOT EXISTS root;
        \\CREATE TABLE IF NOT EXISTS users (id INT, name TEXT, age INT);
    ;

    _ = try db.exec(schema);

    var data = Users{ .id = 2, .name = "Steve", .age = 25 };
    var data2 = Users{ .id = 3, .name = "Tom", .age = 25 };

    _ = try db.insert(Users{ .id = 1, .name = "Charlie", .age = 20 });
    _ = try db.insert(data);

    //Insert pointer
    _ = try db.insert(&data2);

    //Insert array
    _ = try db.insert(&[_]Users{
        Users{ .id = 4, .name = "Tony", .age = 33 },
        Users{ .id = 5, .name = "Sara", .age = 33 },
        Users{ .id = 6, .name = "Tony", .age = 33 },
    });

    var result = try db.execValues("SELECT * FROM users WHERE name = {s}", .{"Charlie"});
    var result2 = try db.execValues("SELECT * FROM users WHERE id = {d}", .{2});
    var result3 = try db.execValues("SELECT * FROM users WHERE age = {d}", .{25});
    var result4 = try db.execValues("SELECT * FROM users WHERE age = {d}", .{33});

    //When all results are not parsed, the memory must be manually deinited
    defer result4.deinit();

    var user = result.parse(Users).?;
    var user2 = result2.parse(Users).?;
    var user3 = result4.parse(Users).?;

    while (result3.parse(Users)) |res| testing.expectEqual(res.age, 25);

    testing.expectEqual(result.rows, 1);
    testing.expectEqual(result2.rows, 1);
    testing.expectEqual(result3.rows, 2);
    testing.expectEqual(result4.rows, 3);

    testing.expectEqual(user.id, 1);
    testing.expectEqual(user.age, 20);

    testing.expectEqual(user2.id, 2);
    testing.expectEqualStrings(user2.name, "Steve");

    testing.expectEqual(user3.id, 4);
    testing.expectEqualStrings(user3.name, "Tony");

    _ = try db.exec("DROP TABLE users");
}

const Stats = struct { wins: u16 = 0, losses: u16 = 0 };
const Player = struct {
    id: u16,
    name: []const u8,
    stats: Stats,
    cards: ?[][]const u8 = null,

    pub fn onSave(self: *Player, comptime field: FieldInfo, builder: *Builder, value: anytype) !void {
        switch (field.type) {
            ?[][]const u8 => try builder.addStringArray(value.?),
            Stats => try builder.addJson(value),
            else => {},
        }
    }

    pub fn onLoad(self: *Player, comptime field: FieldInfo, value: []const u8) !void {
        var parser = Parser.init(allocator);
        switch (field.type) {
            ?[][]const u8 => self.cards = try parser.parseArray(value),
            Stats => self.stats = try parser.parseJson(Stats, value),
            else => {},
        }
    }
};

test "Custom types" {
    var db = try Pg.connect(allocator, build_options.db_uri);

    defer {
        std.debug.assert(!gpa.deinit());
        db.deinit();
    }

    const schema =
        \\CREATE DATABASE IF NOT EXISTS root;
        \\CREATE TABLE IF NOT EXISTS player (id INT, name TEXT, stats JSONB, cards STRING[]);
    ;

    _ = try db.exec(schema);

    var cards = [3][]const u8{
        "Ace",
        "2",
        "Queen",
    };

    var data = Player{ .id = 2, .name = "Steve", .stats = .{ .wins = 5, .losses = 3 }, .cards = cards[0..] };
    _ = try db.insert(&data);

    var data_cache: Player = undefined;
    var result = try db.execValues("SELECT * FROM player WHERE name = {s}", .{"Steve"});
    try result.parseTo(&data_cache);

    testing.expectEqual(data_cache.id, 2);
    testing.expectEqualStrings(data_cache.name, "Steve");
    testing.expectEqual(data_cache.stats.wins, 5);
    testing.expectEqual(data_cache.stats.losses, 3);

    //Free cards allocation
    defer allocator.free(data_cache.cards.?);

    _ = try db.exec("DROP TABLE player");
}
