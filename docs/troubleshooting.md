# Troubleshooting

Start with:

```vim
:ESPInfo
:checkhealth vim.lsp
```

`ESPInfo` checks the project root, Espressif clangd, compilation database,
`idf.py`, `llvm-ar`, and `IDF_PATH`. Neovim's LSP health report shows whether
clangd is enabled, attached, and which root and command it uses.

## `IDF_PATH` is not set or `idf.py` is missing

Activate ESP-IDF before launching Neovim. Activating it in another terminal
after Neovim has started does not update Neovim's environment.

```bash
source ~/.espressif/tools/activate_idf_vX.Y.Z.sh
nvim /path/to/project
```

EIM may define `idf.py` as a shell function. That is fine if activation also
sets `IDF_PATH` and `IDF_PYTHON_ENV_PATH`; ESP32.nvim calls the underlying
Python script directly. See [custom idf.py launchers](lsp.md#custom-idfpy-launchers)
when neither form is available.

## ESP-specific clangd is missing

From an activated ESP-IDF environment:

```bash
idf_tools.py install esp-clang
```

Source the activation script again, restart Neovim, and run `:ESPInfo`.
`clangd --version` should identify an Espressif build.

Mason's clangd does not replace the required ESP-IDF toolchain. The plugin will
ignore a non-Espressif `clangd` on `PATH` and search the standard ESP-IDF tool
directories, but `:checkhealth vim.lsp` should still show the Espressif binary
in the active client's command.

## clangd is not attached

Check all of the following:

1. Neovim is version 0.11 or newer.
2. The ESP32.nvim LSP config is registered, not only the plugin itself.
3. `vim.lsp.enable("clangd")` is called in a plain Neovim setup.
4. The current buffer has a C or C++ filetype.
5. A project marker (`sdkconfig` or `CMakeLists.txt`) exists above the file.

In `:checkhealth vim.lsp`, an active client command containing only
`{ "clangd" }` usually means another config won. The command should resolve to
Espressif's clangd and include `--compile-commands-dir`.

If only the first opened file behaves incorrectly, update ESP32.nvim and
Neovim, run `:ESPReconfigure`, and reproduce once with a fresh LSP log. Include
`:ESPInfo`, `:checkhealth vim.lsp`, and the relevant log tail in a bug report.

## `compile_commands.json` is missing

Run:

```vim
:ESPReconfigure
```

This creates `<build_dir>/compile_commands.json` and restarts clangd. Creating
the directory after clangd starts is not enough because clangd may already have
discarded a missing `--compile-commands-dir`.

## The database was generated for GCC

A normal `idf.py build` commonly writes a GCC database under `build/`.
ESP32.nvim uses a separate clang database so GCC-only flags do not produce
unknown-argument and missing-header diagnostics:

```vim
:ESPReconfigure
```

Do not copy or symlink a GCC database into `build.clang`. Keep a separate GCC
build directory if another workflow needs it.

## Headers such as `driver/gpio.h`, `stdio.h`, or C++ headers are missing

First confirm that `:ESPInfo` reports:

- Espressif's clangd
- a clang-generated database in the configured build directory
- the expected project root

Then inspect the first command in `build.clang/compile_commands.json`. For a
cross-compiler whose built-in headers are not discovered, configure a narrow
[`--query-driver`](lsp.md#query-driver) allowlist matching that compiler.
Prefer this to manually copying include paths into `.clangd`; generated include
paths and their ordering can change with the target and ESP-IDF version.

## Reconfigure fails before clangd starts

Run the equivalent command in the same activated terminal:

```bash
idf.py -B build.clang -D IDF_TOOLCHAIN=clang reconfigure
```

If this also fails, the problem is in the ESP-IDF environment or the project's
clang compatibility rather than Neovim. Confirm `esp-clang` is installed and
see [project compatibility](esp-idf-setup.md#project-compatibility).

## Formatting ignores `.clang-format`

ESP32.nvim passes `--fallback-style=llvm`; clangd uses that only when it cannot
find a `.clang-format` file. Confirm:

- `.clang-format` is in the source file's directory or one of its parents
- the formatter selected by your Neovim setup is clangd/clang-format
- the active clangd root is the expected project

The plugin does not otherwise configure formatting.

## No serial ports appear

Automatic serial-port discovery currently supports macOS and Linux device
names. On Windows, call the API with the COM port explicitly or map it in your
config:

```lua
require("esp32").command("flash", "COM3")
require("esp32").command("monitor", "COM3")
```

Change `COM3` to the port shown by Windows. Build, reconfigure, project info,
and LSP features do not depend on serial-port discovery.

## Changing targets removed project configuration

This is the documented behavior of
[`idf.py set-target`](https://docs.espressif.com/projects/esp-idf/en/stable/esp32/api-guides/tools/idf-py.html#select-the-target-chip-set-target).
`:ESPSetTarget` clears the configured build directory, moves the previous
`sdkconfig` to `sdkconfig.old`, and generates a new `sdkconfig` for the target.

Keep durable project defaults in `sdkconfig.defaults` and review
`sdkconfig.old` when migrating target-specific settings.

## Reporting a problem

Include:

- operating system
- `nvim --version`
- ESP-IDF version and installation method
- `:ESPInfo`
- `:checkhealth vim.lsp`
- the smallest relevant clangd or terminal error

Avoid posting the entire LSP log when a short reproduction and the first error
show the failure.
