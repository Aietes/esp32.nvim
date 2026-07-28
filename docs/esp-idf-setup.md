# ESP-IDF setup

ESP32.nvim uses the tools and environment of an existing ESP-IDF installation.
It does not install ESP-IDF or select an ESP-IDF version for you.

## Recommended: ESP-IDF Installation Manager

[ESP-IDF Installation Manager (EIM)](https://docs.espressif.com/projects/idf-im-ui/en/latest/)
is Espressif's recommended installer for new setups. Its GUI supports a simple
installation and an expert flow with optional tool selection. Select
`esp-clang` when the tool list is shown.

For CLI installation on macOS or Linux, install EIM as described in the
[official CLI guide](https://docs.espressif.com/projects/idf-im-ui/en/latest/cli_installation.html).
For example, Homebrew users can install the manager with:

```bash
brew tap espressif/eim
brew install eim
```

Then install the ESP-IDF version required by your project and include the clang
toolchain:

```bash
eim install -i vX.Y.Z --idf-tools=esp-clang
```

Use a real release identifier in place of `vX.Y.Z`. Keeping the version
project-specific avoids silently moving a working project to a newer ESP-IDF.

`esp-clang` is the installable tool name; the CMake setting used later is
`IDF_TOOLCHAIN=clang`. `IDF_TOOLCHAIN=esp-clang` is not the same setting.

On Windows, run EIM from 64-bit PowerShell or use the GUI. PowerShell is the
supported EIM shell.

## Activate before launching Neovim

EIM writes activation scripts for each installed version. Source the script
that matches the selected version and shell:

```bash
source ~/.espressif/tools/activate_idf_vX.Y.Z.sh
nvim /path/to/project
```

For fish, source the generated `.fish` script instead. On Windows, launch the
generated IDF PowerShell shortcut or source its generated profile:

```powershell
. C:\Espressif\tools\Microsoft.vX.Y.Z.PowerShell_profile.ps1
nvim C:\path\to\project
```

Replace `vX.Y.Z` with the installed version name. The exact file name reflects
the EIM version name and install location. The
[EIM installation guide](https://docs.espressif.com/projects/idf-im-ui/en/latest/cli_installation.html)
documents the generated activation scripts.

Activation matters even when EIM exposes `idf.py` as a shell function. Neovim
cannot call a parent shell's functions directly, but ESP32.nvim can resolve the
underlying Python environment when `IDF_PATH` and `IDF_PYTHON_ENV_PATH` are
present.

Verify the environment before starting Neovim:

```bash
idf.py --version
clangd --version
```

The clangd version should identify the
[Espressif LLVM project](https://github.com/espressif/llvm-project), not only
the system LLVM installation.

## Add esp-clang to an existing installation

From an activated ESP-IDF shell:

```bash
idf_tools.py install esp-clang
```

Source the activation script again afterward so its binaries are added to the
environment. `esp-clang` is an optional ESP-IDF tool; the
[official tools reference](https://docs.espressif.com/projects/esp-idf/en/latest/esp32/api-guides/tools/idf-tools.html#esp-clang)
lists the versions supplied for each host platform.

## Manual ESP-IDF installation

The classic Git checkout remains supported:

```bash
mkdir -p ~/esp
cd ~/esp
git clone --recursive https://github.com/espressif/esp-idf.git
cd esp-idf
./install.sh esp32
source export.sh
idf_tools.py install esp-clang
source export.sh
```

Use a concrete target such as `./install.sh esp32` or `./install.sh esp32c3`.
Follow the
[ESP-IDF Get Started guide](https://docs.espressif.com/projects/esp-idf/en/stable/esp32/get-started/)
for platform prerequisites and supported install options.

## The clang build directory

ESP32.nvim keeps its compilation database and build output in `build.clang` by
default. From Neovim, generate it with:

```vim
:ESPReconfigure
```

The equivalent shell command is:

```bash
idf.py -B build.clang -D IDF_TOOLCHAIN=clang reconfigure
```

Plugin build, flash, clean, and menuconfig actions consistently pass the same
`-B` directory. A separate GCC `build/` directory can coexist with it, but
ESP32.nvim's clangd configuration does not consume that GCC database.

When running ESP-IDF manually, pass the same directory explicitly:

```bash
idf.py -B build.clang build
idf.py -B build.clang flash
```

If you choose another directory, set `build_dir` in the plugin options and use
that same directory for any manual `idf.py -B ...` commands.

## Project compatibility

Espressif documents the
[clang-based toolchain](https://docs.espressif.com/projects/esp-idf/en/latest/esp32/api-guides/tools/idf-clang-tidy.html)
as still under development. ESP-IDF examples and third-party components can
therefore differ in clang support even when they build successfully with GCC.

This plugin currently targets native ESP-IDF projects. Arduino as an ESP-IDF
component is not part of its tested support matrix. A compiler failure in an
otherwise healthy environment may be a project or upstream clang compatibility
issue rather than an LSP configuration failure.

Use these checks to separate the two:

1. Run `:ESPInfo` and confirm the environment, clangd, and database are healthy.
2. Run `idf.py -B build.clang -D IDF_TOOLCHAIN=clang reconfigure` in the same
   activated terminal.
3. If that command fails before Neovim is involved, reduce the failure to the
   affected component and check the
   [ESP-IDF issue tracker](https://github.com/espressif/esp-idf/issues).
