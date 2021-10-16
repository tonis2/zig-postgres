const std = @import("std");
const Postgres = @import("postgres");
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

    var user = result.parse(Users, null).?;
    var user2 = result2.parse(Users, null).?;
    var user3 = result4.parse(Users, null).?;

    while (result3.parse(Users, null)) |res| testing.expectEqual(res.age, 25);

    //Temp memory
    var temp_memory = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const temp_allocator = &temp_memory.allocator;

    //SQL query builder
    var builder = Builder.new(.Update, temp_allocator).table("users").where(try Builder.buildQuery("WHERE id = {d};", .{2}, temp_allocator));

    defer {
        builder.deinit();
        temp_memory.deinit();
    }

    try builder.addColumn("name");
    try builder.addValue("Harold");
    try builder.end();

    _ = try db.exec(builder.command());

    var result5 = try db.execValues("SELECT * FROM users WHERE id = {d}", .{2});
    var user4 = result5.parse(Users, null).?;

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

    testing.expectEqual(user4.id, 2);
    testing.expectEqualStrings(user4.name, "Harold");

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

    pub fn onLoad(self: *Player, comptime field: FieldInfo, value: []const u8, parser: Parser) !void {
        switch (field.type) {
            ?[][]const u8 => self.cards = try parser.parseArray(value, ","),
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

    var result = try db.execValues("SELECT * FROM player WHERE name = {s}", .{"Steve"});
    var data_cache = result.parse(Player, allocator).?;

    testing.expectEqual(data_cache.id, 2);
    testing.expectEqualStrings(data_cache.name, "Steve");
    testing.expectEqual(data_cache.stats.wins, 5);
    testing.expectEqual(data_cache.stats.losses, 3);

    //Free cards allocation
    defer allocator.free(data_cache.cards.?);

    _ = try db.exec("DROP TABLE player");
}

const KeyValue = struct {
    id: ?u32 = null,
    value: i32,
};

test "Nullable type" {
    var db = try Pg.connect(allocator, build_options.db_uri);

    defer {
        std.debug.assert(!gpa.deinit());
        db.deinit();
    }

    const schema =
        \\CREATE DATABASE IF NOT EXISTS root;
        \\CREATE TABLE IF NOT EXISTS keyValue (id SERIAL PRIMARY KEY, value int);
    ;

    _ = try db.exec(schema);

    _ = try db.insert(&[_]KeyValue{
        KeyValue{ .value = 42 },
        KeyValue{ .value = 741 },
        KeyValue{ .value = 33 },
    });

    var result = try db.execValues("SELECT * FROM keyValue WHERE value = {d}", .{42});
    var value42 = result5.parse(KeyValue, null).?;
    testing.expect(value42.id != null);
    testing.expectEqual(value42.value, 42);

    var result = try db.execValues("SELECT * FROM keyValue WHERE value = {d}", .{33});
    var value33 = result5.parse(KeyValue, null).?;
    testing.expect(value33.id != null);
    testing.expect(value33.id > value42.id);

    _ = try db.exec("DROP TABLE keyValue");
}
