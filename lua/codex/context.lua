--- Editor-context extraction for codex.nvim.
--- Turns the current buffer / a line range / a file path into text that can be
--- typed into the Codex prompt as an @-mention plus (for ranges) the snippet.
local M = {}

--- Path of a buffer relative to cwd, or nil for unnamed buffers.
---@param path string?
---@return string?
local function relpath(path)
  if path == nil or path == "" then
    return nil
  end
  return vim.fn.fnamemodify(path, ":.")
end

--- Relative path of the current buffer.
---@return string?
function M.current_file()
  return relpath(vim.api.nvim_buf_get_name(0))
end

--- @class CodexSelection
--- @field filepath string?
--- @field line1 integer
--- @field line2 integer
--- @field filetype string
--- @field text string

--- Read a line range from the current buffer.
---@param line1 integer 1-indexed inclusive
---@param line2 integer 1-indexed inclusive
---@return CodexSelection?
function M.get_range(line1, line2)
  if not line1 or not line2 or line1 == 0 or line2 == 0 then
    return nil
  end
  if line1 > line2 then
    line1, line2 = line2, line1
  end
  local lines = vim.api.nvim_buf_get_lines(0, line1 - 1, line2, false)
  if #lines == 0 then
    return nil
  end
  return {
    filepath = M.current_file(),
    line1 = line1,
    line2 = line2,
    filetype = vim.bo.filetype,
    text = table.concat(lines, "\n"),
  }
end

--- Fallback: read the last visual selection from the '< '> marks.
---@return CodexSelection?
function M.get_visual_selection()
  local s = vim.fn.getpos("'<")
  local e = vim.fn.getpos("'>")
  return M.get_range(s[2], e[2])
end

--- Format an @-mention for a whole file.
---@param path string relative path
---@return string
function M.format_file(path)
  return "@" .. path
end

--- Format a range selection as a mention + fenced snippet.
---@param sel CodexSelection
---@return string
function M.format_selection(sel)
  local header = sel.filepath
    and ("@%s (L%d-%d)"):format(sel.filepath, sel.line1, sel.line2)
    or ("(selection L%d-%d)"):format(sel.line1, sel.line2)
  local fence = "```" .. (sel.filetype ~= "" and sel.filetype or "")
  return table.concat({ header, fence, sel.text, "```", "" }, "\n")
end

return M
