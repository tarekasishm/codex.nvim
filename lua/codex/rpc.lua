--- Low-level JSON-RPC 2.0 client over `codex app-server` (stdio, newline-delimited).
---
--- Handles process spawn, line framing, request/response correlation, outgoing
--- notifications, and dispatch of server-initiated notifications and requests.
--- It knows nothing about Codex semantics — that lives in codex.session.
local logger = require("codex.logger")

--- @class CodexRpc
--- @field job integer? jobstart channel id
--- @field _next_id integer
--- @field _pending table<integer, fun(err: table?, result: any)>
--- @field _pending_meta table<integer, string> method name per id (for logging)
--- @field _stdout_pending string partial-line buffer
--- @field on_notification fun(method: string, params: any)?
--- @field on_request fun(method: string, params: any, respond: fun(result: any?, err: table?))?
--- @field on_exit fun(code: integer)?
local Rpc = {}
Rpc.__index = Rpc

--- Encode a Lua value as JSON, forcing empty tables to `{}` (object) not `[]`.
---@param v any
---@return string
local function encode(v)
  if type(v) == "table" and next(v) == nil then
    return "{}"
  end
  return vim.json.encode(v)
end

--- @return CodexRpc
function Rpc.new()
  return setmetatable({
    job = nil,
    _next_id = 0,
    _pending = {},
    _pending_meta = {},
    _stdout_pending = "",
  }, Rpc)
end

--- Spawn `codex app-server`.
---@param cmd string[] argv, e.g. { "codex", "app-server" }
---@param env table<string,string>
---@param cwd string
---@return boolean ok
function Rpc:spawn(cmd, env, cwd)
  self.job = vim.fn.jobstart(cmd, {
    cwd = cwd,
    env = next(env or {}) and env or nil,
    stdout_buffered = false,
    stderr_buffered = false,
    on_stdout = function(_, data)
      self:_on_stdout(data)
    end,
    on_stderr = function(_, data)
      local msg = vim.trim(table.concat(data or {}, "\n"))
      if msg ~= "" then
        logger.debug("app-server stderr: %s", msg)
      end
    end,
    on_exit = function(_, code)
      logger.debug("app-server exited (code=%s)", tostring(code))
      self.job = nil
      -- Fail any in-flight requests so callers don't hang.
      for id, cb in pairs(self._pending) do
        pcall(cb, { code = -1, message = "app-server exited" }, nil)
        self._pending[id] = nil
      end
      if self.on_exit then
        self.on_exit(code)
      end
    end,
  })
  if not self.job or self.job <= 0 then
    logger.error("failed to spawn %q (is it on your PATH?)", cmd[1])
    self.job = nil
    return false
  end
  return true
end

--- @return boolean
function Rpc:is_running()
  return self.job ~= nil
end

--- Reassemble newline-delimited lines from a jobstart stdout chunk.
---@param data string[]
function Rpc:_on_stdout(data)
  if not data or #data == 0 then
    return
  end
  self._stdout_pending = self._stdout_pending .. data[1]
  for i = 2, #data do
    local line = self._stdout_pending
    self._stdout_pending = data[i]
    if line ~= "" then
      self:_handle_line(line)
    end
  end
end

--- Decode and dispatch one complete JSON line.
---@param line string
function Rpc:_handle_line(line)
  local ok, msg = pcall(vim.json.decode, line)
  if not ok or type(msg) ~= "table" then
    logger.warn("dropping non-JSON line from app-server: %s", line:sub(1, 200))
    return
  end

  if msg.method ~= nil and msg.id ~= nil then
    -- Server → client request: we must reply.
    self:_dispatch_request(msg)
  elseif msg.method ~= nil then
    -- Server → client notification.
    if self.on_notification then
      vim.schedule(function()
        self.on_notification(msg.method, msg.params)
      end)
    end
  elseif msg.id ~= nil then
    -- Response to one of our requests.
    self:_dispatch_response(msg)
  else
    logger.warn("unrecognized JSON-RPC message: %s", line:sub(1, 200))
  end
end

---@param msg table
function Rpc:_dispatch_response(msg)
  local cb = self._pending[msg.id]
  if not cb then
    logger.warn("response for unknown id=%s", tostring(msg.id))
    return
  end
  self._pending[msg.id] = nil
  self._pending_meta[msg.id] = nil
  vim.schedule(function()
    cb(msg.error, msg.result)
  end)
end

---@param msg table
function Rpc:_dispatch_request(msg)
  if not self.on_request then
    -- No handler: reply with a method-not-found error so the server isn't stuck.
    self:_send({ jsonrpc = "2.0", id = msg.id, error = { code = -32601, message = "no handler" } })
    return
  end
  local responded = false
  local respond = function(result, err)
    if responded then
      return
    end
    responded = true
    if err then
      self:_send({ jsonrpc = "2.0", id = msg.id, error = err })
    else
      self:_send({ jsonrpc = "2.0", id = msg.id, result = result or vim.empty_dict() })
    end
  end
  vim.schedule(function()
    local ok, err = pcall(self.on_request, msg.method, msg.params, respond)
    if not ok then
      logger.error("request handler error for %s: %s", msg.method, tostring(err))
      respond(nil, { code = -32603, message = "internal error" })
    end
  end)
end

--- Write a raw JSON-RPC object to the process.
---@param obj table
function Rpc:_send(obj)
  if not self.job then
    logger.warn("cannot send %s: app-server not running", tostring(obj.method or obj.id))
    return
  end
  vim.fn.chansend(self.job, encode(obj) .. "\n")
end

--- Send a request and invoke `callback(err, result)` when the response arrives.
---@param method string
---@param params any
---@param callback fun(err: table?, result: any)?
function Rpc:request(method, params, callback)
  self._next_id = self._next_id + 1
  local id = self._next_id
  if callback then
    self._pending[id] = callback
    self._pending_meta[id] = method
  end
  self:_send({ jsonrpc = "2.0", id = id, method = method, params = params or vim.empty_dict() })
end

--- Send a notification (no response expected).
---@param method string
---@param params any
function Rpc:notify(method, params)
  self:_send({ jsonrpc = "2.0", method = method, params = params or vim.empty_dict() })
end

--- Terminate the process.
function Rpc:stop()
  if self.job then
    vim.fn.jobstop(self.job)
    self.job = nil
  end
end

return Rpc
