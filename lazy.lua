return {
  "Aietes/esp32.nvim",
  name = "esp32.nvim",
  main = "esp32",
  dependencies = {
    "folke/snacks.nvim",
  },
  specs = {
    {
      "folke/which-key.nvim",
      optional = true,
      opts = {
        spec = {
          { "<leader>R", group = "ESP32", icon = { icon = "󰍛", color = "red" } },
        },
      },
    },
  },
  opts = {
    build_dir = "build.clang",
  },
  keys = {
    { "<leader>R",  group = "ESP32" },
    {
      "<leader>Rb",
      function()
        require("esp32").build()
      end,
      desc = "ESP32: Build",
    },
    {
      "<leader>RM",
      function()
        require("esp32").pick("monitor")
      end,
      desc = "ESP32: Pick & Monitor",
    },
    {
      "<leader>Rm",
      function()
        require("esp32").command("monitor")
      end,
      desc = "ESP32: Monitor",
    },
    {
      "<leader>RF",
      function()
        require("esp32").pick("flash")
      end,
      desc = "ESP32: Pick & Flash",
    },
    {
      "<leader>Rf",
      function()
        require("esp32").command("flash")
      end,
      desc = "ESP32: Flash",
    },
    {
      "<leader>Rc",
      function()
        require("esp32").command("menuconfig")
      end,
      desc = "ESP32: Configure",
    },
    {
      "<leader>RC",
      function()
        require("esp32").command("clean")
      end,
      desc = "ESP32: Clean",
    },
    { "<leader>Rr", ":ESPReconfigure<CR>", desc = "ESP32: Reconfigure project" },
    { "<leader>Ri", ":ESPInfo<CR>",        desc = "ESP32: Project Info" },
  },
}
