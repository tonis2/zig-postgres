# zig-postgres


Light bindings around Postgres `libpq`

This is tested with zig `0.8`



Installing `libpg` on debian linux


`sudo apt-get install libpq-dev`



## How to install 

-----

Add this repository as submodule 

`git submodule add git@github.com:tonis2/zig-postgres.git /dependencies/zig-postgres`


Add following code lines into your project `build.zig`


This code adds the package and links required libraries.

```zig
    exe.addPackage(.{ .name = "postgres", .path = "/dependencies/zig-postgres/src/postgres.zig" });
    exe.linkSystemLibrary("c");
    exe.linkSystemLibrary("libpq");
```

## How to use
-----




### Connecting to database


```zig
    const Pg = @import("postgres").Pg;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = &gpa.allocator;
    defer std.debug.assert(!gpa.deinit());

    var db = try Pg.connect(allocator, "postgresql://root@postgresURL:26257?sslmode=disable");

```

### Executing SQL

```zig
   const schema =
        \\CREATE DATABASE IF NOT EXISTS root;
        \\CREATE TABLE IF NOT EXISTS users (id INT, name TEXT, age INT);
    ;

    _ = try db.exec(schema);
```


### Inserting data


Be mindful that this query, uses `struct name` as lowercase letters for `table` name.

```zig
  const Users = struct {
        id: i16,
        name: []const u8,
        age: i16,
    };

  try db.insert(Users{ .id = 1, .name = "Charlie", .age = 20 });
  try db.insert(Users{ .id = 2, .name = "Steve", .age = 25 });
  try db.insert(Users{ .id = 3, .name = "Karl", .age = 25 });


  try db.insert(&[_]Users{
     Users{ .id = 4, .name = "Tony", .age = 25 },
     Users{ .id = 5, .name = "Sara", .age = 32 },
     Users{ .id = 6, .name = "Fred", .age = 11 },
  });

```


### Exec query with values

```zig
try db.execValues("SELECT * FROM users WHERE name = {s}", .{"Charlie"});

_ = try db.execValues("INSERT INTO users (id, name, age) VALUES ({d}, {s}, {d})", .{ 5, "Tom", 32 });

```


### Read query results

```zig
var result = try db.execValues("SELECT * FROM users WHERE id = {d}", .{2});
var user = result.parse(Users).?;

print("{d} \n", .{user.id});
print("{s} \n", .{user.name});

```


```zig
var results = try db.execValues("SELECT * FROM users WHERE age = {d}", .{25});

while (results.parse(Users)) |user| {
    print("{s} \n", .{user.name});
}
```

```zig
var result = try db.execValues("SELECT * FROM users WHERE name = {s}", .{"Charlie"});
var user = result.parse(Users);

if(user) print("{s} \n", .{user.name});
```


Many thanks for this [library](https://github.com/aeronavery/zig-orm)
