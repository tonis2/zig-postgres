const std = @import("std");
const print = std.debug.print;
const build_options = @import("build_options");

const Postgres = @import("postgres");
const Pg = Postgres.Pg;
const Result = Postgres.Result;
const Builder = Postgres.Builder;
const FieldInfo = Postgres.FieldInfo;
const Parser = Postgres.Parser;

const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;

var gpa = std.heap.GeneralPurposeAllocator(.{}){};
const allocator = &gpa.allocator;

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

pub fn main() !void {
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
    defer allocator.free(data_cache.cards.?);

    var result = try db.execValues("SELECT * FROM player WHERE name = {s}", .{"Steve"});
    try result.parseTo(&data_cache);

    print("id {d} \n", .{data_cache.id});
    print("name {s} \n", .{data_cache.name});
    print("wins {d} \n", .{data_cache.stats.wins});
    print("cards {s} \n", .{data_cache.cards.?});

    _ = try db.exec("DROP TABLE player");
}
