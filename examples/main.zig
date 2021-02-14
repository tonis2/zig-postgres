const Database = @import("postgres").Database;

pub fn main() void {
    const db = Database.new("postgresql://root@pop-os:26257?sslmode=disable");
}
