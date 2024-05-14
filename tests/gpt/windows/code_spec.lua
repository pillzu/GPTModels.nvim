---@diagnostic disable: undefined-global

local util = require("gpt.util")
local assert = require("luassert")
local code_window = require('gpt.windows.code')
local stub = require('luassert.stub')
local spy = require('luassert.spy')
local llm = require('gpt.llm')
local cmd = require('gpt.cmd')
local Store = require('gpt.store')

describe("The code window", function()
  before_each(function()
    -- Set current window dims, otherwise it defaults to 0 and nui.layout complains about not having a pos integer height
    vim.api.nvim_win_set_height(0, 100)
    vim.api.nvim_win_set_width(0, 100)

    stub(cmd, "exec")

    Store.clear()
  end)

  it("returns buffer numbers, winids", function()
    local code = code_window.build_and_mount()
    assert.is_not.equal(code.input_bufnr, nil)
    assert.is_not.equal(code.right_bufnr, nil)
    assert.is_not.equal(code.left_bufnr, nil)
    assert.is_not.equal(code.input_winid, nil)
    assert.is_not.equal(code.right_winid, nil)
    assert.is_not.equal(code.left_winid, nil)
  end)

  it("places given provided text in left window", function()
    local given_lines = { "text line 1", "text line 2" }
    local code = code_window.build_and_mount(given_lines)
    local gotten_lines = vim.api.nvim_buf_get_lines(code.left_bufnr, 0, -1, true)
    assert.same(given_lines, gotten_lines)
  end)

  it("shifts through windows on <Tab>", function()
    local code = code_window.build_and_mount()
    local input_bufnr = code.input_bufnr
    local left_bufnr = code.left_bufnr
    local right_bufnr = code.right_bufnr

    local input_win = vim.fn.bufwinid(input_bufnr)
    local left_win = vim.fn.bufwinid(left_bufnr)
    local right_win = vim.fn.bufwinid(right_bufnr)

    local esc = vim.api.nvim_replace_termcodes('<Esc>', true, true, true)
    local tab = vim.api.nvim_replace_termcodes("<Tab>", true, true, true)

    vim.api.nvim_feedkeys(esc, 'mtx', true)
    assert.equal(vim.api.nvim_get_current_win(), input_win)
    vim.api.nvim_feedkeys(tab, 'mtx', true)
    assert.equal(vim.api.nvim_get_current_win(), left_win)
    vim.api.nvim_feedkeys(tab, 'mtx', true)
    assert.equal(vim.api.nvim_get_current_win(), right_win)
    vim.api.nvim_feedkeys(tab, 'mtx', true)
    assert.equal(vim.api.nvim_get_current_win(), input_win)
  end)

  it("shifts through windows on <S-Tab>", function()
    local code = code_window.build_and_mount()
    local input_bufnr = code.input_bufnr
    local left_bufnr = code.left_bufnr
    local right_bufnr = code.right_bufnr

    local input_win = vim.fn.bufwinid(input_bufnr)
    local left_win = vim.fn.bufwinid(left_bufnr)
    local right_win = vim.fn.bufwinid(right_bufnr)

    local esc = vim.api.nvim_replace_termcodes('<Esc>', true, true, true)
    local tab = vim.api.nvim_replace_termcodes("<S-Tab>", true, true, true)

    vim.api.nvim_feedkeys(esc, 'mtx', true)
    assert.equal(vim.api.nvim_get_current_win(), input_win)
    vim.api.nvim_feedkeys(tab, 'mtx', true)
    assert.equal(vim.api.nvim_get_current_win(), right_win)
    vim.api.nvim_feedkeys(tab, 'mtx', true)
    assert.equal(vim.api.nvim_get_current_win(), left_win)
    vim.api.nvim_feedkeys(tab, 'mtx', true)
    assert.equal(vim.api.nvim_get_current_win(), input_win)
  end)

  it("Places llm responses into right window", function()
    local code = code_window.build_and_mount()

    local s = stub(llm, "generate")

    local keys = vim.api.nvim_replace_termcodes('xhello<Esc><CR>', true, true, true)
    vim.api.nvim_feedkeys(keys, 'mtx', false)

    ---@type MakeGenerateRequestArgs
    local args = s.calls[1].refs[1]

    -- simulate a multiline resposne from the llm
    args.on_read(nil, "line 1\nline 2")

    -- Those lines should be separated on newlines and placed into the right buf
    assert.same(vim.api.nvim_buf_get_lines(code.right_bufnr, 0, -1, true), { "line 1", "line 2" })
  end)

  it("includes a system prompt", function()
    code_window.build_and_mount()
    local s = stub(llm, "generate")

    -- Make a request to start a job
    local keys = vim.api.nvim_replace_termcodes('xincluding system prompt?<Esc><CR>', true, true, true)
    vim.api.nvim_feedkeys(keys, 'mtx', false)

    ---@type MakeGenerateRequestArgs
    local args = s.calls[1].refs[1]
    assert.is_not.same(args.llm.system, nil)
  end)

  it("includes file type", function()
    -- return "lua" for filetype request
    stub(vim.api, "nvim_buf_get_option").returns("lua")

    code_window.build_and_mount()
    local s = stub(llm, "generate")

    -- Make a request to start a job
    local keys = vim.api.nvim_replace_termcodes('xincluding filetype?<Esc><CR>', true, true, true)
    vim.api.nvim_feedkeys(keys, 'mtx', false)

    ---@type MakeGenerateRequestArgs
    local args = s.calls[1].refs[1]

    assert.not_same(string.find(args.llm.prompt, "lua"), nil)
    assert.is_not.same(args.llm.prompt, nil)
  end)

  it("Has a loading indicator", function()
    local code = code_window.build_and_mount()

    local s = stub(llm, "generate")

    local keys = vim.api.nvim_replace_termcodes('xloading test<Esc><CR>', true, true, true)
    vim.api.nvim_feedkeys(keys, 'mtx', false)

    ---@type MakeGenerateRequestArgs
    local args = s.calls[1].refs[1]

    -- before on_response gets a response from the llm, the right window should show a loading indicator
    assert.same(vim.api.nvim_buf_get_lines(code.right_bufnr, 0, -1, true), { "Loading..." })

    -- simulate a response from the llm
    args.on_read(nil, "response line")

    -- After the response, the loading indicator should be replaced by the response
    assert.same(vim.api.nvim_buf_get_lines(code.right_bufnr, 0, -1, true), { "response line" })
  end)

  it("finishes jobs in the background when closed", function()
    code_window.build_and_mount()
    local s = stub(llm, "generate")
    local die_called = false

    s.returns({
      die = function()
        die_called = true
      end
    })

    -- Make a request to start a job
    local keys = vim.api.nvim_replace_termcodes('xhello<Esc><CR>', true, true, true)
    vim.api.nvim_feedkeys(keys, 'mtx', false)

    -- quit with :q
    keys = vim.api.nvim_replace_termcodes('<Esc>:q<CR>', true, true, true)
    vim.api.nvim_feedkeys(keys, 'mtx', false)

    -- -- quit with q
    -- keys = vim.api.nvim_replace_termcodes('q', true, true, true)
    -- vim.api.nvim_feedkeys(keys, 'mtx', false)

    assert.is_not.True(die_called)

    -- -- simulate hint of wait time for the nui windows to close
    -- -- TODO This leads to errors about invalid windows. Gotta fix
    -- vim.wait(10)

    ---@type MakeGenerateRequestArgs
    local args = s.calls[1].refs[1]

    args.on_read(nil, "response to be saved in background")

    -- Open up and ensure it's there now
    local code = code_window.build_and_mount()
    assert.same({ "response to be saved in background" }, vim.api.nvim_buf_get_lines(code.right_bufnr, 0, -1, true))

    -- More reponse to still reopen window
    args.on_read(nil, "\nadditional response")

    -- Gets that response without reopening
    local right_lines = vim.api.nvim_buf_get_lines(code.right_bufnr, 0, -1, true)
    assert.same({ "response to be saved in background", "additional response" }, right_lines)
  end)


  it("opens prepopulated w/ prior session when no text provided", function()
    Store.code.right.append("right content")
    Store.code.input.append("input content")
    Store.code.left.append("left content")

    local code = code_window.build_and_mount()

    local right_lines = vim.api.nvim_buf_get_lines(code.right_bufnr, 0, -1, true)
    local input_lines = vim.api.nvim_buf_get_lines(code.input_bufnr, 0, -1, true)
    local left_lines = vim.api.nvim_buf_get_lines(code.left_bufnr, 0, -1, true)

    assert.same({ "right content" }, right_lines)
    assert.same({ "input content" }, input_lines)
    assert.same({ "left content" }, left_lines)
  end)

  it("does not open prepopulated w/ prior session when text is provided", function()
    Store.code.right.append("right content")
    Store.code.input.append("input content")
    Store.code.left.append("left content")

    local code = code_window.build_and_mount({ "provided text" })

    local right_lines = vim.api.nvim_buf_get_lines(code.right_bufnr, 0, -1, true)
    local input_lines = vim.api.nvim_buf_get_lines(code.input_bufnr, 0, -1, true)
    local left_lines = vim.api.nvim_buf_get_lines(code.left_bufnr, 0, -1, true)

    assert.same({ "" }, right_lines)
    assert.same({ "" }, input_lines)
    assert.same({ "provided text" }, left_lines)
  end)

  it("Replaces prior llm response with new one", function()
    local code = code_window.build_and_mount()

    local s = stub(llm, "generate")

    -- Input anything
    local keys = vim.api.nvim_replace_termcodes('xtesting first response<Esc><CR>', true, true, true)
    vim.api.nvim_feedkeys(keys, 'mtx', false)

    ---@type MakeGenerateRequestArgs
    local args_first = s.calls[1].refs[1]

    -- Simulate first response
    args_first.on_read(nil, "first response line")
    if args_first.on_end then args_first.on_end() end

    -- Response is shown
    assert.same(vim.api.nvim_buf_get_lines(code.right_bufnr, 0, -1, true), { "first response line" })

    -- Input whatever
    keys = vim.api.nvim_replace_termcodes('xtesting second response<Esc><CR>', true, true, true)
    vim.api.nvim_feedkeys(keys, 'mtx', false)
    if args_first.on_end then args_first.on_end() end

    ---@type MakeGenerateRequestArgs
    local args_second = s.calls[2].refs[1]

    -- Simulate second response
    args_second.on_read(nil, "second response line")

    -- Second response replaced first response
    assert.same(vim.api.nvim_buf_get_lines(code.right_bufnr, 0, -1, true), { "second response line" })
  end)

  it("clears all windows on <C-n>", function()
    local code = code_window.build_and_mount()

    -- Populate windows with some content
    vim.api.nvim_buf_set_lines(code.input_bufnr, 0, -1, true, { "input content" })
    vim.api.nvim_buf_set_lines(code.left_bufnr, 0, -1, true, { "left content" })
    vim.api.nvim_buf_set_lines(code.right_bufnr, 0, -1, true, { "right content" })
    Store.code.append_file("docs/gpt.txt")

    -- Press <C-n>
    local keys = vim.api.nvim_replace_termcodes("<C-n>", true, true, true)
    vim.api.nvim_feedkeys(keys, 'mtx', true)

    -- Assert all windows are cleared
    assert.same({ '' }, vim.api.nvim_buf_get_lines(code.input_bufnr, 0, -1, true))
    assert.same({ '' }, vim.api.nvim_buf_get_lines(code.left_bufnr, 0, -1, true))
    assert.same({ '' }, vim.api.nvim_buf_get_lines(code.right_bufnr, 0, -1, true))

    -- And the store of included files
    assert.same({}, Store.code.get_files())
  end)

  it("kills active job on <C-c>", function()
    code_window.build_and_mount()
    local s = stub(llm, "generate")
    local die_called = false

    s.returns({
      die = function()
        die_called = true
      end
    })

    -- Make a request to start a job
    local keys = vim.api.nvim_replace_termcodes('xhello<Esc><CR>', true, true, true)
    vim.api.nvim_feedkeys(keys, 'mtx', false)

    -- press ctrl-n
    keys = vim.api.nvim_replace_termcodes('<C-c>', true, true, true)
    vim.api.nvim_feedkeys(keys, 'mtx', false)

    assert.is_true(die_called)
  end)

  it("saves input text on InsertLeave and prepopulates on reopen", function()
    local initial_input = "some initial input"
    local code = code_window.build_and_mount()

    -- Enter insert mode
    local keys = vim.api.nvim_replace_termcodes("i" .. initial_input, true, true, true)
    vim.api.nvim_feedkeys(keys, 'mtx', true)

    -- <Esc> to trigger save
    keys = vim.api.nvim_replace_termcodes("<Esc>", true, true, true)
    vim.api.nvim_feedkeys(keys, 'mtx', true)

    -- Close the window with :q
    keys = vim.api.nvim_replace_termcodes(":q<CR>", true, true, true)
    vim.api.nvim_feedkeys(keys, 'mtx', true)

    -- Reopen the window
    code = code_window.build_and_mount()

    local input_lines = vim.api.nvim_buf_get_lines(code.input_bufnr, 0, -1, true)

    assert.same({ initial_input }, input_lines)
  end)

  it("saves state of all three windows and prepopulates them on reopen", function()
    local llm_stub = stub(llm, "generate")

    -- left window is saved when it opens
    local code = code_window.build_and_mount({ "left" })

    -- Add user input
    vim.api.nvim_buf_set_lines(code.input_bufnr, 0, -1, true, { "input" })

    -- Enter insert mode, so we can leave it
    local keys = vim.api.nvim_replace_termcodes("i", true, true, true)
    vim.api.nvim_feedkeys(keys, 'mtx', true)

    -- <Esc> triggers save
    keys = vim.api.nvim_replace_termcodes("<Esc>", true, true, true)
    vim.api.nvim_feedkeys(keys, 'mtx', true)

    -- <CR> triggers llm call
    keys = vim.api.nvim_replace_termcodes("<CR>", true, true, true)
    vim.api.nvim_feedkeys(keys, 'mtx', true)

    -- right window is saved when an llm response comes in
    ---@type MakeGenerateRequestArgs
    local args = llm_stub.calls[1].refs[1]
    args.on_read(nil, "right")

    -- Close the window with :q
    keys = vim.api.nvim_replace_termcodes(":q<CR>", true, true, true)
    vim.api.nvim_feedkeys(keys, 'mtx', true)

    -- Reopen the window
    code = code_window.build_and_mount()

    local input_lines = vim.api.nvim_buf_get_lines(code.input_bufnr, 0, -1, true)
    local left_lines = vim.api.nvim_buf_get_lines(code.left_bufnr, 0, -1, true)
    local right_lines = vim.api.nvim_buf_get_lines(code.right_bufnr, 0, -1, true)

    assert.same({ "input" }, input_lines)
    assert.same({ "left" }, left_lines)
    assert.same({ "right" }, right_lines)
  end)

  it("cycles through available models with <C-j>", function()
    code_window.build_and_mount()

    local snapshot = assert:snapshot()

    local store_spy = spy.on(Store, "set_llm")

    -- Press <C-j>
    local ctrl_j = vim.api.nvim_replace_termcodes("<C-j>", true, true, true)
    vim.api.nvim_feedkeys(ctrl_j, 'mtx', true)

    assert.spy(store_spy).was_called(1)
    local first_args = store_spy.calls[1].refs
    assert.equal(type(first_args[1]), "string")
    assert.equal(type(first_args[2]), "string")

    -- Press <C-j> again
    vim.api.nvim_feedkeys(ctrl_j, 'mtx', true)

    assert.spy(store_spy).was_called(2)
    local second_args = store_spy.calls[2].refs
    assert.equal(type(second_args[1]), "string")
    assert.equal(type(second_args[2]), "string")

    -- Make sure the model is different, which it definitely should be.
    -- The provider might be the same.
    assert.is_not.equal(first_args[2], second_args[2])

    snapshot:revert()
  end)

  it("cycles through available models with <C-k>", function()
    code_window.build_and_mount()

    local snapshot = assert:snapshot()

    local store_spy = spy.on(Store, "set_llm")

    -- Press <C-k>
    local ctrl_k = vim.api.nvim_replace_termcodes("<C-k>", true, true, true)
    vim.api.nvim_feedkeys(ctrl_k, 'mtx', true)

    assert.spy(store_spy).was_called(1)
    local first_args = store_spy.calls[1].refs
    assert.equal(type(first_args[1]), "string")
    assert.equal(type(first_args[2]), "string")

    -- Press <C-k> again
    vim.api.nvim_feedkeys(ctrl_k, 'mtx', true)

    assert.spy(store_spy).was_called(2)
    local second_args = store_spy.calls[2].refs
    assert.equal(type(second_args[1]), "string")
    assert.equal(type(second_args[2]), "string")

    -- Make sure the model is different, which it definitely should be.
    -- The provider might be the same.
    assert.is_not.equal(first_args[2], second_args[2])

    snapshot:revert()
  end)

  it("includes files on <C-f> and clears them on <C-g>", function()
    code_window.build_and_mount()

    -- I'm only stubbing this because it's so hard to test. One time out of hundreds
    -- I was able to get the test to reflect a picked file. I don't know if there's some
    -- async magic or what but I can't make it work. Tried vim.wait forever.
    local find_files = stub(require('telescope.builtin'), "find_files")

    -- For down the line of this crazy stubbing exercise
    local get_selected_entry = stub(require('telescope.actions.state'), "get_selected_entry")
    get_selected_entry.returns({ "doc/gpt.txt", index = 1 }) -- typical response

    -- And just make sure there are no closing errors
    stub(require('telescope.actions'), "close")

    -- Press ctl-f to open the telescope picker
    local ctrl_f = vim.api.nvim_replace_termcodes('<C-f>', true, true, true)
    vim.api.nvim_feedkeys(ctrl_f, 'mtx', false)

    -- Press enter to select the first file, was Makefile in testing
    local cr = vim.api.nvim_replace_termcodes('<CR>', true, true, true)
    vim.api.nvim_feedkeys(cr, 'mtx', false)

    -- Simulate finding a file
    assert.stub(find_files).was_called(1)
    local attach_mappings = find_files.calls[1].refs[1].attach_mappings
    local map = stub()
    map.invokes(function(_, _, cb)
      cb(9999) -- this will call get_selected_entry internally
    end)
    attach_mappings(nil, map)

    -- Now we'll check what was given to llm.generate
    local generate_stub = stub(llm, "generate")
    vim.api.nvim_feedkeys(cr, 'mtx', false)

    ---@type MakeGenerateRequestArgs
    local args = generate_stub.calls[1].refs[1]

    -- Does the request now contain a system string with the file
    local contains_system_with_file = false
    for _, system_string in ipairs(args.llm.system) do
      if system_string.match(system_string, "doc/gpt.txt") then
        contains_system_with_file = true
      end
    end
    assert.True(contains_system_with_file)

    -- Now we'll make sure C-g clears the files
    local ctrl_g = vim.api.nvim_replace_termcodes('<C-g>', true, true, true)
    vim.api.nvim_feedkeys(ctrl_g, 'mtx', false)
    vim.api.nvim_feedkeys(cr, 'mtx', false)

    ---@type MakeGenerateRequestArgs
    args = generate_stub.calls[2].refs[1]

    -- Does the request now contain a system string with the file
    contains_system_with_file = false
    for _, system_string in ipairs(args.llm.system) do
      if system_string.match(system_string, "doc/gpt.txt") then
        contains_system_with_file = true
      end
    end
    assert.False(contains_system_with_file)
  end)

  it("automatically scrolls chat window when user is not in it", function()
    local code = code_window.build_and_mount()

    local llm_stub = stub(llm, "generate")

    local keys = vim.api.nvim_replace_termcodes('<CR>', true, true, true)
    vim.api.nvim_feedkeys(keys, 'mtx', false)

    ---@type MakeGenerateRequestArgs
    local args = llm_stub.calls[1].refs[1]

    local long_content = ""
    for _ = 1, 1000, 1 do
      long_content = long_content .. "\n"
    end

    args.on_read(nil, long_content)

    local last_line = vim.api.nvim_buf_line_count(vim.api.nvim_win_get_buf(code.right_winid))
    local win_height = vim.api.nvim_win_get_height(code.right_winid)
    local expected_scroll = last_line - win_height + 1
    local actual_scroll = vim.fn.line('w0', code.right_winid)

    assert.equal(expected_scroll, actual_scroll)

    -- Now press s-tab to get into the window
    keys = vim.api.nvim_replace_termcodes('<S-Tab>', true, true, true)
    vim.api.nvim_feedkeys(keys, 'mtx', false)

    -- Another big response
    args.on_read(nil, long_content)

    -- This time we should stay put
    last_line = vim.api.nvim_buf_line_count(vim.api.nvim_win_get_buf(code.right_winid))
    win_height = vim.api.nvim_win_get_height(code.right_winid)
    expected_scroll = actual_scroll -- unchanged since last check
    actual_scroll = vim.fn.line('w0', code.right_winid)

    assert.equal(expected_scroll, actual_scroll)
  end)

  it("handles llm errors gracefully", function()
    local code = code_window.build_and_mount()

    local llm_stub = stub(llm, "generate")

    local keys = vim.api.nvim_replace_termcodes('<CR>', true, true, true)
    vim.api.nvim_feedkeys(keys, 'mtx', false)

    ---@type MakeGenerateRequestArgs
    local args = llm_stub.calls[1].refs[1]

    args.on_read("llm-error", nil)

    local found_match = false
    local right_lines = vim.api.nvim_buf_get_lines(code.right_bufnr, 0, -1, true)
    for _, line in ipairs(right_lines) do
      if string.match(line, "llm%-error") then
        found_match = true
      end
    end
    assert(found_match)

    -- This would mean the provider called on_read with no error and no response
    -- Happens sometimes with openai, probably my fault. Just testing to make
    -- sure it doesn't error.
    args.on_read(nil, nil)

  end)
end)
