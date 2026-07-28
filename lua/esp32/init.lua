local M = {}

---@class ESP32Opts
local defaults = {
  build_dir = "build.clang",
  baudrate = 115200,
  clangd_args = {},
  idf_cmd = nil,
}

local targets

M.options = vim.deepcopy(defaults)
M.state = {
  last_port = nil,
}

local function get_snacks()
  return require("snacks")
end

local function make_clangd_capabilities()
  local capabilities = vim.lsp.protocol.make_client_capabilities()

  -- clangd moved from the custom offsetEncoding extension to the standard
  -- positionEncodings capability in LSP 3.17.
  if capabilities.general then
    capabilities.general.positionEncodings = { "utf-16" }
  else
    capabilities.offsetEncoding = { "utf-16" }
  end

  return capabilities
end

local function is_windows()
  return vim.fn.has("win32") == 1
end

local function get_home()
  return vim.env.HOME or vim.fn.expand("~")
end

local function join_path(...)
  return table.concat({ ... }, "/")
end

local function shellescape(value)
  return vim.fn.shellescape(tostring(value))
end

local function executable_path(path)
  return path and vim.fn.executable(path) == 1
end

--- Candidate ESP-IDF tools directories, most specific first
local function idf_tools_dirs()
  local dirs = {}
  local seen = {}

  local function add(dir)
    if dir and dir ~= "" and not seen[dir] then
      seen[dir] = true
      table.insert(dirs, dir)
    end
  end

  if vim.env.IDF_TOOLS_PATH and vim.env.IDF_TOOLS_PATH ~= "" then
    -- EIM points IDF_TOOLS_PATH at the tools dir itself, classic
    -- idf_tools.py points it at the .espressif root with tools/ inside.
    add(vim.env.IDF_TOOLS_PATH)
    add(join_path(vim.env.IDF_TOOLS_PATH, "tools"))
  end

  add(join_path(get_home(), ".espressif", "tools"))

  if is_windows() then
    -- EIM's default install location on Windows
    add("C:/Espressif/tools")
  end

  return dirs
end

--- Find the Python interpreter of an ESP-IDF virtualenv
local function find_venv_python(env_path)
  local candidates
  if is_windows() then
    candidates = {
      join_path(env_path, "Scripts", "python.exe"),
      join_path(env_path, "python.exe"),
    }
  else
    candidates = { join_path(env_path, "bin", "python") }
  end

  for _, python in ipairs(candidates) do
    if executable_path(python) then
      return python
    end
  end
end

function M.setup(opts)
  M.options = vim.tbl_deep_extend("force", M.options or {}, opts or {})
  M.ensure_clangd()
end

--- List available cu.* serial ports
function M.list_ports()
  local scandir = vim.uv.fs_scandir("/dev")
  local ports = {}
  local patterns = {
    "^cu%.",
    "^ttyUSB%d+$",
    "^ttyACM%d+$",
    "^tty%.usb",
    "^tty%.wchusbserial",
  }

  if scandir then
    while true do
      local name = vim.uv.fs_scandir_next(scandir)
      if not name then
        break
      end

      for _, pattern in ipairs(patterns) do
        if name:match(pattern) then
          table.insert(ports, { port = "/dev/" .. name })
          break
        end
      end
    end
  end

  table.sort(ports, function(a, b)
    return a.port < b.port
  end)

  return ports
end

--- Find the ESP-IDF specific clangd
function M.find_esp_clangd()
  -- if clangd is on the path, check if it is from espressif using.
  -- if so, we are done
  if vim.fn.executable("clangd") == 1 then
    -- use `clangd --version` to check if it is from espressif
    local clangd_version = vim.fn.system("clangd --version")
    if clangd_version:match("espressif") then
      -- return the absolute path to clangd
      return vim.fn.exepath("clangd")
    end
  end

  for _, tools_dir in ipairs(idf_tools_dirs()) do
    local base = join_path(tools_dir, "esp-clang")
    local scandir = vim.uv.fs_scandir(base)
    if scandir then
      local latest
      local latest_key
      while true do
        local name = vim.uv.fs_scandir_next(scandir)
        if not name then
          break
        end
        if name:match("^esp%-.+") then
          local candidate = join_path(base, name, "esp-clang", "bin", "clangd")
          if vim.fn.executable(candidate) == 1 and (not latest_key or name > latest_key) then
            latest = candidate
            latest_key = name
          end
        end
      end
      if latest then
        return latest
      end
    end
  end

  return nil
end

--- Resolve argv that can run idf.py without involving a shell
function M.resolve_idf_argv()
  if type(M.options.idf_cmd) == "table" and #M.options.idf_cmd > 0 then
    return vim.deepcopy(M.options.idf_cmd)
  end

  if type(M.options.idf_cmd) == "string" and M.options.idf_cmd ~= "" then
    return { M.options.idf_cmd }
  end

  if executable_path("idf.py") then
    return { "idf.py" }
  end

  if vim.env.IDF_PATH then
    local idf_py = join_path(vim.env.IDF_PATH, "tools", "idf.py")
    if vim.fn.filereadable(idf_py) == 1 then
      if vim.env.IDF_PYTHON_ENV_PATH then
        local venv_python = find_venv_python(vim.env.IDF_PYTHON_ENV_PATH)
        if venv_python then
          return { venv_python, idf_py }
        end
      end
    end
  end

  return { "idf.py" }
end

--- Escape argv as a command line for terminal-backed commands
function M.resolve_idf_cmd()
  local argv = M.resolve_idf_argv()
  local escaped = {}

  for _, arg in ipairs(argv) do
    -- Keep ordinary command names and paths readable. Anything containing
    -- whitespace or shell syntax must stay one argument in the terminal.
    local unsafe = tostring(arg):gsub("[%w%._/%-]", ""):gsub(":", ""):gsub("\\", "")
    table.insert(escaped, #argv == 1 and unsafe == "" and tostring(arg) or shellescape(arg))
  end

  return table.concat(escaped, " ")
end

--- Root markers of an ESP-IDF project, most specific first
local root_markers = { "sdkconfig", "CMakeLists.txt" }

--- Resolve the ESP-IDF project a buffer belongs to
---
--- Prefers the root an attached clangd resolved, so commands act on the same
--- project the LSP does, and falls back to searching upwards for a marker.
--- Returns nil when nothing looks like a project, leaving callers on Neovim's
--- working directory.
function M.project_root(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()

  for _, client in ipairs(vim.lsp.get_clients({ name = "clangd", bufnr = bufnr })) do
    if client.root_dir then
      return client.root_dir
    end
  end

  local name = vim.api.nvim_buf_get_name(bufnr)
  return vim.fs.root(name ~= "" and name or vim.fn.getcwd(), root_markers)
end

--- Resolve build_dir against a project root
---
--- build_dir is relative by default, and Neovim's working directory is not
--- necessarily the project, so anything that has a root should pass it.
local function build_dir_for(root)
  local dir = M.options.build_dir
  local is_absolute = dir:match("^[/\\]") or dir:match("^%a:[/\\]")

  if root and not is_absolute then
    dir = join_path(root, dir)
  end

  return dir
end

--- Locate the compile database of a project
local function compile_commands_path(root)
  return join_path(build_dir_for(root), "compile_commands.json")
end

--- Create an idf.py command line
---
--- The terminal inherits Neovim's working directory, which is not necessarily
--- the project, so point idf.py at the resolved root with -C when there is one.
function M.make_idf_command(cmd, port, opts)
  local root = M.project_root()
  local full_cmd = M.resolve_idf_cmd()

  if root then
    full_cmd = full_cmd .. " -C " .. shellescape(root)
  end

  full_cmd = full_cmd .. " -B " .. shellescape(build_dir_for(root))

  local selected_port = not (opts and opts.include_port == false) and (port or M.state.last_port)
  if selected_port then
    full_cmd = full_cmd .. " -p " .. shellescape(selected_port)
  end

  return full_cmd .. " " .. cmd
end

--- Create idf.py argv for shell-independent process execution
function M.make_idf_argv(args, port, opts)
  local root = M.project_root()
  local argv = M.resolve_idf_argv()

  if root then
    vim.list_extend(argv, { "-C", root })
  end

  vim.list_extend(argv, { "-B", build_dir_for(root) })

  local selected_port = not (opts and opts.include_port == false) and (port or M.state.last_port)
  if selected_port then
    vim.list_extend(argv, { "-p", selected_port })
  end

  vim.list_extend(argv, args or {})
  return argv
end

--- Build systems prefix the real compiler with these, so skip past them
local compiler_launchers = {
  ccache = true,
  sccache = true,
  distcc = true,
  icecc = true,
  buildcache = true,
}

--- Split a command line into arguments, honouring quoted paths
---
--- Windows toolchain paths contain spaces often enough that splitting on
--- whitespace alone misreads the compiler.
local function split_command(command)
  local args = {}
  local index = 1

  while index <= #command do
    local char = command:sub(index, index)

    if char == " " or char == "\t" then
      index = index + 1
    elseif char == '"' then
      local closing = command:find('"', index + 1, true)
      if not closing then
        break
      end
      table.insert(args, command:sub(index + 1, closing - 1))
      index = closing + 1
    else
      local stop = command:find("[ \t]", index) or (#command + 1)
      table.insert(args, command:sub(index, stop - 1))
      index = stop
    end
  end

  return args
end

--- Reduce a compiler path to a comparable basename
local function compiler_name(path)
  local name = path:match("([^/\\]+)$") or path
  return name:gsub("%.exe$", ""):lower()
end

--- Classify the compiler of a compile database entry
---
--- Accepts either the "command" string or the "arguments" list of an entry.
--- Returns "clang", "gcc", or nil when the name is not recognised.
function M.classify_compiler(command)
  local args
  if type(command) == "table" then
    args = command
  elseif type(command) == "string" and command ~= "" then
    args = split_command(command)
  else
    return nil
  end

  local index = 1

  -- ESP-IDF enables ccache when it is available, which puts the launcher
  -- rather than the compiler in the first position.
  while args[index] and compiler_launchers[compiler_name(args[index])] do
    index = index + 1
  end

  local name = args[index] and compiler_name(args[index])
  if not name then
    return nil
  end

  if name:match("clang%+?%+?$") then
    return "clang"
  end

  -- Covers xtensa-esp32-elf-gcc, riscv32-esp-elf-g++, plain gcc/g++ and the
  -- cc/c++ aliases.
  if name:match("g?cc$") or name:match("g?%+%+$") then
    return "gcc"
  end

  return nil
end

--- Identify the compiler a compile database was generated for
---
--- Returns "clang", "gcc", or nil when the database is missing or the compiler
--- cannot be recognised. A database written for the GCC toolchain drives clangd
--- into reporting unknown arguments and missing headers, because the ESP-IDF
--- GCC flags and newlib headers have no clang equivalent.
function M.compile_commands_toolchain(root)
  local path = compile_commands_path(root)
  if vim.fn.filereadable(path) == 0 then
    return nil
  end

  -- The database grows with the project, so read only far enough to reach the
  -- first entry rather than loading the whole file, then let the JSON decoder
  -- deal with escaping instead of matching quotes by hand.
  local head = table.concat(vim.fn.readfile(path, "", 40), "\n")
  local entry = head:match("%b{}")
  if not entry then
    return nil
  end

  local ok, decoded = pcall(vim.json.decode, entry)
  if not ok or type(decoded) ~= "table" then
    return nil
  end

  return M.classify_compiler(decoded.arguments or decoded.command)
end

--- Ensure compile_commands.json exists and was generated for clang
function M.ensure_compile_commands(root)
  local path = compile_commands_path(root)
  if vim.fn.filereadable(path) == 0 then
    -- clangd drops --compile-commands-dir at startup when the directory is
    -- absent ("The argument will be ignored"), so creating it later is not
    -- enough on its own: the server has to be started again.
    vim.notify(
      "[ESP32] ⚠️ Missing compile_commands.json in " .. path
        .. "\nclangd has already discarded the build directory for this session."
        .. "\nRun :ESPReconfigure, which regenerates it and restarts clangd.",
      vim.log.levels.WARN
    )
    return
  end

  if M.compile_commands_toolchain(root) == "gcc" then
    vim.notify(
      "[ESP32] ⚠️ " .. path .. " was generated for the GCC toolchain."
        .. "\nclangd will report unknown arguments and missing headers."
        .. "\nRun :ESPReconfigure to regenerate it with IDF_TOOLCHAIN=clang.",
      vim.log.levels.WARN
    )
  end
end

--- Restart the clangd clients of a project
---
--- Used after the build directory changes, because clangd only reads
--- --compile-commands-dir at startup.
function M.restart_clangd(root)
  local restarted = false

  for _, client in ipairs(vim.lsp.get_clients({ name = "clangd" })) do
    if not root or client.root_dir == root then
      local buffers = vim.tbl_keys(client.attached_buffers or {})
      table.sort(buffers)

      if client.config and #buffers > 0 then
        local config = client.config
        client:stop()
        restarted = true

        -- stop() marks the old client as stopping synchronously, so start()
        -- cannot reuse it. The first valid buffer creates the replacement;
        -- subsequent buffers reuse that client without replaying unrelated
        -- FileType autocmds or relying on an arbitrary delay.
        vim.schedule(function()
          for _, bufnr in ipairs(buffers) do
            if vim.api.nvim_buf_is_valid(bufnr) then
              local client_id = vim.lsp.start(config, { bufnr = bufnr })
              if not client_id then
                vim.notify("[ESP32] Failed to restart clangd.", vim.log.levels.ERROR)
                return
              end
            end
          end
        end)
      end
    end
  end

  return restarted
end

--- Projects already reported on, so one bad build dir warns once per session
local checked_roots = {}

--- Check the compile database of a project clangd just attached to
---
--- Hooked to LspAttach rather than to opening a buffer because that is where
--- the resolved project root is available, and because the warnings only
--- describe how clangd behaves.
function M.check_attached_client(client_id)
  local client = vim.lsp.get_client_by_id(client_id)
  if not client or client.name ~= "clangd" then
    return
  end

  local root = client.root_dir
  if not root or checked_roots[root] then
    return
  end

  checked_roots[root] = true
  M.ensure_compile_commands(root)
end

vim.api.nvim_create_autocmd("LspAttach", {
  group = vim.api.nvim_create_augroup("Esp32CheckCompileCommands", { clear = true }),
  callback = function(args)
    M.check_attached_client(args.data and args.data.client_id)
  end,
})

--- Ensure esp-clangd exists and warn if not
function M.ensure_clangd()
  if not M.find_esp_clangd() then
    vim.notify("[ESP32] ⚠️ ESP-specific clangd not found. LSP may not work properly.", vim.log.levels.WARN)
  end
end

--- Open a Snacks terminal for idf.py command
function M.command(cmd, port)
  local Snacks = get_snacks()
  local full_cmd = M.make_idf_command(cmd, port)

  local terminal_opts = {
    win = {
      width = 0.6,
      height = 0.7,
      border = "single",
      title = "Ctrl + ] to stop",
      title_pos = "center",
    },
  }

  if cmd == "monitor" then
    Snacks.terminal.toggle(full_cmd, terminal_opts)
  else
    Snacks.terminal.open(full_cmd, terminal_opts)
  end
end

--- Run idf.py build
function M.build()
  M.command("build")
end

-- Setup build command for Neovim
vim.api.nvim_create_user_command("ESPBuild", function()
  M.build()
end, {})

--- Extract target names from `idf.py --list-targets` output
function M.parse_targets(output)
  local items = {}

  -- Only keep bare target names from the external command. Anything else would
  -- become a picker entry and, via confirm(), reach a terminal shell.
  for line in (output or ""):gmatch("[^\r\n]+") do
    local target = line:match("^%s*(esp%w+)%s*$")
    if target then
      table.insert(items, { text = target })
    end
  end

  if #items == 0 then
    return nil
  end

  return items
end

--- List the targets supported by the installed ESP-IDF
---
--- idf.py checks its environment on every run, which takes long enough to be
--- noticeable, so this runs in the background and hands the parsed targets (or
--- nil) to on_targets on the main loop.
function M.get_targets(on_targets)
  local cmd = M.resolve_idf_argv()
  table.insert(cmd, "--list-targets")

  vim.system(cmd, { text = true }, function(result)
    -- idf.py reports environment problems on stderr; only stdout can hold
    -- targets.
    local parsed = M.parse_targets(result.stdout)
    vim.schedule(function()
      on_targets(parsed)
    end)
  end)
end

local function open_target_picker()
  local Snacks = get_snacks()
  Snacks.picker.pick({
    ui_select = true,
    items = targets,
    layout = {
      layout = {
        box = "horizontal",
        width = 0.2,
        height = 0.3,
        {
          box = "vertical",
          border = "single",
          title = "Select ESP32 target",
          { win = "input", height = 1,     border = "bottom" },
          { win = "list",  border = "none" },
        },
      },
    },
    format = function(item)
      return { { item.text } }
    end,
    confirm = function(picker, item)
      picker:close()
      if not item then
        return
      end
      M.change_target(item.text)
    end,
  })
end

--- Pick a target and run idf.py set-target
function M.set_target()
  -- Cached for the session: the target list only changes with the ESP-IDF
  -- install, and querying it starts a full idf.py.
  if targets then
    open_target_picker()
    return
  end

  M.get_targets(function(found)
    if not found then
      vim.notify("[ESP32] No targets found.", vim.log.levels.WARN)
      return
    end

    targets = found
    open_target_picker()
  end)
end

--- Create Snacks picker for port and run idf.py command
function M.pick(cmd)
  local Snacks = get_snacks()
  Snacks.picker.pick({
    prompt = "Select ESP32 port",
    ui_select = true,
    focus = "list",
    finder = M.list_ports,
    layout = {
      layout = {
        box = "horizontal",
        width = 0.2,
        height = 0.2,
        {
          box = "vertical",
          border = "single",
          title = "USB Serial Ports",
          { win = "input", height = 1,     border = "bottom" },
          { win = "list",  border = "none" },
        },
      },
    },
    format = function(item)
      local a = Snacks.picker.util.align
      return { { a(item.port, 20, { align = "left" }) } }
    end,
    confirm = function(picker, item)
      picker:close()
      M.state.last_port = item.port
      M.command(cmd, item.port)
    end,
  })
end

--- Finish an idf.py operation that replaces the clang compile database
local function complete_project_change(root, status, terminal, failure_label, success_message)
  if status ~= 0 then
    vim.notify(
      "[ESP32] " .. failure_label .. " failed with exit code " .. tostring(status) .. ".\nCheck the terminal output.",
      vim.log.levels.ERROR
    )
    return false
  end

  if terminal and type(terminal.close) == "function" then
    terminal:close()
  end
  vim.cmd.checktime()

  if M.restart_clangd(root) then
    vim.notify("[ESP32] " .. success_message .. ", restarting clangd.", vim.log.levels.INFO)
  end

  return true
end

--- Finish an idf.py reconfigure after its terminal exits
---
--- clangd only reads --compile-commands-dir at startup, so a regenerated build
--- directory does not reach a running server. Restart it once idf.py succeeds.
function M.complete_reconfigure(root, status, terminal)
  return complete_project_change(root, status, terminal, "Reconfigure", "Reconfigured")
end

--- Finish an idf.py set-target after its terminal exits
function M.complete_target_change(root, status, terminal)
  return complete_project_change(root, status, terminal, "Set target", "Target changed")
end

--- Change the project target while keeping a clang compile database
function M.change_target(target)
  if type(target) ~= "string" or not target:match("^esp%w+$") then
    vim.notify("[ESP32] Invalid target.", vim.log.levels.ERROR)
    return false
  end

  local Snacks = get_snacks()
  local root = M.project_root()

  -- set-target clears and regenerates the build directory, so let the new
  -- clangd client check it again.
  checked_roots = {}

  local terminal = Snacks.terminal.open(
    M.make_idf_argv({ "-D", "IDF_TOOLCHAIN=clang", "set-target", target }, nil, { include_port = false }),
    {
      auto_close = false,
      win = {
        width = 0.5,
        height = 0.4,
        title = "ESP-IDF Set Target",
        title_pos = "center",
      },
    }
  )

  local bufnr = type(terminal) == "table" and terminal.buf
  if not bufnr then
    return false
  end

  vim.api.nvim_create_autocmd("TermClose", {
    buffer = bufnr,
    once = true,
    callback = function()
      M.complete_target_change(root, vim.v.event.status, terminal)
    end,
  })

  return true
end

--- Run idf.py reconfigure for build.clang
---
--- Keep the terminal alive until our TermClose handler sees the exit status.
--- Snacks otherwise removes a successful terminal before later handlers run.
function M.reconfigure()
  local Snacks = get_snacks()
  local root = M.project_root()

  -- The build dir is about to change, so let it be reported on again.
  checked_roots = {}

  local terminal = Snacks.terminal.open(M.make_idf_command("-D IDF_TOOLCHAIN=clang reconfigure"), {
    auto_close = false,
    win = {
      width = 0.5,
      height = 0.4,
      title = "ESP-IDF Reconfigure",
      title_pos = "center",
    },
  })

  local bufnr = type(terminal) == "table" and terminal.buf
  if not bufnr then
    return
  end

  vim.api.nvim_create_autocmd("TermClose", {
    buffer = bufnr,
    once = true,
    callback = function()
      M.complete_reconfigure(root, vim.v.event.status, terminal)
    end,
  })
end

--- Build the clangd command for a project root
---
--- Public so the resolved command stays inspectable: lsp_config() passes cmd as
--- a function, which :checkhealth reports only as <function>.
function M.clangd_cmd(root, opts)
  local clangd = M.find_esp_clangd()
  if not clangd then
    -- Reporting belongs to starting a server, not to inspecting the command.
    if not (opts and opts.silent) then
      vim.notify("[ESP32] No esp-clangd found. Falling back to system clangd.", vim.log.levels.WARN)
    end
    clangd = "clangd"
  end

  local cmd = {
    clangd,
    -- Absolute where a root is known: clangd resolves this against its own
    -- working directory, which Neovim documents as unrelated to root_dir.
    "--compile-commands-dir=" .. build_dir_for(root),
    "--background-index",
    "--clang-tidy",
    "--header-insertion=iwyu",
    "--completion-style=detailed",
    -- clangd 20 rejects the bare flag and wants an explicit boolean.
    "--function-arg-placeholders=true",
    "--fallback-style=llvm",
  }

  vim.list_extend(cmd, M.options.clangd_args or {})

  return cmd
end

--- Set up ESP32 LSP configuration
function M.lsp_config()
  return {
    -- A function rather than a list so the build directory can be resolved
    -- against the project root, which is only known once a client is created
    -- for it. Same shape as nvim-lspconfig's own jsonls and ruby_lsp configs.
    cmd = function(dispatchers, config)
      local root = config and config.root_dir

      return vim.lsp.rpc.start(M.clangd_cmd(root), dispatchers, {
        cwd = (config and config.cmd_cwd) or root,
        env = config and config.cmd_env,
        detached = config and config.detached,
      })
    end,
    -- Prefer the ESP-IDF project root and avoid falling back to a parent git
    -- repository, which breaks nested projects/monorepos.
    root_markers = root_markers,
    capabilities = make_clangd_capabilities(),
    init_options = {
      usePlaceholders = true,
      completeUnimported = true,
      clangdFileStatus = true,
    },
  }
end

--- Show ESP32 setup info
function M.info()
  local messages = {}

  -- clangd check
  if M.find_esp_clangd() then
    table.insert(messages, "✓ Found esp-clangd")
  else
    table.insert(messages, "✗ ESP-specific clangd missing")
  end

  -- compile_commands.json check, against the same project the LSP uses
  local root = M.project_root()
  local path = compile_commands_path(root)
  if vim.fn.filereadable(path) == 1 then
    local toolchain = M.compile_commands_toolchain(root)
    if toolchain == "clang" then
      table.insert(messages, "✓ compile_commands.json exists")
    elseif toolchain == "gcc" then
      table.insert(messages, "✗ compile_commands.json was generated for GCC, run :ESPReconfigure")
    else
      -- Unrecognised is not the same as healthy; say so rather than imply a
      -- clang database.
      table.insert(messages, "? compile_commands.json exists, unrecognised compiler")
    end
  else
    table.insert(messages, "✗ compile_commands.json missing in " .. path)
  end

  table.insert(messages, "clangd: " .. table.concat(M.clangd_cmd(root, { silent = true }), " "))

  -- Check ESP-IDF environment
  local function check_bin(bin)
    return vim.fn.executable(bin) == 1 and "✓" or "✗"
  end

  local has_idf_cmd = M.resolve_idf_cmd() ~= "idf.py" or check_bin("idf.py") == "✓"
  table.insert(messages, (has_idf_cmd and "✓" or "✗") .. " idf.py")
  table.insert(messages, check_bin("llvm-ar") .. " llvm-ar")
  table.insert(messages, "IDF_PATH: " .. (vim.env.IDF_PATH or "✗ not set"))

  if vim.env.IDF_PATH == nil then
    table.insert(messages, "⚠️ Source an ESP-IDF environment before launching Neovim:")
    if is_windows() then
      table.insert(messages, [[. C:\Espressif\tools\Microsoft.<version>.PowerShell_profile.ps1]])
    else
      table.insert(messages, "source ~/.espressif/tools/activate_idf_<version>.sh")
      table.insert(messages, "or source ~/esp/esp-idf/export.sh")
    end
  end

  vim.notify(table.concat(messages, "\n"), vim.log.levels.INFO)
end

-- Setup custom commands for Neovim
vim.api.nvim_create_user_command("ESPReconfigure", function()
  M.reconfigure()
end, {})

vim.api.nvim_create_user_command("ESPInfo", function()
  M.info()
end, {})

vim.api.nvim_create_user_command("ESPSetTarget", function()
  M.set_target()
end, {})

return M
