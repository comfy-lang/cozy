const std = @import("std");
const http = std.http;
const Child = std.process.Child;

const comfyCompilerUrl = "https://github.com/comfy-lang/comfy/releases/download/v0.1.0/comfy";
const cozyDefaultPath = "~/.cozy/bin";
const cozyConfigPath = "~/.cozy/config.toml";

pub fn main() !void {
    const stdout = std.io.getStdOut().writer();
    const allocator = std.heap.page_allocator;

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 2) {
        try printHelp(stdout);
        return;
    }

    const command = args[1];

    if (std.mem.eql(u8, command, "new")) {
        const project_name = if (args.len >= 3) args[2] else "my-comfy-project";
        createProject(project_name, stdout, allocator) catch return;
        try stdout.print("Project {s} created successfully.\n", .{project_name});
        return;
    }

    if (std.mem.eql(u8, command, "build")) {
        try buildProject(stdout);
        return;
    }

    if (std.mem.eql(u8, command, "run")) {
        const file = if (args.len >= 3) args[2] else "src/main.fy";
        try runFile(file, stdout);
        return;
    }

    if (std.mem.eql(u8, command, "get-compiler")) {
        const target_path = if (args.len >= 4 and std.mem.eql(u8, args[2], "--path")) args[3] else null;
        try downloadCompiler(target_path, stdout);
    } else {
        try stdout.print("Unknown command: {s}\n", .{command});
        try printHelp(stdout);
    }
}

fn printHelp(writer: anytype) !void {
    try writer.print(
        \\cozy - the CLI tool and package manager for comfy-lang
        \\
        \\Usage:
        \\  cozy new <project-name>         Create a new comfy project
        \\  cozy build                      Build the current project
        \\  cozy run <file>                 Build and run a file (default: src/main.fy)
        \\  cozy get-compiler [--path dir]  Download the comfy compiler binary
        \\
    , .{});
}

fn createProject(name: []const u8, writer: anytype, allocator: std.mem.Allocator) !void {
    try writer.print("Creating project: {s}\n", .{name});

    std.fs.cwd().makeDir(name) catch |err| {
        if (err == error.PathAlreadyExists) {
            try writer.print("Project {s} already exists. Please choose a different name.\n", .{name});
            return error.PathAlreadyExists;
        }
        try writer.print("Failed to create project directory: {s}\n", .{name});
        std.debug.print("Error: {}\n", .{err});
        return err;
    };

    const buildDir = try std.fmt.allocPrint(allocator, "{s}/build", .{name});
    defer allocator.free(buildDir);
    try std.fs.cwd().makeDir(buildDir);

    const source_dir = try std.fmt.allocPrint(allocator, "{s}/src", .{name});
    defer allocator.free(source_dir);
    try std.fs.cwd().makeDir(source_dir);

    const project_file = try std.fmt.allocPrint(allocator, "{s}/project.comfx", .{name});
    defer allocator.free(project_file);
    const file = try std.fs.cwd().createFile(project_file, .{});
    defer file.close();
    try file.writeAll("[target]\narch = \"arm32\" \noutput = \"build/main.s\"\n[meta]\nname = \"a comfy project\" \nversion = \"0.1.0\"\ndescription = \"A cozy project\"\n");

    const main_file = try std.fmt.allocPrint(allocator, "{s}/src/main.fy", .{name});
    defer allocator.free(main_file);

    const mainFile = try std.fs.cwd().createFile(main_file, .{});
    defer mainFile.close();
    try mainFile.writeAll("fn main() {\n $write(1, \"Hello Comfy! :3\");\n $exit(0);\n}\n");
}

fn buildProject(writer: anytype) !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer if (gpa.deinit() != .ok) @panic("leak");
    const allocator = gpa.allocator();
    const compiler_path = try getCompilerPath(allocator);
    defer allocator.free(compiler_path);

    const current_dir_path = try std.fs.cwd().realpathAlloc(allocator, ".");
    defer allocator.free(current_dir_path);

    const source_dir_main_file = try std.fmt.allocPrint(allocator, "{s}/src/main.fy", .{current_dir_path});
    defer allocator.free(source_dir_main_file);

    const argv = [_][]const u8{ compiler_path, source_dir_main_file };

    try writer.print("Building project using: {s}\n", .{compiler_path});

    var child = Child.init(&argv, allocator);
    child.stdout_behavior = .Pipe;
    child.stderr_behavior = .Pipe;

    var stdout: std.ArrayListUnmanaged(u8) = .empty;
    defer stdout.deinit(allocator);
    var stderr: std.ArrayListUnmanaged(u8) = .empty;
    defer stderr.deinit(allocator);

    try child.spawn();
    try child.collectOutput(allocator, &stdout, &stderr, 1024);
    const term = try child.wait();

    if (term.Exited != 0) {
        try writer.print("Build failed with exit code: {}\n", .{term});
        try writer.print("Compiler stderr:\n{s}\n", .{stderr.items});
        return error.CompilationFailed;
    }

    try writer.print("Build succeeded:\n{s}", .{stdout.items});
}

fn runFile(file: []const u8, writer: anytype) !void {
    const allocator = std.heap.page_allocator;
    const compiler_path = try getCompilerPath(allocator);
    defer allocator.free(compiler_path);

    try writer.print("Running {s} with compiler: {s}\n", .{ file, compiler_path });
    // TODO: exec compiler on file
}

fn downloadCompiler(path_override: ?[]const u8, writer: anytype) !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const path_raw = path_override orelse cozyDefaultPath;
    const resolved_path = try resolveHomePath(path_raw, allocator);
    defer allocator.free(resolved_path);

    try writer.print("Downloading comfy compiler to: {s}\n", .{resolved_path});

    try std.fs.cwd().makePath(resolved_path);

    var client = http.Client{ .allocator = allocator };
    defer client.deinit();

    const body = try downloadComfyCompilerBinary(&client, allocator);
    defer allocator.free(body);

    const compiler_path = try std.fs.path.join(allocator, &[_][]const u8{
        resolved_path, "comfy",
    });
    defer allocator.free(compiler_path);

    const file = try std.fs.createFileAbsolute(compiler_path, .{});
    defer file.close();

    try file.writeAll(body);
    try file.chmod(0o755);

    // Save compiler path to config
    const config_path = try resolveHomePath(cozyConfigPath, allocator);
    defer allocator.free(config_path);

    const config_file = try std.fs.createFileAbsolute(config_path, .{ .truncate = true });
    defer config_file.close();

    const config_line = try std.fmt.allocPrint(allocator, "compiler_path = \"{s}\"\n", .{compiler_path});
    defer allocator.free(config_line);
    try config_file.writeAll(config_line);
    try writer.print("Compiler downloaded successfully to {s}\n", .{compiler_path});
}

fn downloadComfyCompilerBinary(client: *http.Client, allocator: std.mem.Allocator) ![]const u8 {
    const uri = try std.Uri.parse(comfyCompilerUrl);
    const buf = try allocator.alloc(u8, 1024 * 8);
    defer allocator.free(buf);
    var req = try client.open(.GET, uri, .{
        .server_header_buffer = buf,
    });
    defer req.deinit();

    try req.send();
    try req.finish();
    try req.wait();

    try std.testing.expectEqual(req.response.status, .ok);

    var rdr = req.reader();
    const body = try rdr.readAllAlloc(allocator, 1024 * 1024 * 4);

    return body;
}

fn resolveHomePath(path: []const u8, allocator: std.mem.Allocator) ![]u8 {
    if (std.mem.startsWith(u8, path, "~")) {
        const home = try std.process.getEnvVarOwned(allocator, "HOME");
        defer allocator.free(home);
        return try std.fs.path.join(allocator, &[_][]const u8{ home, path[1..] });
    }
    return try allocator.dupe(u8, path);
}

fn getCompilerPath(allocator: std.mem.Allocator) ![]u8 {
    const config_path = try resolveHomePath(cozyConfigPath, allocator);
    defer allocator.free(config_path);

    const file = try std.fs.openFileAbsolute(config_path, .{});
    defer file.close();

    const contents = try file.readToEndAlloc(allocator, 1024);
    defer allocator.free(contents);

    if (std.mem.startsWith(u8, contents, "compiler_path = ")) {
        const start = std.mem.indexOfScalar(u8, contents, '"') orelse return error.InvalidFormat;
        const end = std.mem.lastIndexOfScalar(u8, contents, '"') orelse return error.InvalidFormat;
        return try allocator.dupe(u8, contents[start + 1 .. end]);
    }

    return error.InvalidConfigFormat;
}
