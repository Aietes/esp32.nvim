# LSP configuration

ESP32.nvim provides a clangd configuration; your Neovim setup must register and
enable it.

## LazyVim

Add this alongside the ESP32.nvim plugin spec:

```lua
{
  "neovim/nvim-lspconfig",
  opts = function(_, opts)
    opts.servers = opts.servers or {}
    opts.servers.clangd = require("esp32").lsp_config()
  end,
}
```

LazyVim will register and enable the resulting server configuration.

## Plain Neovim 0.11+

After ESP32.nvim is available on the runtime path:

```lua
vim.lsp.config("clangd", require("esp32").lsp_config())
vim.lsp.enable("clangd")
```

`vim.lsp.config()` and `vim.lsp.enable()` are the native Neovim 0.11 APIs. The
[Neovim LSP documentation](https://neovim.io/doc/user/lsp.html) describes the
same registration flow.

## What the configuration does

`require("esp32").lsp_config()`:

- resolves the configured build directory against the ESP-IDF project root
- starts Espressif's clangd with that compilation database
- prefers `sdkconfig` and `CMakeLists.txt` as project root markers
- avoids falling back to a parent `.git` directory for nested projects
- uses current LSP position-encoding capabilities
- appends any configured `clangd_args`

The plugin searches for Espressif's clangd in this order:

1. `clangd` on `PATH`, if `clangd --version` identifies an Espressif build
2. `IDF_TOOLS_PATH`, supporting EIM and classic ESP-IDF layouts
3. `~/.espressif/tools/esp-clang`
4. `C:\Espressif\tools\esp-clang` on Windows

If it cannot find Espressif's build when the server starts, it warns and falls
back to `clangd` on `PATH`. `:ESPInfo` reports the exact command without
triggering that warning.

## Compilation databases and restarts

clangd needs the flags, target, definitions, and include paths from
`compile_commands.json`. ESP32.nvim points it at `build.clang` by default.

Run `:ESPReconfigure` when the database is missing or was produced by GCC. The
command:

1. runs `idf.py -B <build_dir> -D IDF_TOOLCHAIN=clang reconfigure`
2. waits for a successful exit
3. restarts clangd clients attached to that project
4. reattaches their buffers

The restart is intentional. clangd reads its compilation database at startup,
and its own troubleshooting guide notes that it must be restarted after the
database changes.

`:ESPSetTarget` performs the same restart after ESP-IDF regenerates the project
for the selected chip.

## Nested projects and working directories

ESP-IDF commands do not depend on Neovim's current working directory. The plugin
uses the root of the attached clangd client, or searches upward from the current
buffer for `sdkconfig` or `CMakeLists.txt`, then passes that root to `idf.py`.

This is useful for an ESP-IDF project nested inside a monorepo. Use `:ESPInfo`
and `:checkhealth vim.lsp` to verify the resolved root if commands affect the
wrong directory.

When go-to-definition opens framework source below `$IDF_PATH/components`, the
plugin reuses the clangd client from the originating project. This keeps the
framework buffer on the application's compilation database instead of treating
the component's own `CMakeLists.txt` as a separate project root.

## Other C and C++ projects

The snippets above replace the enabled `clangd` configuration with the
ESP32.nvim configuration. `CMakeLists.txt` is also common outside ESP-IDF, so a
single global setup can use Espressif's clangd for other CMake projects.

If you regularly work on both ESP-IDF and non-ESP projects, use separate
Neovim profiles or choose the clangd configuration conditionally in your own
config. Avoid enabling two clangd configurations for the same buffer.

## Query-driver

Cross-toolchain projects sometimes need clangd to query the compiler named in
`compile_commands.json` for its built-in include paths. Add a narrow allowlist
through `clangd_args`:

```lua
{
  "Aietes/esp32.nvim",
  opts = {
    clangd_args = {
      "--query-driver=/absolute/path/to/*-gcc,/absolute/path/to/*-g++",
    },
  },
}
```

Match the actual compiler paths found in `build.clang/compile_commands.json`.
The [clangd system-header guide](https://clangd.llvm.org/guides/system-headers#query-driver)
recommends this over hard-coding include directories.

`--query-driver` permits clangd to execute matching compiler binaries to inspect
their defaults. `--query-driver=**` is convenient, but it permits every compiler
path supplied by a compilation database. Use it only when you trust the
projects and generated databases you open.

## Custom idf.py launchers

The default command resolution is:

1. configured `idf_cmd`
2. an executable `idf.py` on `PATH`
3. `$IDF_PYTHON_ENV_PATH`'s Python running `$IDF_PATH/tools/idf.py`

The third form supports EIM shells where `idf.py` is a shell function. It
resolves to:

- `$IDF_PYTHON_ENV_PATH/bin/python $IDF_PATH/tools/idf.py` on macOS and Linux
- `%IDF_PYTHON_ENV_PATH%\Scripts\python.exe %IDF_PATH%\tools\idf.py` on Windows

For a custom environment manager or wrapper:

```lua
opts = {
  idf_cmd = { "mise", "exec", "--", "idf.py" },
}
```

An argv list is preferred when a launcher needs multiple arguments. A string is
also accepted for a single executable path.
