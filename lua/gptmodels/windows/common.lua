local Store = require('gptmodels.store')
local cmd = require('gptmodels.cmd')
local util = require('gptmodels.util')

local M = {}

function M.build_common_popup_opts(title)
  return {
    border = {
      style = "rounded",
      text = {
        top = " " .. title .. " ",
        top_align = "center",
        bottom = "",
        bottom_align = "center",
      },
    },
    focusable = true,
    enter = true,
    win_options = {
      -- winhighlight = "Normal:Normal",
      winhighlight = "Normal:Normal,FloatBorder:SpecialChar",
    },
  }
end

-- This works to close the popup. Probably good to delete the buffer too!
function M.close_popup(bufnr)
  vim.api.nvim_buf_delete(bufnr, { force = true })
end

function M.model_display_name()
  return Store.llm_provider .. "." .. Store.llm_model
end

-- Render text to a buffer _if the buffer is still valid_,
-- so this is safe to call on potentially closed buffers.
---@param bufnr integer
---@param text string
function M.safe_render_buffer_from_text(bufnr, text)
  if not bufnr then return end
  -- local buf_loaded = vim.api.nvim_buf_is_loaded(bufnr)
  local buf_loaded = true
  local buf_valid = vim.api.nvim_buf_is_valid(bufnr)

  if not (buf_loaded and buf_valid) then return end

  local buf_writable = vim.bo[bufnr].modifiable
  if not buf_writable then return end

  local response_lines = vim.split(text or "", "\n")
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, true, response_lines)
end

-- Render text to a buffer _if the buffer is still valid_,
-- so this is safe to call on potentially closed buffers.
---@param bufnr integer
---@param lines string[]
function M.safe_render_buffer_from_lines(bufnr, lines)
  if not bufnr then return end
  local buf_loaded = vim.api.nvim_buf_is_loaded(bufnr)
  local buf_valid = vim.api.nvim_buf_is_valid(bufnr)
  if not (buf_loaded and buf_valid) then return end

  local buf_writable = vim.bo[bufnr].modifiable
  if not buf_writable then return end

  vim.api.nvim_buf_set_lines(bufnr, 0, -1, true, lines)
end

-- Check for required programs, warn user if they're not there
---@return string | nil
function M.check_deps()
  local failed = false
  local return_string = [[
Error - missing required dependencies.
GPTModels.nvim requires the following programs installed, which are not detected in your path:
  ]]

  for _, prog in ipairs({ "ollama", "curl" }) do
    cmd.exec({
      sync = true,
      cmd = "which",
      args = { prog },
      onexit = function (code)
        if code ~= 0 then
          return_string = return_string .. prog .. " "
          failed = true
        end
      end
    })
  end

  if failed then
    return return_string
  else
    return nil
  end
end

return M
