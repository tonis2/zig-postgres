const Builder = @import("std").build.Builder;

pub fn build(b: *Builder) void {
    const target = b.standardTargetOptions(.{});
    const mode = b.standardReleaseOptions();

    const exe = b.addExecutable("main", "examples/main.zig");
    exe.setTarget(target);
    exe.setBuildMode(mode);
    exe.addPackagePath("postgres", "src/postgres.zig");
    exe.linkSystemLibrary("c");
    exe.linkSystemLibrary("pq");
    exe.install();

    const run_cmd = exe.run();
    run_cmd.step.dependOn(b.getInstallStep());

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const tests = b.addTest("tests.zig");
    tests.setBuildMode(mode);
    tests.setTarget(target);
    tests.linkSystemLibrary("c");
    tests.linkSystemLibrary("pq");

    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&tests.step);
}
