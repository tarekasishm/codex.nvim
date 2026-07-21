--- User command definitions for codex.nvim.
local M = {}

--- Create the :Codex* user commands.
---@param codex table the codex.init module (public API)
function M.create(codex)
  local cmd = vim.api.nvim_create_user_command

  cmd("Codex", function(o)
    codex.toggle(o.fargs)
  end, { nargs = "*", desc = "Toggle the Codex terminal (extra args passed to codex)" })

  cmd("CodexOpen", function(o)
    codex.open(o.fargs)
  end, { nargs = "*", desc = "Open/focus the Codex terminal" })

  cmd("CodexClose", function()
    codex.close()
  end, { desc = "Hide the Codex terminal" })

  cmd("CodexFocus", function()
    codex.focus()
  end, { desc = "Focus the Codex terminal" })

  cmd("CodexSend", function(o)
    codex.send_selection(o)
  end, { range = true, desc = "Send the visual selection (or current file) to Codex" })

  cmd("CodexAdd", function(o)
    codex.add(o.args)
  end, { nargs = "?", complete = "file", desc = "Add a file to Codex context as an @-mention" })

  cmd("CodexSendText", function(o)
    codex.send_text(o.args, o.bang)
  end, { nargs = "+", bang = true, desc = "Type text into Codex (! to submit)" })

  cmd("CodexStatus", function()
    local s = codex.status()
    vim.notify(
      ("[codex] provider=%s running=%s open=%s"):format(s.provider, tostring(s.running), tostring(s.open)),
      vim.log.levels.INFO
    )
  end, { desc = "Show Codex terminal status" })

  -- Phase 2: app-server chat
  cmd("CodexChat", function()
    codex.chat()
  end, { desc = "Open the Codex app-server transcript" })

  cmd("CodexAsk", function(o)
    codex.ask(o.args)
  end, { nargs = "+", desc = "Ask Codex (app-server) and stream the reply" })

  cmd("CodexChatSend", function(o)
    codex.chat_send(o)
  end, { range = true, desc = "Send selection/file to Codex chat with a prompt" })

  cmd("CodexInterrupt", function()
    codex.interrupt()
  end, { desc = "Interrupt the in-flight Codex turn" })

  cmd("CodexStopServer", function()
    codex.stop_server()
  end, { desc = "Stop the Codex app-server" })
end

return M
