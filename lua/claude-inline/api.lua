--- DEPRECATED: This module contained the old OpenAI integration.
--- Claude Code handles all LLM interactions now.
--- Keeping this file as a stub to avoid breaking requires.
local M = {}

-- Functions removed in Phase 5:
-- - get_response(): OpenAI curl calls - replaced by Claude Code terminal
-- - accept_api_response() / reject_api_response(): Old extmark-based flow - replaced by diff.lua
-- - get_old_code_region() / get_new_code_region(): Helper UI for old flow - removed

return M
