const std = @import("std");
const http = std.http;

const comfyCompilerUrl = "https://github.com/comfy-lang/comfy/releases/download/v0.1.0/comfy";
const cozyDefaultPath = "~/.cozy/bin";

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
        try createProject(project_name, stdout);
    }

    if (std.mem.eql(u8, command, "build")) {
        try buildProject(stdout);
    }

    if (std.mem.eql(u8, command, "run")) {
        const file = if (args.len >= 3) args[2] else "src/main.fy";
        try runFile(file, stdout);
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
    try std.fs.cwd().makeDir(name);
    const source_dir = try std.fmt.allocPrint(allocator, "{s}/src", .{name});
    defer allocator.free(source_dir);
    try std.fs.cwd().makeDir(source_dir);

    const project_file = try std.fmt.allocPrint(allocator, "{s}/project.comfx", .{name});
    defer allocator.free(project_file);
    const file = try std.fs.cwd().createFile(project_file, .{});
    defer file.close();
    try file.writeAll("[meta]\nversion: \"0.1.0\"\ndescription: \"A cozy project\"\n");

    const main_file = try std.fmt.allocPrint(allocator, "{s}/src/main.fy", .{name});
    defer allocator.free(main_file);

    const mainFile = try std.fs.cwd().createFile(main_file, .{});
    defer mainFile.close();
    try mainFile.writeAll("fn main() {\n $write(1, \"Hello Comfy! :3\");\n$exit(0);\n}\n");
}

fn buildProject(writer: anytype) !void {
    // TODO: call comfy binary with args
    try writer.print("Building project...\n", .{});
}

fn runFile(file: []const u8, writer: anytype) !void {
    // TODO: call comfy binary on the given file
    try writer.print("Running {s}...\n", .{file});
}

fn downloadCompiler(path_override: ?[]const u8, writer: anytype) !void {
    const path = path_override orelse cozyDefaultPath;
    try writer.print("Downloading comfy compiler to: {s}\n", .{path});
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    const heapAlloc = std.heap.page_allocator;

    const home_dir = try std.process.getEnvVarOwned(heapAlloc, "HOME");
    defer heapAlloc.free(home_dir);

    const full_path = try std.fs.path.join(heapAlloc, &[_][]const u8{
        home_dir, ".cozy", "bin",
    });
    defer heapAlloc.free(full_path);

    var root = try std.fs.openDirAbsolute("/", .{});
    defer root.close();

    try root.makePath(full_path);

    var client = http.Client{ .allocator = allocator };
    defer client.deinit();

    const body = try downloadComfyCompilerBinary(&client, allocator);
    defer allocator.free(body);

    const compiler_path = try std.fs.path.join(heapAlloc, &[_][]const u8{
        full_path, "comfy",
    });
    defer heapAlloc.free(compiler_path);

    const file = try std.fs.createFileAbsolute(compiler_path, .{});
    defer file.close();

    try file.writeAll(body);
    try file.chmod(0o755);

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
