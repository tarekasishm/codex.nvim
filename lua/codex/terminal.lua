--- Terminal provider dispatcher for codex.nvim.
--- Selects a concrete provider (native / snacks) and delegates lifecycle calls.
local logger = require("codex.logger")

local M = {}

--- @type CodexConfig
local config = nil
--- @type table active provider module
local provider = nil

--- Resolve the provider module from config.
---@param cfg CodexConfig
---@return table
local function resolve_provider(cfg)
  local name = cfg.terminal.provider
  if name == "native" then
    return require("codex.terminal.native")
  end
  if name == "snacks" then
    local snacks = require("codex.terminal.snacks")
    if snacks.available() then
      return snacks
    end
    logger.warn("terminal.provider='snacks' but snacks.nvim not found; using native")
    return require("codex.terminal.native")
  end
  -- auto
  local snacks = require("codex.terminal.snacks")
  if snacks.available() then
    return snacks
  end
  return require("codex.terminal.native")
end

--- @param cfg CodexConfig
function M.setup(cfg)
  config = cfg
  provider = resolve_provider(cfg)
end

--- Build the argv passed to the terminal.
---@param extra string[]?
---@return string[]
local function build_cmd(extra)
  local cmd = { config.codex_cmd }
  vim.list_extend(cmd, config.args or {})
  if extra and #extra > 0 then
    vim.list_extend(cmd, extra)
  end
  return cmd
end

--- Open (spawn if needed) the codex terminal.
---@param extra string[]? extra args appended to the codex invocation
function M.open(extra)
  if provider.is_running() then
    provider.focus(config)
    return
  end
  provider.open(build_cmd(extra), config.env, config)
end

--- Toggle the terminal window; spawns a process if none exists.
---@param extra string[]?
function M.toggle(extra)
  if not provider.toggle(config) then
    provider.open(build_cmd(extra), config.env, config)
  end
end

function M.focus()
  if provider.is_running() then
    provider.focus(config)
  else
    provider.open(build_cmd(nil), config.env, config)
  end
end

function M.close()
  provider.close()
end

--- @return boolean
function M.is_running()
  return provider ~= nil and provider.is_running()
end

--- Wrap multi-line text in bracketed-paste markers so a TUI text input treats it
--- as pasted content instead of submitting on every embedded newline.
---@param text string
---@return string
local function prepare(text)
  if text:find("\n") then
    return "\27[200~" .. text .. "\27[201~"
  end
  return text
end

--- Send text to the running codex process, spawning one first if needed.
---@param text string
---@param submit boolean?
---@param on_ready fun()? optional callback after the process is ready
function M.send(text, submit, on_ready)
  submit = submit == nil and config.send_submit or submit
  text = prepare(text)
  if provider.is_running() then
    local ok = provider.send(text, submit)
    if ok and config.focus_after_send then
      provider.focus(config)
    end
    if on_ready then on_ready() end
    return ok
  end

  -- Not running: spawn, then send once the process has had a moment to start.
  provider.open(build_cmd(nil), config.env, config)
  vim.defer_fn(function()
    provider.send(text, submit)
    if config.focus_after_send then
      provider.focus(config)
    end
    if on_ready then on_ready() end
  end, 400)
  return true
end

--- @return boolean running, boolean open, string provider_name
function M.status()
  local name = config and config.terminal.provider or "?"
  if provider == require("codex.terminal.snacks") then
    name = "snacks"
  elseif provider == require("codex.terminal.native") then
    name = "native"
  end
  return M.is_running(), provider ~= nil and provider.is_open() or false, name
end

return M
