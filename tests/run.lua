local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
vim.opt.runtimepath:prepend(root)

local support = dofile(root .. "/tests/support.lua")
local suites = {
  "setup_schema_spec.lua",
  "collection_spec.lua",
  "store_spec.lua",
  "form_spec.lua",
  "persistence_spec.lua",
  "schedule_analytics_spec.lua",
  "review_queue_spec.lua",
  "dashboard_spec.lua",
  "review_session_spec.lua",
  "resilience_spec.lua",
}

for _, filename in ipairs(suites) do
  local path = root .. "/tests/" .. filename
  local loader, load_error = loadfile(path)
  assert(loader, load_error)
  local suite = loader()
  assert(type(suite) == "function", path .. " must return a test function")
  suite(support)
end

vim.g.neorg_flashcards_tests_passed = true
print("neorg_flashcards tests passed")
