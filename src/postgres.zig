const std = @import("std");
const db = @cImport({
    @cInclude("libpq-fe.h");
});

pub const Database = struct {
    connection: db.PGconn,

    pub fn new(address: []const u8) Database {
        return Database{
            .connection = db.PQconnectdb(address),
        };
    }
};
