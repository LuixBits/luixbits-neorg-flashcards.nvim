-- Buffer-local shortcuts live here so mappings, compact footer hints, and
-- contextual help cannot quietly disagree with one another.

local M = {}

local HUB = { "overview", "cards", "stats" }
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
    action({ "q" }, "close", "Close the flashcard hub", HUB, {
      hints = { overview = "close", cards = "close", stats = "close" },
      essential = true,
    }),
    action({ "<Esc>" }, "escape", "Clear a card filter, or close the hub", HUB),
    action({ "?" }, "context_help", "Show keys for the current page", HUB, {
      hints = { overview = "keys", cards = "keys", stats = "keys" },
      essential = true,
    }),
    -- Keep destructive discovery near `?` so the Cards ribbon retains it in
    -- the normal 54-column detail pane. It still drops before core navigation
    -- in the narrowest stacked layout.
    action({ "D" }, "delete_card", "Delete the selected card after confirmation", { "cards" }, {
      hints = { cards = "delete" },
      capability = "delete",
    }),
    action({ "H" }, "plugin_help", "Open the full plugin guide", HUB, { capability = "help" }),
    action({ "1" }, "overview", "Open Overview", HUB),
    action({ "2" }, "cards", "Open Cards", HUB, { hints = { overview = "cards", stats = "cards" } }),
    action({ "3" }, "stats", "Open Stats", HUB, { hints = { overview = "stats" } }),
    action({ "<Tab>" }, "next_page", "Open the next page", HUB),
    action({ "<S-Tab>" }, "previous_page", "Open the previous page", HUB),
    action({ "j", "<Down>" }, "next", "Select the next item or scroll the focused pane", HUB, {
      hint_key = "j/k",
      hints = { overview = "navigate", cards = "navigate", stats = "scroll" },
      essential = true,
      descriptions = {
        overview = "Select the next card; scroll when the side pane is focused",
        cards = "Select the next card; scroll when the detail pane is focused",
        stats = "Scroll the focused pane down",
      },
    }),
    action({ "k", "<Up>" }, "previous", "Select the previous item or scroll the focused pane", HUB, {
      descriptions = {
        overview = "Select the previous card; scroll when the side pane is focused",
        cards = "Select the previous card; scroll when the detail pane is focused",
        stats = "Scroll the focused pane up",
      },
    }),
    action({ "<C-d>", "<PageDown>" }, "scroll_down", "Scroll the focused pane down half a page", HUB, {
      hint_key = "Ctrl-D/U",
      hint_id = "page_scroll",
      hints = { overview = "page", cards = "page", stats = "page" },
    }),
    action({ "<C-u>", "<PageUp>" }, "scroll_up", "Scroll the focused pane up half a page", HUB),
    action({ "gg" }, "scroll_top", "Go to the first item or top of the focused pane", HUB),
    action({ "G" }, "scroll_bottom", "Go to the last item or bottom of the focused pane", HUB),
    action({ "<CR>" }, "activate", "Run the primary action", HUB, {
      descriptions = {
        overview = "Review everything due now",
        cards = "Review the selected card",
        stats = "Open Cards",
      },
      hints = { overview = "review due", cards = "review" },
    }),
    action({ "r" }, "review", "Review the selected queue or card", HUB),
    action({ "d" }, "review_due", "Review everything due now", HUB, {
      hints = { stats = "review due" },
    }),
    action({ "A" }, "review_all", "Review the full collection", HUB, { hints = { stats = "review all" } }),
    action({ "a" }, "add", "Add a flashcard", { "overview", "cards" }, {
      hints = { overview = "add" },
      capability = "add",
    }),
    action({ "/" }, "search", "Search cards", { "cards" }, {
      hints = { cards = "search" },
    }),
    action({ "f" }, "filter", "Choose a card state filter", { "cards" }, { hints = { cards = "filter" } }),
    action({ "o" }, "sort", "Cycle card sorting", { "cards" }, { hints = { cards = "sort" } }),
    action({ "X" }, "clear", "Clear search and filter", { "cards" }),
    action({ "x" }, "toggle_suspend", "Suspend or unsuspend the selected card", { "cards" }, {
      hints = { cards = "suspend" },
      capability = "suspend",
    }),
    action({ "b" }, "bury", "Bury the selected card until tomorrow", { "cards" }, {
      hints = { cards = "bury" },
      capability = "bury",
    }),
    action({ "p" }, "peek", "Open the selected card preview", { "overview", "cards" }),
    action({ "e" }, "open_source", "Edit the selected card source", { "overview", "cards" }),
    action({ "c" }, "check", "Check the flashcard collection", HUB, { capability = "check" }),
    action({ "m" }, "migrate", "Migrate collection metadata", HUB, { capability = "migrate" }),
    action({ "R" }, "refresh", "Reload the collection", HUB, { hints = { stats = "refresh" } }),
  },
  review = {
    action({ "q", "<Esc>" }, "close", "Close review", REVIEW_ALL, {
      hints = { review_question = "close", review_answer = "close", review_complete = "close" },
      essential = true,
    }),
    action({ "?" }, "context_help", "Show keys for the current review state", REVIEW_ALL, {
      hints = { review_question = "keys", review_answer = "keys", review_complete = "keys" },
      essential = true,
    }),
    action({ "<CR>", "<Space>" }, "flip_or_next", "Reveal the answer", { "review_question", "review_complete" }, {
      descriptions = {
        review_question = "Reveal the answer",
        review_complete = "Close the completed review",
      },
      hint_key = { review_question = "Enter/Space", review_complete = "Enter" },
      hints = { review_question = "reveal", review_complete = "return" },
      essential = { review_question = true },
    }),
    action({ "j" }, "next", "Browse the next pending card", REVIEW_ACTIVE, {
      hint_key = "j/k",
      hints = { review_question = "browse", review_answer = "browse" },
    }),
    action({ "k" }, "previous", "Browse the previous pending card", REVIEW_ACTIVE),
    action({ "h" }, "hint", "Show a progressive hint", { "review_question" }, {
      hints = { review_question = "hint" },
    }),
    action({ "t" }, "type_answer", "Type and check the answer", { "review_question" }, {
      hints = { review_question = "type" },
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
    action({ "e" }, "edit", "Edit the current card source", REVIEW_ACTIVE),
    action({ "b" }, "bury", "Bury the card until tomorrow", REVIEW_ACTIVE, {
      hints = { review_question = "bury", review_answer = "bury" },
      capability = "bury",
    }),
    action({ "x" }, "suspend", "Suspend the card", REVIEW_ACTIVE, {
      hints = { review_question = "suspend", review_answer = "suspend" },
      capability = "suspend",
    }),
  },
  form = {
    action({ "q", "<Esc>" }, "close", "Cancel the add form (Normal mode)", { "form" }, {
      modes = { "n" },
      hint_key = "q",
      hints = { form = "close" },
      essential = true,
    }),
    action({ "?" }, "context_help", "Show form keys (Normal mode)", { "form" }, {
      modes = { "n" },
      hints = { form = "keys" },
      essential = true,
    }),
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
    }),
    action({ "<CR>" }, "next_or_save", "Move next; save and return from the last field (Insert mode)", { "form" }, {
      modes = { "i" },
      hint_key = "Enter",
      hints = { form = "next/save" },
    }),
    action({ "<Tab>" }, "next_form_field", "Move to the next field (Insert mode)", { "form" }, {
      modes = { "i" },
      hint_key = "Tab/S-Tab",
      hints = { form = "fields" },
    }),
    action({ "<S-Tab>" }, "previous_form_field", "Move to the previous field (Insert mode)", { "form" }, {
      modes = { "i" },
    }),
    action({ "<Esc>" }, "leave_insert", "Leave the field and return to Normal mode", { "form" }, {
      modes = { "i" },
    }),
    action({ "j" }, "next_form_field", "Select the next field (Normal mode)", { "form" }, {
      modes = { "n" },
      hint_key = "j/k",
      hints = { form = "fields" },
    }),
    action({ "k" }, "previous_form_field", "Select the previous field (Normal mode)", { "form" }, {
      modes = { "n" },
    }),
    action({ "<CR>", "i" }, "edit_field", "Edit the selected field (Normal mode)", { "form" }, {
      modes = { "n" },
    }),
  },
}

local context_titles = {
  overview = "Overview keys",
  cards = "Cards keys",
  stats = "Stats keys",
  review_question = "Review keys · question",
  review_answer = "Review keys · answer",
  review_complete = "Review keys · complete",
  form = "Add form keys",
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
    ["<C-s>"] = "Ctrl-S",
    ["<C-n>"] = "Ctrl-N",
    ["<C-d>"] = "Ctrl-D",
    ["<C-u>"] = "Ctrl-U",
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

local function description_for(item, context)
  return context_value(item.descriptions, context) or item.description or item.action
end

local function keys_for_help(item)
  local keys = {}
  for _, key in ipairs(item.keys or {}) do
    table.insert(keys, display_key(key))
  end
  return table.concat(keys, " / ")
end

function M.title(context)
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

function M.footer(context, width, capabilities)
  local parts = {}
  local seen = {}
  for _, item in ipairs(catalog[surface_for(context)] or {}) do
    local hint = context_value(item.hints, context)
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

  local function rendered()
    local values = {}
    for _, part in ipairs(parts) do
      table.insert(values, part.text)
    end
    return " " .. table.concat(values, "  \194\183  ") .. " "
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
  return result
end

function M.help_lines(context, capabilities)
  local lines = {
    "* " .. M.title(context),
    "",
    "These are the shortcuts available here.",
    "",
  }
  for _, item in ipairs(catalog[surface_for(context)] or {}) do
    if contains(item.contexts, context) and has_capability(item, capabilities) then
      table.insert(lines, string.format("  %-17s %s", keys_for_help(item), description_for(item, context)))
    end
  end
  table.insert(lines, "")
  table.insert(lines, "  q / Esc / ?       close this help window")
  return lines
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
