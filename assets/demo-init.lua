-- Minimal init used only for recording assets/demo.gif (see assets/demo.tape).
-- Launch with: nvim -u assets/demo-init.lua <file>  (from the repo root)
vim.opt.rtp:append(vim.fn.getcwd())
vim.o.number = true
vim.o.signcolumn = "no"
vim.o.laststatus = 0
vim.o.cmdheight = 1

require("codex").setup({
  terminal = { split_side = "right", split_width_percentage = 0.45 },
  app_server = {
    sandbox = "read-only",
    approval_policy = "never",
    show_reasoning = false,
  },
})
