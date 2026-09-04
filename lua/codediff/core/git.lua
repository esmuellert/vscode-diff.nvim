-- Public facade for Git operations.
local M = {}

local changes = require("codediff.core.git.changes")
local content = require("codediff.core.git.content")
local history = require("codediff.core.git.history")
local refs = require("codediff.core.git.refs")
local repository = require("codediff.core.git.repository")
local revision = require("codediff.core.git.revision")
local statistics = require("codediff.core.git.statistics")
local worktree = require("codediff.core.git.worktree")

M.get_git_root = repository.get_git_root
M.get_git_root_sync = repository.get_git_root_sync
M.get_git_dir = repository.get_git_dir
M.get_relative_path = repository.get_relative_path

M.resolve_revision = revision.resolve_revision
M.get_revision_parents = revision.get_revision_parents
M.get_merge_base = revision.get_merge_base
M.resolve_path_at_revision = revision.resolve_path_at_revision
M.get_rev_candidates = revision.get_rev_candidates

M.list_remote_refs = refs.list_remote_refs
M.fetch_remote_refs = refs.fetch_remote_refs
M.list_local_refs = refs.list_local_refs
M.delete_local_refs = refs.delete_local_refs

M.clear_cache = content.clear_cache
M.get_file_content = content.get_file_content

M.get_status = changes.get_status
M.get_diff_revision = changes.get_diff_revision
M.get_diff_revisions = changes.get_diff_revisions
M.get_diff_staged = changes.get_diff_staged
M.get_commit_files = changes.get_commit_files

M.get_status_with_line_stats = statistics.get_status_with_line_stats
M.get_diff_revision_with_line_stats = statistics.get_diff_revision_with_line_stats
M.get_diff_revisions_with_line_stats = statistics.get_diff_revisions_with_line_stats

M.apply_patch = worktree.apply_patch
M.stage_file = worktree.stage_file
M.unstage_file = worktree.unstage_file
M.stage_all = worktree.stage_all
M.unstage_all = worktree.unstage_all
M.restore_file = worktree.restore_file
M.delete_untracked = worktree.delete_untracked

M.get_commit_list = history.get_commit_list

return M
