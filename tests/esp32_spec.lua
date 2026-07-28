local MiniTest = require("mini.test")
local expect = MiniTest.expect

local T = MiniTest.new_set()

local original_notify = vim.notify
local original_home = vim.env.HOME
local original_idf_path = vim.env.IDF_PATH
local original_idf_python_env_path = vim.env.IDF_PYTHON_ENV_PATH
local original_idf_tools_path = vim.env.IDF_TOOLS_PATH
local original_fn = {}
local original_uv = {}
local original_system = vim.system
local original_schedule = vim.schedule
local notifications = {}
local system_calls = {}

--- Stub vim.system() with a fixed result for the spawned command
local function set_system_result(result)
  vim.system = function(cmd, opts, on_exit)
    table.insert(system_calls, { cmd = cmd, opts = opts })
    on_exit(result)
    return { wait = function() return result end }
  end
end

--- Run fn with vim.schedule() applied inline.
---
--- The async target lookup defers its callback off the libuv thread, and
--- driving the real event loop from inside a case stops MiniTest from running
--- the remaining ones, so collapse the deferral instead of waiting on it.
local function run_scheduled(fn)
  vim.schedule = function(callback)
    callback()
  end

  local ok, err = pcall(fn)
  vim.schedule = original_schedule

  if not ok then
    error(err)
  end
end

local function restore_command(name)
  pcall(vim.api.nvim_del_user_command, name)
end

local function reset_module()
  restore_command("ESPBuild")
  restore_command("ESPReconfigure")
  restore_command("ESPInfo")
  restore_command("ESPSetTarget")
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
    idf_cmd = nil,
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
  system_calls = {}
  vim.notify = function(message, level)
    table.insert(notifications, { message = message, level = level })
  end
  vim.env.HOME = original_home
  vim.env.IDF_PATH = nil
  vim.env.IDF_PYTHON_ENV_PATH = nil
  vim.env.IDF_TOOLS_PATH = nil
  vim.fn.has = original_fn.has
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
  set_system_result({ code = 0, stdout = "", stderr = "" })
  vim.fn.readfile = function()
    return {}
  end
  set_scandir({})
end

--- Present a compile_commands.json whose first entry uses the given compiler
local function set_compile_commands(compiler)
  vim.fn.filereadable = function(path)
    return path:match("compile_commands%.json$") and 1 or 0
  end
  vim.fn.readfile = function()
    return {
      "[",
      "{",
      '  "directory": "/project/build.clang",',
      '  "command": "' .. compiler .. ' -DFOO -Iinclude -c main.c",',
      '  "file": "/project/main/main.c"',
      "}",
      "]",
    }
  end
end

T.hooks = {
  pre_once = function()
    original_fn.has = vim.fn.has
    original_fn.executable = vim.fn.executable
    original_fn.system = vim.fn.system
    original_fn.exepath = vim.fn.exepath
    original_fn.filereadable = vim.fn.filereadable
    original_fn.expand = vim.fn.expand
    original_fn.readfile = vim.fn.readfile
    original_uv.fs_scandir = vim.uv.fs_scandir
    original_uv.fs_scandir_next = vim.uv.fs_scandir_next
  end,
  post_once = function()
    reset_module()
    vim.notify = original_notify
    vim.env.HOME = original_home
    vim.env.IDF_PATH = original_idf_path
    vim.env.IDF_PYTHON_ENV_PATH = original_idf_python_env_path
    vim.env.IDF_TOOLS_PATH = original_idf_tools_path
    vim.fn.has = original_fn.has
    vim.fn.executable = original_fn.executable
    vim.fn.system = original_fn.system
    vim.fn.exepath = original_fn.exepath
    vim.fn.filereadable = original_fn.filereadable
    vim.fn.expand = original_fn.expand
    vim.fn.readfile = original_fn.readfile
    vim.uv.fs_scandir = original_uv.fs_scandir
    vim.uv.fs_scandir_next = original_uv.fs_scandir_next
    vim.system = original_system
    vim.schedule = original_schedule
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

T["find_esp_clangd() honors IDF_TOOLS_PATH"] = function()
  prepare_case()
  vim.env.IDF_TOOLS_PATH = "/custom/espressif/tools"

  set_scandir({
    ["/custom/espressif/tools/esp-clang"] = {
      "esp-19.1.2_20231212",
      "esp-20.1.1_20250829",
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

  expect.equality(
    esp32.find_esp_clangd(),
    "/custom/espressif/tools/esp-clang/esp-20.1.1_20250829/esp-clang/bin/clangd"
  )
end

T["find_esp_clangd() honors a classic IDF_TOOLS_PATH pointing at the .espressif root"] = function()
  prepare_case()
  vim.env.IDF_TOOLS_PATH = "/custom/espressif"

  set_scandir({
    ["/custom/espressif/tools/esp-clang"] = {
      "esp-20.1.1_20250829",
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

  expect.equality(
    esp32.find_esp_clangd(),
    "/custom/espressif/tools/esp-clang/esp-20.1.1_20250829/esp-clang/bin/clangd"
  )
end

T["find_esp_clangd() falls back to the Windows EIM tools dir"] = function()
  prepare_case()
  local previous_has = vim.fn.has
  vim.fn.has = function(feature)
    if feature == "win32" then
      return 1
    end
    return previous_has(feature)
  end

  set_scandir({
    ["C:/Espressif/tools/esp-clang"] = {
      "esp-20.1.1_20250829",
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
  vim.fn.has = previous_has

  expect.equality(clangd, "C:/Espressif/tools/esp-clang/esp-20.1.1_20250829/esp-clang/bin/clangd")
end

T["resolve_idf_cmd() uses the Scripts python interpreter on Windows"] = function()
  prepare_case()
  local previous_has = vim.fn.has
  vim.fn.has = function(feature)
    if feature == "win32" then
      return 1
    end
    return previous_has(feature)
  end
  vim.env.IDF_PATH = "C:/Espressif/frameworks/esp-idf-v6.0.2"
  vim.env.IDF_PYTHON_ENV_PATH = "C:/Espressif/python_env/idf6.0_py3.11_env"

  vim.fn.executable = function(path)
    return path == "C:/Espressif/python_env/idf6.0_py3.11_env/Scripts/python.exe" and 1 or 0
  end
  vim.fn.filereadable = function(path)
    return path == "C:/Espressif/frameworks/esp-idf-v6.0.2/tools/idf.py" and 1 or 0
  end

  local esp32 = load_module()
  reset_plugin_state(esp32)
  local cmd = esp32.resolve_idf_cmd()
  local argv = esp32.resolve_idf_argv()
  vim.fn.has = previous_has

  expect.equality(argv, {
    "C:/Espressif/python_env/idf6.0_py3.11_env/Scripts/python.exe",
    "C:/Espressif/frameworks/esp-idf-v6.0.2/tools/idf.py",
  })
  expect.equality(
    cmd,
    "'C:/Espressif/python_env/idf6.0_py3.11_env/Scripts/python.exe' "
      .. "'C:/Espressif/frameworks/esp-idf-v6.0.2/tools/idf.py'"
  )
end

T["get_targets() invokes the Windows EIM Python command without a shell"] = function()
  prepare_case()
  local previous_has = vim.fn.has
  vim.fn.has = function(feature)
    if feature == "win32" then
      return 1
    end
    return previous_has(feature)
  end
  vim.env.IDF_PATH = "C:/Program Files/Espressif/frameworks/esp-idf-v6.0.2"
  vim.env.IDF_PYTHON_ENV_PATH = "C:/Program Files/Espressif/python_env/idf6.0_py3.11_env"

  vim.fn.executable = function(path)
    return path == "C:/Program Files/Espressif/python_env/idf6.0_py3.11_env/Scripts/python.exe" and 1 or 0
  end
  vim.fn.filereadable = function(path)
    return path == "C:/Program Files/Espressif/frameworks/esp-idf-v6.0.2/tools/idf.py" and 1 or 0
  end

  local esp32 = load_module()
  reset_plugin_state(esp32)
  set_system_result({ code = 0, stdout = "esp32\n", stderr = "" })

  local found
  run_scheduled(function()
    esp32.get_targets(function(items)
      found = items
    end)
  end)

  vim.fn.has = previous_has

  expect.equality(system_calls[1].cmd, {
    "C:/Program Files/Espressif/python_env/idf6.0_py3.11_env/Scripts/python.exe",
    "C:/Program Files/Espressif/frameworks/esp-idf-v6.0.2/tools/idf.py",
    "--list-targets",
  })
  expect.equality(system_calls[1].opts, { text = true })
  expect.equality(found, { { text = "esp32" } })
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
  local cmd = esp32.clangd_cmd()

  expect.equality(type(config.cmd), "function")
  expect.equality(cmd[1], esp32_path)
  expect_truthy(vim.tbl_contains(cmd, "--compile-commands-dir=build.custom"))
  expect_truthy(vim.tbl_contains(cmd, "--function-arg-placeholders=true"))
  expect_truthy(vim.tbl_contains(cmd, "--query-driver=**"))
  expect_truthy(vim.tbl_contains(cmd, "--enable-config"))
  expect.equality(config.root_markers, { "sdkconfig", "CMakeLists.txt" })
  expect_truthy(config.capabilities ~= nil)
  expect.equality(config.capabilities.general.positionEncodings, { "utf-16" })
end

T["clangd_cmd() falls back to system clangd and warns when esp clangd is missing"] = function()
  prepare_case()
  local esp32 = load_module()
  reset_plugin_state(esp32)

  local cmd = esp32.clangd_cmd()

  expect.equality(cmd[1], "clangd")
  expect.equality(#notifications, 1)
  expect.equality(
    notifications[1].message,
    "[ESP32] No esp-clangd found. Falling back to system clangd."
  )
  expect.equality(notifications[1].level, vim.log.levels.WARN)
end

T["clangd_cmd() stays quiet when only inspecting the command"] = function()
  prepare_case()
  local esp32 = load_module()
  reset_plugin_state(esp32)

  local cmd = esp32.clangd_cmd(nil, { silent = true })

  expect.equality(cmd[1], "clangd")
  expect.equality(#notifications, 0)
end

T["clangd_cmd() makes the compile database absolute against a root"] = function()
  prepare_case()
  local esp32 = load_module()
  reset_plugin_state(esp32)

  local cmd = esp32.clangd_cmd("/project/blink", { silent = true })

  expect_truthy(vim.tbl_contains(cmd, "--compile-commands-dir=/project/blink/build.clang"))
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
  expect_truthy(notifications[1].message:match("Missing compile_commands%.json in build%.missing/compile_commands%.json"))
  -- Regenerating alone is not enough: clangd already discarded the flag.
  expect_truthy(notifications[1].message:match("restarts clangd"))
  expect.equality(notifications[1].level, vim.log.levels.WARN)
end

T["compile_commands_toolchain() recognises a GCC database"] = function()
  prepare_case()
  local esp32 = load_module()
  reset_plugin_state(esp32)
  set_compile_commands("/opt/espressif/bin/xtensa-esp32-elf-gcc")

  expect.equality(esp32.compile_commands_toolchain(), "gcc")
end

T["compile_commands_toolchain() recognises a clang database"] = function()
  prepare_case()
  local esp32 = load_module()
  reset_plugin_state(esp32)
  set_compile_commands("/opt/espressif/esp-clang/bin/clang")

  expect.equality(esp32.compile_commands_toolchain(), "clang")
end

T["classify_compiler() recognises the GCC variants ESP-IDF produces"] = function()
  prepare_case()
  local esp32 = load_module()
  reset_plugin_state(esp32)

  local gcc = {
    "/opt/esp/bin/xtensa-esp32-elf-gcc -c main.c",
    "/opt/esp/bin/xtensa-esp32-elf-g++ -c main.cpp",
    "/opt/esp/bin/riscv32-esp-elf-gcc -c main.c",
    "gcc -c main.c",
    "gcc.exe -c main.c",
    "/usr/bin/cc -c main.c",
    -- ESP-IDF puts ccache in front of the compiler when it is available.
    "/usr/bin/ccache /opt/esp/bin/xtensa-esp32-elf-gcc -c main.c",
    "sccache gcc -c main.c",
    -- Windows toolchain paths containing spaces arrive quoted.
    '"C:/Program Files/esp/xtensa-esp32-elf-gcc.exe" -c main.c',
  }

  for _, command in ipairs(gcc) do
    expect.equality(esp32.classify_compiler(command), "gcc")
  end
end

T["classify_compiler() recognises the clang variants"] = function()
  prepare_case()
  local esp32 = load_module()
  reset_plugin_state(esp32)

  local clang = {
    "/opt/esp/esp-clang/bin/clang -c main.c",
    "/opt/esp/esp-clang/bin/clang++ -c main.cpp",
    "clang.exe -c main.c",
    "ccache /opt/esp/esp-clang/bin/clang -c main.c",
    '"C:/Program Files/esp/clang.exe" -c main.c',
  }

  for _, command in ipairs(clang) do
    expect.equality(esp32.classify_compiler(command), "clang")
  end
end

T["classify_compiler() accepts the arguments list form"] = function()
  prepare_case()
  local esp32 = load_module()
  reset_plugin_state(esp32)

  expect.equality(
    esp32.classify_compiler({ "/opt/esp/bin/xtensa-esp32-elf-gcc", "-c", "main.c" }),
    "gcc"
  )
  expect.equality(esp32.classify_compiler({ "ccache", "clang", "-c", "main.c" }), "clang")
  expect.equality(esp32.classify_compiler({}), nil)
  expect.equality(esp32.classify_compiler(nil), nil)
  expect.equality(esp32.classify_compiler("/opt/rustc -c main.rs"), nil)
end

T["compile_commands_toolchain() reads a quoted Windows compiler path"] = function()
  prepare_case()
  local esp32 = load_module()
  reset_plugin_state(esp32)

  vim.fn.filereadable = function(path)
    return path:match("compile_commands%.json$") and 1 or 0
  end
  vim.fn.readfile = function()
    return {
      "[",
      "{",
      '  "directory": "C:/project/build.clang",',
      '  "command": "\\"C:/Program Files/esp/xtensa-esp32-elf-gcc.exe\\" -c main.c",',
      '  "file": "C:/project/main.c"',
      "}",
      "]",
    }
  end

  expect.equality(esp32.compile_commands_toolchain(), "gcc")
end

T["compile_commands_toolchain() returns nil without a database"] = function()
  prepare_case()
  local esp32 = load_module()
  reset_plugin_state(esp32)

  expect.equality(esp32.compile_commands_toolchain(), nil)
end

T["ensure_compile_commands() warns when the database was generated for GCC"] = function()
  prepare_case()
  local esp32 = load_module()
  reset_plugin_state(esp32)
  set_compile_commands("/opt/espressif/bin/riscv32-esp-elf-gcc")

  esp32.ensure_compile_commands()

  expect.equality(#notifications, 1)
  expect_truthy(notifications[1].message:match("generated for the GCC toolchain"))
  expect_truthy(notifications[1].message:match("ESPReconfigure"))
  expect.equality(notifications[1].level, vim.log.levels.WARN)
end

T["ensure_compile_commands() stays quiet for a clang database"] = function()
  prepare_case()
  local esp32 = load_module()
  reset_plugin_state(esp32)
  set_compile_commands("/opt/espressif/esp-clang/bin/clang")

  esp32.ensure_compile_commands()

  expect.equality(#notifications, 0)
end

T["compile_commands_toolchain() resolves build_dir against the project root"] = function()
  prepare_case()
  local esp32 = load_module()
  reset_plugin_state(esp32)

  local checked
  vim.fn.filereadable = function(path)
    checked = path
    return 0
  end

  esp32.compile_commands_toolchain("/project/blink")

  expect.equality(checked, "/project/blink/build.clang/compile_commands.json")
end

T["compile_commands_toolchain() leaves an absolute build_dir alone"] = function()
  prepare_case()
  local esp32 = load_module()
  reset_plugin_state(esp32)
  esp32.options.build_dir = "/elsewhere/build"

  local checked
  vim.fn.filereadable = function(path)
    checked = path
    return 0
  end

  esp32.compile_commands_toolchain("/project/blink")

  expect.equality(checked, "/elsewhere/build/compile_commands.json")
end

T["LspAttach checks the project clangd attached to, once per root"] = function()
  prepare_case()
  local esp32 = load_module()
  reset_plugin_state(esp32)
  set_compile_commands("/opt/espressif/bin/xtensa-esp32-elf-gcc")

  local previous_get_client = vim.lsp.get_client_by_id
  vim.lsp.get_client_by_id = function(id)
    if id == 1 then
      return { name = "clangd", root_dir = "/project/blink" }
    end
    return { name = "lua_ls", root_dir = "/project/blink" }
  end

  esp32.check_attached_client(1)
  esp32.check_attached_client(1)
  esp32.check_attached_client(2)

  vim.lsp.get_client_by_id = previous_get_client

  -- Same root twice and a non-clangd client must not add more warnings.
  expect.equality(#notifications, 1)
  expect_truthy(notifications[1].message:match("generated for the GCC toolchain"))
  expect_truthy(notifications[1].message:match("^%[ESP32%].*/project/blink/build%.clang"))
end

T["restart_clangd() replaces the matching client and reattaches its buffers"] = function()
  prepare_case()
  local esp32 = load_module()
  reset_plugin_state(esp32)

  local previous_get_clients = vim.lsp.get_clients
  local previous_start = vim.lsp.start
  local previous_buf_is_valid = vim.api.nvim_buf_is_valid
  local previous_schedule = vim.schedule
  local matching_stopped = false
  local other_stopped = false
  local requested_filter
  local starts = {}
  local config = {
    name = "clangd",
    root_dir = "/project/blink",
  }

  vim.lsp.get_clients = function(filter)
    requested_filter = filter
    return {
      {
        root_dir = "/project/blink",
        attached_buffers = { [12] = "c", [11] = "c" },
        config = config,
        stop = function()
          matching_stopped = true
        end,
      },
      {
        root_dir = "/project/other",
        stop = function()
          other_stopped = true
        end,
      },
    }
  end
  vim.api.nvim_buf_is_valid = function()
    return true
  end
  vim.schedule = function(callback)
    callback()
  end
  vim.lsp.start = function(client_config, opts)
    table.insert(starts, { config = client_config, bufnr = opts.bufnr })
    return 42
  end

  local restarted = esp32.restart_clangd("/project/blink")

  vim.lsp.get_clients = previous_get_clients
  vim.lsp.start = previous_start
  vim.api.nvim_buf_is_valid = previous_buf_is_valid
  vim.schedule = previous_schedule

  expect.equality(restarted, true)
  expect.equality(requested_filter, { name = "clangd" })
  expect.equality(matching_stopped, true)
  expect.equality(other_stopped, false)
  expect.equality(starts, {
    { config = config, bufnr = 11 },
    { config = config, bufnr = 12 },
  })
end

T["complete_reconfigure() closes a successful terminal and restarts clangd"] = function()
  prepare_case()
  local esp32 = load_module()
  reset_plugin_state(esp32)

  local restarted_root
  local closed = false
  esp32.restart_clangd = function(root)
    restarted_root = root
    return true
  end

  local completed = esp32.complete_reconfigure("/project/blink", 0, {
    close = function()
      closed = true
    end,
  })

  expect.equality(completed, true)
  expect.equality(closed, true)
  expect.equality(restarted_root, "/project/blink")
  expect.equality(notifications, {
    {
      message = "[ESP32] Reconfigured, restarting clangd.",
      level = vim.log.levels.INFO,
    },
  })
end

T["complete_reconfigure() keeps a failed terminal open and does not restart clangd"] = function()
  prepare_case()
  local esp32 = load_module()
  reset_plugin_state(esp32)

  local restarted = false
  local closed = false
  esp32.restart_clangd = function()
    restarted = true
    return true
  end

  local completed = esp32.complete_reconfigure("/project/blink", 2, {
    close = function()
      closed = true
    end,
  })

  expect.equality(completed, false)
  expect.equality(closed, false)
  expect.equality(restarted, false)
  expect.equality(notifications, {
    {
      message = "[ESP32] Reconfigure failed with exit code 2.\nCheck the terminal output.",
      level = vim.log.levels.ERROR,
    },
  })
end

T["reconfigure() disables Snacks auto-close until its exit handler runs"] = function()
  prepare_case()
  local terminal_opts
  local autocmd_spec
  local terminal = { buf = 123 }
  local esp32 = load_module({
    terminal = {
      open = function(_, opts)
        terminal_opts = opts
        return terminal
      end,
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
  })
  reset_plugin_state(esp32)
  esp32.project_root = function()
    return "/project/blink"
  end

  local previous_create_autocmd = vim.api.nvim_create_autocmd
  vim.api.nvim_create_autocmd = function(event, spec)
    autocmd_spec = vim.tbl_extend("force", { event = event }, spec)
    return 1
  end

  esp32.reconfigure()

  vim.api.nvim_create_autocmd = previous_create_autocmd

  expect.equality(terminal_opts.auto_close, false)
  expect.equality(autocmd_spec.event, "TermClose")
  expect.equality(autocmd_spec.buffer, 123)
  expect.equality(autocmd_spec.once, true)
  expect.equality(type(autocmd_spec.callback), "function")
end

T["make_idf_command() uses the EIM Python environment when idf.py is a shell function"] = function()
  prepare_case()
  vim.env.IDF_PATH = "/home/test/.espressif/v6.0.1/esp-idf/v6.0.1/esp-idf"
  vim.env.IDF_PYTHON_ENV_PATH = "/home/test/.espressif/tools/python/v6.0.1/venv"

  vim.fn.executable = function(path)
    if path == "idf.py" then
      return 0
    end

    return path == "/home/test/.espressif/tools/python/v6.0.1/venv/bin/python" and 1 or 0
  end

  vim.fn.filereadable = function(path)
    return path == "/home/test/.espressif/v6.0.1/esp-idf/v6.0.1/esp-idf/tools/idf.py" and 1 or 0
  end

  local esp32 = load_module()
  reset_plugin_state(esp32)
  esp32.options.build_dir = "build clang"

  expect.equality(
    esp32.make_idf_command("monitor", "/dev/ttyUSB0"),
    "'/home/test/.espressif/tools/python/v6.0.1/venv/bin/python' "
      .. "'/home/test/.espressif/v6.0.1/esp-idf/v6.0.1/esp-idf/tools/idf.py' "
      .. "-B 'build clang' -p '/dev/ttyUSB0' monitor"
  )
end

T["resolve_idf_cmd() does not guess a Python interpreter without IDF_PYTHON_ENV_PATH"] = function()
  prepare_case()
  vim.env.IDF_PATH = "/home/test/.espressif/v6.0.1/esp-idf/v6.0.1/esp-idf"

  vim.fn.executable = function(path)
    return (path == "python3" or path == "python") and 1 or 0
  end

  vim.fn.filereadable = function(path)
    return path == "/home/test/.espressif/v6.0.1/esp-idf/v6.0.1/esp-idf/tools/idf.py" and 1 or 0
  end

  local esp32 = load_module()
  reset_plugin_state(esp32)

  expect.equality(esp32.resolve_idf_cmd(), "idf.py")
end

T["make_idf_command() respects a configured idf_cmd"] = function()
  prepare_case()
  local esp32 = load_module()
  reset_plugin_state(esp32)
  esp32.setup({
    idf_cmd = "/usr/local/bin/idf.py-wrapper",
  })

  expect.equality(
    esp32.make_idf_command("build"),
    "/usr/local/bin/idf.py-wrapper -B 'build.clang' build"
  )
end

T["resolve_idf_argv() supports paths with spaces and argv overrides"] = function()
  prepare_case()
  local esp32 = load_module()
  reset_plugin_state(esp32)

  esp32.options.idf_cmd = "C:/Program Files/Espressif/idf.py"
  expect.equality(esp32.resolve_idf_argv(), { "C:/Program Files/Espressif/idf.py" })
  expect.equality(esp32.resolve_idf_cmd(), "'C:/Program Files/Espressif/idf.py'")

  esp32.options.idf_cmd = { "mise", "exec", "--", "idf.py" }
  expect.equality(esp32.resolve_idf_argv(), { "mise", "exec", "--", "idf.py" })
end

T["resolve_idf_cmd() ignores an empty idf_cmd override"] = function()
  prepare_case()
  vim.fn.executable = function(path)
    return path == "idf.py" and 1 or 0
  end

  local esp32 = load_module()
  reset_plugin_state(esp32)
  esp32.setup({
    idf_cmd = "",
  })

  expect.equality(esp32.resolve_idf_cmd(), "idf.py")
end

T["info() reports idf.py available when an EIM Python command can be resolved"] = function()
  prepare_case()
  vim.env.IDF_PATH = "/home/test/.espressif/v6.0.1/esp-idf/v6.0.1/esp-idf"
  vim.env.IDF_PYTHON_ENV_PATH = "/home/test/.espressif/tools/python/v6.0.1/venv"

  vim.fn.executable = function(path)
    if path == "/home/test/.espressif/tools/python/v6.0.1/venv/bin/python" then
      return 1
    end

    return 0
  end

  vim.fn.filereadable = function(path)
    return path == "/home/test/.espressif/v6.0.1/esp-idf/v6.0.1/esp-idf/tools/idf.py" and 1 or 0
  end

  local esp32 = load_module()
  reset_plugin_state(esp32)
  esp32.info()

  expect.equality(#notifications, 1)
  expect.equality(notifications[1].message, table.concat({
    "✗ ESP-specific clangd missing",
    "✗ compile_commands.json missing in build.clang/compile_commands.json",
    "clangd: clangd --compile-commands-dir=build.clang --background-index --clang-tidy --header-insertion=iwyu --completion-style=detailed --function-arg-placeholders=true --fallback-style=llvm",
    "✓ idf.py",
    "✗ llvm-ar",
    "IDF_PATH: /home/test/.espressif/v6.0.1/esp-idf/v6.0.1/esp-idf",
  }, "\n"))
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
  vim.fn.readfile = function()
    return {
      "[",
      "{",
      '  "command": "/opt/espressif/esp-clang/bin/clang -c main.c"',
      "}",
      "]",
    }
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
    "clangd: /opt/espressif/clangd --compile-commands-dir=build.clang --background-index --clang-tidy --header-insertion=iwyu --completion-style=detailed --function-arg-placeholders=true --fallback-style=llvm",
    "✓ idf.py",
    "✓ llvm-ar",
    "IDF_PATH: /opt/esp-idf",
  }, "\n"))
end

T["info() suggests EIM and manual activation when ESP-IDF is not active"] = function()
  prepare_case()
  local esp32 = load_module()
  reset_plugin_state(esp32)
  esp32.info()

  expect.equality(#notifications, 1)
  expect.equality(notifications[1].level, vim.log.levels.INFO)
  expect.equality(notifications[1].message, table.concat({
    "✗ ESP-specific clangd missing",
    "✗ compile_commands.json missing in build.clang/compile_commands.json",
    "clangd: clangd --compile-commands-dir=build.clang --background-index --clang-tidy --header-insertion=iwyu --completion-style=detailed --function-arg-placeholders=true --fallback-style=llvm",
    "✗ idf.py",
    "✗ llvm-ar",
    "IDF_PATH: ✗ not set",
    "⚠️ Source an ESP-IDF environment before launching Neovim:",
    "source ~/.espressif/tools/activate_idf_<version>.sh",
    "or source ~/esp/esp-idf/export.sh",
  }, "\n"))
end

T["info() suggests the PowerShell profile on Windows when ESP-IDF is not active"] = function()
  prepare_case()
  local previous_has = vim.fn.has
  vim.fn.has = function(feature)
    if feature == "win32" then
      return 1
    end
    return previous_has(feature)
  end

  local esp32 = load_module()
  reset_plugin_state(esp32)
  esp32.info()
  vim.fn.has = previous_has

  expect.equality(#notifications, 1)
  expect.equality(notifications[1].message, table.concat({
    "✗ ESP-specific clangd missing",
    "✗ compile_commands.json missing in build.clang/compile_commands.json",
    "clangd: clangd --compile-commands-dir=build.clang --background-index --clang-tidy --header-insertion=iwyu --completion-style=detailed --function-arg-placeholders=true --fallback-style=llvm",
    "✗ idf.py",
    "✗ llvm-ar",
    "IDF_PATH: ✗ not set",
    "⚠️ Source an ESP-IDF environment before launching Neovim:",
    [[. C:\Espressif\tools\Microsoft.<version>.PowerShell_profile.ps1]],
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
  expect_truthy(commands.ESPSetTarget ~= nil)
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
  expect.equality(calls[1].cmd, "idf.py -B 'build.clang' -p '/dev/ttyUSB9' monitor")
  expect.equality(calls[2].method, "open")
  expect.equality(calls[2].cmd, "idf.py -B 'build.clang' -p '/dev/ttyUSB9' flash")
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
  expect.equality(calls[1].cmd, "idf.py -B 'build.clang' -p '/dev/ttyACM0' monitor")
end

T["parse_targets() keeps target names and drops idf.py diagnostics"] = function()
  prepare_case()
  local esp32 = load_module()
  reset_plugin_state(esp32)

  -- Only bare target names from the external command may reach the picker.
  local targets = esp32.parse_targets(table.concat({
    "nvm: version 22 is already in use",
    "WARNING: The IDF_PYTHON_ENV_PATH is missing in environmental variables!",
    "Setting IDF_PATH environment variable: /home/test/esp32-project/esp-idf",
    "esp32",
    "esp32s3",
    "esp32c61",
  }, "\n"))

  expect.equality(#targets, 3)
  expect.equality(targets[1].text, "esp32")
  expect.equality(targets[2].text, "esp32s3")
  expect.equality(targets[3].text, "esp32c61")
end

T["parse_targets() returns nil when no target survives"] = function()
  prepare_case()
  local esp32 = load_module()
  reset_plugin_state(esp32)

  expect.equality(esp32.parse_targets(""), nil)
  -- A failure that merely mentions a target name is not a target list.
  expect.equality(esp32.parse_targets("ERROR: unsupported target esp32c6 in sdkconfig"), nil)
end

T["set_target() runs set-target for the picked target"] = function()
  prepare_case()
  local picker_spec
  local selected_target
  local esp32 = load_module({
    terminal = {
      open = function() end,
      toggle = function() end,
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
  esp32.change_target = function(target)
    selected_target = target
  end
  set_system_result({ code = 0, stdout = "esp32\nesp32s3\n", stderr = "" })

  run_scheduled(function()
    esp32.set_target()
  end)

  expect.equality(#picker_spec.items, 2)

  picker_spec.confirm({ close = function() end }, { text = "esp32s3" })

  expect.equality(system_calls[1].cmd, { "idf.py", "--list-targets" })
  expect.equality(system_calls[1].opts, { text = true })
  expect.equality(selected_target, "esp32s3")
end

T["change_target() preserves the clang toolchain and registers its completion handler"] = function()
  prepare_case()
  local opened
  local autocmd_spec
  local terminal = { buf = 123 }
  local esp32 = load_module({
    terminal = {
      open = function(cmd, opts)
        opened = { cmd = cmd, opts = opts }
        return terminal
      end,
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
  })
  reset_plugin_state(esp32)
  esp32.state.last_port = "/dev/ttyUSB9"
  esp32.project_root = function()
    return "/project/blink"
  end

  local previous_create_autocmd = vim.api.nvim_create_autocmd
  vim.api.nvim_create_autocmd = function(event, spec)
    autocmd_spec = vim.tbl_extend("force", { event = event }, spec)
    return 1
  end

  local started = esp32.change_target("esp32s3")

  vim.api.nvim_create_autocmd = previous_create_autocmd

  expect.equality(started, true)
  expect.equality(opened.cmd, {
    "idf.py",
    "-C",
    "/project/blink",
    "-B",
    "/project/blink/build.clang",
    "-D",
    "IDF_TOOLCHAIN=clang",
    "set-target",
    "esp32s3",
  })
  expect.equality(opened.opts.auto_close, false)
  expect.equality(opened.opts.win.title, "ESP-IDF Set Target")
  expect.equality(vim.tbl_contains(opened.cmd, "/dev/ttyUSB9"), false)
  expect.equality(autocmd_spec.event, "TermClose")
  expect.equality(autocmd_spec.buffer, 123)
  expect.equality(autocmd_spec.once, true)
  expect.equality(type(autocmd_spec.callback), "function")
end

T["complete_target_change() closes the terminal and restarts project clangd"] = function()
  prepare_case()
  local esp32 = load_module()
  reset_plugin_state(esp32)

  local restarted_root
  local closed = false
  esp32.restart_clangd = function(root)
    restarted_root = root
    return true
  end

  local completed = esp32.complete_target_change("/project/blink", 0, {
    close = function()
      closed = true
    end,
  })

  expect.equality(completed, true)
  expect.equality(closed, true)
  expect.equality(restarted_root, "/project/blink")
  expect.equality(notifications, {
    {
      message = "[ESP32] Target changed, restarting clangd.",
      level = vim.log.levels.INFO,
    },
  })
end

T["set_target() warns and skips the picker when no targets are found"] = function()
  prepare_case()
  local picked = false
  local esp32 = load_module({
    terminal = {
      open = function() end,
      toggle = function() end,
    },
    picker = {
      pick = function()
        picked = true
      end,
      util = {
        align = function(value)
          return value
        end,
      },
    },
  })

  reset_plugin_state(esp32)
  -- idf.py keeps warnings and errors on stderr, so stdout holds no targets.
  set_system_result({
    code = 1,
    stdout = "",
    stderr = "WARNING: The IDF_PYTHON_ENV_PATH is missing in environmental variables!\n",
  })

  run_scheduled(function()
    esp32.set_target()
  end)

  expect.equality(picked, false)
  expect.equality(#notifications, 1)
  expect_truthy(notifications[1].message:match("No targets found"))
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
