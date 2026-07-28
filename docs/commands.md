# Commands and Lua API

The [README](../README.md#commands-and-keymaps) lists the user commands and
default lazy.nvim keymaps. The same operations can be called from custom
keymaps and configuration through the Lua API.

## Select and remember a serial port

```lua
require("esp32").pick("monitor")
require("esp32").pick("flash")
```

`pick(command)` opens the serial-port picker, remembers the selected port for
the current Neovim session, and runs the given ESP-IDF command with that port.
Automatic port discovery currently supports macOS and Linux.

## Run a command directly

```lua
require("esp32").command("monitor")
require("esp32").command("flash", "COM3")
```

`command(command, port?)` runs an ESP-IDF command in a floating terminal. When
`port` is omitted, it reuses the last port selected with `pick()`, if one is
available. Passing the port explicitly is useful on Windows, where automatic
port discovery is not currently supported.

Both functions use the configured project root and `build_dir`.

## Terminal behavior

Commands run in floating terminals. Short-lived commands close when they
finish, while interactive commands such as `menuconfig` remain open while the
process is running.

- Press `Ctrl + ]` to stop the process and close its terminal.
- Press `q` to hide a monitor terminal without stopping it. Running the same
  monitor command again reattaches to that terminal.
