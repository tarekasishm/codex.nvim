--- App-server (Phase 2) session orchestration.
--- Owns the RPC connection, drives the initialize → thread/start → turn/start
--- flow, and maps server notifications/requests onto the transcript UI and
--- approval prompts.
local Rpc = require("codex.rpc")
local ui = require("codex.ui")
local approvals = require("codex.approvals")
local logger = require("codex.logger")

local M = {}

local S = {
  rpc = nil, ---@type CodexRpc?
  ready = false,
  starting = false,
  thread_id = nil, ---@type string?
  turn_id = nil, ---@type string?
  cfg = nil, ---@type CodexConfig?
  ready_cbs = {}, ---@type fun()[]
}

--- @return boolean
function M.is_running()
  return S.rpc ~= nil and S.rpc:is_running()
end

--- @return table
function M.status()
  return { running = M.is_running(), ready = S.ready, thread = S.thread_id, turn = S.turn_id }
end

-- ---------------------------------------------------------------------------
-- Notification + request dispatch
-- ---------------------------------------------------------------------------

--- @param method string
--- @param params table
function M._on_notification(method, params)
  params = params or {}
  if method == "turn/started" then
    if params.turn then
      S.turn_id = params.turn.id
    end
  elseif method == "item/agentMessage/delta" then
    ui.agent_delta(params.itemId, params.delta or "")
  elseif method == "item/reasoning/textDelta" or method == "item/reasoning/summaryTextDelta" then
    ui.reasoning_delta(params.itemId, params.delta or "")
  elseif method == "item/commandExecution/outputDelta" then
    ui.command_output(params.itemId, params.delta or "")
  elseif method == "item/fileChange/patchUpdated" then
    ui.file_change(params.changes)
  elseif method == "item/started" then
    local item = params.item or {}
    if item.type == "commandExecution" then
      ui.command_started(item.id, item.command or "")
    end
  elseif method == "item/completed" then
    local item = params.item or {}
    if item.type == "commandExecution" then
      ui.command_completed(item.id, item.status or "completed", item.exitCode)
    elseif item.type == "fileChange" then
      ui.file_change(item.changes)
    end
  elseif method == "turn/completed" then
    S.turn_id = nil
    ui.turn_completed()
    if params.turn and params.turn.status == "failed" and params.turn.error then
      ui.error(tostring(params.turn.error.message or params.turn.error))
    end
  elseif method == "thread/tokenUsage/updated" then
    local tu = params.tokenUsage
    if tu and tu.total then
      ui.set_winbar(
        (" Codex — tokens %d in / %d out (total %d)"):format(
          tu.total.inputTokens or 0,
          tu.total.outputTokens or 0,
          tu.total.totalTokens or 0
        )
      )
    end
  elseif method == "error" then
    ui.error(params.message or vim.inspect(params))
  else
    logger.trace("unhandled notification: %s", method)
  end
end

--- @param method string
--- @param params table
--- @param respond fun(result: any?, err: table?)
function M._on_request(method, params, respond)
  if approvals.handle(method, params, respond, ui) then
    return
  end
  logger.debug("no handler for server request %s; replying empty", method)
  respond(vim.empty_dict())
end

-- ---------------------------------------------------------------------------
-- Lifecycle
-- ---------------------------------------------------------------------------

--- Start (spawn + initialize) the app-server, invoking `cb` when ready.
---@param cfg CodexConfig
---@param cb fun()?
function M.start(cfg, cb)
  S.cfg = cfg
  if M.is_running() and S.ready then
    if cb then cb() end
    return
  end
  if cb then
    table.insert(S.ready_cbs, cb)
  end
  if S.starting then
    return
  end
  S.starting = true

  local rpc = Rpc.new()
  S.rpc = rpc
  rpc.on_notification = M._on_notification
  rpc.on_request = M._on_request
  rpc.on_exit = function()
    S.ready = false
    S.starting = false
    S.thread_id = nil
    S.turn_id = nil
    S.rpc = nil
    ui.note("app-server stopped")
  end

  local cmd = { cfg.codex_cmd, "app-server" }
  vim.list_extend(cmd, cfg.app_server.args or {})
  if not rpc:spawn(cmd, cfg.env, vim.fn.getcwd()) then
    S.starting = false
    S.rpc = nil
    return
  end

  rpc:request("initialize", {
    clientInfo = { name = "codex.nvim", version = "0.2.0", title = "codex.nvim" },
  }, function(err, result)
    S.starting = false
    if err then
      logger.error("initialize failed: %s", vim.inspect(err))
      return
    end
    logger.debug("initialized against %s", result and result.userAgent or "app-server")
    rpc:notify("initialized", {})
    S.ready = true
    local cbs = S.ready_cbs
    S.ready_cbs = {}
    for _, f in ipairs(cbs) do
      pcall(f)
    end
  end)
end

--- Ensure a thread exists, then invoke `cb`.
---@param cb fun()
function M.ensure_thread(cb)
  if S.thread_id then
    cb()
    return
  end
  local as = S.cfg.app_server
  local params = { cwd = vim.fn.getcwd() }
  if as.model then params.model = as.model end
  if as.approval_policy then params.approvalPolicy = as.approval_policy end
  if as.sandbox then params.sandbox = as.sandbox end

  S.rpc:request("thread/start", params, function(err, result)
    if err or not result or not result.thread then
      ui.error("thread/start failed: " .. vim.inspect(err or result))
      return
    end
    S.thread_id = result.thread.id
    logger.debug("thread started: %s", S.thread_id)
    cb()
  end)
end

--- Send a user message, starting the server/thread as needed and streaming the reply.
---@param text string
---@param cfg CodexConfig?
function M.ask(text, cfg)
  if cfg then S.cfg = cfg end
  if not S.cfg then
    logger.error("session not configured; call setup() first")
    return
  end
  if text == nil or vim.trim(text) == "" then
    return
  end
  M.start(S.cfg, function()
    M.ensure_thread(function()
      ui.open(S.cfg)
      ui.user_message(text)
      local params = {
        threadId = S.thread_id,
        input = { { type = "text", text = text } },
      }
      if S.cfg.app_server.model then
        params.model = S.cfg.app_server.model
      end
      S.rpc:request("turn/start", params, function(err, result)
        if err then
          ui.error("turn/start failed: " .. vim.inspect(err))
          return
        end
        if result and result.turn then
          S.turn_id = result.turn.id
        end
      end)
    end)
  end)
end

--- Open the transcript window (starting the server lazily).
---@param cfg CodexConfig
function M.open(cfg)
  S.cfg = cfg
  ui.open(cfg)
  M.start(cfg)
end

--- Interrupt the in-flight turn.
function M.interrupt()
  if M.is_running() and S.thread_id and S.turn_id then
    S.rpc:request("turn/interrupt", { threadId = S.thread_id, turnId = S.turn_id }, function()
      ui.note("turn interrupted")
    end)
  else
    logger.info("no active turn to interrupt")
  end
end

--- Stop the app-server and reset session state.
function M.stop()
  if S.rpc then
    S.rpc:stop()
  end
  S.rpc = nil
  S.ready = false
  S.starting = false
  S.thread_id = nil
  S.turn_id = nil
  S.ready_cbs = {}
end

return M
