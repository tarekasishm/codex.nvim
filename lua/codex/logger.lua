--- Minimal leveled logger for codex.nvim.
local M = {}

local LEVELS = { trace = 0, debug = 1, info = 2, warn = 3, error = 4, off = 5 }

M._level = LEVELS.info

--- Set the active log level from a string ("trace"|"debug"|"info"|"warn"|"error"|"off").
---@param level string
function M.set_level(level)
  M._level = LEVELS[level] or LEVELS.info
end

local function log(level, msg, ...)
  if LEVELS[level] < M._level then
    return
  end
  local text = select("#", ...) > 0 and string.format(msg, ...) or msg
  local vim_level = ({
    trace = vim.log.levels.TRACE,
    debug = vim.log.levels.DEBUG,
    info = vim.log.levels.INFO,
    warn = vim.log.levels.WARN,
    error = vim.log.levels.ERROR,
  })[level] or vim.log.levels.INFO
  vim.schedule(function()
    vim.notify("[codex] " .. text, vim_level)
  end)
end

function M.trace(msg, ...) log("trace", msg, ...) end
function M.debug(msg, ...) log("debug", msg, ...) end
function M.info(msg, ...) log("info", msg, ...) end
function M.warn(msg, ...) log("warn", msg, ...) end
function M.error(msg, ...) log("error", msg, ...) end

return M
