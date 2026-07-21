--- Transcript UI for the app-server (Phase 2) integration.
--- Renders streamed thread items into a scratch buffer shown in a split.
local M = {}

--- @type table
local state = {
  bufnr = nil, ---@type integer?
  winid = nil, ---@type integer?
  cfg = nil, ---@type CodexConfig?
  -- streaming block currently being rendered:
  cur_kind = nil, ---@type string?
  cur_id = nil, ---@type string?
  cur_start = nil, ---@type integer? 0-indexed line where the block's content begins
  cur_text = "",
}

local function buf_valid()
  return state.bufnr ~= nil and vim.api.nvim_buf_is_valid(state.bufnr)
end

local function win_valid()
  return state.winid ~= nil and vim.api.nvim_win_is_valid(state.winid)
end

--- Run `fn` with the transcript buffer temporarily modifiable.
---@param fn fun()
local function edit(fn)
  if not buf_valid() then
    return
  end
  vim.bo[state.bufnr].modifiable = true
  local ok, err = pcall(fn)
  vim.bo[state.bufnr].modifiable = false
  if not ok then
    require("codex.logger").error("ui render error: %s", tostring(err))
  end
end

local function line_count()
  return vim.api.nvim_buf_line_count(state.bufnr)
end

--- Append lines at the end of the buffer.
---@param lines string[]
local function append(lines)
  edit(function()
    vim.api.nvim_buf_set_lines(state.bufnr, -1, -1, false, lines)
  end)
end

--- Scroll the transcript window to the bottom.
local function scroll_bottom()
  if win_valid() then
    vim.api.nvim_win_set_cursor(state.winid, { line_count(), 0 })
  end
end

--- Ensure the transcript buffer exists.
---@param cfg CodexConfig
function M.ensure_buffer(cfg)
  state.cfg = cfg
  if buf_valid() then
    return
  end
  state.bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_name(state.bufnr, "codex://transcript")
  vim.bo[state.bufnr].filetype = "markdown"
  vim.bo[state.bufnr].buftype = "nofile"
  vim.bo[state.bufnr].swapfile = false
  vim.bo[state.bufnr].modifiable = false
  append({ "# Codex", "" })
end

--- Open (or focus) the transcript split.
---@param cfg CodexConfig
function M.open(cfg)
  M.ensure_buffer(cfg)
  if win_valid() then
    vim.api.nvim_set_current_win(state.winid)
    return
  end
  local width = math.floor(vim.o.columns * cfg.terminal.split_width_percentage)
  local side = cfg.terminal.split_side == "left" and "topleft" or "botright"
  vim.cmd(("%s vertical %dnew"):format(side, width))
  state.winid = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(state.winid, state.bufnr)
  vim.wo[state.winid].number = false
  vim.wo[state.winid].relativenumber = false
  vim.wo[state.winid].signcolumn = "no"
  vim.wo[state.winid].wrap = true
  vim.wo[state.winid].linebreak = true
  scroll_bottom()
end

function M.close()
  if win_valid() then
    vim.api.nvim_win_close(state.winid, true)
  end
  state.winid = nil
end

--- @return boolean
function M.is_open()
  return win_valid()
end

--- Set the winbar (used for status / token usage).
---@param text string
function M.set_winbar(text)
  if win_valid() then
    pcall(function()
      vim.wo[state.winid].winbar = text:gsub("%%", "%%%%")
    end)
  end
end

-- ---------------------------------------------------------------------------
-- Streaming block management
-- ---------------------------------------------------------------------------

--- Finalize any open streaming block.
local function close_block()
  if state.cur_kind then
    append({ "" })
    state.cur_kind = nil
    state.cur_id = nil
    state.cur_start = nil
    state.cur_text = ""
  end
end

--- Begin a streaming block with a header; content is rendered under it.
---@param kind string
---@param id string
---@param header string
local function begin_block(kind, id, header)
  close_block()
  append({ header })
  state.cur_kind = kind
  state.cur_id = id
  state.cur_start = line_count() -- 0-indexed line where content starts (append below)
  state.cur_text = ""
  append({ "" })
  scroll_bottom()
end

--- Append delta text to the current streaming block, re-rendering its content.
---@param kind string
---@param id string
---@param header string
---@param delta string
local function stream(kind, id, header, delta)
  if state.cur_kind ~= kind or state.cur_id ~= id then
    begin_block(kind, id, header)
  end
  state.cur_text = state.cur_text .. delta
  edit(function()
    local lines = vim.split(state.cur_text, "\n", { plain = true })
    vim.api.nvim_buf_set_lines(state.bufnr, state.cur_start, -1, false, lines)
  end)
  scroll_bottom()
end

-- ---------------------------------------------------------------------------
-- Public semantic render API (called by codex.session)
-- ---------------------------------------------------------------------------

--- Render the user's outgoing message.
---@param text string
function M.user_message(text)
  close_block()
  local lines = { "---", "", "### You", "" }
  vim.list_extend(lines, vim.split(text, "\n", { plain = true }))
  vim.list_extend(lines, { "", "### Codex", "" })
  append(lines)
  scroll_bottom()
end

--- Streamed agent message text.
---@param id string
---@param delta string
function M.agent_delta(id, delta)
  stream("agent", id, "", delta)
end

--- Streamed reasoning text (optional; controlled by config).
---@param id string
---@param delta string
function M.reasoning_delta(id, delta)
  if state.cfg and state.cfg.app_server and state.cfg.app_server.show_reasoning then
    stream("reasoning", id, "> _thinking_", delta)
  end
end

--- A command the agent is executing.
---@param id string
---@param command string
function M.command_started(id, command)
  begin_block("command", id, "```console")
  state.cur_text = "$ " .. command .. "\n"
  edit(function()
    vim.api.nvim_buf_set_lines(state.bufnr, state.cur_start, -1, false, vim.split(state.cur_text, "\n", { plain = true }))
  end)
end

--- Streamed command output.
---@param id string
---@param delta string
function M.command_output(id, delta)
  if state.cur_kind == "command" and state.cur_id == id then
    state.cur_text = state.cur_text .. delta
    edit(function()
      vim.api.nvim_buf_set_lines(state.bufnr, state.cur_start, -1, false, vim.split(state.cur_text, "\n", { plain = true }))
    end)
    scroll_bottom()
  end
end

--- Command finished.
---@param id string
---@param status string
---@param exit_code integer?
function M.command_completed(id, status, exit_code)
  if state.cur_kind == "command" and state.cur_id == id then
    append({ "```", ("_exit: %s (%s)_"):format(tostring(exit_code), status), "" })
    state.cur_kind = nil
    state.cur_id = nil
    scroll_bottom()
  end
end

--- A file change / patch.
---@param changes table[] list of { path, kind, diff }
function M.file_change(changes)
  close_block()
  local lines = { "#### File changes", "" }
  for _, c in ipairs(changes or {}) do
    table.insert(lines, ("- `%s` (%s)"):format(c.path or "?", c.kind or "edit"))
  end
  table.insert(lines, "")
  for _, c in ipairs(changes or {}) do
    if c.diff and c.diff ~= "" then
      table.insert(lines, "```diff")
      vim.list_extend(lines, vim.split(c.diff, "\n", { plain = true }))
      table.insert(lines, "```")
      table.insert(lines, "")
    end
  end
  append(lines)
  scroll_bottom()
end

--- Render an error line.
---@param msg string
function M.error(msg)
  close_block()
  append({ ("> **error:** %s"):format(msg), "" })
  scroll_bottom()
end

--- Turn finished — close any open block.
function M.turn_completed()
  close_block()
  scroll_bottom()
end

--- Free a note into the transcript (system/status messages).
---@param msg string
function M.note(msg)
  close_block()
  append({ ("_%s_"):format(msg), "" })
  scroll_bottom()
end

return M
