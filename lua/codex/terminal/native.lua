--- Native Neovim terminal provider for codex.nvim.
--- Manages a single split window running the Codex CLI. State is module-local
--- (there is only ever one Codex terminal at a time).
local logger = require("codex.logger")

local M = {}

--- @type table
local state = {
  bufnr = nil, ---@type integer? terminal buffer
  winid = nil, ---@type integer? window showing the terminal (nil when hidden)
  chan = nil, ---@type integer? terminal job channel id
  job = nil, ---@type integer? jobstart id
}

local function win_valid()
  return state.winid ~= nil and vim.api.nvim_win_is_valid(state.winid)
end

local function buf_valid()
  return state.bufnr ~= nil and vim.api.nvim_buf_is_valid(state.bufnr)
end

--- @return boolean
function M.is_running()
  return state.job ~= nil and buf_valid()
end

--- @return boolean
function M.is_open()
  return win_valid()
end

--- @return integer?
function M.get_bufnr()
  return buf_valid() and state.bufnr or nil
end

--- Open the split window (creating it) and return its id.
---@param cfg CodexConfig
---@return integer winid
local function open_split(cfg)
  local width = math.floor(vim.o.columns * cfg.terminal.split_width_percentage)
  local side = cfg.terminal.split_side == "left" and "topleft" or "botright"
  vim.cmd(("%s vertical %dnew"):format(side, width))
  return vim.api.nvim_get_current_win()
end

--- Show the existing terminal buffer in a fresh split.
---@param cfg CodexConfig
local function show(cfg)
  if win_valid() then
    return
  end
  local winid = open_split(cfg)
  vim.api.nvim_win_set_buf(winid, state.bufnr)
  state.winid = winid
  vim.wo[winid].number = false
  vim.wo[winid].relativenumber = false
  vim.wo[winid].signcolumn = "no"
  if cfg.terminal.auto_insert then
    vim.cmd("startinsert")
  end
end

--- Start a new codex process in a new terminal split.
---@param cmd string[] full argv (codex + args)
---@param env table<string,string>
---@param cfg CodexConfig
function M.open(cmd, env, cfg)
  if M.is_running() then
    M.focus(cfg)
    return
  end

  local winid = open_split(cfg)
  local bufnr = vim.api.nvim_create_buf(false, false)
  vim.api.nvim_win_set_buf(winid, bufnr)
  state.winid = winid
  state.bufnr = bufnr

  local job_opts = {
    cwd = vim.fn.getcwd(),
    env = next(env) and env or nil,
    on_exit = function(_, code)
      logger.debug("codex process exited (code=%s)", tostring(code))
      state.job = nil
      state.chan = nil
      if cfg.terminal.auto_close then
        M.close()
      end
    end,
  }
  -- jobstart({term=true}) is Neovim 0.11+; fall back to termopen on older versions.
  -- Both attach the terminal to the current buffer (already set above).
  if vim.fn.has("nvim-0.11") == 1 then
    job_opts.term = true
    state.chan = vim.fn.jobstart(cmd, job_opts)
  else
    state.chan = vim.fn.termopen(cmd, job_opts)
  end

  if not state.chan or state.chan <= 0 then
    logger.error("failed to start codex (is %q on your PATH?)", cmd[1])
    M.close()
    return
  end
  state.job = state.chan

  vim.wo[winid].number = false
  vim.wo[winid].relativenumber = false
  vim.wo[winid].signcolumn = "no"
  vim.bo[bufnr].filetype = "codex_terminal"
  if cfg.terminal.auto_insert then
    vim.cmd("startinsert")
  end
end

--- Close/hide the split window. Keeps the process alive (buffer is hidden).
function M.close()
  if win_valid() then
    vim.api.nvim_win_close(state.winid, true)
  end
  state.winid = nil
  if not M.is_running() and buf_valid() then
    vim.api.nvim_buf_delete(state.bufnr, { force = true })
    state.bufnr = nil
  end
end

--- Focus the terminal window, opening the split if hidden.
---@param cfg CodexConfig
function M.focus(cfg)
  if not win_valid() then
    show(cfg)
  end
  if win_valid() then
    vim.api.nvim_set_current_win(state.winid)
    if cfg.terminal.auto_insert then
      vim.cmd("startinsert")
    end
  end
end

--- Toggle window visibility (process stays alive when hidden).
---@param cfg CodexConfig
function M.toggle(cfg)
  if win_valid() then
    M.close()
  elseif buf_valid() then
    show(cfg)
  else
    -- nothing running; caller decides whether to spawn
    return false
  end
  return true
end

--- Type text into the running codex process.
---@param text string
---@param submit boolean  append a carriage return to submit
---@return boolean ok
function M.send(text, submit)
  if not M.is_running() then
    return false
  end
  vim.fn.chansend(state.chan, text)
  if submit then
    vim.fn.chansend(state.chan, "\r")
  end
  return true
end

return M
