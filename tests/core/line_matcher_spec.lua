local config = require("codediff.config")
local diff = require("codediff.core.diff")

local compute = function(original, modified, line_matcher, options)
  return diff.compute_diff(
    original,
    modified,
    vim.tbl_extend("force", options or {}, {
      line_matcher = line_matcher,
      max_computation_time_ms = 60000,
    })
  )
end

describe("Line matching", function()
  after_each(function()
    config.options = vim.deepcopy(config.defaults)
  end)

  it("defaults to native similarity matching", function()
    assert.same({ strategy = "similarity", threshold = 0.75 }, config.defaults.diff.line_matcher)
    local result = compute({ "local old_name = 1" }, { "local new_name = 1" }, nil)
    assert.equal(1, #result.changes[1].line_mappings)
  end)

  local invalid_options = {
    {
      name = "rejects a non-table matcher",
      value = "similarity",
      pattern = "must be a table",
    },
    {
      name = "rejects an unknown strategy",
      value = { strategy = "unknown" },
      pattern = "must be one of",
    },
    {
      name = "rejects an unknown option",
      value = { strategy = "similarity", window = 10 },
      pattern = "unknown diff.line_matcher option",
    },
    {
      name = "rejects a negative threshold",
      value = { strategy = "similarity", threshold = -0.1 },
      pattern = "between 0 and 1",
    },
    {
      name = "rejects a threshold above one",
      value = { strategy = "similarity", threshold = 1.1 },
      pattern = "between 0 and 1",
    },
    {
      name = "rejects a non-number threshold",
      value = { strategy = "similarity", threshold = "high" },
      pattern = "between 0 and 1",
    },
    {
      name = "rejects a vscode threshold",
      value = { strategy = "vscode", threshold = 0.5 },
      pattern = "only valid for the similarity strategy",
    },
    {
      name = "rejects an equal-line-count threshold",
      value = { strategy = "equal_line_count", threshold = 0.5 },
      pattern = "only valid for the similarity strategy",
    },
  }

  for _, test_case in ipairs(invalid_options) do
    it(test_case.name, function()
      local success, message = pcall(config.setup, { diff = { line_matcher = test_case.value } })
      assert.is_false(success)
      assert.matches(test_case.pattern, message)
    end)
  end

  it("replaces strategy-specific options cleanly", function()
    config.setup({ diff = { line_matcher = { strategy = "vscode" } } })
    assert.same({ strategy = "vscode" }, config.options.diff.line_matcher)
  end)

  it("validates direct compute options", function()
    local success, message = pcall(compute, { "old" }, { "new" }, { strategy = "vscode", threshold = 0.5 })
    assert.is_false(success)
    assert.matches("only valid for the similarity strategy", message)
  end)

  local mapping_cases = {
    {
      name = "vscode maps a complete many-to-many block",
      strategy = { strategy = "vscode" },
      original = { "old one", "old two" },
      modified = { "new one", "new two", "new three" },
      expected = { { 1, 3, 1, 4 } },
      has_inner_changes = true,
    },
    {
      name = "equal_line_count maps equal blocks positionally",
      strategy = { strategy = "equal_line_count" },
      original = { "old one", "old two" },
      modified = { "new one", "new two" },
      expected = { { 1, 2, 1, 2 }, { 2, 3, 2, 3 } },
      has_inner_changes = true,
    },
    {
      name = "equal_line_count leaves unequal blocks unmatched",
      strategy = { strategy = "equal_line_count" },
      original = { "old one" },
      modified = { "new one", "new two" },
      expected = {},
      has_inner_changes = false,
    },
    {
      name = "similarity leaves unrelated lines unmatched",
      strategy = { strategy = "similarity" },
      original = { "aaaaaaaa" },
      modified = { "zzzzzzzz" },
      expected = {},
      has_inner_changes = false,
    },
    {
      name = "similarity maps ordered lines around an unmatched gap",
      strategy = { strategy = "similarity" },
      original = { "local old_name = 1", "removed without match", "print(old_name)" },
      modified = { "local new_name = 1", "print(new_name)", "unrelated insertion" },
      expected = { { 1, 2, 1, 2 }, { 3, 4, 2, 3 } },
      has_inner_changes = true,
    },
  }

  for _, test_case in ipairs(mapping_cases) do
    it(test_case.name, function()
      local result = compute(test_case.original, test_case.modified, test_case.strategy)
      local mappings = {}
      for index, mapping in ipairs(result.changes[1].line_mappings) do
        mappings[index] = {
          mapping.original.start_line,
          mapping.original.end_line,
          mapping.modified.start_line,
          mapping.modified.end_line,
        }
      end
      assert.same(test_case.expected, mappings)
      assert.equal(test_case.has_inner_changes, #result.changes[1].inner_changes > 0)
    end)
  end

  it("honors similarity threshold boundaries", function()
    local rejected = compute({ "cat" }, { "cut" }, { strategy = "similarity" })
    local accepted = compute({ "cat" }, { "cut" }, { strategy = "similarity", threshold = 2 / 3 })
    assert.equal(0, #rejected.changes[1].line_mappings)
    assert.equal(1, #accepted.changes[1].line_mappings)
  end)

  it("preserves original-major tie ordering", function()
    local result = compute({ "alpha old", "alpha old" }, { "alpha new", "alpha new" }, { strategy = "similarity", threshold = 0.5 })
    assert.same({ start_line = 1, end_line = 2 }, result.changes[1].line_mappings[1].original)
    assert.same({ start_line = 1, end_line = 2 }, result.changes[1].line_mappings[1].modified)
    assert.same({ start_line = 2, end_line = 3 }, result.changes[1].line_mappings[2].original)
    assert.same({ start_line = 2, end_line = 3 }, result.changes[1].line_mappings[2].modified)
  end)

  it("uses byte-based similarity for unicode input", function()
    local result = compute({ "café" }, { "cafe" }, { strategy = "similarity", threshold = 0.6 })
    assert.equal(1, #result.changes[1].line_mappings)
  end)

  local trim_whitespace_cases = {
    { name = "whitespace-only lines", original = "    ", modified = "" },
    { name = "leading whitespace removal", original = "  x", modified = "x" },
    { name = "leading whitespace addition", original = "x", modified = "  x" },
    { name = "trailing whitespace removal", original = "x  ", modified = "x" },
    { name = "trailing whitespace addition", original = "x", modified = "x  " },
    { name = "leading and trailing whitespace", original = "  value  ", modified = "value" },
  }

  for _, test_case in ipairs(trim_whitespace_cases) do
    it("refines " .. test_case.name .. " for every matcher", function()
      for _, strategy in ipairs({ "similarity", "vscode", "equal_line_count" }) do
        local result = compute({ "before", test_case.original, "after" }, { "before", test_case.modified, "after" }, { strategy = strategy })
        assert.equal(1, #result.changes)
        assert.equal(1, #result.changes[1].line_mappings)
        assert.is_true(#result.changes[1].inner_changes > 0)
      end
    end)
  end

  it("leaves pure changes unmatched except for vscode", function()
    local strategies = { "similarity", "equal_line_count" }
    for _, strategy in ipairs(strategies) do
      local insertion = compute({ "before", "after" }, { "before", "added", "after" }, { strategy = strategy })
      local deletion = compute({ "before", "removed", "after" }, { "before", "after" }, { strategy = strategy })
      assert.equal(0, #insertion.changes[1].line_mappings)
      assert.equal(0, #deletion.changes[1].line_mappings)
    end

    local vscode = compute({ "before", "after" }, { "before", "added", "after" }, { strategy = "vscode" })
    assert.equal(1, #vscode.changes[1].line_mappings)
  end)

  it("preserves ignored whitespace and subword options", function()
    local whitespace = compute({ "  value" }, { "    value  " }, { strategy = "similarity" }, { ignore_trim_whitespace = true })
    assert.equal(0, #whitespace.changes)

    local subword = compute({ "local oldValueName = 1" }, { "local newValueName = 1" }, { strategy = "similarity" }, { extend_to_subwords = true })
    assert.is_true(#subword.changes[1].inner_changes > 0)
  end)

  it("handles empty Neovim buffers", function()
    for _, strategy in ipairs({ "similarity", "vscode", "equal_line_count" }) do
      local result = compute({ "" }, { "content" }, { strategy = strategy })
      assert.equal(1, #result.changes)
    end
  end)
end)
