# Installation methods

ESP32.nvim requires [snacks.nvim](https://github.com/folke/snacks.nvim) for its
terminals and pickers. A complete LSP setup also uses
[nvim-lspconfig](https://github.com/neovim/nvim-lspconfig) for clangd's base
filetype configuration.

The installation method determines who installs dependencies, calls `setup()`,
and creates keymaps.

## lazy.nvim

```lua
{
  "Aietes/esp32.nvim",
}
```

ESP32.nvim ships a
[lazy.nvim package spec](https://lazy.folke.io/packages). With lazy.nvim's
default package sources enabled, that spec:

- installs `folke/snacks.nvim`
- calls `require("esp32").setup({ build_dir = "build.clang" })`
- adds all documented default keymaps
- adds an ESP32 group to which-key.nvim when which-key is already installed

The spec does not install or configure `nvim-lspconfig`. LazyVim already
provides it; other lazy.nvim setups should install it separately if they want
clangd:

```lua
{
  "neovim/nvim-lspconfig",
}
```

Then connect ESP32.nvim's configuration as described in
[LSP configuration](lsp.md).

## Native `vim.pack`

Neovim 0.12 introduced the built-in `vim.pack` plugin manager. Add the complete
set to `init.lua`:

```lua
vim.pack.add({
  "https://github.com/folke/snacks.nvim",
  "https://github.com/neovim/nvim-lspconfig",
  "https://github.com/Aietes/esp32.nvim",
})

require("snacks").setup({})
require("esp32").setup()

vim.lsp.config("clangd", require("esp32").lsp_config())
vim.lsp.enable("clangd")
```

The [official `vim.pack` documentation](https://neovim.io/doc/user/pack.html#vim.pack)
currently describes the manager as experimental but stable enough for daily
use. It requires Git and records installed revisions in
`stdpath("config") .. "/nvim-pack-lock.json"`.

To update:

```vim
:packupdate
```

Review the proposed changes and use `:write` to accept them. Keep the lockfile
under version control with the rest of the Neovim configuration.

Unlike lazy.nvim, `vim.pack` does not consume this repository's `lazy.lua`
package spec. It therefore does not create ESP32 keymaps or configure
which-key. Add only the mappings you use:

```lua
vim.keymap.set("n", "<leader>Rb", require("esp32").build, {
  desc = "ESP32: Build",
})

vim.keymap.set("n", "<leader>Rf", function()
  require("esp32").pick("flash")
end, {
  desc = "ESP32: Pick & Flash",
})
```

The user commands `:ESPBuild`, `:ESPReconfigure`, `:ESPInfo`, and
`:ESPSetTarget` are registered when the ESP32 module is loaded.

## Other plugin managers

With another manager, apply the same contract using its normal dependency and
configuration syntax:

1. Install `folke/snacks.nvim`.
2. Install `Aietes/esp32.nvim`.
3. Install `neovim/nvim-lspconfig` when using the LSP integration.
4. Call `require("snacks").setup({})`.
5. Call `require("esp32").setup(opts)` with any overrides.
6. Register and enable the [ESP32 clangd configuration](lsp.md).
7. Add your preferred keymaps; the lazy.nvim defaults are not applied.

Do not copy the contents of `lazy.lua` into another manager verbatim. It is a
lazy.nvim package specification, not the plugin's general configuration API.
