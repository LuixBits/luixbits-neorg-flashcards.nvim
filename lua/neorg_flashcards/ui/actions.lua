-- Buffer-local shortcuts live here so mappings, compact footer hints, and
-- contextual help cannot quietly disagree with one another.

local M = {}

local HUB = { "desk", "overview", "stats" }
local REVIEW_ACTIVE = { "review_question", "review_answer" }
local REVIEW_ALL = { "review_question", "review_answer", "review_complete" }

local function action(keys, name, description, contexts, extra)
  local item = extra or {}
  item.keys = keys
  item.action = name
  item.description = description
  item.contexts = contexts
  return item
end

local catalog = {
  hub = {
    action({ "h", "<Left>" }, "left", "Select left / go back", HUB, {
      descriptions = {
        desk = "Select the previous box or note",
        overview = "Go back to chapters or collections",
        stats = "Select the previous day",
      },
    }),
    action({ "l", "<Right>" }, "right", "Select right / open selection", HUB, {
      descriptions = {
        desk = "Select the next box or note",
        overview = "Open the collection, chapter or card",
        stats = "Select the next day",
      },
    }),
    action({ "[" }, "month_previous", "Previous month", { "stats" }),
    action({ "]" }, "month_next", "Next month", { "stats" }),
    action({ "." }, "today", "Select today", { "stats" }),
    action(
      { "m" },
      "manage",
      "Actions for the selected collection, chapter or card",
      { "overview" },
      { hints = { overview = "manage" }, capability = "manage" }
    ),
    action({ "g" }, "category", "Filter cards by tag / switch Desk chapters and tags", { "desk", "overview" }),
    action({ "n" }, "new_chapter", "Create a chapter", { "overview" }, { capability = "manage" }),
    action({ "M" }, "move_card", "Move the selected card to a chapter", { "overview" }, { capability = "move_card" }),
    action({ "q" }, "close", "Close the flashcard hub", HUB, {
      hints = { desk = "close", overview = "close", stats = "close" },
      essential = true,
    }),
    action({ "<Esc>" }, "escape", "Clear a card filter, or close the hub", HUB),
    action({ "?" }, "context_help", "Show keys for the current page", HUB, {
      hints = { desk = "keys", overview = "keys", stats = "keys" },
      essential = true,
    }),
    -- Keep destructive discovery near `?` so the Cards ribbon retains it in
    -- the normal 54-column detail pane. It still drops before core navigation
    -- in the narrowest stacked layout.
    action({ "D" }, "delete_card", "Delete the selected card after confirmation", { "overview" }, {
      hints = { overview = "delete" },
      capability = "delete",
    }),
    action({ "H" }, "plugin_help", "Open the quick plugin guide", HUB, { capability = "help" }),
    action({ "C" }, "collection", "Switch collection", HUB, {
      hints = { desk = "collection", overview = "collection", stats = "collection" },
      capability = "collection",
    }),
    action({ "1" }, "desk", "Open Desk", HUB),
    action({ "2" }, "overview", "Open Overview", HUB, { hints = { desk = "overview", stats = "overview" } }),
    action({ "3" }, "stats", "Open Stats", HUB, { hints = { desk = "stats" } }),
    action({ "<Tab>" }, "next_page", "Open the next page", HUB),
    action({ "<S-Tab>" }, "previous_page", "Open the previous page", HUB),
    action({ "j", "<Down>" }, "next", "Select the next item or scroll the focused pane", HUB, {
      hint_key = "j/k",
      hints = { desk = "navigate", overview = "navigate", stats = "calendar" },
      essential = { desk = true, overview = true },
      descriptions = {
        desk = "Select the next row of boxes or notes",
        overview = "Select the next collection, chapter or card; scroll in details",
        stats = "Select the next week; scroll when the detail pane is focused",
      },
    }),
    action({ "k", "<Up>" }, "previous", "Select the previous item or scroll the focused pane", HUB, {
      descriptions = {
        desk = "Select the previous row of boxes or notes",
        overview = "Select the previous collection, chapter or card; scroll in details",
        stats = "Select the previous week; scroll when the detail pane is focused",
      },
    }),
    action({ "<C-h>" }, "focus_left", "Focus the pane to the left (also Ctrl-W h)", { "overview", "stats" }, {
      hint_key = "Ctrl-h/j/k/l",
      hints = { overview = "panes", stats = "panes" },
    }),
    action({ "<C-j>" }, "focus_down", "Focus the pane below (also Ctrl-W j)", { "overview", "stats" }),
    action({ "<C-k>" }, "focus_up", "Focus the pane above (also Ctrl-W k)", { "overview", "stats" }),
    action({ "<C-l>" }, "focus_right", "Focus the pane to the right (also Ctrl-W l)", { "overview", "stats" }),
    action({ "<C-w>w" }, "focus_other_pane", "Focus the other hub pane", { "overview", "stats" }),
    action({ "<C-d>", "<PageDown>" }, "scroll_down", "Scroll the focused pane down half a page", HUB, {
      hint_key = "Ctrl-D/U",
      hint_id = "page_scroll",
      hints = { desk = "page", overview = "page", stats = "scroll" },
      essential = { stats = true },
    }),
    action({ "<C-u>", "<PageUp>" }, "scroll_up", "Scroll the focused pane up half a page", HUB),
    action({ "gg" }, "scroll_top", "Go to the first item or top of the focused pane", HUB),
    action({ "G" }, "scroll_bottom", "Go to the last item or bottom of the focused pane", HUB),
    action({ "<CR>" }, "activate", "Run the primary action", HUB, {
      descriptions = {
        desk = "Open the selected deck or study category",
        overview = "Open the collection or chapter; review a selected card",
        stats = "Inspect cards reviewed or scheduled on the selected day",
      },
      hints = { desk = "open/study", overview = "open" },
    }),
    action({ "r" }, "review", "Review the selected queue or card", HUB, { capability = "review_selected" }),
    action({ "d" }, "review_due", "Review everything due now", HUB, {
      hints = { stats = "review due" },
    }),
    action({ "A" }, "review_all", "Review the full collection", HUB, { hints = { stats = "review all" } }),
    action({ "a" }, "add", "Add a card here / create a collection", { "desk", "overview" }, {
      hints = { desk = "add" },
      capability = "add",
    }),
    action({ "/" }, "search", "Search cards or category notes", { "desk", "overview" }, {
      hints = { overview = "search" },
    }),
    action({ "f" }, "filter", "Choose a card view or type", { "overview" }, { hints = { overview = "view" } }),
    action({ "o" }, "sort", "Cycle card sorting", { "overview" }, { hints = { overview = "sort" } }),
    action({ "X" }, "clear", "Clear search and filter", { "overview" }),
    action({ "x" }, "toggle_suspend", "Suspend or resume the selected card", { "overview" }, {
      hints = { overview = "suspend" },
      capability = "suspend",
      presentation = function(_, action_state)
        if action_state and action_state.selected_availability == "suspended" then
          return { description = "Resume the selected card", hint = "resume" }
        elseif action_state and action_state.selected_availability then
          return { description = "Suspend the selected card until you resume it", hint = "suspend" }
        end
      end,
    }),
    action({ "b" }, "bury", "Bury the selected card until tomorrow", { "overview" }, {
      hints = { overview = "bury" },
      capability = "bury",
      presentation = function(_, action_state)
        if action_state and action_state.selected_availability == "buried" then
          return { description = "Unbury the selected card", hint = "unbury" }
        end
      end,
    }),
    action({ "p" }, "peek", "Open the selected card preview", { "desk", "overview" }),
    action({ "e" }, "edit_card", "Edit the selected card", { "desk", "overview" }, {
      presentation = function(_, state)
        if state and state.selection_kind and state.selection_kind ~= "card" then
          return { description = "Rename the selected collection or chapter" }
        end
      end,
    }),
    action({ "c" }, "check", "Check the flashcard collection", HUB, { capability = "check" }),
    action({ "R" }, "refresh", "Reload the collection", HUB, { hints = { stats = "refresh" } }),
  },
  review = {
    action({ "h", "<Left>", "q", "<Esc>" }, "close", "Return to the workspace", REVIEW_ALL, {
      hints = { review_question = "back", review_answer = "back", review_complete = "back" },
      essential = true,
    }),
    action({ "?" }, "context_help", "Show keys for the current review state", REVIEW_ALL, {
      hints = { review_question = "keys", review_answer = "keys", review_complete = "keys" },
      essential = true,
    }),
    action(
      { "l", "<Right>", "<CR>", "<Space>" },
      "flip_or_next",
      "Reveal the answer",
      { "review_question", "review_complete" },
      {
        descriptions = {
          review_question = "Reveal the answer",
          review_complete = "Close the completed review",
        },
        hint_key = "l/Enter",
        hints = { review_question = "reveal", review_complete = "return" },
        essential = { review_question = true },
      }
    ),
    action({ "j", "<Down>" }, "next", "Browse the next pending card", REVIEW_ACTIVE, {
      hint_key = "j/k",
      hints = { review_question = "browse", review_answer = "browse" },
    }),
    action({ "k", "<Up>" }, "previous", "Browse the previous pending card", REVIEW_ACTIVE),
    action({ "H" }, "hint", "Show a progressive hint", { "review_question" }, {
      hints = { review_question = "hint" },
    }),
    action({ "t" }, "type_answer", "Type and check the answer", { "review_question" }, {
      hints = { review_question = "type" },
      capability = "type_answer",
    }),
    action({ "1" }, "rate_again", "Rate Again", REVIEW_ACTIVE, {
      descriptions = {
        review_question = "Reveal first, then rate Again",
        review_answer = "Rate Again",
      },
      hint_key = "1/2/3",
      hints = { review_answer = "rate" },
      essential = { review_answer = true },
    }),
    action({ "2" }, "rate_hard", "Rate Hard", REVIEW_ACTIVE, {
      descriptions = {
        review_question = "Reveal first, then rate Hard",
        review_answer = "Rate Hard",
      },
    }),
    action({ "3" }, "rate_good", "Rate Good", REVIEW_ACTIVE, {
      descriptions = {
        review_question = "Reveal first, then rate Good",
        review_answer = "Rate Good",
      },
    }),
    action({ "u" }, "undo", "Undo the last rating", REVIEW_ALL, {
      hints = { review_answer = "undo", review_complete = "undo" },
      essential = { review_complete = true },
    }),
    action({ "s" }, "stats", "Open Stats", { "review_complete" }, {
      hints = { review_complete = "stats" },
      capability = "stats",
    }),
    action({ "e" }, "edit", "Edit the current card", REVIEW_ACTIVE),
    action({ "b" }, "bury", "Bury the card until tomorrow", REVIEW_ACTIVE, {
      hints = { review_question = "bury", review_answer = "bury" },
      capability = "bury",
    }),
    action({ "x" }, "suspend", "Suspend the card until you resume it with x in Overview", REVIEW_ACTIVE, {
      hints = { review_question = "suspend", review_answer = "suspend" },
      capability = "suspend",
    }),
  },
  form = {
    action({ "<C-s>" }, "save_close", "Save the card and return (Normal or Insert mode)", { "form" }, {
      modes = { "n", "i" },
      hint_key = "Ctrl-S",
      hints = { form = "save" },
      essential = true,
    }),
    action({ "<C-n>" }, "save_new", "Save and start another card (Normal or Insert mode)", { "form" }, {
      modes = { "n", "i" },
      hint_key = "Ctrl-N",
      hints = { form = "new" },
      capability = "save_new",
    }),
    action({ "<Tab>" }, "next_form_field", "Move to the next field (Normal or Insert mode)", { "form" }, {
      modes = { "n", "i" },
      hint_key = "Tab/S-Tab",
      hints = { form = "fields" },
    }),
    action({ "<S-Tab>" }, "previous_form_field", "Move to the previous field (Normal or Insert mode)", { "form" }, {
      modes = { "n", "i" },
    }),
    action({ "?" }, "context_help", "Show form keys (Normal mode)", { "form" }, {
      modes = { "n" },
      hints = { form = "keys" },
      essential = true,
    }),
    action({ "q", "<Esc>" }, "close", "Close the card form (Normal mode)", { "form" }, {
      modes = { "n" },
      hint_key = "q",
      hints = { form = "close" },
      essential = true,
    }),
    action({ "<CR>" }, "next_or_save", "Move next; save and return from the last field (Insert mode)", { "form" }, {
      modes = { "i" },
      hint_key = "Enter",
      hints = { form = "next/save" },
    }),
    action({ "<Esc>" }, "leave_insert", "Leave the field and return to Normal mode", { "form" }, {
      modes = { "i" },
    }),
    action({ "<CR>", "i" }, "edit_field", "Edit the selected field (Normal mode)", { "form" }, {
      modes = { "n" },
    }),
  },
}

local context_titles = {
  desk = "Desk keys",
  overview = "Overview keys",
  stats = "Stats keys",
  review_question = "Review keys · question",
  review_answer = "Review keys · answer",
  review_complete = "Review keys · complete",
  form = "Card form keys",
}

local function contains(values, expected)
  for _, value in ipairs(values or {}) do
    if value == expected then
      return true
    end
  end
  return false
end

local function has_capability(item, capabilities)
  return item.capability == nil or (capabilities and capabilities[item.capability]) == true
end

local function surface_for(context)
  if context == "hub" or contains(HUB, context) then
    return "hub"
  end
  if context == "review" or contains(REVIEW_ALL, context) then
    return "review"
  end
  if context == "form" then
    return "form"
  end
end

local function display_key(key)
  local labels = {
    ["<CR>"] = "Enter",
    ["<Esc>"] = "Esc",
    ["<Tab>"] = "Tab",
    ["<S-Tab>"] = "S-Tab",
    ["<Space>"] = "Space",
    ["<Down>"] = "Down",
    ["<Up>"] = "Up",
    ["<Left>"] = "Left",
    ["<Right>"] = "Right",
    ["<C-h>"] = "Ctrl-H",
    ["<C-j>"] = "Ctrl-J",
    ["<C-k>"] = "Ctrl-K",
    ["<C-l>"] = "Ctrl-L",
    ["<C-s>"] = "Ctrl-S",
    ["<C-n>"] = "Ctrl-N",
    ["<C-d>"] = "Ctrl-D",
    ["<C-u>"] = "Ctrl-U",
    ["<C-w>w"] = "Ctrl-W W (<C-w>w)",
    ["<PageDown>"] = "PageDown",
    ["<PageUp>"] = "PageUp",
  }
  return labels[key] or key
end

local function context_value(value, context)
  if type(value) == "table" then
    return value[context]
  end
  return value
end

local function presentation_for(item, context, action_state)
  if type(item.presentation) ~= "function" then
    return {}
  end
  local ok, presentation = pcall(item.presentation, context, action_state)
  if ok and type(presentation) == "table" then
    return presentation
  end
  return {}
end

local function description_for(item, context, action_state)
  local presentation = presentation_for(item, context, action_state)
  return presentation.description or context_value(item.descriptions, context) or item.description or item.action
end

local function keys_for_help(item)
  local keys = {}
  for _, key in ipairs(item.keys or {}) do
    table.insert(keys, display_key(key))
  end
  return table.concat(keys, " / ")
end

function M.title(context, _)
  return context_titles[context] or "Flashcard keys"
end

---Return concrete mappings for a whole surface. Context filtering happens in
---the generated help and footer; mappings stay installed as the UI changes.
function M.available_bindings(surface, capabilities)
  surface = surface_for(surface) or surface
  local result = {}
  for _, item in ipairs(catalog[surface] or {}) do
    if has_capability(item, capabilities) then
      for _, mode in ipairs(item.modes or { "n" }) do
        for _, key in ipairs(item.keys or {}) do
          table.insert(result, {
            key = key,
            mode = mode,
            action = item.action,
            description = item.description or item.action,
          })
        end
      end
    end
  end
  return result
end

---Return whether an action is valid in the current context. Mappings remain
---installed across page changes, so dispatchers must enforce this boundary.
function M.is_available(surface, action_name, context, capabilities)
  surface = surface_for(surface) or surface
  for _, item in ipairs(catalog[surface] or {}) do
    if item.action == action_name then
      return contains(item.contexts, context) and has_capability(item, capabilities)
    end
  end
  return false
end

function M.footer(context, width, capabilities)
  local parts = {}
  local seen = {}
  for _, item in ipairs(catalog[surface_for(context)] or {}) do
    local presentation = presentation_for(item, context, capabilities)
    local hint = presentation.hint or context_value(item.hints, context)
    if hint and contains(item.contexts, context) and has_capability(item, capabilities) then
      local id = item.hint_id or item.action
      if not seen[id] then
        seen[id] = true
        table.insert(parts, {
          text = string.format("%s %s", context_value(item.hint_key, context) or display_key(item.keys[1]), hint),
          essential = context_value(item.essential, context) == true,
        })
      end
    end
  end

  local function rendered(compact)
    local values = {}
    for _, part in ipairs(parts) do
      table.insert(values, part.text)
    end
    return " " .. table.concat(values, compact and " \194\183 " or "  \194\183  ") .. " "
  end

  width = math.max(12, tonumber(width) or 80)
  local result = rendered()
  while vim.fn.strdisplaywidth(result) > width and #parts > 3 do
    local remove_index
    for index = #parts, 1, -1 do
      if not parts[index].essential then
        remove_index = index
        break
      end
    end
    if not remove_index then
      break
    end
    table.remove(parts, remove_index)
    result = rendered()
  end
  return vim.fn.strdisplaywidth(result) > width and rendered(true) or result
end

function M.help_lines(context, capabilities)
  local lines = {
    "* " .. M.title(context, capabilities),
    "",
    "These are the shortcuts available here.",
    "",
  }
  local rows, key_width = {}, 17
  for _, item in ipairs(catalog[surface_for(context)] or {}) do
    if contains(item.contexts, context) and has_capability(item, capabilities) then
      local keys = keys_for_help(item)
      key_width = math.max(key_width, vim.fn.strdisplaywidth(keys))
      table.insert(rows, { keys = keys, description = description_for(item, context, capabilities) })
    end
  end
  for _, row in ipairs(rows) do
    local padding = string.rep(" ", key_width - vim.fn.strdisplaywidth(row.keys) + 2)
    table.insert(lines, "  " .. row.keys .. padding .. row.description)
  end
  if context == "form" then
    table.insert(lines, "")
    table.insert(lines, "  j/k or arrows     move through the editable lines (Normal mode)")
    table.insert(lines, "  o/O               add a line in a multiline field (Normal mode)")
    table.insert(lines, "  u / Ctrl-R        undo / redo changes (Normal mode)")
  end
  table.insert(lines, "")
  table.insert(lines, "  /                 find text in this help window")
  table.insert(lines, "  n / N             next / previous match")
  table.insert(lines, "  q / Esc / ?       close this help window")
  return lines
end

function M.help_footer()
  return " / find · n/N matches · q/Esc/? close "
end

function M.description(surface, name, context)
  surface = surface_for(surface) or surface
  for _, item in ipairs(catalog[surface] or {}) do
    if item.action == name then
      return description_for(item, context)
    end
  end
  return name
end

return M
