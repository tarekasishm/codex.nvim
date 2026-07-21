--- Configuration defaults and validation for codex.nvim.
local M = {}

--- @class CodexTerminalConfig
--- @field provider "auto"|"native"|"snacks"
--- @field split_side "left"|"right"
--- @field split_width_percentage number  -- 0.0 - 1.0
--- @field auto_close boolean             -- close the split when the codex process exits
--- @field auto_insert boolean            -- enter insert/terminal mode when the split is focused
--- @field hidden boolean                 -- (snacks) keep the buffer alive when toggled off

--- @class CodexAppServerConfig
--- @field args string[]              -- extra args appended to `codex app-server`
--- @field model string?              -- model override (e.g. "gpt-5-codex")
--- @field approval_policy string?    -- "untrusted"|"on-failure"|"on-request"|"never"
--- @field sandbox string?            -- "read-only"|"workspace-write"|"danger-full-access"
--- @field show_reasoning boolean     -- render reasoning/thinking deltas in the transcript

--- @class CodexConfig
--- @field codex_cmd string          -- executable name/path for the Codex CLI
--- @field args string[]             -- default args always passed to codex
--- @field env table<string,string>  -- extra environment variables for the codex process
--- @field auto_start boolean        -- open the terminal automatically on setup()
--- @field terminal CodexTerminalConfig
--- @field app_server CodexAppServerConfig
--- @field send_submit boolean       -- default: append newline (submit) when sending context
--- @field focus_after_send boolean  -- focus the terminal after sending context
--- @field log_level string          -- "trace"|"debug"|"info"|"warn"|"error"|"off"

--- @type CodexConfig
M.defaults = {
  codex_cmd = "codex",
  args = {},
  env = {},
  auto_start = false,
  terminal = {
    provider = "auto",
    split_side = "right",
    split_width_percentage = 0.40,
    auto_close = false,
    auto_insert = true,
    hidden = true,
  },
  app_server = {
    args = {},
    model = nil,
    approval_policy = nil,
    sandbox = nil,
    show_reasoning = false,
  },
  send_submit = false,
  focus_after_send = false,
  log_level = "info",
}

--- Validate a merged config, returning (ok, err).
---@param cfg CodexConfig
---@return boolean ok
---@return string? err
function M.validate(cfg)
  if type(cfg.codex_cmd) ~= "string" or cfg.codex_cmd == "" then
    return false, "codex_cmd must be a non-empty string"
  end
  if type(cfg.args) ~= "table" then
    return false, "args must be a list of strings"
  end
  if type(cfg.env) ~= "table" then
    return false, "env must be a table"
  end
  local t = cfg.terminal
  if type(t) ~= "table" then
    return false, "terminal must be a table"
  end
  local valid_providers = { auto = true, native = true, snacks = true }
  if not valid_providers[t.provider] then
    return false, ("terminal.provider must be one of auto|native|snacks (got %q)"):format(tostring(t.provider))
  end
  if t.split_side ~= "left" and t.split_side ~= "right" then
    return false, 'terminal.split_side must be "left" or "right"'
  end
  local w = t.split_width_percentage
  if type(w) ~= "number" or w <= 0 or w >= 1 then
    return false, "terminal.split_width_percentage must be a number in (0, 1)"
  end
  return true
end

--- Deep-merge user opts over defaults and validate.
---@param opts CodexConfig?
---@return CodexConfig
function M.merge(opts)
  local cfg = vim.tbl_deep_extend("force", vim.deepcopy(M.defaults), opts or {})
  local ok, err = M.validate(cfg)
  if not ok then
    error("[codex] invalid config: " .. err, 0)
  end
  return cfg
end

return M
