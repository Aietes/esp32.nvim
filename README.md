# esp32.nvim

**ESP32 development helper for Neovim.**  
Designed for a smooth ESP-IDF workflow inside Neovim and [LazyVim](https://github.com/LazyVim/LazyVim).  
Uses [snacks.nvim](https://github.com/folke/snacks.nvim) for terminal and picker UIs.

## ✨ Features

- 🧠 Automatically detects ESP-IDF-specific `clangd`
- 🛠 Configures `build_dir` (`build.clang`) for IDF builds
- 🖥️ Launch `idf.py monitor` and `idf.py flash` in floating terminals
- 🔎 Pick available USB serial ports dynamically on macOS and Linux
- 📋 Check project setup with `:ESPInfo`
- 🛠 Quickly run reconfigure with `:ESPReconfigure`
- ⚙️ Provides LSP configuration for ESP-IDF projects
- 🔧 Supports extra `clangd` arguments for advanced toolchain setups

## 🚀 Requirements

- [ESP-IDF](https://github.com/espressif/esp-idf) installed and initialized
- ESP-specific `clangd` is installed via `idf_tools.py install esp-clang`
- ESP-specific `clangd` is configured via `idf.py -B build.clang -D IDF_TOOLCHAIN=clang reconfigure` (can be done via command `:ESPReconfigure`)
- [snacks.nvim](https://github.com/folke/snacks.nvim) (automatically installed via LazyVim dependencies)

## 📦 Installation (with Lazy.nvim)

Install via Lazy.nvim or any other plugin manager. Via Lazy.nvim:

```lua
{
  "Aietes/esp32.nvim",
}
```

When installed through Lazy.nvim, the plugin ships a packaged `lazy.lua` spec. That means Lazy.nvim users automatically get:

- the `snacks.nvim` dependency
- the default `build_dir = "build.clang"` option
- the default ESP32 keymaps

The packaged default keymaps are:

- `<leader>Rb`: build
- `<leader>RM`: pick and monitor
- `<leader>Rm`: monitor
- `<leader>RF`: pick and flash
- `<leader>Rf`: flash
- `<leader>Rc`: menuconfig
- `<leader>RC`: clean
- `<leader>Rr`: reconfigure
- `<leader>Ri`: project info

ESP32 commands open in a floating terminal, which automatically closes when the command is done. For long-running commands like `monitor` and `menuconfig`, the terminal stays open until you close it:

- Press `q` to close the terminal window (`idf.py monitor` keeps running when closed with `q` and you can reattach to it later)
- Press `Ctrl + ]` to stop the running process and close the terminal window

## 🔧 Configuration

```lua
opts = {
  build_dir = "build.clang", -- directory for CMake builds (must match your clangd compile_commands.json)
  clangd_args = {}, -- optional extra clangd arguments
}
```

To customize the packaged defaults, override them in your own spec:

```lua
{
  "Aietes/esp32.nvim",
  opts = {
    build_dir = "build.custom",
    clangd_args = {
      "--query-driver=**",
    },
  },
  keys = {
    { "<leader>em", function() require("esp32").pick("monitor") end, desc = "ESP32: Pick & Monitor" },
  },
}
```

> ⚠️ **Attention:** To get code completion and diagnostics working correctly, the LSP must be configured properly. This plugin provides the required LSP configuration through `require("esp32").lsp_config()`. You need to hook that into your Neovim LSP setup in one of the two ways below.

### LazyVim

If you use LazyVim, add this to your `nvim-lspconfig` spec, LazyVim will take care of the rest:

```lua
{
  "neovim/nvim-lspconfig",
  opts = function(_, opts)
    opts.servers = opts.servers or {}
    opts.servers.clangd = require("esp32").lsp_config()
    return opts
  end,
}
```

### Plain Neovim / Other distros

If you manage your LSP setup manually, include the LSP config from this plugin directly where it fits in your setup:

```lua
vim.lsp.config("clangd", require("esp32").lsp_config())
vim.lsp.enable("clangd")
```

### LSP

This plugin exposes the required LSP setup through:

```lua
require("esp32").lsp_config()
```

That configuration:

- points the LSP at your configured `build_dir`
- prefers `sdkconfig` and `CMakeLists.txt` as root markers so nested ESP-IDF projects do not attach to a parent git repository by accident

If you need additional `clangd` flags for your environment, you can pass them through `clangd_args`:

```lua
opts = {
  build_dir = "build.clang",
  clangd_args = {
    "--query-driver=**",
  },
}
```

## 🛠 Commands

| Command           | Description                                                                                 |
| :---------------- | :------------------------------------------------------------------------------------------ |
| `:ESPReconfigure` | Runs `idf.py -B build.clang -D IDF_TOOLCHAIN=clang reconfigure`                             |
| `:ESPInfo`        | Shows ESP32 project setup info                                                              |
| `:ESPBuild`       | Runs a build of the project                                                                 |
| `pick`            | Pick a serial port and run a command on it. Remembers the selected port for later commands. |
| `command`         | Run a command, reusing the last selected port when available.                               |

The plugin defines the user commands above automatically. When installed through Lazy.nvim, the packaged `lazy.lua` also provides the default keymaps listed above.

## 📋 Notes

- This plugin does **not** install ESP-IDF automatically, see the recommended setup [below](#️-recommended-esp-idf-setup)
- You must either:
  - Use a Nix flake (recommended, see [below](#️-nix-flake-setup))
  - Or manually source `~/esp/esp-idf/export.sh` before launching Neovim

---

## ⚙️ Recommended ESP-IDF Setup

Clone and install ESP-IDF:

```bash
mkdir -p ~/esp
cd ~/esp
git clone --recursive https://github.com/espressif/esp-idf.git
cd esp-idf
./install.sh esp32c3
```

Install the Espressif-specific `clangd`:

```bash
idf_tools.py install esp-clang
```

Create your build directory using clang:

```bash
idf.py -B build.clang -D IDF_TOOLCHAIN=clang reconfigure
```

From now on, **always** build and flash using:

```bash
idf.py -B build.clang build
idf.py -B build.clang flash
```

## ❄️ Nix Flake Setup

Using [nix](https://github.com/DeterminateSystems/nix-installer) is highly recommended. Use this `flake.nix` to create a reproducible ESP32 development environment:

```nix
{
  description = "Development ESP32 C3 with ESP-IDF";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let pkgs = nixpkgs.legacyPackages.${system};
      in {
        devShells.default = pkgs.mkShell {
          buildInputs = with pkgs; [ cmake ninja dfu-util python3 ccache ];
          shellHook = ''
            . $HOME/esp/esp-idf/export.sh
          '';
        };
      });
}
```

Then use [direnv](https://direnv.net/) with a `.envrc`:

```bash
touch .envrc
echo 'use flake' > .envrc
direnv allow
```

This will automatically load the environment when you enter the directory.
✅ Now Neovim and the plugin will inherit the full ESP-IDF toolchain environment.

## 📜 License

MIT License © 2026 [Aietes](https://github.com/Aietes)
