-- @description RestartRecording
-- @version 1.0
-- @author Rock Kennedy
-- @about
--   Immediately gives another try at a failed recording attempt.

command_id = 40668

-- Run the action
reaper.Main_OnCommand(command_id, 0)

command_id = 1013

-- Run the action
reaper.Main_OnCommand(command_id, 0)
