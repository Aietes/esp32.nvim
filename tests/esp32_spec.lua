local MiniTest = require("mini.test")
local expect = MiniTest.expect

local T = MiniTest.new_set()

local original_notify = vim.notify
local original_home = vim.env.HOME
local original_idf_path = vim.env.IDF_PATH
local original_fn = {}
local original_uv = {}
local notifications = {}

local function restore_command(name)
  pcall(vim.api.nvim_del_user_command, name)
end

local function reset_module()
  restore_command("ESPBuild")
  restore_command("ESPReconfigure")
  restore_command("ESPInfo")
  package.loaded["esp32"] = nil
  package.loaded["snacks"] = nil
end

local function load_module(snacks)
  package.loaded["snacks"] = snacks or {
    terminal = {
      open = function() end,
      toggle = function() end,
    },
    picker = {
      pick = function() end,
      util = {
        align = function(value)
          return value
        end,
      },
    },
  }

  return require("esp32")
end

local function set_scandir(entries_by_path)
  local iterators = {}

  vim.uv.fs_scandir = function(path)
    local entries = entries_by_path[path]
    if not entries then
      return nil
    end

    local handle = { path = path }
    iterators[handle] = vim.deepcopy(entries)
    return handle
  end

  vim.uv.fs_scandir_next = function(handle)
    local entries = iterators[handle]
    if not entries or #entries == 0 then
      return nil
    end

    return table.remove(entries, 1)
  end
end

local function reset_plugin_state(esp32)
  esp32.options = vim.deepcopy({
    build_dir = "build.clang",
    baudrate = 115200,
    clangd_args = {},
  })
  esp32.state = {
    last_port = nil,
  }
end

local function expect_truthy(value)
  expect.equality(not not value, true)
end

local function prepare_case()
  reset_module()
  notifications = {}
  vim.notify = function(message, level)
    table.insert(notifications, { message = message, level = level })
  end
  vim.env.HOME = original_home
  vim.env.IDF_PATH = nil
  vim.fn.executable = function()
    return 0
  end
  vim.fn.system = function()
    return ""
  end
  vim.fn.exepath = function(bin)
    return bin
  end
  vim.fn.filereadable = function()
    return 0
  end
  vim.fn.expand = function()
    return "/home/test"
  end
  set_scandir({})
end

T.hooks = {
  pre_once = function()
    original_fn.executable = vim.fn.executable
    original_fn.system = vim.fn.system
    original_fn.exepath = vim.fn.exepath
    original_fn.filereadable = vim.fn.filereadable
    original_fn.expand = vim.fn.expand
    original_uv.fs_scandir = vim.uv.fs_scandir
    original_uv.fs_scandir_next = vim.uv.fs_scandir_next
  end,
  post_once = function()
    reset_module()
    vim.notify = original_notify
    vim.env.HOME = original_home
    vim.env.IDF_PATH = original_idf_path
    vim.fn.executable = original_fn.executable
    vim.fn.system = original_fn.system
    vim.fn.exepath = original_fn.exepath
    vim.fn.filereadable = original_fn.filereadable
    vim.fn.expand = original_fn.expand
    vim.uv.fs_scandir = original_uv.fs_scandir
    vim.uv.fs_scandir_next = original_uv.fs_scandir_next
  end,
}

T["list_ports() matches supported device names and sorts results"] = function()
  prepare_case()
  set_scandir({
    ["/dev"] = {
      "ttyUSB1",
      "not-a-port",
      "cu.usbmodem101",
      "ttyACM0",
      "tty.wchusbserial123",
      "tty.usbserial-0001",
      "ttyUSB0",
    },
  })

  local esp32 = load_module()
  reset_plugin_state(esp32)
  local ports = esp32.list_ports()

  expect.equality(ports, {
    { port = "/dev/cu.usbmodem101" },
    { port = "/dev/tty.usbserial-0001" },
    { port = "/dev/tty.wchusbserial123" },
    { port = "/dev/ttyACM0" },
    { port = "/dev/ttyUSB0" },
    { port = "/dev/ttyUSB1" },
  })
end

T["find_esp_clangd() picks the newest installed Espressif clangd"] = function()
  prepare_case()
  local previous_home = vim.env.HOME
  vim.env.HOME = "/home/test"
  vim.fn.expand = function()
    return "/home/test"
  end

  set_scandir({
    ["/home/test/.espressif/tools/esp-clang"] = {
      "esp-20.1.0_20240101",
      "esp-20.1.1_20250829",
      "esp-19.1.2_20231212",
    },
  })

  vim.fn.executable = function(path)
    if path == "clangd" then
      return 0
    end
    return 1
  end

  local esp32 = load_module()
  reset_plugin_state(esp32)
  local clangd = esp32.find_esp_clangd()

  expect_truthy(clangd)
  expect.equality(clangd:match("^/home/test/.+"), "/home/test/.espressif/tools/esp-clang/esp-20.1.1_20250829/esp-clang/bin/clangd")
  expect.equality(clangd:match("esp%-20%.1%.1_20250829"), "esp-20.1.1_20250829")
  expect.equality(clangd:match("esp%-clang/bin/clangd$"), "esp-clang/bin/clangd")
  vim.env.HOME = previous_home
end

T["lsp_config() uses build_dir, root markers, and appends clangd_args"] = function()
  prepare_case()
  local esp32_path = "/opt/espressif/clangd"

  vim.fn.executable = function(path)
    if path == "clangd" then
      return 1
    end
    return path == esp32_path and 1 or 0
  end
  vim.fn.system = function()
    return "clangd version espressif"
  end
  vim.fn.exepath = function()
    return esp32_path
  end

  local esp32 = load_module()
  reset_plugin_state(esp32)
  esp32.setup({
    build_dir = "build.custom",
    clangd_args = { "--query-driver=**", "--enable-config" },
  })

  local config = esp32.lsp_config()

  expect.equality(config.cmd[1], esp32_path)
  expect_truthy(vim.tbl_contains(config.cmd, "--compile-commands-dir=build.custom"))
  expect_truthy(vim.tbl_contains(config.cmd, "--query-driver=**"))
  expect_truthy(vim.tbl_contains(config.cmd, "--enable-config"))
  expect.equality(config.root_markers, { "sdkconfig", "CMakeLists.txt" })
  expect_truthy(config.capabilities ~= nil)
  expect.equality(config.capabilities.general.positionEncodings, { "utf-16" })
end

T["lsp_config() falls back to system clangd and warns when esp clangd is missing"] = function()
  prepare_case()
  local esp32 = load_module()
  reset_plugin_state(esp32)

  local config = esp32.lsp_config()

  expect.equality(config.cmd[1], "clangd")
  expect.equality(#notifications, 1)
  expect.equality(
    notifications[1].message,
    "[ESP32] No esp-clangd found. Falling back to system clangd."
  )
  expect.equality(notifications[1].level, vim.log.levels.WARN)
end

T["setup() merges options and warns when esp clangd is missing"] = function()
  prepare_case()
  local esp32 = load_module()
  reset_plugin_state(esp32)

  esp32.setup({
    build_dir = "build.test",
    clangd_args = { "--query-driver=**" },
  })

  expect.equality(esp32.options.build_dir, "build.test")
  expect.equality(esp32.options.baudrate, 115200)
  expect.equality(esp32.options.clangd_args, { "--query-driver=**" })
  expect.equality(#notifications, 1)
  expect.equality(
    notifications[1].message,
    "[ESP32] ⚠️ ESP-specific clangd not found. LSP may not work properly."
  )
end

T["ensure_compile_commands() warns when compile_commands.json is missing"] = function()
  prepare_case()
  local esp32 = load_module()
  reset_plugin_state(esp32)
  esp32.options.build_dir = "build.missing"

  esp32.ensure_compile_commands()

  expect.equality(#notifications, 1)
  expect.equality(
    notifications[1].message,
    "[ESP32] ⚠️ Missing compile_commands.json in build.missing/compile_commands.json"
  )
  expect.equality(notifications[1].level, vim.log.levels.WARN)
end

T["info() reports project and environment status"] = function()
  prepare_case()
  local esp32_path = "/opt/espressif/clangd"

  vim.fn.executable = function(bin)
    if bin == "clangd" then
      return 1
    end
    if bin == "idf.py" or bin == "llvm-ar" then
      return 1
    end
    return 0
  end
  vim.fn.system = function()
    return "clangd version espressif"
  end
  vim.fn.exepath = function()
    return esp32_path
  end
  vim.fn.filereadable = function(path)
    if path == "build.clang/compile_commands.json" then
      return 1
    end
    return 0
  end
  vim.env.IDF_PATH = "/opt/esp-idf"

  local esp32 = load_module()
  reset_plugin_state(esp32)
  esp32.info()

  expect.equality(#notifications, 1)
  expect.equality(notifications[1].level, vim.log.levels.INFO)
  expect.equality(notifications[1].message, table.concat({
    "✓ Found esp-clangd",
    "✓ compile_commands.json exists",
    "✓ idf.py",
    "✓ llvm-ar",
    "IDF_PATH: /opt/esp-idf",
  }, "\n"))
end

T["module load registers user commands"] = function()
  prepare_case()
  local esp32 = load_module()
  reset_plugin_state(esp32)

  local commands = vim.api.nvim_get_commands({})
  expect.equality(type(esp32.build), "function")
  expect_truthy(commands.ESPBuild ~= nil)
  expect_truthy(commands.ESPReconfigure ~= nil)
  expect_truthy(commands.ESPInfo ~= nil)
end

T["command() reuses the last selected port and toggles monitor sessions"] = function()
  prepare_case()
  local calls = {}
  local esp32 = load_module({
    terminal = {
      open = function(cmd, opts)
        table.insert(calls, { method = "open", cmd = cmd, opts = opts })
      end,
      toggle = function(cmd, opts)
        table.insert(calls, { method = "toggle", cmd = cmd, opts = opts })
      end,
    },
    picker = {
      pick = function() end,
      util = {
        align = function(value)
          return value
        end,
      },
    },
  })

  reset_plugin_state(esp32)
  esp32.state.last_port = "/dev/ttyUSB9"
  esp32.command("monitor")
  esp32.command("flash")

  expect.equality(calls[1].method, "toggle")
  expect.equality(calls[1].cmd, "idf.py -B build.clang -p /dev/ttyUSB9 monitor")
  expect.equality(calls[2].method, "open")
  expect.equality(calls[2].cmd, "idf.py -B build.clang -p /dev/ttyUSB9 flash")
end

T["pick() stores the selected port and runs the command with it"] = function()
  prepare_case()
  local picker_spec
  local calls = {}
  local esp32 = load_module({
    terminal = {
      open = function(cmd, opts)
        table.insert(calls, { method = "open", cmd = cmd, opts = opts })
      end,
      toggle = function(cmd, opts)
        table.insert(calls, { method = "toggle", cmd = cmd, opts = opts })
      end,
    },
    picker = {
      pick = function(spec)
        picker_spec = spec
      end,
      util = {
        align = function(value)
          return value
        end,
      },
    },
  })

  reset_plugin_state(esp32)
  esp32.pick("monitor")
  picker_spec.confirm({ close = function() end }, { port = "/dev/ttyACM0" })

  expect.equality(esp32.state.last_port, "/dev/ttyACM0")
  expect.equality(calls[1].method, "toggle")
  expect.equality(calls[1].cmd, "idf.py -B build.clang -p /dev/ttyACM0 monitor")
end

T["lazy.lua packaged spec exposes expected defaults"] = function()
  prepare_case()
  local spec = dofile("lazy.lua")

  expect.equality(spec.main, "esp32")
  expect_truthy(vim.tbl_contains(spec.dependencies, "folke/snacks.nvim"))
  expect.equality(spec.opts.build_dir, "build.clang")
  expect.equality(spec.keys[1].group, "ESP32")
  expect.equality(spec.specs[1][1], "folke/which-key.nvim")
  expect.equality(spec.specs[1].optional, true)
end

return T
