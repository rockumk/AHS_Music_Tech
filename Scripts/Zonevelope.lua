-- @description Zonvelope
-- @author Rock Kennedy
-- @version 1.0.0
-- @about
--   Zonevelope - Sets volume envelope points on every track at start and end of each region.
-- @changelog
--   First Release

function dBFromVal(val) return 20*math.log(val, 100) end
function ValFromdB(dB_val) return ((10^((dB_val)/10))) end
-- y = 0.1581 * x^2 + 7.416 * x + 716.2
function ValFromdB(dB_val) return ((dB_val+150)^4.4/5270672.893) end

local customvolume = 0
local makechange = false
local SliderFlags_None = 0
local result1, result2
local ctx = reaper.ImGui_CreateContext('Zone Level Choice')
reaper.ImGui_SetNextWindowSize(ctx, 888, 995, reaper.ImGui_Cond_FirstUseEver())
local radioSelection = { value = 1 }
local function loop()
  local rv
  local lumox
  reaper.ImGui_SetNextWindowSize(ctx,310, 700)
  local visible, open = reaper.ImGui_Begin(ctx, 'Zonvelope', 1, ImGui_WindowFlags_NoCollapse)
  if visible then
  reaper.ImGui_Text( ctx, '\nThis script creates volume zones by \nadding pairs of volume envelope points\nto every track and region of your song.\nThese zones can then serve as faders.\n\nThis script should be run only ONCE...\nafter all tracks are prepped, but before\nyou have added your own volume envelope\npoints.\n\nCustom volumes are approximate.\n\nAt what volume do you wish to set ALL of\nyour zones?\n\n')
  
 reaper.ImGui_BeginGroup(ctx) 
  if reaper.ImGui_RadioButton( ctx, " No Change", radioSelection.value == 1 ) then
    radioSelection.value = 1
  end
  if reaper.ImGui_RadioButton( ctx, "+12 dB", radioSelection.value == 2 ) then
    radioSelection.value = 2
  end
  if reaper.ImGui_RadioButton( ctx, " +6 dB", radioSelection.value == 3 ) then
    radioSelection.value = 3
  end
  if reaper.ImGui_RadioButton( ctx, " +3 dB", radioSelection.value == 4 ) then
    radioSelection.value = 4
  end
  if reaper.ImGui_RadioButton( ctx, "  0 dB", radioSelection.value == 5 ) then
    radioSelection.value = 5
  end
  if reaper.ImGui_RadioButton( ctx, " -3 dB", radioSelection.value == 6 ) then
    radioSelection.value = 6
  end
  if reaper.ImGui_RadioButton( ctx, " -6 dB", radioSelection.value == 7 ) then
    radioSelection.value = 7
  end
  if reaper.ImGui_RadioButton( ctx, " -9 dB", radioSelection.value == 8 ) then
    radioSelection.value = 8
  end
  if reaper.ImGui_RadioButton( ctx, "-12 dB", radioSelection.value == 9 ) then
    radioSelection.value = 9
  end
  if reaper.ImGui_RadioButton( ctx, "-18 dB", radioSelection.value == 10 ) then
    radioSelection.value = 10
  end
  if reaper.ImGui_RadioButton( ctx, "-24 dB", radioSelection.value == 11 ) then
    radioSelection.value = 11
  end
  if reaper.ImGui_RadioButton( ctx, "-30 dB", radioSelection.value == 12 ) then
    radioSelection.value = 12
  end
  if reaper.ImGui_RadioButton( ctx, "-40 dB", radioSelection.value == 13 ) then
    radioSelection.value = 13
  end
  if reaper.ImGui_RadioButton( ctx, "-60 dB", radioSelection.value == 14 ) then
    radioSelection.value = 14
  end
  if reaper.ImGui_RadioButton( ctx, "-90 dB", radioSelection.value == 15 ) then
    radioSelection.value = 15
  end
  if reaper.ImGui_RadioButton( ctx, "-inf dB", radioSelection.value == 16 ) then
    radioSelection.value = 16
  end

  
   reaper.ImGui_EndGroup(ctx)
   reaper.ImGui_SameLine(ctx, 40,121 )
   reaper.ImGui_BeginGroup(ctx)
   if reaper.ImGui_RadioButton( ctx, "Custom", radioSelection.value == 17 ) then
     radioSelection.value = 17
   end
  if radioSelection.value ==  17 then

retval, customvolume = reaper.ImGui_VSliderDouble( ctx, "##dbvolume", 140, 340, customvolume, -150, 12,"", reaper.ImGui_SliderFlags_Logarithmic())

  end
   reaper.ImGui_EndGroup(ctx)
   reaper.ImGui_Spacing(ctx)
   reaper.ImGui_Spacing(ctx)
   reaper.ImGui_Spacing(ctx)
   
   if radioSelection.value == 1 then 
   shownumber = ValFromdB(12)
   reaper.ImGui_Text(ctx,"Add points - Leave all Volumes unchanged")
   reaper.ImGui_Spacing(ctx)
   makechange = false
   end   
   
   if radioSelection.value == 2 then 
   shownumber = 1000
   reaper.ImGui_Text(ctx,shownumber)
   reaper.ImGui_SameLine(ctx, 40,123 )
   reaper.ImGui_Text(ctx,"+12 dB")
   reaper.ImGui_Spacing(ctx)
   makechange = true
   end
   
   if radioSelection.value == 3 then 
   shownumber = 852.77445440699
   reaper.ImGui_Text(ctx,shownumber)
   reaper.ImGui_SameLine(ctx, 40,123 )
   reaper.ImGui_Text(ctx,"+6 dB")
   reaper.ImGui_Spacing(ctx)
   makechange = true
   end
   
   if radioSelection.value == 4 then 
   shownumber = 782.75892367871
   reaper.ImGui_Text(ctx,shownumber)
   reaper.ImGui_SameLine(ctx, 40,123 )
   reaper.ImGui_Text(ctx,"+3 dB")
   reaper.ImGui_Spacing(ctx)
   makechange = true
   end  
   
   if radioSelection.value == 5 then
   shownumber = 716.2178503
   reaper.ImGui_Text(ctx,shownumber)
   reaper.ImGui_SameLine(ctx, 40,123 )
   reaper.ImGui_Text(ctx,"0 dB")
   reaper.ImGui_Spacing(ctx)
   makechange = true
   end
   
   if radioSelection.value == 6 then
   shownumber = 652.8388356
   reaper.ImGui_Text(ctx,shownumber)
   reaper.ImGui_SameLine(ctx, 40,123 )
   reaper.ImGui_Text(ctx,"-3 dB")
   reaper.ImGui_Spacing(ctx)
   makechange = true
   end
   
   if radioSelection.value == 7 then
   shownumber = 592.84833614363
   reaper.ImGui_Text(ctx,shownumber)
   reaper.ImGui_SameLine(ctx, 40,123 )
   reaper.ImGui_Text(ctx,"-6 dB")
   reaper.ImGui_Spacing(ctx)
   makechange = true
   end
   
   if radioSelection.value == 8 then 
   shownumber = 536.48410029014
   reaper.ImGui_Text(ctx,shownumber)
   reaper.ImGui_SameLine(ctx, 40,123 )
   reaper.ImGui_Text(ctx,"-9 dB")
   reaper.ImGui_Spacing(ctx)
   makechange = true
   end
   
   if radioSelection.value == 9 then 
   shownumber = 483.94960711346
   reaper.ImGui_Text(ctx,shownumber)
   reaper.ImGui_SameLine(ctx, 40,123 )
   reaper.ImGui_Text(ctx,"-12 dB")
   reaper.ImGui_Spacing(ctx)
   makechange = true
   end
   
   if radioSelection.value == 10 then 
   shownumber = 390.79705422132
   reaper.ImGui_Text(ctx,shownumber)
   reaper.ImGui_SameLine(ctx, 40,123 )
   reaper.ImGui_Text(ctx,"-18 dB")
   reaper.ImGui_Spacing(ctx)
   makechange = true
   end
   
   if radioSelection.value == 11 then 
   shownumber = 313.29868329181
   reaper.ImGui_Text(ctx,shownumber)
   reaper.ImGui_SameLine(ctx, 40,123 )
   reaper.ImGui_Text(ctx,"-24 dB")
   reaper.ImGui_Spacing(ctx)
   makechange = true
   end
   
   if radioSelection.value == 12 then 
   shownumber = 250.09008724531
   reaper.ImGui_Text(ctx,shownumber)
   reaper.ImGui_SameLine(ctx, 40,123 )
   reaper.ImGui_Text(ctx,"-30 dB")
   reaper.ImGui_Spacing(ctx)
   makechange = true
   end
   
   if radioSelection.value == 13 then 
   shownumber = 170.98374287074
   reaper.ImGui_Text(ctx,shownumber)
   reaper.ImGui_SameLine(ctx, 40,123 )
   reaper.ImGui_Text(ctx,"-40 dB")
   reaper.ImGui_Spacing(ctx)
   makechange = true
   end
   
   if radioSelection.value == 14 then 
   shownumber = 79.482342854382
   reaper.ImGui_Text(ctx,shownumber)
   reaper.ImGui_SameLine(ctx, 40,123 )
   reaper.ImGui_Text(ctx,"-60 dB")
   reaper.ImGui_Spacing(ctx)
   makechange = true
   end
   
   if radioSelection.value == 15 then 
   shownumber = 25.138596785163
   reaper.ImGui_Text(ctx,shownumber)
   reaper.ImGui_SameLine(ctx, 40,123 )
   reaper.ImGui_Text(ctx,"-90 dB")
   reaper.ImGui_Spacing(ctx)
   makechange = true
   end
   
   if radioSelection.value == 16 then 
   shownumber = 0
   reaper.ImGui_Text(ctx,shownumber)
   reaper.ImGui_SameLine(ctx, 40,123 )
   reaper.ImGui_Text(ctx,"-inf dB")
   reaper.ImGui_Spacing(ctx)
   makechange = true
   end
   
   
   
   
   
   
   
   
   
   
   
   
   
   if radioSelection.value == 17 then 
   shownumber = ValFromdB(customvolume)
   reaper.ImGui_Text(ctx,shownumber)
   reaper.ImGui_SameLine(ctx, 40,123 )
   reaper.ImGui_Text(ctx,customvolume .. " dB")
   reaper.ImGui_Spacing(ctx)
   makechange = true
   end
   
   reaper.ImGui_Spacing(ctx)
   reaper.ImGui_Spacing(ctx)
   reaper.ImGui_Spacing(ctx)
   result1 = reaper.ImGui_Button(ctx, "Cancel",140, 40)
   reaper.ImGui_SameLine(ctx, 50,111 )
   result2 = reaper.ImGui_Button(ctx, "Zone it!",140, 40)
   
if result1 then 
open = false
run_it = false
end

if result2 then
open = false
run_it = true
end
  
   reaper.ImGui_End(ctx)
  end
  if open then
    reaper.defer(loop)
    
  else
  if run_it then

-----------------------------------------------------------------------


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
        local _, startvalue, _, _, _ = reaper.Envelope_Evaluate(env, start_pos, 0 , 0)
        local _, endvalue, _, _, _ = reaper.Envelope_Evaluate(env, end_pos, 0 , 0)
        
        if makechange then
        reaper.InsertEnvelopePoint(env, start_pos, shownumber, 0, 0, false, true)
        reaper.InsertEnvelopePoint(env, end_pos, shownumber, 0, 0, false, true)      
        
        else
        reaper.InsertEnvelopePoint(env, start_pos, startvalue, 0, 0, false, true)
        reaper.InsertEnvelopePoint(env, end_pos, endvalue, 0, 0, false, true)
        end
        
        
        
        
        reaper.Envelope_SortPoints(env)
      end
    end
  end
end
local UNDO_STATE_TRACKENV = 32
reaper.Undo_EndBlock('Insert points at region boundaries in every track volume envelopes', UNDO_STATE_TRACKENV)





-----------------------------------------------------------------------
else


end
  
  end
end


reaper.defer(loop)

