-- @description ZoneMixZero
-- @version 1.0.0
-- @author Rock Kennedy
-- @about
--   # ZoneMixZero
--   Sets envelope points on every track at start and end of each region.
-- @changelog
--   Name Change
  
reaper.Undo_BeginBlock()
reaper.Main_OnCommand(40296, 0) -- select all tracks
reaper.Main_OnCommand(40406, 0) -- Runs the "Render to File" command
local num_tracks = reaper.CountTracks(nil)
local num_markers, num_regions = reaper.CountProjectMarkers(nil)
for mi = 0, num_markers + num_regions - 1 do
  local rv, isrgn, start_pos, end_pos = reaper.EnumProjectMarkers(mi)
  if rv and isrgn then
    for ti = 0, num_tracks - 1 do
      local track = reaper.GetTrack(nil, ti)
      local env = reaper.GetTrackEnvelopeByName(track, "Volume")
      if env then
        reaper.InsertEnvelopePoint(env, start_pos, .501, 0, 0, true, true)
        reaper.InsertEnvelopePoint(env, end_pos, .501, 0, 0, true, true)
        reaper.Envelope_SortPoints(env)
      end
    end
  end
end

local UNDO_STATE_TRACKENV = 32
reaper.Undo_EndBlock('Insert points at region boundaries in every track volume envelopes', UNDO_STATE_TRACKENV)

