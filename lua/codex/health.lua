--- Health checks for codex.nvim (:checkhealth codex).
local M = {}

local function start(name)
  (vim.health.start or vim.health.report_start)(name)
end
local function ok(msg)
  (vim.health.ok or vim.health.report_ok)(msg)
end
local function warn(msg, advice)
  (vim.health.warn or vim.health.report_warn)(msg, advice)
end
local function err(msg, advice)
  (vim.health.error or vim.health.report_error)(msg, advice)
end

function M.check()
  start("codex.nvim")

  -- Neovim version
  if vim.fn.has("nvim-0.10") == 1 then
    ok("Neovim " .. tostring(vim.version()))
  else
    err("Neovim 0.10+ is required")
  end

  -- Codex CLI
  local cmd = "codex"
  local codex_mod = package.loaded["codex"]
  if codex_mod and codex_mod.config then
    cmd = codex_mod.config.codex_cmd
  end
  local exe = vim.fn.exepath(cmd)
  if exe ~= "" then
    local version = vim.fn.system({ cmd, "--version" })
    version = vim.trim((version or ""):gsub("\n.*", ""))
    ok(("Codex CLI found: %s (%s)"):format(exe, version ~= "" and version or "unknown version"))
  else
    err(("Codex CLI %q not found on PATH"):format(cmd), {
      "Install the Codex CLI (npm i -g @openai/codex) or set config.codex_cmd",
    })
  end

  -- Auth
  local codex_home = vim.env.CODEX_HOME or (vim.env.HOME .. "/.codex")
  if vim.fn.filereadable(codex_home .. "/auth.json") == 1 then
    ok("Auth file present (" .. codex_home .. "/auth.json)")
  else
    warn("No auth.json found in " .. codex_home, { "Run `codex login` in a terminal" })
  end

  -- Terminal provider
  local snacks_ok = pcall(require, "snacks")
  if snacks_ok then
    ok("snacks.nvim available (used when provider='auto')")
  else
    ok("snacks.nvim not found; native terminal provider will be used")
  end
end

return M
