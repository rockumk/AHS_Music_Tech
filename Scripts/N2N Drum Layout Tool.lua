-- @description N2N Drum Layout Tool
-- @author Rock Kennedy + ChatGPT
-- @version 2.4

local r = reaper

----------------------------------------------------------------
-- CONFIG
----------------------------------------------------------------
-- FX Name to search for (partial match):
local TARGET_FX_NAME = "N2N Drum Arranger"

local TRACK_SWING = "Absolute Grid & Reverb"

-- MIDI channel is 0-based in REAPER API:
-- 15 == Channel 16
local CH_PC   = 15
local CH_SWNG = 15

local CC_BANK_MSB = 0
local CC_SWING    = 119

local DEFAULT_SWING = 0

local GAP = 6
local BTN_H = 28
local SMALL_W = 28
local SECT_W  = (SMALL_W * 2) + GAP

-- TOP ROW button widths (Updated per your manual tweaks)
local W_OFF     = 62   -- 55 + 7
local W_DEF     = 62   -- 55 + 7
local W_CLEAR   = 97   -- 90 + 7
local W_SET_SW  = 94
local W_PROCESS = 144  -- 120 + 24

-- UI
local UI_MUTE = 0.55  -- 0..1 (lower = more muted)
local UI_GRAY = 0.25  -- baseline gray blend
local SWING_SLIDER_W = 130

-- Text stamp items:
local TEXT_ITEM_BEATS = 4
local TEXT_STAMP_TAG  = "Drum"  -- marker used for Clear All


----------------------------------------------------------------
-- COLOR UTILS
  ----------------------------------------------------------------
local function clamp01(x)
  return (x < 0) and 0 or ((x > 1) and 1 or x)
end

local function mute_rgb(rr,gg,bb)
  return UI_GRAY + (rr-UI_GRAY)*UI_MUTE,
         UI_GRAY + (gg-UI_GRAY)*UI_MUTE,
         UI_GRAY + (bb-UI_GRAY)*UI_MUTE
end

local function brighten_rgb(rr,gg,bb, amt)
  return rr + (1-rr)*amt,
         gg + (1-gg)*amt,
         bb + (1-bb)*amt
end

local function rgba_u32(rr,gg,bb,aa)
  return r.ImGui_ColorConvertDouble4ToU32(
    clamp01(rr), clamp01(gg), clamp01(bb), clamp01(aa or 1)
  )
end

local function item_color_native(rr, gg, bb)
  local R = math.floor(clamp01(rr) * 255 + 0.5)
  local G = math.floor(clamp01(gg) * 255 + 0.5)
  local B = math.floor(clamp01(bb) * 255 + 0.5)
  return r.ColorToNative(R, G, B) | 0x1000000
end


----------------------------------------------------------------
-- TIME
----------------------------------------------------------------
local function qn64()
  return 1/16 -- 1/64 note in QN
end

local function get_timesig_at_time(t)
  if r.TimeMap2_GetTimeSigAtTime then
    local ok, rv, num, den = pcall(r.TimeMap2_GetTimeSigAtTime, 0, t)
    if ok and num and den and den ~= 0 then
      return num, den
    end
  end

  if r.TimeMap_GetTimeSigAtTime then
    local ok, a, b = pcall(r.TimeMap_GetTimeSigAtTime, 0, t)
    if ok and a and b and b ~= 0 then
      return a, b
    end

    local ok2, c, d = pcall(r.TimeMap_GetTimeSigAtTime, t)
    if ok2 and c and d and d ~= 0 then
      return c, d
    end
  end

  return 4, 4
end

local function beats_to_qn_at_time(t, beats)
  local _, den = get_timesig_at_time(t)
  local beat_qn = 4 / (den or 4)
  return (beats or 4) * beat_qn
end

-- 1/64 early, but never earlier than 0.0
local function stamp_time_64_or_zero(cursor_time)
  local qn = r.TimeMap2_timeToQN(0, cursor_time) - qn64()
  local t  = r.TimeMap2_QNToTime(0, qn)
  if t < 0 then t = 0 end
  return t
end


----------------------------------------------------------------
-- TAB DEFINITIONS
----------------------------------------------------------------
local tabs = {}
local function t(id, row, name, w, rr, gg, bb, prog)
  tabs[#tabs+1] = {id=id,row=row,name=name,w=w,r=rr,g=gg,b=bb,prog=prog}
end

-- ROW 1
t(0,0,"Off",55,0.7,0.7,0.7,0)

t(1,1,"Intro",SECT_W,0.2,1.0,1.0,11)
t(2,1,"2",SMALL_W,0.2,1.0,1.0,12)
t(3,1,"3",SMALL_W,0.2,1.0,1.0,13)

t(4,1,"Verse",SECT_W,0.4,0.6,1.0,21)
t(5,1,"2",SMALL_W,0.4,0.6,1.0,22)
t(6,1,"3",SMALL_W,0.4,0.6,1.0,23)

t(7,1,"Pre",SECT_W,0.7,0.4,1.0,31)
t(8,1,"2",SMALL_W,0.7,0.4,1.0,32)
t(9,1,"3",SMALL_W,0.7,0.4,1.0,33)

t(10,1,"Chorus",SECT_W,1.0,0.4,0.4,41)
t(11,1,"2",SMALL_W,1.0,0.4,0.4,42)
t(12,1,"3",SMALL_W,1.0,0.4,0.4,43)

t(13,1,"Bridge",SECT_W,1.0,0.9,0.2,51)
t(14,1,"2",SMALL_W,1.0,0.9,0.2,52)
t(15,1,"3",SMALL_W,1.0,0.9,0.2,53)

t(16,1,"Outro",SECT_W,0.5,0.8,0.7,61)
t(17,1,"2",SMALL_W,0.5,0.8,0.7,62)
t(18,1,"3",SMALL_W,0.5,0.8,0.7,63)

t(19,1,"Hit 1",44,0.8,0.8,0.8,71)
t(20,1,"Hit 2",44,0.8,0.8,0.8,72)

t(21,1,"Fill 1<",44,0.7,0.4,1.0,81)
t(22,1,"Fill 1=",44,0.7,0.4,1.0,82)
t(23,1,"Fill 1>",44,0.7,0.4,1.0,83)

t(24,1,"Flex 1",44,0.8,0.8,0.8,91)
t(25,1,"Flex 2",44,0.8,0.8,0.8,92)
t(26,1,"Flex 3",44,0.8,0.8,0.8,93)
t(27,1,"Flex 4",44,0.8,0.8,0.8,94)
t(28,1,"Flex 5",44,0.8,0.8,0.8,95)

-- ROW 2
t(29,0,"Def",55,0.8,0.8,0.8,101)

t(30,2,"4",SMALL_W,0.2,1.0,1.0,14)
t(31,2,"5",SMALL_W,0.2,1.0,1.0,15)
t(32,2,"6",SMALL_W,0.2,1.0,1.0,16)
t(33,2,"7",SMALL_W,0.2,1.0,1.0,17)

t(34,2,"4",SMALL_W,0.4,0.6,1.0,24)
t(35,2,"5",SMALL_W,0.4,0.6,1.0,25)
t(36,2,"6",SMALL_W,0.4,0.6,1.0,26)
t(37,2,"7",SMALL_W,0.4,0.6,1.0,27)

t(38,2,"4",SMALL_W,0.7,0.4,1.0,34)
t(39,2,"5",SMALL_W,0.7,0.4,1.0,35)
t(40,2,"6",SMALL_W,0.7,0.4,1.0,36)
t(41,2,"7",SMALL_W,0.7,0.4,1.0,37)

t(42,2,"4",SMALL_W,1.0,0.4,0.4,44)
t(43,2,"5",SMALL_W,1.0,0.4,0.4,45)
t(44,2,"6",SMALL_W,1.0,0.4,0.4,46)
t(45,2,"7",SMALL_W,1.0,0.4,0.4,47)

t(46,2,"4",SMALL_W,1.0,0.9,0.2,54)
t(47,2,"5",SMALL_W,1.0,0.9,0.2,55)
t(48,2,"6",SMALL_W,1.0,0.9,0.2,56)
t(49,2,"7",SMALL_W,1.0,0.9,0.2,57)

t(50,2,"4",SMALL_W,0.5,0.8,0.7,64)
t(51,2,"5",SMALL_W,0.5,0.8,0.7,65)
t(52,2,"6",SMALL_W,0.5,0.8,0.7,66)
t(53,2,"7",SMALL_W,0.5,0.8,0.7,67)

t(54,2,"Hit 3",44,0.8,0.8,0.8,73)
t(55,2,"Hit 4",44,0.8,0.8,0.8,74)

t(56,2,"Fill 2<",44,0.8,0.3,0.9,84)
t(57,2,"Fill 2=",44,0.8,0.3,0.9,85)
t(58,2,"Fill 2>",44,0.8,0.3,0.9,86)

t(59,2,"Flex 6",44,0.8,0.8,0.8,96)
t(60,2,"Flex 7",44,0.8,0.8,0.8,97)
t(61,2,"Flex 8",44,0.8,0.8,0.8,98)
t(62,2,"Flex 9",44,0.8,0.8,0.8,99)
t(63,2,"Flex 10",44,0.8,0.8,0.8,100)

local prog_to_tabid = {}
local prog_to_color = {}
for _,tb in ipairs(tabs) do
  prog_to_tabid[tb.prog] = tb.id
  prog_to_color[tb.prog] = {tb.r, tb.g, tb.b}
end


----------------------------------------------------------------
-- TRACK HELPERS
----------------------------------------------------------------
local function find_track(name)
  for i=0,r.CountTracks(0)-1 do
    local tr = r.GetTrack(0,i)
    local _,n = r.GetTrackName(tr)
    if n == name then return tr end
  end
end

-- Find track by scanning FX for a partial name match
local function find_drum_track_by_fx()
  for i = 0, r.CountTracks(0) - 1 do
    local tr = r.GetTrack(0, i)
    local fx_count = r.TrackFX_GetCount(tr)
    for fx = 0, fx_count - 1 do
      local retval, buf = r.TrackFX_GetFXName(tr, fx, "")
      if retval and buf:find(TARGET_FX_NAME, 1, true) then
        return tr
      end
    end
  end
  return nil
end


----------------------------------------------------------------
-- LABEL HELPERS
----------------------------------------------------------------
local function tab_label_from_prog(prog)
  if not prog then return nil end

  if prog == 0 then return "Drums Off" end
  if prog == 101 then return "Drums Default" end

  if prog >= 11 and prog <= 17 then
    local v = prog - 10
    return (v == 1) and "Intro" or ("Intro " .. v)
  end
  if prog >= 21 and prog <= 27 then
    local v = prog - 20
    return (v == 1) and "Verse" or ("Verse " .. v)
  end
  if prog >= 31 and prog <= 37 then
    local v = prog - 30
    return (v == 1) and "Pre" or ("Pre " .. v)
  end
  if prog >= 41 and prog <= 47 then
    local v = prog - 40
    return (v == 1) and "Chorus" or ("Chorus " .. v)
  end
  if prog >= 51 and prog <= 57 then
    local v = prog - 50
    return (v == 1) and "Bridge" or ("Bridge " .. v)
  end
  if prog >= 61 and prog <= 67 then
    local v = prog - 60
    return (v == 1) and "Outro" or ("Outro " .. v)
  end

  if prog >= 71 and prog <= 74 then
    return "Hit " .. tostring(prog - 70)
  end

  if prog == 81 then return "Fill 1<" end
  if prog == 82 then return "Fill 1-" end
  if prog == 83 then return "Fill 1>" end

  if prog == 84 then return "Fill 2<" end
  if prog == 85 then return "Fill 2-" end
  if prog == 86 then return "Fill 2>" end

  if prog >= 91 and prog <= 100 then
    return "Flex " .. tostring(prog - 90)
  end

  return "Drums PC " .. tostring(prog)
end


----------------------------------------------------------------
-- ITEM HELPERS
----------------------------------------------------------------
local function ensure_midi_item_at(track, t_start, t_end)
  return r.CreateNewMIDIItemInProj(track, t_start, t_end, false)
end

local function ensure_named_text_item(track, t_start, t_end, label, rr, gg, bb)
  if not track then return nil end

  local it = r.AddMediaItemToTrack(track)
  if not it then return nil end

  r.SetMediaItemInfo_Value(it, "D_POSITION", t_start)
  r.SetMediaItemInfo_Value(it, "D_LENGTH", math.max(0.001, (t_end - t_start)))

  r.GetSetMediaItemInfo_String(it, "P_NAME", label or "", true)
  r.GetSetMediaItemInfo_String(it, "P_NOTES", TEXT_STAMP_TAG .. "\n" .. (label or ""), true)

  if rr and gg and bb then
    r.SetMediaItemInfo_Value(it, "I_CUSTOMCOLOR", item_color_native(rr, gg, bb))
  end

  return it
end

local function stamp_text_clip(track, label, t_time, rr, gg, bb)
  if not track then return end

  local qn_start = r.TimeMap2_timeToQN(0, t_time) -- NO early offset
  local qn_len   = beats_to_qn_at_time(t_time, TEXT_ITEM_BEATS)
  local qn_end   = qn_start + qn_len

  local t_start = r.TimeMap2_QNToTime(0, qn_start)
  local t_end   = r.TimeMap2_QNToTime(0, qn_end)

  ensure_named_text_item(track, t_start, t_end, label, rr, gg, bb)
end


----------------------------------------------------------------
-- MIDI EVENT HELPERS
----------------------------------------------------------------
local function insert_bank_and_pc(take, ppq, bank, prog)
  r.MIDI_InsertCC(take, false, false, ppq,     0xB0, CH_PC, CC_BANK_MSB, bank)
  r.MIDI_InsertCC(take, false, false, ppq + 1, 0xC0, CH_PC, prog,        0)
end

local function insert_swing_cc(take, ppq, value)
  r.MIDI_InsertCC(take, false, false, ppq, 0xB0, CH_SWNG, CC_SWING, value)
end


----------------------------------------------------------------
-- SCAN: nearest preceding Program Change (for highlight)
----------------------------------------------------------------
local function find_active_tab(track, cursor)
  if not track then return end
  local best_ppq, best_prog

  for i=0,r.CountTrackMediaItems(track)-1 do
    local it = r.GetTrackMediaItem(track,i)
    local tk = r.GetActiveTake(it)

    if tk and r.TakeIsMIDI(tk) then
      -- Correctly read Count (retval, notes, ccs, sysex)
      local _, notecnt, cccnt, _ = r.MIDI_CountEvts(tk)
      if cccnt > 0 then
        local cur_ppq = r.MIDI_GetPPQPosFromProjTime(tk, cursor)
        for j=0,cccnt-1 do
          local ok,_,_,ppq,msgtype,chan,msg2,_ = r.MIDI_GetCC(tk,j)
          if ok and chan==CH_PC and msgtype==0xC0 and ppq<=cur_ppq then
            if (not best_ppq) or (ppq > best_ppq) then
              best_ppq, best_prog = ppq, msg2
            end
          end
        end
      end
    end
  end

  return best_prog and prog_to_tabid[best_prog]
end


----------------------------------------------------------------
-- STAMP PC + TEXT
----------------------------------------------------------------
local function stamp_pc(track, prog, bank, cursor)
  if not track then return end

  local t_midi = stamp_time_64_or_zero(cursor)

  local it = ensure_midi_item_at(track, t_midi, t_midi + 1)
  local tk = r.GetActiveTake(it) or r.GetTake(it, 0)
  if not tk or not r.TakeIsMIDI(tk) then return end

  local ppq = r.MIDI_GetPPQPosFromProjTime(tk, t_midi)
  insert_bank_and_pc(tk, ppq, bank, prog)
  r.MIDI_Sort(tk)

  local label = tab_label_from_prog(prog)
  local col = prog_to_color[prog]
  local rr, gg, bb = 0.7, 0.7, 0.7
  if col then rr, gg, bb = col[1], col[2], col[3] end
  stamp_text_clip(track, label, cursor, rr, gg, bb)

  r.UpdateArrange()
end

local function stamp_pc_at_time(track, prog, bank, t_time_for_region)
  if not track then return end

  local t_midi = stamp_time_64_or_zero(t_time_for_region)

  local it = ensure_midi_item_at(track, t_midi, t_midi + 1)
  local tk = r.GetActiveTake(it) or r.GetTake(it, 0)
  if not tk or not r.TakeIsMIDI(tk) then return end

  local ppq = r.MIDI_GetPPQPosFromProjTime(tk, t_midi)
  insert_bank_and_pc(tk, ppq, bank, prog)
  r.MIDI_Sort(tk)

  local label = tab_label_from_prog(prog)
  local col = prog_to_color[prog]
  local rr, gg, bb = 0.7, 0.7, 0.7
  if col then rr, gg, bb = col[1], col[2], col[3] end
  stamp_text_clip(track, label, t_time_for_region, rr, gg, bb)

  r.UpdateArrange()
end


----------------------------------------------------------------
-- STAMP SWING + TEXT
----------------------------------------------------------------
local function stamp_swing(track_swing, swing_value, cursor)
  if not track_swing then return end

  local t_midi = stamp_time_64_or_zero(cursor)

  local it = ensure_midi_item_at(track_swing, t_midi, t_midi + 1)
  local tk = r.GetActiveTake(it) or r.GetTake(it, 0)
  if not tk or not r.TakeIsMIDI(tk) then return end

  local ppq = r.MIDI_GetPPQPosFromProjTime(tk, t_midi)
  insert_swing_cc(tk, ppq, swing_value)
  r.MIDI_Sort(tk)

  stamp_text_clip(track_swing, ("Swing " .. tostring(swing_value)), cursor, 0.35, 0.35, 0.35)

  r.UpdateArrange()
end


----------------------------------------------------------------
-- CLEAR ALL (Nuclear Option / FIXED COUNT)
----------------------------------------------------------------
local function is_probably_n2n_text_item(it)
  local _, name = r.GetSetMediaItemInfo_String(it, "P_NAME", "", false)
  local _, notes = r.GetSetMediaItemInfo_String(it, "P_NOTES", "", false)

  if notes and notes:find(TEXT_STAMP_TAG, 1, true) then
    return true
  end

  name = name or ""
  if name:match("^Drums") then return true end
  if name:match("^Intro") then return true end
  if name:match("^Verse") then return true end
  if name:match("^Pre") then return true end
  if name:match("^Chorus") then return true end
  if name:match("^Bridge") then return true end
  if name:match("^Outro") then return true end
  if name:match("^Hit") then return true end
  if name:match("^Fill") then return true end
  if name:match("^Flex") then return true end
  if name:match("^Swing") then return true end

  return false
end

local function clear_all_drums_stamps(tr_drums)
  if not tr_drums then return end

  r.Undo_BeginBlock()

  for i = r.CountTrackMediaItems(tr_drums) - 1, 0, -1 do
    local it = r.GetTrackMediaItem(tr_drums, i)
    local should_delete = false

    -- 1. Check Text Items (Name match)
    if is_probably_n2n_text_item(it) then
      should_delete = true
    else
      -- 2. Check MIDI Items (Aggressive Content Scan)
      local tk = r.GetActiveTake(it)
      if tk and r.TakeIsMIDI(tk) then
        r.MIDI_Sort(tk)
        
        -- FIX: Read the 3rd return value (cccnt), not 2nd (notecnt)
        local _, notecnt, cccnt, _ = r.MIDI_CountEvts(tk)
        
        -- Loop limit must use cccnt
        for j = 0, cccnt - 1 do
          local ok, _, _, _, msgtype, chan, msg2, _ = r.MIDI_GetCC(tk, j)
          if ok then
            -- Program Change (0xC0..0xCF)
            if (msgtype >= 0xC0 and msgtype <= 0xCF) then
              should_delete = true
              break
            end
            
            -- Bank Select MSB (0xB0..0xBF, CC#0)
            if (msgtype >= 0xB0 and msgtype <= 0xBF) and (msg2 == CC_BANK_MSB) then
              should_delete = true
              break
            end
          end
        end
      end
    end

    if should_delete then
      r.DeleteTrackMediaItem(tr_drums, it)
    end
  end

  r.UpdateArrange()
  r.Undo_EndBlock("N2N Drum Layout Tool: Clear All", -1)
end


----------------------------------------------------------------
-- REGIONS: Process Regions button
----------------------------------------------------------------
local function parse_region_to_prog(name)
  if not name or name == "" then return nil end

  local base_map = {
    Intro  = 11,
    Verse  = 21,
    Pre    = 31,
    Chorus = 41,
    Bridge = 51,
    Outro  = 61,
  }

  local order = {"Intro","Verse","Pre","Chorus","Bridge","Outro"}

  local hit_key = nil
  for _,k in ipairs(order) do
    if name:find(k, 1, true) then
      hit_key = k
      break
    end
  end
  if not hit_key then return nil end

  local var = tonumber(name:match(hit_key.."%s*(%d+)"))
  if not var then var = 1 end
  if var < 1 then var = 1 end
  if var > 7 then var = 7 end

  return base_map[hit_key] + (var - 1)
end

local function stamp_off_at_time0(tr_drums, bank)
  if not tr_drums then return end
  
  -- Always stamp text "Drums Off" at 0.0
  stamp_text_clip(tr_drums, "Drums Off", 0.0, 0.7, 0.7, 0.7)

  -- Create MIDI PC 0
  local t0 = 0.0
  local it0 = ensure_midi_item_at(tr_drums, t0, t0 + 1)
  local tk0 = r.GetActiveTake(it0) or r.GetTake(it0, 0)
  if tk0 and r.TakeIsMIDI(tk0) then
    local ppq0 = r.MIDI_GetPPQPosFromProjTime(tk0, t0)
    insert_bank_and_pc(tk0, ppq0, bank, 0)
    r.MIDI_Sort(tk0)
  end
end

local function process_regions(tr_drums, bank)
  if not tr_drums then return end

  local _, num_markers, num_regions = r.CountProjectMarkers(0)
  local total = (num_markers or 0) + (num_regions or 0)

  local first_valid_drum_region_pos = nil
  local last_region_end  = nil

  for i=0,total-1 do
    local rv, isrgn, pos, rgnend, name = r.EnumProjectMarkers(i)
    if rv and isrgn then
      if (not last_region_end) or (rgnend > last_region_end) then
        last_region_end = rgnend
      end
      if parse_region_to_prog(name) then
        if (not first_valid_drum_region_pos) or (pos < first_valid_drum_region_pos) then
          first_valid_drum_region_pos = pos
        end
      end
    end
  end

  r.Undo_BeginBlock()

  local need_start_off = false
  if not first_valid_drum_region_pos then
    need_start_off = true
  elseif first_valid_drum_region_pos > 0.001 then
    need_start_off = true
  end

  if need_start_off then
    stamp_off_at_time0(tr_drums, bank)
  end

  for i=0,total-1 do
    local rv, isrgn, pos, rgnend, name = r.EnumProjectMarkers(i)
    if rv and isrgn then
      local prog = parse_region_to_prog(name or "")
      if prog then
        stamp_pc(tr_drums, prog, bank, pos)
      end
    end
  end

  if last_region_end then
    stamp_pc_at_time(tr_drums, 0, bank, last_region_end)
  end

  r.Undo_EndBlock("N2N Drum Layout Tool: Process Regions", -1)
end


----------------------------------------------------------------
-- IMGUI
----------------------------------------------------------------
local ctx = r.ImGui_CreateContext("N2N Drum Layout Tool")
local measure_bank = 1
local swing_value = DEFAULT_SWING

local function ui_btn(label, w, h, id)
  return r.ImGui_Button(ctx, label.."##"..id, w, h)
end

local function draw_tab_row(row, active, tr, cursor)
  for _,tb in ipairs(tabs) do
    if tb.row==row then
      local r0,g0,b0 = mute_rgb(tb.r,tb.g,tb.b)
      if active==tb.id then
        r0,g0,b0 = brighten_rgb(r0,g0,b0,0.35)
      end

      r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(),        rgba_u32(r0,g0,b0,1))
      r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), rgba_u32(brighten_rgb(r0,g0,b0,0.20)))
      r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(),  rgba_u32(brighten_rgb(r0,g0,b0,0.30)))
      r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(),          (active==tb.id) and rgba_u32(0,0,0,1) or rgba_u32(1,1,1,1))

      if r.ImGui_Button(ctx, tb.name.."##tab"..tb.id, tb.w, BTN_H) then
        stamp_pc(tr, tb.prog, measure_bank, cursor)
      end

      r.ImGui_PopStyleColor(ctx, 4)
      r.ImGui_SameLine(ctx, nil, GAP)
    end
  end
end

local function loop()
  r.ImGui_SetNextWindowSize(ctx, 1180, 190, r.ImGui_Cond_FirstUseEver())

  local vis,open = r.ImGui_Begin(ctx,"N2N Drum Layout Tool",true)
  if vis then
    local tr_drums = find_drum_track_by_fx()
    if not tr_drums then tr_drums = find_track("N2N Drums") end
    local tr_swing = find_track(TRACK_SWING)

    local cur = r.GetCursorPosition()
    local active = find_active_tab(tr_drums, cur)

    ----------------------------------------------------------------
    -- TOP ROW
    ----------------------------------------------------------------
    do
      -- Off
      do
        local rr,gg,bb = mute_rgb(0.7,0.7,0.7)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), rgba_u32(rr,gg,bb,1))
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), rgba_u32(1,1,1,1))
        if ui_btn("Off", W_OFF, BTN_H, "ctl_off") then
          stamp_pc(tr_drums, 0, measure_bank, cur)
        end
        r.ImGui_PopStyleColor(ctx,2)
      end

      r.ImGui_SameLine(ctx,nil,GAP)

      -- Default
      do
        local rr,gg,bb = mute_rgb(0.85,0.85,0.85)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), rgba_u32(rr,gg,bb,1))
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), rgba_u32(0,0,0,1))
        if ui_btn("Default", W_DEF, BTN_H, "ctl_def") then
          stamp_pc(tr_drums, 101, measure_bank, cur)
        end
        r.ImGui_PopStyleColor(ctx,2)
      end

      r.ImGui_SameLine(ctx,nil,GAP)

      -- Clear All
      do
        local rr,gg,bb = mute_rgb(0.45,0.45,0.45)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), rgba_u32(rr,gg,bb,1))
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), rgba_u32(1,1,1,1))
        if ui_btn("Clear All", W_CLEAR, BTN_H, "ctl_clear") then
          clear_all_drums_stamps(tr_drums)
        end
        r.ImGui_PopStyleColor(ctx,2)
      end

      r.ImGui_SameLine(ctx,nil,GAP*6)

      -- Measure offset radios
      r.ImGui_Text(ctx,"Measure offset:")
      for i=1,4 do
        r.ImGui_SameLine(ctx,nil,GAP)
        if r.ImGui_RadioButton(ctx, "Bar "..i.."##bar"..i, measure_bank==i) then
          measure_bank=i
        end
      end

      r.ImGui_SameLine(ctx,nil,GAP*8)

      -- Swing slider + Set Swing (Manual tweak offset applied to GAP logic here)
      r.ImGui_Text(ctx,"Swing:")
      r.ImGui_SameLine(ctx,nil,GAP+13)

      r.ImGui_PushItemWidth(ctx, SWING_SLIDER_W)
      local changed, v = r.ImGui_SliderInt(ctx, "##swing_amt", swing_value, 0, 100)
      r.ImGui_PopItemWidth(ctx)
      if changed then swing_value = v end

      r.ImGui_SameLine(ctx,nil,GAP)

      do
        local rr,gg,bb = mute_rgb(0.35,0.35,0.35)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), rgba_u32(rr,gg,bb,1))
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), rgba_u32(1,1,1,1))
        if ui_btn("Set Swing", W_SET_SW, BTN_H, "ctl_sw") then
          stamp_swing(tr_swing, swing_value, cur)
        end
        r.ImGui_PopStyleColor(ctx,2)
      end

      r.ImGui_SameLine(ctx,nil,GAP)

      do
        local rr,gg,bb = mute_rgb(0.30,0.30,0.30)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), rgba_u32(rr,gg,bb,1))
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), rgba_u32(1,1,1,1))
        if ui_btn("Process Regions", W_PROCESS, BTN_H, "ctl_pr") then
          process_regions(tr_drums, measure_bank)
        end
        r.ImGui_PopStyleColor(ctx,2)
      end
    end

    r.ImGui_Separator(ctx)

    draw_tab_row(1, active, tr_drums, cur)
    r.ImGui_NewLine(ctx)
    draw_tab_row(2, active, tr_drums, cur)

    r.ImGui_End(ctx)
  end

  if open then
    r.defer(loop)
  else
    if r.ImGui_DestroyContext then
      r.ImGui_DestroyContext(ctx)
    end
  end
end

r.defer(loop) 
