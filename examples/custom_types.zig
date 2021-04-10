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
const Allocator = std.mem.Allocator;

var gpa = std.heap.GeneralPurposeAllocator(.{}){};
const allocator = &gpa.allocator;

const Stats = struct { wins: u16, losses: u16 };

const Users = struct {
    id: u16 = 0,
    name: []const u8 = "",
    age: u16 = 0,
    cards: ?[][]const u8 = null,
    stats: Stats = Stats{ .wins = 0, .losses = 0 },

    pub fn onSave(self: *Users, comptime field: FieldInfo, builder: *Builder, value: anytype) !void {
        switch (field.type) {
            ?[][]const u8 => {
                if (value == null) return;
                // Create ARRAY[value, value]
                _ = try builder.buffer.writer().write("ARRAY[");
                for (value.?) |entry, i| _ = {
                    _ = try builder.buffer.writer().write(try std.fmt.allocPrint(builder.allocator, "'{s}'", .{entry}));
                    if (i < value.?.len - 1) _ = try builder.buffer.writer().write(",");
                };
                _ = try builder.buffer.writer().write("]");

                // Append ARRAY string to SQL builder as value
                try builder.values.append(builder.buffer.toOwnedSlice());
            },
            Stats => {
                //Convert stats to json and push to builder values
                _ = try builder.buffer.writer().write("('");
                var buffer = std.ArrayList(u8).init(builder.allocator);
                try std.json.stringify(self.stats, .{}, buffer.writer());
                _ = try builder.buffer.writer().write(buffer.toOwnedSlice());
                _ = try builder.buffer.writer().write("')");
                _ = try builder.values.append(builder.buffer.toOwnedSlice());
            },
            else => {},
        }
    }

    pub fn onLoad(self: *Users, comptime field: FieldInfo, value: []const u8) !void {
        switch (field.type) {
            ?[][]const u8 => {
                var buffer = ArrayList([]const u8).init(allocator);

                const parser = try Utf8View.init(value);
                var iterator = parser.iterator();
                var pause: usize = 1;
                while (iterator.nextCodepointSlice()) |char| {
                    if (std.mem.eql(u8, ",", iterator.peek(1))) {
                        try buffer.append(value[pause..iterator.i]);
                        pause = iterator.i + 1;
                    }
                    if (std.mem.eql(u8, "}", iterator.peek(1))) {
                        try buffer.append(value[pause..iterator.i]);
                        pause = iterator.i + 1;
                    }
                }
                self.cards = buffer.toOwnedSlice();
            },
            Stats => {
                //Convert json string to struct
                self.stats = try std.json.parse(Stats, &std.json.TokenStream.init(value), .{ .allocator = allocator });
            },
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
        \\CREATE TABLE IF NOT EXISTS users (id INT, name TEXT, age INT, cards STRING[], stats JSONB);
    ;

    _ = try db.exec(schema);

    var cards = [3][]const u8{
        "Ace",
        "2",
        "Queen",
    };

    var cards2 = [3][]const u8{
        "3",
        "5",
        "Jocker",
    };

    //Save data to db
    var user = Users{ .id = 1, .age = 3, .name = "Karl", .stats = Stats{ .wins = 0, .losses = 5 }, .cards = cards[0..] };
    var user2 = Users{ .id = 1, .age = 3, .name = "Steve", .stats = Stats{ .wins = 0, .losses = 5 }, .cards = null };
    _ = try db.insert(&user);
    _ = try db.insert(&user2);

    var user_result = Users{};

    defer allocator.free(user_result.cards.?);

    //Find data from database
    var result = try db.execValues("SELECT * FROM users WHERE name = {s};", .{"Karl"});
    try result.parseTo(&user_result);

    print("id {d} \n", .{user_result.id});
    print("name {s} \n", .{user_result.name});
    print("wins {d} \n", .{user_result.stats.wins});
    print("cards {s} \n", .{user_result.cards.?});

    _ = try db.exec("DROP TABLE users");
}
