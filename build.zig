const Builder = @import("std").build.Builder;

const examples = [2][]const u8{ "main", "custom_types" };

pub fn build(b: *Builder) void {
    const target = b.standardTargetOptions(.{});
    const mode = b.standardReleaseOptions();

    const db_uri = b.option(
        []const u8,
        "db",
        "Specify the database url",
    ) orelse "postgresql://root@tonis-xps:26257?sslmode=disable";

    inline for (examples) |example| {
        const exe = b.addExecutable(example, "examples/" ++ example ++ ".zig");
        exe.setTarget(target);
        exe.setBuildMode(mode);
        exe.addBuildOption([]const u8, "db_uri", db_uri);

        exe.addPackagePath("postgres", "src/postgres.zig");
        exe.linkSystemLibrary("c");
        exe.linkSystemLibrary("libpq");

        exe.install();

        const run_cmd = exe.run();
        run_cmd.step.dependOn(b.getInstallStep());

        const run_step = b.step(example, "Run the app");
        run_step.dependOn(&run_cmd.step);
    }

    const tests = b.addTest("tests.zig");
    tests.setBuildMode(mode);
    tests.setTarget(target);
    tests.linkSystemLibrary("c");
    tests.linkSystemLibrary("libpq");
    tests.addBuildOption([]const u8, "db_uri", db_uri);

    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&tests.step);
}
