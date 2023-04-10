-- @description ZoSplit
-- @version 1.0.0
-- @author Rock Kennedy
-- @about
--   # ZoSplit
--   Sets 2 envelope points on every track at cursor.
-- @changelog
--   New


reaper.Undo_BeginBlock()
local num_tracks = reaper.CountTracks(nil)
local num_markers, num_regions = reaper.CountProjectMarkers(nil)
samplerate = tonumber(reaper.SNM_GetIntConfigVar("projsrate", 0))
cursor_pos = reaper.GetCursorPosition()
for ti = 0, num_tracks - 1 do
  local track = reaper.GetTrack(nil, ti)
  local env = reaper.GetTrackEnvelopeByName(track, "Volume")
  if env then
    local _, value, _, _, _ = reaper.Envelope_Evaluate(env, cursor_pos, 0 , 0)
    reaper.InsertEnvelopePoint(env, cursor_pos, value, 0, 0, false, true)
    reaper.InsertEnvelopePoint(env, cursor_pos, value, 0, 0, false, true)
    reaper.Envelope_SortPoints(env)
  end
end
local UNDO_STATE_TRACKENV = 32
reaper.Undo_EndBlock('Insert points at region boundaries in every track volume envelopes', UNDO_STATE_TRACKENV)
