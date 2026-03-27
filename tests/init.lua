vim.opt.rtp:prepend(vim.fn.fnamemodify("./tests/deps/mini.nvim", ":p"))
vim.opt.rtp:prepend(vim.fn.fnamemodify(".", ":p"))

local mini_test = require("mini.test")
require("tests.esp32_spec")

mini_test.run_file("tests/esp32_spec.lua")
