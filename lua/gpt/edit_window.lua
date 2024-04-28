local util   = require('gpt.util')
local com    = require('gpt.window.common')
local Layout = require("nui.layout")
local Popup  = require("nui.popup")

local M      = {}

local on_CR  = function(input_bufnr, code_bufnr)
  local input_text = vim.api.nvim_buf_get_lines(input_bufnr, 0, -1, false)
  local code_text = vim.api.nvim_buf_get_lines(code_bufnr, 0, -1, false)

  local text = util.merge_tables(input_text, code_text)

  -- Add input text to chat
  vim.api.nvim_buf_set_lines(code_bufnr, -1, -1, true, input_text)

  -- Clear input
  vim.api.nvim_buf_set_lines(input_bufnr, 0, -1, true, {})
end

function M.build_and_mount(selected_text)
  local left_popup = Popup(com.build_common_popup_opts("Current"))
  local right_popup = Popup(com.build_common_popup_opts("Edits"))
  local input = Popup(com.build_common_popup_opts("Prompt"))

  -- Turn off syntax highlighting for input buffer.
  vim.api.nvim_buf_set_option(input.bufnr, 'filetype', 'txt')
  vim.api.nvim_buf_set_option(input.bufnr, 'syntax', '')

  -- Make input a 'scratch' buffer, effectively making it a temporary buffer
  vim.api.nvim_buf_set_option(input.bufnr, "buftype", "nofile")

  -- Set buffers to same filetype as current file, for highlighting
  vim.api.nvim_buf_set_option(left_popup.bufnr, 'filetype', vim.bo.filetype)
  vim.api.nvim_buf_set_option(right_popup.bufnr, 'filetype', vim.bo.filetype)

  -- The windows are small, so let's not wrap TODO Couldn't figure this out in 5 mins of looking

  -- Theoretically we'll always have selected_text at this point, but ok to defend
  if selected_text then
    vim.api.nvim_buf_set_lines(left_popup.bufnr, 0, -1, true, selected_text)
  end

  -- Set <CR>
  vim.api.nvim_buf_set_keymap(input.bufnr, "n", "<CR>", "",
    { noremap = true, silent = true, callback = function() on_CR(input.bufnr, left_popup.bufnr) end }
  )

  local bufs = { left_popup.bufnr, right_popup.bufnr, input.bufnr }
  for i, buf in ipairs(bufs) do
    -- Tab cycles through windows
    vim.api.nvim_buf_set_keymap(buf, "n", "<Tab>", "", {
      noremap = true,
      silent = true,
      callback = function()
        local next_buf_index = (i % #bufs) + 1
        local next_win = vim.fn.bufwinid(bufs[next_buf_index])
        vim.api.nvim_set_current_win(next_win)
      end
    })

    -- Shift-Tab cycles through windows
    vim.api.nvim_buf_set_keymap(buf, "n", "<S-Tab>", "", {
      noremap = true,
      silent = true,
      callback = function()
        local prev_buf_index = (i - 2) % #bufs + 1
        local prev_win = vim.fn.bufwinid(bufs[prev_buf_index])
        vim.api.nvim_set_current_win(prev_win)
      end
    })
  end

  local layout = Layout(
    {
      position = "50%",
      size = {
        width = "90%",
        height = "90%",
      },
    },
    Layout.Box({
      Layout.Box({
        Layout.Box(left_popup, { size = "50%" }),
        Layout.Box(right_popup, { size = "50%" }),
      }, { dir = "row", size = "80%" }),
      Layout.Box(input, { size = "22%" }),
    }, { dir = "col" })
  )

  layout:mount()

  -- start window in insert mode
  vim.api.nvim_command('startinsert')

  return {
    input_bufnr = input.bufnr,
    left_bufnr = left_popup.bufnr,
    right_bufnr = right_popup.bufnr
  }
end

return M