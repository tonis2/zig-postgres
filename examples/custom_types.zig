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

const Stats = struct { wins: u16, losses: u16 };

const Users = struct {
    id: u16 = 0,
    name: []const u8 = "",
    age: u16 = 0,
    cards: ArrayList([]const u8),
    stats: Stats = Stats{ .wins = 0, .losses = 0 },

    pub fn onSave(self: *const Users, comptime field: FieldInfo, builder: *Builder) !void {
        switch (field.type) {
            ArrayList([]const u8) => {
                // Create ARRAY[value, value] string
                _ = try builder.buffer.writer().write("ARRAY[");
                for (self.cards.items) |value, i| _ = {
                    _ = try builder.buffer.writer().write(try std.fmt.allocPrint(builder.allocator, "'{s}'", .{value}));
                    if (i < self.cards.items.len - 1)
                        _ = try builder.buffer.writer().write(",");
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
            ArrayList([]const u8) => {
                // Parse ARRAY[value, value] to values and append these values to ArrayList
                const parser = try Utf8View.init(value);
                var iterator = parser.iterator();
                var pause: usize = 1;
                while (iterator.nextCodepointSlice()) |char| {
                    if (std.mem.eql(u8, ",", iterator.peek(1))) {
                        try self.cards.append(value[pause..iterator.i]);
                        pause = iterator.i + 1;
                    }
                    if (std.mem.eql(u8, "}", iterator.peek(1))) {
                        try self.cards.append(value[pause..iterator.i]);
                        pause = iterator.i + 1;
                    }
                }
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

    //Save data to db
    _ = try db.insert(Users{ .id = 1, .age = 3, .name = "Steve", .stats = Stats{ .wins = 0, .losses = 5 }, .cards = ArrayList([]const u8).fromOwnedSlice(allocator, cards[0..]) });
    _ = try db.insert(Users{ .id = 21, .age = 4, .name = "Karl", .stats = Stats{ .wins = 3, .losses = 1 }, .cards = ArrayList([]const u8).fromOwnedSlice(allocator, cards[0..]) });

    var user_result = Users{ .cards = ArrayList([]const u8).init(allocator) };
    defer user_result.cards.deinit();

    var result = try db.execValues("SELECT * FROM users WHERE name = {s};", .{"Steve"});

    try result.parseTo(&user_result);

    user_result.cards.shrinkAndFree(0);

    //Find data from database
    var result2 = try db.execValues("SELECT * FROM users WHERE name = {s};", .{"Karl"});
    try result2.parseTo(&user_result);

    print("id {d} \n", .{user_result.id});
    print("name {s} \n", .{user_result.name});
    print("wins {d} \n", .{user_result.stats.wins});

    for (user_result.cards.items) |value| {
        print("card {s} \n", .{value});
    }
    _ = try db.exec("DROP TABLE users");
}
