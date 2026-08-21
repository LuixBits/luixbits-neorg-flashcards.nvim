-- The hub's action catalogue is the single source of truth for buffer-local
-- mappings, contextual footer hints, and the in-app help panel.

local M = {}

M.bindings = {
  { key = "q", action = "close", description = "Close the flashcard hub" },
  { key = "<Esc>", action = "escape", description = "Clear a card filter, or close the hub" },
  { key = "?", action = "context_help", description = "Show keys for the current page" },
  { key = "H", action = "plugin_help", description = "Open the full plugin guide", capability = "help" },
  { key = "1", action = "overview", description = "Open Overview" },
  { key = "2", action = "cards", description = "Open Cards" },
  { key = "3", action = "stats", description = "Open Stats" },
  { key = "<Tab>", action = "next_page", description = "Open the next page" },
  { key = "<S-Tab>", action = "previous_page", description = "Open the previous page" },
  { key = "j", action = "next", description = "Select the next card" },
  { key = "<Down>", action = "next", description = "Select the next card" },
  { key = "k", action = "previous", description = "Select the previous card" },
  { key = "<Up>", action = "previous", description = "Select the previous card" },
  { key = "<CR>", action = "activate", description = "Run the primary action" },
  { key = "r", action = "review", description = "Review the selected queue or card" },
  { key = "d", action = "review_due", description = "Review everything due now" },
  { key = "A", action = "review_all", description = "Review the full collection" },
  { key = "a", action = "add", description = "Add a flashcard", capability = "add" },
  { key = "/", action = "search", description = "Search cards" },
  { key = "f", action = "filter", description = "Choose a card state filter" },
  { key = "o", action = "sort", description = "Cycle card sorting" },
  { key = "X", action = "clear", description = "Clear search and filter" },
  {
    key = "x",
    action = "toggle_suspend",
    description = "Suspend or unsuspend the selected card",
    capability = "suspend",
  },
  { key = "b", action = "bury", description = "Bury the selected card until tomorrow", capability = "bury" },
  { key = "p", action = "peek", description = "Open the selected card preview" },
  { key = "e", action = "open_source", description = "Edit the selected card source" },
  { key = "c", action = "check", description = "Check the flashcard collection", capability = "check" },
  { key = "m", action = "migrate", description = "Migrate collection metadata", capability = "migrate" },
  { key = "R", action = "refresh", description = "Reload the collection" },
  -- Kept as a compatibility bridge for the original two-pane dashboard.
  { key = "s", action = "alternate_pane", description = "Move to the other hub region" },
}

local page_hints = {
  overview = {
    { key = "<CR>", label = "review due" },
    { key = "a", label = "add", capability = "add" },
    { key = "j/k", label = "queue" },
    { key = "2", label = "cards" },
    { key = "3", label = "stats" },
    { key = "?", label = "help" },
    { key = "q", label = "close" },
  },
  cards = {
    { key = "/", label = "search" },
    { key = "f", label = "filter" },
    { key = "o", label = "sort" },
    { key = "j/k", label = "select" },
    { key = "<CR>", label = "review" },
    { key = "x", label = "suspend", capability = "suspend" },
    { key = "b", label = "bury", capability = "bury" },
    { key = "?", label = "help" },
    { key = "q", label = "close" },
  },
  stats = {
    { key = "2", label = "cards" },
    { key = "d", label = "review due" },
    { key = "A", label = "review all" },
    { key = "R", label = "refresh" },
    { key = "?", label = "help" },
    { key = "q", label = "close" },
  },
}

local page_actions = {
  overview = {
    "activate",
    "add",
    "next",
    "previous",
    "review",
    "peek",
    "open_source",
    "review_all",
    "check",
    "migrate",
  },
  cards = {
    "search",
    "filter",
    "sort",
    "clear",
    "toggle_suspend",
    "bury",
    "next",
    "previous",
    "activate",
    "peek",
    "open_source",
    "add",
    "check",
    "migrate",
  },
  stats = { "review_due", "review_all", "refresh", "check", "migrate" },
}

local always_help = { "overview", "cards", "stats", "next_page", "previous_page", "context_help", "close" }

local function has_capability(item, capabilities)
  return item.capability == nil or (capabilities and capabilities[item.capability]) == true
end

local function binding_by_action(action)
  for _, item in ipairs(M.bindings) do
    if item.action == action then
      return item
    end
  end
end

local function display_key(key)
  return key:gsub("<CR>", "Enter"):gsub("<Esc>", "Esc"):gsub("<Tab>", "Tab"):gsub("<S%-Tab>", "S-Tab")
end

function M.footer(page, width, capabilities)
  local parts = {}
  for _, hint in ipairs(page_hints[page] or page_hints.overview) do
    if has_capability(hint, capabilities) then
      table.insert(parts, display_key(hint.key) .. " " .. hint.label)
    end
  end

  local prefix = " "
  local suffix = " "
  local separator = "  \194\183  "
  local result = prefix .. table.concat(parts, separator) .. suffix
  width = math.max(12, tonumber(width) or 80)
  while vim.fn.strdisplaywidth(result) > width and #parts > 3 do
    table.remove(parts, #parts - 2)
    result = prefix .. table.concat(parts, separator) .. suffix
  end
  return result
end

function M.help_lines(page, capabilities)
  local wanted = {}
  for _, action in ipairs(always_help) do
    wanted[action] = true
  end
  for _, action in ipairs(page_actions[page] or {}) do
    wanted[action] = true
  end

  local title = page:sub(1, 1):upper() .. page:sub(2)
  local lines = {
    "* " .. title .. " keys",
    "",
    "The footer is generated from these actions.",
    "",
  }
  for _, item in ipairs(M.bindings) do
    if wanted[item.action] and has_capability(item, capabilities) and item.key ~= "<Esc>" then
      table.insert(lines, string.format("  %-9s %s", display_key(item.key), item.description))
    end
  end
  table.insert(lines, "")
  table.insert(lines, "  q / Esc  close this help")
  return lines
end

function M.available_bindings(capabilities)
  local result = {}
  for _, item in ipairs(M.bindings) do
    if has_capability(item, capabilities) then
      table.insert(result, item)
    end
  end
  return result
end

function M.description(action)
  local item = binding_by_action(action)
  return item and item.description or action
end

return M
