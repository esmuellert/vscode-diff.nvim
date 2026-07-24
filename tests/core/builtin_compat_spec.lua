-- Tests for the built-in diff compatibility layer (codediff.builtin_compat)
local helpers = require('tests.helpers')

describe('builtin_compat', function()
  before_each(function()
    helpers.ensure_plugin_loaded()
    require('codediff.builtin_compat').setup()
  end)

  describe('command registration', function()
    it('registers :Diffsplit and :Diffoff proxy commands', function()
      assert.equals(2, vim.fn.exists(':Diffsplit'))
      assert.equals(2, vim.fn.exists(':Diffoff'))
    end)
  end)

  describe('apply_diffopt (iwhite -> ignore_trim_whitespace)', function()
    it('maps iwhite/iwhiteeol to ignore_trim_whitespace', function()
      local config = require('codediff.config')
      config.options.builtin_compat.sync_diffopt = true
      local compat = require('codediff.builtin_compat')

      -- Preserve the user's diffopt and restore it afterwards.
      local saved = vim.o.diffopt

      vim.o.diffopt = 'internal,filler,closeoff,iwhite'
      compat.apply_diffopt()
      assert.is_true(config.options.diff.ignore_trim_whitespace, 'iwhite should set ignore_trim_whitespace')

      vim.o.diffopt = 'internal,filler,closeoff'
      compat.apply_diffopt()
      assert.is_false(config.options.diff.ignore_trim_whitespace, 'no iwhite should unset ignore_trim_whitespace')

      vim.o.diffopt = saved
    end)

    it('is a no-op when sync_diffopt is disabled', function()
      local config = require('codediff.config')
      config.options.builtin_compat.sync_diffopt = false
      local compat = require('codediff.builtin_compat')
      local saved = vim.o.diffopt

      config.options.diff.ignore_trim_whitespace = false
      vim.o.diffopt = 'iwhite'
      compat.apply_diffopt()
      assert.is_false(config.options.diff.ignore_trim_whitespace, 'should stay unchanged when disabled')

      vim.o.diffopt = saved
    end)
  end)

  describe('command dispatch', function()
    it('Diffoff is inert when not in a codediff view', function()
      -- No codediff session open -> should not error, just notify.
      local lifecycle = require('codediff.ui.lifecycle')
      local tab = vim.api.nvim_get_current_tabpage()
      assert.is_nil(lifecycle.get_session(tab))
      -- Running the command should be safe (no error raised).
      assert.has_no.errors(function()
        vim.cmd("Diffoff")
      end)
    end)
  end)
end)
