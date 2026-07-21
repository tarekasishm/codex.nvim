# codex.nvim

Embed the [OpenAI Codex CLI](https://github.com/openai/codex) inside Neovim — a
toggleable Codex terminal split plus commands to push editor context (selections
and files) straight into your Codex session.

Inspired by [claudecode.nvim](https://github.com/coder/claudecode.nvim), adapted
to how Codex actually integrates with editors.

> **Two ways to use it:**
>
> - **Terminal mode (Phase 1)** — runs the interactive `codex` TUI in a split and
>   feeds it context. Full-fidelity official UX.
> - **Chat mode (Phase 2)** — drives `codex app-server` over JSON-RPC (the same
>   mechanism as OpenAI's VS Code extension). Streams the reply into a transcript
>   buffer, surfaces command/file approvals as prompts, and shows token usage.

## Features

### Terminal mode

- **Toggle a Codex split** with `:Codex` — the process stays alive when hidden.
- **Send the visual selection** to Codex as a file-referenced code snippet.
- **Add files** to the conversation as `@`-mentions.
- **Send arbitrary text** into the prompt.
- **Native or [snacks.nvim](https://github.com/folke/snacks.nvim) terminal**, auto-detected.
- Multi-line context is sent via bracketed paste, so it lands as one block instead
  of submitting line-by-line.

### Chat mode (app-server)

- **`:CodexChat` / `:CodexAsk {prompt}`** — talk to Codex without leaving your buffers.
- **Streamed replies** rendered live into a markdown transcript window.
- **Command execution & file-change approvals** surfaced as `vim.ui.select` prompts.
- **Reasoning, command output, and diffs** rendered inline; **token usage** in the winbar.
- **`:CodexInterrupt`** to stop an in-flight turn.

`:checkhealth codex` verifies the CLI, auth, and provider. Zero required
dependencies (snacks.nvim optional).

## Requirements

- Neovim **0.10+** (0.11+ uses the modern `jobstart({term=true})` path).
- The `codex` CLI on your `PATH` — `npm i -g @openai/codex`, then `codex login`.

## Installation

[lazy.nvim](https://github.com/folke/lazy.nvim) — a full spec with keymaps for
both modes. Replace `OWNER/codex.nvim` with the repository path.

```lua
{
  "OWNER/codex.nvim",
  dependencies = { "folke/snacks.nvim" }, -- optional, for the snacks terminal provider
  opts = {
    terminal = { split_side = "right", split_width_percentage = 0.40 },
    app_server = { show_reasoning = false }, -- chat mode
  },
  cmd = {
    "Codex", "CodexSend", "CodexAdd",
    "CodexChat", "CodexAsk", "CodexChatSend", "CodexInterrupt",
  },
  keys = {
    -- terminal mode
    { "<leader>cc", "<cmd>Codex<cr>", desc = "Codex: toggle terminal" },
    { "<leader>cs", "<cmd>CodexSend<cr>", mode = "v", desc = "Codex: send selection" },
    { "<leader>ca", "<cmd>CodexAdd<cr>", desc = "Codex: add current file" },
    -- chat mode (app-server)
    { "<leader>ck", "<cmd>CodexChat<cr>", desc = "Codex: open chat" },
    { "<leader>cq", ":CodexAsk ", desc = "Codex: ask (type a prompt)" },
    { "<leader>cx", "<cmd>CodexChatSend<cr>", mode = { "n", "v" }, desc = "Codex: send selection to chat" },
    { "<leader>ci", "<cmd>CodexInterrupt<cr>", desc = "Codex: interrupt turn" },
  },
}
```

Calling `require("codex").setup{}` (or lazy's `opts`) is required — it registers
the commands.

## Configuration

Defaults:

```lua
require("codex").setup({
  codex_cmd = "codex",       -- executable name/path for the Codex CLI
  args = {},                 -- default args always passed to codex (e.g. { "--model", "gpt-5-codex" })
  env = {},                  -- extra environment variables for the codex process
  auto_start = false,        -- open the terminal on setup()
  terminal = {
    provider = "auto",       -- "auto" | "native" | "snacks"
    split_side = "right",    -- "left" | "right"
    split_width_percentage = 0.40,
    auto_close = false,      -- close the split when codex exits
    auto_insert = true,      -- enter terminal mode when focused
    hidden = true,           -- (snacks) keep buffer alive when toggled off
  },
  app_server = {             -- chat mode (Phase 2)
    args = {},               -- extra args appended to `codex app-server`
    model = nil,             -- model override, e.g. "gpt-5-codex"
    approval_policy = nil,   -- "untrusted"|"on-failure"|"on-request"|"never"
    sandbox = nil,           -- "read-only"|"workspace-write"|"danger-full-access"
    show_reasoning = false,  -- render reasoning/thinking deltas in the transcript
  },
  send_submit = false,       -- append <CR> (submit) when sending context
  focus_after_send = false,  -- focus the terminal after sending
  log_level = "info",        -- "trace"|"debug"|"info"|"warn"|"error"|"off"
})
```

## Commands

### Terminal mode

| Command | Mode | Description |
|---|---|---|
| `:Codex [args]` | n | Toggle the Codex terminal. Extra args are passed to `codex` (e.g. `:Codex resume`, `:Codex --model gpt-5-codex`). |
| `:CodexOpen [args]` | n | Open/focus the terminal. |
| `:CodexClose` | n | Hide the terminal (process keeps running). |
| `:CodexFocus` | n | Focus the terminal window. |
| `:CodexSend` | v / n | Send the visual selection as a referenced snippet; in normal mode sends the current file as an `@`-mention. |
| `:CodexAdd [path]` | n | Add a file (default: current buffer) as an `@`-mention. |
| `:CodexSendText[!] {text}` | n | Type text into the prompt. `!` submits it. |
| `:CodexStatus` | n | Show provider / running / open status. |

### Chat mode (app-server)

| Command | Mode | Description |
|---|---|---|
| `:CodexChat` | n | Open the transcript window (starts the app-server lazily). |
| `:CodexAsk {prompt}` | n | Send a prompt and stream the reply. |
| `:CodexChatSend` | v / n | Send the selection/current file plus a prompt (asked via `vim.ui.input`). |
| `:CodexInterrupt` | n | Interrupt the in-flight turn. |
| `:CodexStopServer` | n | Stop the app-server process. |

## Lua API

```lua
local codex = require("codex")
codex.toggle()             -- or codex.toggle({ "resume" })
codex.open({ "--model", "gpt-5-codex" })
codex.focus()
codex.close()
codex.send_selection(opts) -- opts = user-command opts (range/line1/line2)
codex.add("lua/foo.lua")
codex.send_text("explain this repo", true) -- submit
codex.status()             -- { running, open, provider }
```

## How it works

**Terminal mode** spawns `codex` in a terminal buffer and communicates by typing
into its PTY:

- **File mentions** are sent as literal `@relative/path` tokens.
- **Selections** are sent as an `@file (L1-9)` header + fenced code block, wrapped
  in bracketed-paste escapes (`ESC[200~ … ESC[201~`) so the block is pasted rather
  than submitted line by line.

**Chat mode** spawns `codex app-server` and speaks newline-delimited JSON-RPC 2.0
over stdio — the same protocol OpenAI's VS Code extension uses:

- Handshake: `initialize` → `initialized`, then a thread via `thread/start`.
- Each prompt is a `turn/start` with `input: [{ type = "text", text = … }]`.
- Server notifications drive the UI: `item/agentMessage/delta` (streamed text),
  `item/commandExecution/outputDelta`, `item/fileChange/patchUpdated`,
  `turn/completed`, `thread/tokenUsage/updated`.
- Server → client requests `item/commandExecution/requestApproval` and
  `item/fileChange/requestApproval` become `vim.ui.select` prompts, answered with
  `accept` / `acceptForSession` / `decline`.

Auth and configuration are shared with the CLI via `~/.codex/` — codex.nvim does
not manage credentials.

## Roadmap

Phase 3 ideas, building on the app-server integration:

- Apply file-change diffs into real buffers with a native side-by-side review
  (accept/reject hunks) instead of read-only diff rendering.
- `turn/steer` (append to an in-flight turn) and `thread/resume` / thread picker.
- A model picker via `model/list`, and richer input (image / skill items).
- Feed diagnostics and workspace context automatically per turn.

## License

MIT
