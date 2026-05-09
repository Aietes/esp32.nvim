[![Version](https://img.shields.io/github/v/tag/Aietes/esp32.nvim?style=for-the-badge&label=version&sort=semver)](https://github.com/Aietes/esp32.nvim/tags)
[![Tests](https://img.shields.io/github/actions/workflow/status/Aietes/esp32.nvim/tests.yml?branch=main&style=for-the-badge&label=tests)](https://github.com/Aietes/esp32.nvim/actions/workflows/tests.yml)
[![Last Commit](https://img.shields.io/github/last-commit/Aietes/esp32.nvim?style=for-the-badge)](https://github.com/Aietes/esp32.nvim/commits/main)
[![Neovim](https://img.shields.io/badge/Neovim-0.10%2B-57A143?style=for-the-badge&logo=neovim&logoColor=white)](https://neovim.io/)
[![License](https://img.shields.io/github/license/Aietes/esp32.nvim?style=for-the-badge)](https://github.com/Aietes/esp32.nvim/blob/main/LICENSE)

**ESP32.nvim** makes working with ESP-IDF projects in Neovim a breeze.

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

- [ESP-IDF](https://github.com/espressif/esp-idf) installed and initialized. The recommended upstream setup is now [ESP-IDF Installation Manager](https://docs.espressif.com/projects/idf-im-ui/en/latest/).
- ESP-specific `clangd` is installed. With ESP-IDF Installation Manager, include `esp-clang` in the selected tools, or run `idf_tools.py install esp-clang` from an activated ESP-IDF shell.
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
  idf_cmd = nil, -- optional idf.py command override
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

### ESP-IDF Command Resolution

By default, ESP32.nvim runs `idf.py` from the active ESP-IDF environment. If `idf.py` is not an executable on `PATH`, the plugin can also use an activated EIM environment by running:

```bash
$IDF_PYTHON_ENV_PATH/bin/python $IDF_PATH/tools/idf.py
```

This handles EIM shells where `idf.py` is provided as a shell function instead of a standalone executable. If your setup needs a custom wrapper, configure `idf_cmd`:

```lua
opts = {
  idf_cmd = "/path/to/idf.py-wrapper",
}
```

## 🛠 Commands

| Command           | Description                                                                                 |
| :---------------- | :------------------------------------------------------------------------------------------ |
| `:ESPReconfigure` | Runs ESP-IDF reconfigure with `-B build.clang -D IDF_TOOLCHAIN=clang`                       |
| `:ESPInfo`        | Shows ESP32 project setup info                                                              |
| `:ESPBuild`       | Runs a build of the project                                                                 |
| `pick`            | Pick a serial port and run a command on it. Remembers the selected port for later commands. |
| `command`         | Run a command, reusing the last selected port when available.                               |

The plugin defines the user commands above automatically. When installed through Lazy.nvim, the packaged `lazy.lua` also provides the default keymaps listed above.

## 📋 Notes

- This plugin does **not** install ESP-IDF automatically, see the recommended setup [below](#️-recommended-esp-idf-setup)
- You must either:
  - Source an ESP-IDF environment before launching Neovim
  - Or use a project-local Nix/direnv shell to source that environment for you

---

## ⚙️ Recommended ESP-IDF Setup

Espressif now recommends ESP-IDF Installation Manager (EIM) for new setups. On macOS:

```bash
brew tap espressif/eim
brew install eim
eim install -i v5.5 --idf-tools=esp-clang
```

On Linux, use the package source recommended by Espressif for your distribution, or install EIM with Homebrew:

```bash
brew tap espressif/eim
brew install eim
eim install -i v5.5 --idf-tools=esp-clang
```

After installation, activate the generated ESP-IDF environment before launching Neovim. EIM creates a per-version activation script under `~/.espressif/tools`:

```bash
source ~/.espressif/tools/activate_idf_v5.5.sh
```

Then make sure the Espressif-specific `clangd` is installed. If you did not select `esp-clang` during the EIM install, run:

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

### Manual ESP-IDF Clone

If you prefer the classic manual ESP-IDF clone, that still works:

```bash
mkdir -p ~/esp
cd ~/esp
git clone --recursive https://github.com/espressif/esp-idf.git
cd esp-idf
./install.sh esp32c3
source ~/esp/esp-idf/export.sh
```

Then follow the same `esp-clang` and `build.clang` steps above.

## ❄️ Optional Nix/Direnv Activation

EIM is the recommended way to install and manage ESP-IDF. If your project already uses [nix](https://github.com/DeterminateSystems/nix-installer) and [direnv](https://direnv.net/), you can use a flake to activate an existing EIM or manual ESP-IDF install when you enter the project.

This does **not** install ESP-IDF with Nix; it only makes Neovim inherit the same ESP-IDF environment every time the project shell loads.

```nix
{
  description = "ESP-IDF activation shell";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
        idfVersion = "v5.5";
        eimActivation = "$HOME/.espressif/tools/activate_idf_${idfVersion}.sh";
        manualActivation = "$HOME/esp/esp-idf/export.sh";
      in {
        devShells.default = pkgs.mkShell {
          buildInputs = with pkgs; [ cmake ninja dfu-util python3 ccache ];
          shellHook = ''
            if [ -f "${eimActivation}" ]; then
              . "${eimActivation}"
            elif [ -f "${manualActivation}" ]; then
              . "${manualActivation}"
            else
              echo "ESP-IDF activation script not found." >&2
              echo "Run: eim install -i ${idfVersion} --idf-tools=esp-clang" >&2
            fi
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

This will automatically activate the existing ESP-IDF environment when you enter the directory.
✅ Now Neovim and the plugin will inherit the full ESP-IDF toolchain environment.

## 📜 License

MIT License © 2026 [Aietes](https://github.com/Aietes)
