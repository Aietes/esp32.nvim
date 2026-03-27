## Running tests

This test suite uses `mini.test`.

1. Clone `mini.nvim` into `tests/deps/mini.nvim`

```bash
mkdir -p tests/deps
git clone https://github.com/echasnovski/mini.nvim tests/deps/mini.nvim
```

2. Run the suite in headless Neovim:

```bash
nvim --headless -u NONE -c "luafile tests/init.lua"
```
