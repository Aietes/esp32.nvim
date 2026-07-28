[![Version](https://img.shields.io/github/v/tag/Aietes/esp32.nvim?style=for-the-badge&label=version&sort=semver)](https://github.com/Aietes/esp32.nvim/tags)
[![Tests](https://img.shields.io/github/actions/workflow/status/Aietes/esp32.nvim/tests.yml?branch=main&style=for-the-badge&label=tests)](https://github.com/Aietes/esp32.nvim/actions/workflows/tests.yml)
[![Last Commit](https://img.shields.io/github/last-commit/Aietes/esp32.nvim?style=for-the-badge)](https://github.com/Aietes/esp32.nvim/commits/main)
[![Neovim](https://img.shields.io/badge/Neovim-0.11%2B-57A143?style=for-the-badge&logo=neovim&logoColor=white)](https://neovim.io/)
[![License](https://img.shields.io/github/license/Aietes/esp32.nvim?style=for-the-badge)](https://github.com/Aietes/esp32.nvim/blob/main/LICENSE)

# ESP32.nvim

ESP32.nvim provides an ESP-IDF workflow for Neovim and
[LazyVim](https://github.com/LazyVim/LazyVim): build, flash, monitor, configure,
select targets, and use Espressif's clangd without leaving the editor.

## ✨ Features

- 🛠️ Run ESP-IDF build, flash, monitor, menuconfig, clean, and reconfigure tasks
- 🔌 Select serial ports on macOS and Linux and reuse the last selection
- 🎯 Select any target supported by the active ESP-IDF installation
- 🧠 Detect Espressif's `clangd` and configure it for the project
- 🔎 Detect missing or GCC-generated compilation databases
- 🔄 Restart project clangd clients after reconfigure and target changes
- 📋 Inspect the active environment, clangd command, and build database with `:ESPInfo`

## Requirements

- Neovim 0.11 or newer
- An activated [ESP-IDF](https://github.com/espressif/esp-idf) environment
- Espressif's `esp-clang` tool (optional in ESP-IDF, required for this LSP workflow)
- [snacks.nvim](https://github.com/folke/snacks.nvim) (installed automatically by lazy.nvim)

[ESP-IDF Installation Manager](https://docs.espressif.com/projects/idf-im-ui/en/latest/)
is the recommended upstream installer. See
[ESP-IDF setup](docs/esp-idf-setup.md) for EIM, manual installation, activation,
and clang toolchain details.

> ESP32.nvim is an ESP-IDF clang workflow. Espressif still describes parts of
> the clang toolchain as under development, so some projects or components that
> build with GCC may not yet build with clang. See
> [project compatibility](docs/esp-idf-setup.md#project-compatibility).

## Quick start

### 1. Install the plugin

#### lazy.nvim

```lua
{
  "Aietes/esp32.nvim",
}
```

With lazy.nvim's standard package support, the repository's `lazy.lua` spec:

- installs the required `snacks.nvim` dependency
- calls `require("esp32").setup()` with `build_dir = "build.clang"`
- provides the [default keymaps](#commands-and-keymaps)
- adds the ESP32 which-key group when which-key.nvim is already installed

It does not configure clangd; complete step 2 below.

For native `vim.pack` and other plugin managers, see
[Installation methods](docs/installation.md).

### 2. Connect the LSP

> **Attention:** Installing ESP32.nvim does not configure clangd automatically.
> Complete the LSP setup below to enable completion, diagnostics, hover, and
> go-to-definition.

Choose the setup that matches your configuration.

For LazyVim:

```lua
{
  "neovim/nvim-lspconfig",
  opts = function(_, opts)
    opts.servers = opts.servers or {}
    opts.servers.clangd = require("esp32").lsp_config()
  end,
}
```

For plain Neovim 0.11+:

```lua
vim.lsp.config("clangd", require("esp32").lsp_config())
vim.lsp.enable("clangd")
```

If you do not use lazy.nvim, install and configure `snacks.nvim`, then call
`require("esp32").setup()` before enabling the LSP.

See [LSP configuration](docs/lsp.md) for clangd detection, nested project roots,
non-ESP C/C++ projects, and advanced toolchains.

### 3. Start in an activated environment

Activate the intended ESP-IDF version before launching Neovim:

```bash
source ~/.espressif/tools/activate_idf_vX.Y.Z.sh
cd /path/to/your/project
nvim
```

Replace `vX.Y.Z` with the installed version name. Use the activation script
generated for your shell. Windows users should launch or source the
EIM-generated PowerShell environment.

Alternatively, a project-local [Nix/direnv setup](docs/nix-direnv.md) can
activate an existing ESP-IDF installation automatically whenever you enter the
project directory, so Neovim inherits the environment without a manual
`source` step.

### 4. Generate the clang database

Open a C or C++ file and run:

```vim
:ESPReconfigure
```

This creates the configured build directory (default: `build.clang`) with
`IDF_TOOLCHAIN=clang`, then restarts clangd so it reads the new database.

### 5. Verify the setup

```vim
:ESPInfo
```

It should report an Espressif clangd, a clang-generated
`compile_commands.json`, a working `idf.py`, and a populated `IDF_PATH`.
If not, follow the [troubleshooting guide](docs/troubleshooting.md).

## Configuration

Override the packaged defaults in your plugin spec:

```lua
{
  "Aietes/esp32.nvim",
  opts = {
    build_dir = "build.clang",
    clangd_args = {},
    idf_cmd = nil,
  },
}
```

| Option | Default | Purpose |
| --- | --- | --- |
| `build_dir` | `"build.clang"` | Project-relative ESP-IDF build directory and clangd compilation database |
| `clangd_args` | `{}` | Extra arguments appended to the generated clangd command |
| `idf_cmd` | `nil` | `idf.py` executable or argv override, such as `{ "mise", "exec", "--", "idf.py" }` |

For cross-toolchain include problems, read
[Query-driver](docs/lsp.md#query-driver) before adding a broad
`--query-driver=**` rule.

## Commands and keymaps

The user commands are always available:

| Command | Action |
| --- | --- |
| `:ESPBuild` | Build with the configured build directory |
| `:ESPReconfigure` | Regenerate the clang build database and restart clangd |
| `:ESPInfo` | Show project, toolchain, and LSP diagnostics |
| `:ESPSetTarget` | Pick a supported chip target and regenerate the project |

The packaged lazy.nvim spec adds:

| Key | Action |
| --- | --- |
| `<leader>Rb` | Build |
| `<leader>RM` / `<leader>Rm` | Pick a port and monitor / monitor with the remembered port |
| `<leader>RF` / `<leader>Rf` | Pick a port and flash / flash with the remembered port |
| `<leader>Rc` | Open menuconfig |
| `<leader>RC` | Clean |
| `<leader>Rr` | Reconfigure |
| `<leader>Ri` | Show project info |
| `<leader>Rt` | Set target |

Override a key through your own lazy.nvim spec:

```lua
{
  "Aietes/esp32.nvim",
  keys = {
    {
      "<leader>em",
      function()
        require("esp32").pick("monitor")
      end,
      desc = "ESP32: Pick & Monitor",
    },
  },
}
```

Commands open in a floating terminal. Press `Ctrl + ]` to stop the process and
close it. Pressing `q` hides a monitor terminal without stopping it, so the same
command can reattach later.

> `:ESPSetTarget` follows `idf.py set-target`: it clears the build directory,
> regenerates `sdkconfig`, and saves the previous configuration as
> `sdkconfig.old`.

## Documentation

- [ESP-IDF setup](docs/esp-idf-setup.md) — installation, activation, esp-clang, and project compatibility
- [Installation methods](docs/installation.md) — lazy.nvim, native vim.pack, and other managers
- [LSP configuration](docs/lsp.md) — integration, detection, roots, compilation databases, and query-driver
- [Commands and Lua API](docs/commands.md) — custom mappings, remembered ports, and terminal behavior
- [Troubleshooting](docs/troubleshooting.md) — symptom-based checks for the most common setup failures
- [Nix and direnv](docs/nix-direnv.md) — project-local activation of an existing ESP-IDF installation

## License

MIT License © 2026 [Aietes](https://github.com/Aietes)
