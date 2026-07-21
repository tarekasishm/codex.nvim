--- codex.nvim — embed the OpenAI Codex CLI in Neovim.
---
--- Phase 1: an embedded-terminal integration. Toggle the Codex TUI in a split
--- and push editor context (selections / files) into it. A deeper app-server
--- (JSON-RPC) integration is planned for phase 2.
local config = require("codex.config")
local terminal = require("codex.terminal")
local context = require("codex.context")
local logger = require("codex.logger")

local M = {}

--- @type CodexConfig?
M.config = nil

--- @return boolean
local function ensure_setup()
  if not M.config then
    M.setup({})
  end
  return M.config ~= nil
end

--- Initialize the plugin.
---@param opts CodexConfig?
function M.setup(opts)
  M.config = config.merge(opts)
  logger.set_level(M.config.log_level)
  terminal.setup(M.config)
  require("codex.commands").create(M)
  if M.config.auto_start then
    terminal.open()
  end
end

--- Toggle the Codex terminal (spawns codex if not running).
---@param extra string[]?
function M.toggle(extra)
  ensure_setup()
  terminal.toggle(extra)
end

--- Open / focus the Codex terminal.
---@param extra string[]?
function M.open(extra)
  ensure_setup()
  terminal.open(extra)
end

function M.focus()
  ensure_setup()
  terminal.focus()
end

function M.close()
  ensure_setup()
  terminal.close()
end

--- Send arbitrary text to Codex.
---@param text string
---@param submit boolean?
function M.send_text(text, submit)
  ensure_setup()
  if text == nil or text == "" then
    return
  end
  terminal.send(text, submit)
end

--- Send a selection (line range) or the current file as context.
--- When invoked with a range, sends the snippet; otherwise an @-file mention.
---@param opts table Neovim user-command opts (range, line1, line2) or nil
function M.send_selection(opts)
  ensure_setup()
  opts = opts or {}
  local text
  if opts.range and opts.range > 0 then
    local sel = context.get_range(opts.line1, opts.line2)
    if not sel then
      logger.warn("no selection to send")
      return
    end
    text = context.format_selection(sel)
  else
    local file = context.current_file()
    if not file then
      logger.warn("current buffer has no file to send")
      return
    end
    text = context.format_file(file) .. "\n"
  end
  terminal.send(text, M.config.send_submit)
end

--- Add a file (or the current file) to the Codex context as an @-mention.
---@param path string?
function M.add(path)
  ensure_setup()
  path = (path and path ~= "") and vim.fn.fnamemodify(path, ":.") or context.current_file()
  if not path then
    logger.warn("no file path to add")
    return
  end
  terminal.send(context.format_file(path) .. "\n", M.config.send_submit)
end

--- @return table status { running, open, provider }
function M.status()
  ensure_setup()
  local running, open, provider = terminal.status()
  return { running = running, open = open, provider = provider }
end

-- ---------------------------------------------------------------------------
-- Phase 2: app-server (JSON-RPC) chat
-- ---------------------------------------------------------------------------

--- Open the app-server transcript window (starts the server lazily).
function M.chat()
  ensure_setup()
  require("codex.session").open(M.config)
end

--- Send a message to Codex over the app-server and stream the reply.
---@param text string
function M.ask(text)
  ensure_setup()
  require("codex.session").ask(text, M.config)
end

--- Send the current selection/file to the app-server chat, prompting for a question.
---@param opts table user-command opts (range/line1/line2)
function M.chat_send(opts)
  ensure_setup()
  opts = opts or {}
  local snippet
  if opts.range and opts.range > 0 then
    local sel = context.get_range(opts.line1, opts.line2)
    if not sel then
      logger.warn("no selection to send")
      return
    end
    snippet = context.format_selection(sel)
  else
    local file = context.current_file()
    snippet = file and (context.format_file(file) .. "\n") or ""
  end
  vim.ui.input({ prompt = "Ask Codex: " }, function(question)
    if not question or vim.trim(question) == "" then
      return
    end
    require("codex.session").ask(question .. "\n\n" .. snippet, M.config)
  end)
end

--- Interrupt the in-flight app-server turn.
function M.interrupt()
  ensure_setup()
  require("codex.session").interrupt()
end

--- Stop the app-server process.
function M.stop_server()
  ensure_setup()
  require("codex.session").stop()
end

--- @return table app-server session status
function M.server_status()
  ensure_setup()
  return require("codex.session").status()
end

return M
