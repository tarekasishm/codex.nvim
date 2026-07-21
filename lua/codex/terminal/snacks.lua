--- snacks.nvim terminal provider for codex.nvim.
--- Thin wrapper over Snacks.terminal that mirrors the native provider's API.
local logger = require("codex.logger")

local M = {}

--- @type snacks.win? the cached Codex terminal object
local term = nil

--- @return boolean
function M.available()
  local ok, snacks = pcall(require, "snacks")
  return ok and snacks.terminal ~= nil
end

local function term_valid()
  return term ~= nil and term.buf ~= nil and vim.api.nvim_buf_is_valid(term.buf)
end

--- @return boolean
function M.is_running()
  return term_valid()
end

--- @return boolean
function M.is_open()
  return term_valid() and term:valid() and term.win ~= nil and vim.api.nvim_win_is_valid(term.win)
end

--- @return integer?
function M.get_bufnr()
  return term_valid() and term.buf or nil
end

---@param cfg CodexConfig
---@return snacks.terminal.Opts
local function snacks_opts(cfg)
  return {
    cwd = vim.fn.getcwd(),
    env = next(cfg.env) and cfg.env or nil,
    auto_close = cfg.terminal.auto_close,
    start_insert = cfg.terminal.auto_insert,
    win = {
      position = cfg.terminal.split_side,
      width = cfg.terminal.split_width_percentage,
    },
  }
end

--- @param cmd string[]
--- @param env table<string,string>
--- @param cfg CodexConfig
function M.open(cmd, env, cfg)
  local Snacks = require("snacks")
  cfg = vim.tbl_deep_extend("force", cfg, { env = env })
  term = Snacks.terminal.open(cmd, snacks_opts(cfg))
  if not term then
    logger.error("snacks.terminal failed to open codex")
  end
end

function M.close()
  if term_valid() then
    term:hide()
  end
end

---@param cfg CodexConfig
function M.focus(cfg)
  if term_valid() then
    term:show()
    if term.win and vim.api.nvim_win_is_valid(term.win) then
      vim.api.nvim_set_current_win(term.win)
      if cfg.terminal.auto_insert then
        vim.cmd("startinsert")
      end
    end
  end
end

---@param cfg CodexConfig
---@return boolean handled
function M.toggle(cfg)
  if not term_valid() then
    return false
  end
  term:toggle()
  return true
end

--- @param text string
--- @param submit boolean
--- @return boolean ok
function M.send(text, submit)
  if not term_valid() then
    return false
  end
  local chan = vim.b[term.buf].terminal_job_id
  if not chan then
    return false
  end
  vim.fn.chansend(chan, text)
  if submit then
    vim.fn.chansend(chan, "\r")
  end
  return true
end

return M
