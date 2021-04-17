const std = @import("std");
const Builder = @import("../src/sql_builder.zig").Builder;
const testing = std.testing;

test "builder" {
    var temp_memory = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const allocator = &temp_memory.allocator;
    defer temp_memory.deinit();

    var builder = Builder.new(.Insert, allocator).table("test");

    try builder.addColumn("id");
    try builder.addColumn("name");
    try builder.addColumn("age");

    try builder.addValue("5");
    try builder.addValue("Test");
    try builder.addValue("3");
    try builder.end();

    testing.expectEqualStrings("INSERT INTO test (id,name,age) VALUES (5,'Test',3);", builder.command());

    builder.deinit();

    var builder2 = Builder.new(.Insert, allocator).table("test");

    try builder2.addColumn("id");
    try builder2.addColumn("name");
    try builder2.addColumn("age");

    try builder2.addValue("5");
    try builder2.addValue("Test");
    try builder2.addValue("3");

    try builder2.addValue("1");
    try builder2.addValue("Test2");
    try builder2.addValue("53");

    try builder2.addValue("3");
    try builder2.addValue("Test3");
    try builder2.addValue("53");
    try builder2.end();

    testing.expectEqualStrings("INSERT INTO test (id,name,age) VALUES (5,'Test',3),(1,'Test2',53),(3,'Test3',53);", builder2.command());
    builder2.deinit();

    var builder3 = Builder.new(.Update, allocator).table("test").where(try Builder.buildQuery("WHERE NAME = {s};", .{"Steve"}, allocator));

    try builder3.addColumn("id");
    try builder3.addColumn("name");
    try builder3.addColumn("age");

    try builder3.addValue("5");
    try builder3.addValue("Test");
    try builder3.addValue("3");

    try builder3.end();

    testing.expectEqualStrings("UPDATE test SET id=5,name='Test',age=3 WHERE NAME = 'Steve';", builder3.command());
    builder3.deinit();
}
