# zig-mcp

An MCP (Model Context Protocol) server written in Zig. Provides a set of tools for AI assistants to interact with the filesystem, run shell commands, perform arithmetic, make web requests, and proxy prompts to other LLMs.

## Requirements

- Zig 0.16.0 or later

## Building

```bash
zig build
```

## Running

```bash
zig build run
```

To pass arguments to the server:

```bash
zig build run -- [args]
```

By default the server listens on `0.0.0.0:8000`.

## Configuration

Configuration is defined in `build.zig.zon`:

| Setting | Default | Description |
|---|---|---|
| `hostname` | `0.0.0.0` | Network interface to bind |
| `port` | `8000` | TCP port to listen on |
| `storage_directory` | `storage` | Root directory for file operations |

## Tools

The server exposes the following tools via the MCP `tools/list` and `tools/call` methods:

### Arithmetic
- **arithmetic** — Basic math: `add`, `subtract`, `multiply`, `divide`, `sqrt`

### File Operations
- **file_write** — Create or replace a file
- **file_append** — Append content to a file
- **file_overwrite** — Overwrite content at a specific position
- **file_read** — Read entire file content
- **file_read_slice** — Read a portion of a file
- **file_list** — List files in the current directory
- **file_size** — Get file size in bytes
- **file_delete** — Delete a file or directory

### Directory
- **change_directory** — Change working directory
- **current_directory** — Get the current working directory
- **home_directory** — Navigate to the user's home directory

### Memory
- **remember** — Store content in memory by keyword
- **recall** — Retrieve stored content by keyword

### Web
- **web_request** — Fetch content from a URL (strips HTML tags)

### Shell Commands
- **gcc** — Run the GNU C Compiler
- **make** — Run GNU Make
- **man** — View manual pages
- **openscad** — Render 3D models from `.scad` files
- **valgrind** — Memory debugging and leak detection
- **grep** — Search text in files
- **git** — Run git version control commands

### LLM Proxy
- **ask_other_llm** — Forward a prompt to another LLM server (via the connecting client's origin header)

## Protocol

The server implements the MCP JSON-RPC protocol. It handles the following method hashes:

- `initialize` — Server initialization
- `tools/list` — List available tools
- `tools/call` — Invoke a tool
- `notifications/initialized` — Client initialized notification
- `notifications/cancelled` — Cancellation notification

## Security

- All file operations are sandboxed within the configured `storage_directory`
- Absolute paths are rejected for file operations
- The `.git` directory cannot be deleted
- Cross-origin requests are allowed (CORS headers)

## License

Unlicense
