--- Handle server → client approval requests from the app-server.
--- Presents a vim.ui.select prompt and replies with the chosen decision.
local logger = require("codex.logger")

local M = {}

-- Decision enum values (v2 protocol) shared by command-exec and file-change approvals.
local CHOICES = {
  { label = "Accept", decision = "accept" },
  { label = "Accept for session", decision = "acceptForSession" },
  { label = "Decline", decision = "decline" },
}

--- @param method string
--- @param params table
--- @param respond fun(result: any?, err: table?)
--- @param ui table the codex.ui module (for echoing context into the transcript)
--- @return boolean handled
function M.handle(method, params, respond, ui)
  params = params or {}
  local prompt, context_note

  if method == "item/commandExecution/requestApproval" then
    local cmd = params.command or "(command)"
    prompt = "Codex wants to run a command:"
    context_note = "$ " .. cmd
  elseif method == "item/fileChange/requestApproval" then
    prompt = "Codex wants to apply file changes"
    context_note = params.grantRoot and ("under " .. params.grantRoot) or nil
  else
    return false
  end

  if params.reason and params.reason ~= "" then
    prompt = prompt .. "\nReason: " .. params.reason
  end
  if context_note and ui then
    ui.note("approval requested — " .. context_note)
  end

  vim.ui.select(CHOICES, {
    prompt = prompt,
    format_item = function(item)
      return item.label
    end,
  }, function(choice)
    local decision = choice and choice.decision or "decline"
    logger.debug("approval %s -> %s", method, decision)
    respond({ decision = decision })
  end)

  return true
end

return M
