--desc:N2NCue
--version: 3.5.2
--author: Rock Kennedy
--about:
-- # N2NCue
--  - Live and layout cuing of N2N drum and arp patterns

local r = reaper

----------------------------------------------------------------
-- GMEM CONFIG
----------------------------------------------------------------
local GMEM_NAMESPACE = "N2N_Ecosystem_RSKennedy"
local GMEM_BASE_ADDR = 7500000
local GMEM_SLOTS_PER_INSTANCE = 4
local GMEM_CUE_INST_BASE = 7100500
local GMEM_INFO_BASE = 8200000  -- MOVED: Was inside function, now constant

----------------------------------------------------------------
-- CONFIG
----------------------------------------------------------------
local TARGET_FX_NAMES = {
  ["N2N Drum Arranger.jsfx"] = "Drum",
  ["N2N Arp.jsfx"] = "Arp"
}

local TRACK_SWING = "Absolute Grid & Reverb"

local CH_PC   = 15
local CH_SWNG = 15
local CC_BANK_MSB = 0
local CC_SWING    = 119
local DEFAULT_SWING = 0

local GAP = 6
local BTN_H = 20
local SMALL_W = 28
local SECT_W  = (SMALL_W * 2) + GAP
local HEADER_WIDTH = 140
local GAP_CONTROL_TO_ROW1 = 0
local GAP_ROW1_TO_ROW2    = 0
local W_CLEAR   = 97
local W_SET_SW  = 94
local W_PROCESS = 144
local UI_MUTE = 0.55
local UI_GRAY = 0.25
local SWING_SLIDER_W = 130
local TEXT_ITEM_BEATS = 4
local TEXT_STAMP_TAG  = "Drum"
local INDICATOR_SIZE = 3
local INDICATOR_MARGIN = 1
local live_mode = true

local g_tracks = {}
local gmem_step = 0
local gmem_cycle = 0
local last_full_refresh_time = 0  -- timestamp of last full track scan/validate
local debug_printed = false

-- ADDED: Performance caches (update throttling)
local cache_active_tabs = {}  -- [track_key] = {tab_id, time}
local CACHE_DURATION = 0.1    -- active tab cache valid for 100ms
local last_dup_check = 0      -- throttle duplicate ID checks
local last_gmem_write = 0     -- throttle GMEM writes
local pending_gmem_write = false  -- flag when track data changes

-- CLEANED UP: Removed duplicate declarations (were declared again below)
local dup_ids = {}      -- [id] = count
local has_dup_ids = false
local dup_popup_open = false
local dup_popup_track = nil
local dup_popup_id = 0
local dup_popup_request = false
local dup_modal_open = true
local dup_popup_center_next = false

----------------------------------------------------------------
-- COLOR UTILS
----------------------------------------------------------------
local function clamp01(x)
  return (x < 0) and 0 or ((x > 1) and 1 or x)
end

local function draw_blinking_bold_text(x, y, text, col_u32, blink_on)
  if not blink_on then return end
  local dl = r.ImGui_GetWindowDrawList(ctx)
  -- Fake "bold": draw text twice with a 1px offset
  r.ImGui_DrawList_AddText(dl, x, y, col_u32, text)
  r.ImGui_DrawList_AddText(dl, x+1, y, col_u32, text)
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

local function get_track_color_data(track)
  if not track then return 0.4, 0.4, 0.4, 1, 1, 1 end
  
  local native = r.GetTrackColor(track)
  
  if not native or native == 0 then
    return 0.4, 0.4, 0.4, 1, 1, 1
  end
  
  native = tonumber(native) or 0
  if native == 0 then
    return 0.4, 0.4, 0.4, 1, 1, 1
  end
  
  local rr = (native % 256) / 255
  local gg = (math.floor(native / 256) % 256) / 255
  local bb = (math.floor(native / 65536) % 256) / 255
  
  local lum = 0.299*rr + 0.587*gg + 0.114*bb
  
  local tr, tg, tb = 1, 1, 1
  if lum > 0.6 then
    tr, tg, tb = 0, 0, 0
  end
  
  return rr, gg, bb, tr, tg, tb
end

----------------------------------------------------------------
-- TIME
----------------------------------------------------------------
local function qn64()
  return 1/16
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
 
local PC_PREROLL_64THS = 8  -- 4 = 1/16 note, 2 = 1/32, 1 = 1/64

local function stamp_time_64_or_zero(cursor_time)
  local preroll_qn = (PC_PREROLL_64THS or 1) * qn64()
  local qn = r.TimeMap2_timeToQN(0, cursor_time) - preroll_qn
  local t  = r.TimeMap2_QNToTime(0, qn)
  if t < 0 then t = 0 end
  return t
end

----------------------------------------------------------------
-- TAB DEFINITIONS (DRUM LAYOUT)
----------------------------------------------------------------
local tabs = {}
local function t(id, row, name, w, rr, gg, bb, prog)
  tabs[#tabs+1] = {id=id,row=row,name=name,w=w,r=rr,g=gg,b=bb,prog=prog}
end

-- ROW 0 (Off/Default)
t(0,0,"Off",SECT_W,0.4,0.4,0.4,0)
t(29,0,"Def",SECT_W,0.8,0.8,0.8,101)

-- ROW 1
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

local function find_first_unused_id()
  local used = {}

  for _, td in ipairs(g_tracks) do
    if td.is_alive and td.inst_id and td.inst_id > 0 then
      used[td.inst_id] = true
    end
  end

  local id = 1
  while used[id] do id = id + 1 end
  return id
end

local function set_jsfx_slider5_instance_id(tr_data, new_id)
  if not tr_data or not tr_data.is_alive then return false end
  if not r.ValidatePtr(tr_data.track, "MediaTrack*") then return false end

  local param_idx = 4 -- slider 5 (0-based)
  new_id = math.floor(tonumber(new_id) or 0)

  local ok = r.TrackFX_SetParam(tr_data.track, tr_data.fx_idx, param_idx, new_id)
  tr_data.inst_id = new_id

  r.TrackList_AdjustWindows(false)
  r.UpdateArrange()

  return ok ~= false
end

----------------------------------------------------------------
-- PATTERN STATE HELPERS
----------------------------------------------------------------
local function check_bit(value, bit_pos)
  if not value then return false end
  local div = 2 ^ bit_pos
  return math.floor(value / div) % 2 == 1
end

local function is_pattern_populated(tr_data, prog)
  if not tr_data or not tr_data.is_alive or not tr_data.pattern_bits then 
    return false 
  end
  if prog < 0 or prog > 127 then 
    return false 
  end
  
  local packet_idx = math.floor(prog / 32)
  local bit_idx = prog % 32
  
  local packet_val = tr_data.pattern_bits[packet_idx + 1]
  if not packet_val then 
    return false 
  end
  
  return check_bit(packet_val, bit_idx)
end

----------------------------------------------------------------
-- TRACK HELPERS & GMEM STATE MACHINE
----------------------------------------------------------------

local function compute_duplicate_ids()
  dup_ids = {}
  has_dup_ids = false

  for _, tr_data in ipairs(g_tracks) do
    if tr_data.is_alive and tr_data.inst_id and tr_data.inst_id > 0 then
      dup_ids[tr_data.inst_id] = (dup_ids[tr_data.inst_id] or 0) + 1
    end
  end

  for id, cnt in pairs(dup_ids) do
    if cnt > 1 then
      has_dup_ids = true
      break
    end
  end
end

local function is_dup_id(id)
  return id and id > 0 and dup_ids[id] and dup_ids[id] > 1
end

local function scan_project_tracks()
  local found = {}
  local seen_tracks = {}
  
  for i = 0, r.CountTracks(0) - 1 do
    local tr = r.GetTrack(0, i)
    local fx_count = r.TrackFX_GetCount(tr)
    
    for fx = 0, fx_count - 1 do
      local retval, buf = r.TrackFX_GetFXName(tr, fx, "")
      if retval and buf then
        -- Normalize the buffer: lowercase and extract just the filename if it's a path
        local normalized = buf:lower()
        
        -- Check if it's a JSFX by looking for the name (with or without .jsfx extension)
        for fx_name, track_type in pairs(TARGET_FX_NAMES) do
          -- Strip .jsfx for comparison if present
          local name_without_ext = fx_name:gsub("%.jsfx$", ""):lower()
          local name_with_ext = fx_name:lower()
          
          -- Check multiple patterns that might appear on different platforms
          local matches = (
            normalized:find(name_with_ext, 1, true) or           -- Full name with extension
            normalized:find(name_without_ext, 1, true) or        -- Name without extension
            normalized:find("js: " .. name_without_ext, 1, true) -- REAPER's JS: prefix
          )
          
          if matches then
            local _, tr_name = r.GetTrackName(tr)
            local key = tostring(tr)
            
            if not seen_tracks[key] then
              seen_tracks[key] = {
                track = tr,
                name = tr_name,
                type = track_type,
                fx_idx = fx,
                key = key
              }
              table.insert(found, seen_tracks[key])
            end
            goto next_fx
          end
        end
      end
      ::next_fx::
    end
  end
  
  return found
end

local function validate_existing_tracks()
  for _, gt in ipairs(g_tracks) do
    if not r.ValidatePtr(gt.track, "MediaTrack*") then
      gt.is_alive = false
      goto continue
    end
    
    local retval, buf = r.TrackFX_GetFXName(gt.track, gt.fx_idx, "")
    
    if not retval then
      local found = false
      local fx_count = r.TrackFX_GetCount(gt.track)
      for fx = 0, fx_count - 1 do
        local rv, name = r.TrackFX_GetFXName(gt.track, fx, "")
        if rv and name then
          for fx_name, _ in pairs(TARGET_FX_NAMES) do
            if name:find(fx_name, 1, true) then
              gt.fx_idx = fx
              found = true
              break
            end
          end
        end
        if found then break end
      end
      
      if not found then
        gt.is_alive = false
        gt.inst_id = 0
      end
    else
      local correct_fx = false
      for fx_name, _ in pairs(TARGET_FX_NAMES) do
        if buf:find(fx_name, 1, true) then
          correct_fx = true
          break
        end
      end
      
      if not correct_fx then
        local found = false
        local fx_count = r.TrackFX_GetCount(gt.track)
        for fx = 0, fx_count - 1 do
          local rv, name = r.TrackFX_GetFXName(gt.track, fx, "")
          if rv and name then
            for fx_name, _ in pairs(TARGET_FX_NAMES) do
              if name:find(fx_name, 1, true) then
                gt.fx_idx = fx
                found = true
                break
              end
            end
          end
          if found then break end
        end
        
        if not found then
          gt.is_alive = false
          gt.inst_id = 0
        end
      end
    end
    
    ::continue::
  end
end

local function step_validate_and_refresh(check_colors)
  validate_existing_tracks()
  
  local current_tracks = scan_project_tracks()

  local current_keys = {}
  for _, ct in ipairs(current_tracks) do
    current_keys[ct.key] = true
  end
  for key, _ in pairs(cache_active_tabs) do
    if not current_keys[key] then
      cache_active_tabs[key] = nil
    end
  end

  local old_g_tracks = g_tracks
  g_tracks = {}

  for _, ct in ipairs(current_tracks) do
    local matching_old = nil
    for _, old in ipairs(old_g_tracks) do
      if r.ValidatePtr(old.track, "MediaTrack*") and old.track == ct.track and old.fx_idx == ct.fx_idx then
        matching_old = old
        break
      end
    end

    local new_entry = {
      track     = ct.track,
      name      = ct.name,
      type      = ct.type,
      fx_idx    = ct.fx_idx,
      key       = ct.key,
      is_alive  = true,
      bg_r      = 0.4, bg_g = 0.4, bg_b = 0.4,
      txt_r     = 1,   txt_g = 1,   txt_b = 1
    }

    if matching_old then
      new_entry.inst_id      = matching_old.inst_id
      new_entry.pattern_bits = matching_old.pattern_bits or {}
      if not check_colors then
        new_entry.bg_r, new_entry.bg_g, new_entry.bg_b = matching_old.bg_r, matching_old.bg_g, matching_old.bg_b
        new_entry.txt_r, new_entry.txt_g, new_entry.txt_b = matching_old.txt_r, matching_old.txt_g, matching_old.txt_b
      end
    else
      new_entry.inst_id = 0
      new_entry.pattern_bits = {}
    end

    table.insert(g_tracks, new_entry)
  end

  validate_existing_tracks()

  if check_colors then
    for _, gt in ipairs(g_tracks) do
      if gt.is_alive and r.ValidatePtr(gt.track, "MediaTrack*") then
        local rr, gg, bb, tr, tg, tb = get_track_color_data(gt.track)
        gt.bg_r, gt.bg_g, gt.bg_b = rr, gg, bb
        gt.txt_r, gt.txt_g, gt.txt_b = tr, tg, tb
      end
    end
  end
end

local function step_read_instance_ids()
  for _, tr_data in ipairs(g_tracks) do
    if tr_data.is_alive and r.ValidatePtr(tr_data.track, "MediaTrack*") then
      local val = r.TrackFX_GetParam(tr_data.track, tr_data.fx_idx, 4)
      tr_data.inst_id = math.floor(val + 0.5)
    else
      tr_data.inst_id = 0
    end
  end
end

local function step_read_gmem_packet(packet_idx)
  for idx, tr_data in ipairs(g_tracks) do
    if tr_data.is_alive and tr_data.inst_id > 0 then
      local base_addr = GMEM_BASE_ADDR + ((tr_data.inst_id - 1) * GMEM_SLOTS_PER_INSTANCE)
      local addr = base_addr + packet_idx
      local value = r.gmem_read(addr)
      tr_data.pattern_bits[packet_idx + 1] = value
    end
  end
end

----------------------------------------------------------------
-- GMEM to JSFX TRACK # COLOR
----------------------------------------------------------------

local function write_track_info_to_gmem()
  r.gmem_attach(GMEM_NAMESPACE)
  
  for _, tr_data in ipairs(g_tracks) do
    if tr_data.is_alive and r.ValidatePtr(tr_data.track, "MediaTrack*") and tr_data.inst_id >= 1 and tr_data.inst_id <= 512 then
      local track_num = math.floor(r.GetMediaTrackInfo_Value(tr_data.track, "IP_TRACKNUMBER"))
      local native_col = r.GetTrackColor(tr_data.track)
      
      local col_r, col_g, col_b = 0.5, 0.5, 0.5
      if native_col and native_col ~= 0 then
        local rr = (native_col % 256) / 255
        local gg = (math.floor(native_col / 256) % 256) / 255
        local bb = (math.floor(native_col / 65536) % 256) / 255
        col_r, col_g, col_b = rr, gg, bb
      end
      
      local base_addr = GMEM_INFO_BASE + ((tr_data.inst_id - 1) * 4)
      
      r.gmem_write(base_addr + 0, track_num)
      r.gmem_write(base_addr + 1, col_r)
      r.gmem_write(base_addr + 2, col_g)
      r.gmem_write(base_addr + 3, col_b)
    end
  end
end

local function step_finalize()
  gmem_cycle = gmem_cycle + 1
  gmem_step = 0
end

local function process_gmem_state_machine()
  local now = r.time_precise()
  local REFRESH_INTERVAL = 2.0
  
  if now - last_full_refresh_time >= REFRESH_INTERVAL then
    step_validate_and_refresh(true)
    last_full_refresh_time = now
    pending_gmem_write = true
  end

  if pending_gmem_write and (now - last_gmem_write > 2.0) then
    write_track_info_to_gmem()
    last_gmem_write = now
    pending_gmem_write = false
  end

  r.gmem_attach(GMEM_NAMESPACE)
  
  if gmem_step == 0 then
    step_validate_and_refresh(false)
    gmem_step = 1
  elseif gmem_step == 1 then
    step_read_instance_ids()
    gmem_step = 2
  elseif gmem_step == 2 then
    step_read_gmem_packet(0)
    gmem_step = 3
  elseif gmem_step == 3 then
    step_read_gmem_packet(1)
    gmem_step = 4
  elseif gmem_step == 4 then
    step_read_gmem_packet(2)
    gmem_step = 5
  elseif gmem_step == 5 then
    step_read_gmem_packet(3)
    gmem_step = 6
  elseif gmem_step == 6 then
    step_finalize()
  end
end

local function find_track(name)
  for i=0,r.CountTracks(0)-1 do
    local tr = r.GetTrack(0,i)
    local _,n = r.GetTrackName(tr)
    if n == name then return tr end
  end
end

-- LIVE CUE SENDER
local function send_live_cue(inst_id, pattern)
  if not inst_id or inst_id < 1 or inst_id > 128 then return end
  local offset = GMEM_CUE_INST_BASE + (inst_id - 1)
  r.gmem_write(offset, pattern + 1)
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
  if prog == 82 then return "Fill 1=" end
  if prog == 83 then return "Fill 1>" end
  if prog == 84 then return "Fill 2<" end
  if prog == 85 then return "Fill 2=" end
  if prog == 86 then return "Fill 2>" end
  if prog >= 91 and prog <= 100 then
    return "Flex " .. tostring(prog - 90)
  end
  return "Arp Pattern # " .. tostring(prog)
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
  local qn_start = r.TimeMap2_timeToQN(0, t_time)
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
  if not track or not r.ValidatePtr(track, "MediaTrack*") then return nil end
  
  local track_key = tostring(track)
  local now = r.time_precise()
  local cached = cache_active_tabs[track_key]
  if cached and (now - cached.time) < CACHE_DURATION then
    return cached.tab_id
  end
  
  local best_ppq, best_prog

  for i=0,r.CountTrackMediaItems(track)-1 do
    local it = r.GetTrackMediaItem(track,i)
    local tk = r.GetActiveTake(it)
    if tk and r.TakeIsMIDI(tk) then
      local _, notecnt, cccnt, _ = r.MIDI_CountEvts(tk)
      if cccnt > 0 then
        local cur_ppq = r.MIDI_GetPPQPosFromProjTime(tk, cursor)
        for j=0,cccnt-1 do
          local ok,_,_,ppq,chanmsg,chan,msg2,msg3 = r.MIDI_GetCC(tk,j)
          local is_pc = (chanmsg >= 0xC0 and chanmsg <= 0xCF)
          if ok and is_pc and chan == CH_PC and ppq <= cur_ppq then
            if (not best_ppq) or (ppq > best_ppq) then
              best_ppq, best_prog = ppq, msg2
            end
          end
        end
      end
    end
  end

  local result = best_prog and prog_to_tabid[best_prog]
  cache_active_tabs[track_key] = {tab_id = result, time = now}
  return result
end

-- ADDED: ARP version returns raw program 0-127
local function find_active_prog(track, cursor)
  if not track or not r.ValidatePtr(track, "MediaTrack*") then return nil end
  
  local best_ppq, best_prog
  for i=0,r.CountTrackMediaItems(track)-1 do
    local it = r.GetTrackMediaItem(track,i)
    local tk = r.GetActiveTake(it)
    if tk and r.TakeIsMIDI(tk) then
      local _, notecnt, cccnt, _ = r.MIDI_CountEvts(tk)
      if cccnt > 0 then
        local cur_ppq = r.MIDI_GetPPQPosFromProjTime(tk, cursor)
        for j=0,cccnt-1 do
          local ok,_,_,ppq,chanmsg,chan,msg2,msg3 = r.MIDI_GetCC(tk,j)
          local is_pc = (chanmsg >= 0xC0 and chanmsg <= 0xCF)
          if ok and is_pc and chan == CH_PC and ppq <= cur_ppq then
            if (not best_ppq) or (ppq > best_ppq) then
              best_ppq, best_prog = ppq, msg2
            end
          end
        end
      end
    end
  end
  return best_prog
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
-- CLEAR ALL
----------------------------------------------------------------
local function is_probably_n2n_text_item(it)
  local _, name = r.GetSetMediaItemInfo_String(it, "P_NAME", "", false)
  local _, notes = r.GetSetMediaItemInfo_String(it, "P_NOTES", "", false)
  if notes and notes:find(TEXT_STAMP_TAG, 1, true) then return true end
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

local function clear_all_on_track(tr)
  if not tr then return end
  for i = r.CountTrackMediaItems(tr) - 1, 0, -1 do
    local it = r.GetTrackMediaItem(tr, i)
    local should_delete = false
    if is_probably_n2n_text_item(it) then
      should_delete = true
    else
      local tk = r.GetActiveTake(it)
      if tk and r.TakeIsMIDI(tk) then
        r.MIDI_Sort(tk)
        local _, notecnt, cccnt, _ = r.MIDI_CountEvts(tk)
        for j = 0, cccnt - 1 do
          local ok, _, _, _, chanmsg, chan, msg2, msg3 = r.MIDI_GetCC(tk, j)
          if ok then
            local is_pc = (chanmsg >= 0xC0 and chanmsg <= 0xCF)
            local is_cc = (chanmsg >= 0xB0 and chanmsg <= 0xBF)
          
            if is_pc and chan == CH_PC then
              should_delete = true
              break
            end
          
            if is_cc and (msg2 == CC_BANK_MSB) then
              should_delete = true
              break
            end
          end
        end
      end
    end
    if should_delete then
      r.DeleteTrackMediaItem(tr, it)
    end
  end
end

local function clear_all_drums_stamps(tracks_table)
  r.Undo_BeginBlock()
  for _, tr_data in ipairs(tracks_table) do
    if r.ValidatePtr(tr_data.track, "MediaTrack*") then
      clear_all_on_track(tr_data.track)
    end
  end
  r.UpdateArrange()
  r.Undo_EndBlock("N2N Multi-Track: Clear All", -1)
end

local function open_all_targeted_fx_windows()
for _, tr_data in ipairs(g_tracks) do
if tr_data.is_alive and r.ValidatePtr(tr_data.track, "MediaTrack*") then
-- Enable the FX first (in case it's bypassed)
r.TrackFX_SetEnabled(tr_data.track, tr_data.fx_idx, true)
-- 3 = show floating window
r.TrackFX_Show(tr_data.track, tr_data.fx_idx, 3)
end
end
end


----------------------------------------------------------------
-- REGIONS: Process Regions
----------------------------------------------------------------
local function parse_region_to_prog(name)
  if not name or name == "" then return nil end
  local base_map = {
    Intro  = 11, Verse  = 21, Pre    = 31,
    Chorus = 41, Bridge = 51, Outro  = 61,
  }
  local order = {"Intro","Verse","Pre","Chorus","Bridge","Outro"}
  local hit_key = nil
  for _,k in ipairs(order) do
    if name:find(k, 1, true) then hit_key = k break end
  end
  if not hit_key then return nil end
  local var = tonumber(name:match(hit_key.."%s*(%d+)"))
  if not var then var = 1 end
  if var < 1 then var = 1 end
  if var > 7 then var = 7 end
  return base_map[hit_key] + (var - 1)
end

local function stamp_off_at_time0(tr, bank)
  if not tr then return end
  stamp_text_clip(tr, "Drums Off", 0.0, 0.7, 0.7, 0.7)
  local t0 = 0.0
  local it0 = ensure_midi_item_at(tr, t0, t0 + 1)
  local tk0 = r.GetActiveTake(it0) or r.GetTake(it0, 0)
  if tk0 and r.TakeIsMIDI(tk0) then
    local ppq0 = r.MIDI_GetPPQPosFromProjTime(tk0, t0)
    insert_bank_and_pc(tk0, ppq0, bank, 0)
    r.MIDI_Sort(tk0)
  end
end

local function process_regions_for_track(tr, bank)
  if not tr then return end
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

  local need_start_off = false
  if not first_valid_drum_region_pos then
    need_start_off = true
  elseif first_valid_drum_region_pos > 0.001 then
    need_start_off = true
  end

  if need_start_off then
    stamp_off_at_time0(tr, bank)
  end

  for i=0,total-1 do
    local rv, isrgn, pos, rgnend, name = r.EnumProjectMarkers(i)
    if rv and isrgn then
      local prog = parse_region_to_prog(name or "")
      if prog then
        stamp_pc(tr, prog, bank, pos)
      end
    end
  end

  if last_region_end then
    stamp_pc_at_time(tr, 0, bank, last_region_end)
  end
end

local function process_regions_all(tracks_table, bank)
  r.Undo_BeginBlock()
  for _, tr_data in ipairs(tracks_table) do
    if r.ValidatePtr(tr_data.track, "MediaTrack*") then
      if tr_data.type == "Drum" then
        process_regions_for_track(tr_data.track, bank)
      end
      -- if tr_data.type == "Arp" then
      --   (do nothing, or call an arp-specific region processor later)
      -- end
    end
  end
  r.Undo_EndBlock("N2N Multi-Track: Process Regions", -1)
end

----------------------------------------------------------------
-- IMGUI
----------------------------------------------------------------
local ctx = r.ImGui_CreateContext("N2N Multi-Track Layout Tool")

-- Font (create once, attach once)
local font = r.ImGui_CreateFont("Arial", 18)
r.ImGui_Attach(ctx, font)

local font_small = r.ImGui_CreateFont("Arial", 12)  -- Smaller font for ARP buttons
r.ImGui_Attach(ctx, font_small)

local measure_bank = 1
local swing_value = DEFAULT_SWING

local function ui_btn(label, w, h, id)
  return r.ImGui_Button(ctx, label.."##"..id, w, h)
end

local function draw_pattern_indicator(tr_data, prog)
  if is_pattern_populated(tr_data, prog) then
    local x, y = r.ImGui_GetItemRectMin(ctx)
    local draw_list = r.ImGui_GetWindowDrawList(ctx)
    r.ImGui_DrawList_AddRectFilled(
      draw_list, 
      x + INDICATOR_MARGIN, 
      y + INDICATOR_MARGIN,
      x + INDICATOR_MARGIN + INDICATOR_SIZE, 
      y + INDICATOR_MARGIN + INDICATOR_SIZE +13,
      rgba_u32(1, 1, 1, 1))
    local x, y = r.ImGui_GetItemRectMin(ctx)
    local draw_list = r.ImGui_GetWindowDrawList(ctx)
    r.ImGui_DrawList_AddRectFilled(
      draw_list, 
      x + INDICATOR_MARGIN, 
      y + INDICATOR_MARGIN,
      x + INDICATOR_MARGIN + INDICATOR_SIZE + 5, 
      y + INDICATOR_MARGIN + INDICATOR_SIZE,
      rgba_u32(1, 1, 1, 1))    
    local x, y = r.ImGui_GetItemRectMin(ctx)
    local draw_list = r.ImGui_GetWindowDrawList(ctx)
    r.ImGui_DrawList_AddRectFilled(
      draw_list, 
      x + INDICATOR_MARGIN, 
      y + INDICATOR_MARGIN + 14,
      x + INDICATOR_MARGIN + INDICATOR_SIZE + 5, 
      y + INDICATOR_MARGIN + INDICATOR_SIZE + 14,
      rgba_u32(1, 1, 1, 1))     
      
      
      

  end
end

local function draw_partial_row_0(active, tr_data, cursor, track_idx)
  local first = true
  local tr = tr_data.track
  
  for _,tb in ipairs(tabs) do
    if tb.id==0 or tb.id==29 then
      if not first then
        r.ImGui_SameLine(ctx, nil, GAP)
      else
        first = false
      end
      
      local r0,g0,b0 = mute_rgb(tb.r,tb.g,tb.b)

      
      if not tr_data.is_alive then
        r0,g0,b0 = UI_GRAY, UI_GRAY, UI_GRAY
      end

      r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(),        rgba_u32(r0,g0,b0,1))
      r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), rgba_u32(brighten_rgb(r0,g0,b0,0.20)))
      r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(),  rgba_u32(brighten_rgb(r0,g0,b0,0.30)))
      r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(),          (active==tb.id) and rgba_u32(0,0,0,1) or rgba_u32(1,1,1,1))

      local clicked = r.ImGui_Button(ctx, tb.name.."##tab"..tb.id.."##t"..track_idx, tb.w, BTN_H)
      
      draw_pattern_indicator(tr_data, tb.prog)
      
      
      if clicked and tr_data.is_alive then
      if live_mode then
      send_live_cue(tr_data.inst_id, tb.prog)
      else
      stamp_pc(tr, tb.prog, measure_bank, cursor)
      end
      end



      r.ImGui_PopStyleColor(ctx, 4)
    end
  end
end

local function draw_tab_row(row, active, tr_data, cursor, track_idx)
  local first = true
  local tr = tr_data.track
  
  for _,tb in ipairs(tabs) do
    if tb.row==row then
      if not first then
        r.ImGui_SameLine(ctx, nil, GAP)
      else
        first = false
      end
      
      local r0,g0,b0 = mute_rgb(tb.r,tb.g,tb.b)

      
      if not tr_data.is_alive then
        r0,g0,b0 = UI_GRAY, UI_GRAY, UI_GRAY
      end

      r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(),        rgba_u32(r0,g0,b0,1))
      r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), rgba_u32(brighten_rgb(r0,g0,b0,0.20)))
      r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(),  rgba_u32(brighten_rgb(r0,g0,b0,0.30)))
r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), rgba_u32(1,1,1,1))




      local clicked = r.ImGui_Button(ctx, tb.name.."##tab"..tb.id.."##t"..track_idx, tb.w, BTN_H)
      
      draw_pattern_indicator(tr_data, tb.prog)
      
      if clicked and tr_data.is_alive then
      if live_mode then
      send_live_cue(tr_data.inst_id, tb.prog)
      else
      stamp_pc(tr, tb.prog, measure_bank, cursor)
      end
      end

      r.ImGui_PopStyleColor(ctx, 4)
    end
  end
end

-- ADDED: ARP Layout Function
local function draw_arp_interface(active_prog, tr_data, cursor, track_idx)
  local tr = tr_data.track
  local ARP_BTN_W = 17  -- narrow for 64 buttons
  local ARP_GAP = 4     -- slightly tighter spacing
  
  -- Color lookup: groups of 8, cycling through Drum colors
  local function get_arp_color(prog)
    local group = math.floor(prog / 8) % 8
    if group == 0 or group == 7 then return 0.8, 0.8, 0.8 end  -- Grey (Hit)
    if group == 1 then return 0.2, 1.0, 1.0 end  -- Intro Cyan
    if group == 2 then return 0.4, 0.6, 1.0 end  -- Verse Blue  
    if group == 3 then return 0.7, 0.4, 1.0 end  -- Pre Purple
    if group == 4 then return 1.0, 0.4, 0.4 end  -- Chorus Red
    if group == 5 then return 1.0, 0.9, 0.2 end  -- Bridge Yellow
    if group == 6 then return 0.5, 0.8, 0.7 end  -- Outro Teal
    return 0.5, 0.5, 0.5
  end
  
  -- Clear button (first item, no SameLine before)
  local blue_r, blue_g, blue_b = 0.25, 0.55, 1.0
  if not tr_data.is_alive then
    blue_r, blue_g, blue_b = UI_GRAY, UI_GRAY, UI_GRAY
  end
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), rgba_u32(blue_r, blue_g, blue_b, 1))
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), rgba_u32(brighten_rgb(blue_r, blue_g, blue_b, 0.15)))
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), rgba_u32(brighten_rgb(blue_r, blue_g, blue_b, 0.25)))
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), rgba_u32(1,1,1,1))
  
  if r.ImGui_Button(ctx, "Clear##clr"..track_idx, SECT_W, BTN_H) then
    r.Undo_BeginBlock()
    clear_all_on_track(tr_data.track)
    r.Undo_EndBlock("N2N: Clear " .. tr_data.name, -1)
  end
  r.ImGui_PopStyleColor(ctx, 4)
  
  -- Process R button
  r.ImGui_SameLine(ctx, nil, GAP)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), rgba_u32(blue_r, blue_g, blue_b, 1))
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), rgba_u32(brighten_rgb(blue_r, blue_g, blue_b, 0.15)))
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), rgba_u32(brighten_rgb(blue_r, blue_g, blue_b, 0.25)))
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), rgba_u32(1,1,1,1))
  
  if r.ImGui_Button(ctx, "Process R##prc"..track_idx, SECT_W, BTN_H) then
    r.Undo_BeginBlock()
    process_regions_for_track(tr_data.track, measure_bank)
    r.Undo_EndBlock("N2N: Process " .. tr_data.name, -1)
  end
  r.ImGui_PopStyleColor(ctx, 4)
  
  -- Row 1: Program buttons 0-63
  r.ImGui_PushFont(ctx, font_small, 12)
  for prog = 0, 63 do
    if prog > 0 then r.ImGui_SameLine(ctx, nil, ARP_GAP) end
    
    local rr, gg, bb = get_arp_color(prog)
    if not tr_data.is_alive then
      rr, gg, bb = UI_GRAY, UI_GRAY, UI_GRAY
    end
    
    local is_active = (active_prog == prog)
    local display_rr, display_gg, display_bb = rr, gg, bb
    if is_active then
      display_rr, display_gg, display_bb = brighten_rgb(rr, gg, bb, 0.4)
    end
    
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), rgba_u32(mute_rgb(display_rr, display_gg, display_bb)))
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), rgba_u32(brighten_rgb(rr, gg, bb, 0.2)))
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), rgba_u32(brighten_rgb(rr, gg, bb, 0.3)))
    
    local lum = 0.299*rr + 0.587*gg + 0.114*bb
    local txt_col = (lum > 0.6) and rgba_u32(0,0,0,1) or rgba_u32(1,1,1,1)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), txt_col)
    
    if r.ImGui_Button(ctx, tostring(prog).."##arp"..prog.."t"..track_idx, ARP_BTN_W, BTN_H) and tr_data.is_alive then
      if live_mode then
        send_live_cue(tr_data.inst_id, prog)
      else
        stamp_pc(tr, prog, measure_bank, cursor)
      end
    end
    
    draw_pattern_indicator(tr_data, prog)
    r.ImGui_PopStyleColor(ctx, 4)
  end
  -- Row 2: Program buttons 64-127 (starts on new line)
  for prog = 64, 127 do
    if prog > 64 then
      r.ImGui_SameLine(ctx, nil, ARP_GAP)
    end
    
    local rr, gg, bb = get_arp_color(prog)
    if not tr_data.is_alive then
      rr, gg, bb = UI_GRAY, UI_GRAY, UI_GRAY
    end
    
    local is_active = (active_prog == prog)
    local display_rr, display_gg, display_bb = rr, gg, bb
    if is_active then
      display_rr, display_gg, display_bb = brighten_rgb(rr, gg, bb, 0.4)
    end
    
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), rgba_u32(mute_rgb(display_rr, display_gg, display_bb)))
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), rgba_u32(brighten_rgb(rr, gg, bb, 0.2)))
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), rgba_u32(brighten_rgb(rr, gg, bb, 0.3)))
    
    local lum = 0.299*rr + 0.587*gg + 0.114*bb
    local txt_col = (lum > 0.6) and rgba_u32(0,0,0,1) or rgba_u32(1,1,1,1)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), txt_col)
    
    if r.ImGui_Button(ctx, (prog < 100) and tostring(prog) or tostring(prog):sub(2) .."##arp"..prog.."t"..track_idx, ARP_BTN_W, BTN_H) and tr_data.is_alive then
      if live_mode then
        send_live_cue(tr_data.inst_id, prog)
      else
        stamp_pc(tr, prog, measure_bank, cursor)
      end
    end
    
    draw_pattern_indicator(tr_data, prog)
    r.ImGui_PopStyleColor(ctx, 4)
  end
    r.ImGui_PopFont(ctx)
end

local function loop()
  local now = r.time_precise()
  
  process_gmem_state_machine()
  
  if now - last_dup_check > 0.5 then
    compute_duplicate_ids()
    last_dup_check = now
  end
  
  if r.ImGui_IsKeyPressed(ctx, r.ImGui_Key_Space()) then
    step_validate_and_refresh(true)
    print("Manual refresh triggered via SPACE")
  end
  
  r.ImGui_SetNextWindowSize(ctx, 1488, 500, r.ImGui_Cond_Appearing())
  r.ImGui_SetNextWindowSizeConstraints(ctx, 1488, 202, 9999, 9999) 
  local vis,open = r.ImGui_Begin(ctx,"N2N Multi-Track Layout Tool",true)
  
  if dup_popup_request then
    r.ImGui_OpenPopup(ctx, "N2N ID Conflict")
    dup_popup_request = false
  end
  if vis then
    r.ImGui_PushFont(ctx, font,15)
    local tr_swing = find_track(TRACK_SWING)
    local cur = r.GetCursorPosition()

    do
      r.ImGui_SameLine(ctx, nil, GAP*3)
      local live_col = live_mode and rgba_u32(.02, 0.9, 0.2, 1) or rgba_u32(0.6, 0.7, 0.9, 1)
      r.ImGui_TextColored(ctx, live_col, live_mode and " LIVE ON!" or "PC Layout")
      r.ImGui_SameLine(ctx, nil, GAP*2)
      local rv, v = r.ImGui_Checkbox(ctx, "##live_mode_chk", live_mode)
      if rv then live_mode = v end
      
      r.ImGui_SameLine(ctx, nil, GAP*4)
      local rr,gg,bb = mute_rgb(0.45,0.45,0.45)
      r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), rgba_u32(rr,gg,bb,1))
      r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), rgba_u32(1,1,1,1))
      if ui_btn("Clear All PCs", HEADER_WIDTH-10, BTN_H, "ctl_clear") then
        clear_all_drums_stamps(g_tracks)
      end
      r.ImGui_PopStyleColor(ctx,2)
      r.ImGui_SameLine(ctx,nil,GAP)

      local rr,gg,bb = mute_rgb(0.45,0.45,0.45)
      r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), rgba_u32(rr,gg,bb,1))
      r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), rgba_u32(1,1,1,1))
      if ui_btn("Open FX Windows", HEADER_WIDTH-10, BTN_H, "ctl_openfx") then
      open_all_targeted_fx_windows()
      end
      r.ImGui_PopStyleColor(ctx,2)
      r.ImGui_SameLine(ctx,nil,GAP*4)



      r.ImGui_Text(ctx,"Measure offset:")
      for i=1,4 do
        r.ImGui_SameLine(ctx,nil,GAP)
        if r.ImGui_RadioButton(ctx, "Bar "..i.."##bar"..i, measure_bank==i) then
          measure_bank=i
        end
      end

      r.ImGui_SameLine(ctx,nil,GAP*6)
      r.ImGui_Text(ctx,"Swing:")
      r.ImGui_SameLine(ctx,nil,GAP)

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
          process_regions_all(g_tracks, measure_bank)
        end
        r.ImGui_PopStyleColor(ctx,2)
      end
      
    end

    r.ImGui_Separator(ctx)
    r.ImGui_Text(ctx, string.format("Found %d N2N instrument(s)", #g_tracks, gmem_cycle, gmem_step))
    
    if has_dup_ids then
      r.ImGui_SameLine(ctx, nil, GAP*3)
      r.ImGui_TextColored(ctx, rgba_u32(1, 0.75, 0.25, 1), "⚠ DUPLICATE INST: IDs DETECTED — CLICK ON RED ID FOR INFO!")
    end
    r.ImGui_Spacing(ctx)

    if #g_tracks == 0 then
      r.ImGui_TextColored(ctx, rgba_u32(1,0.3,0.3,1), "No tracks found with N2N Drum Arranger.jsfx or N2N Arp.jsfx")
    else
      r.ImGui_BeginChild(ctx, "TrackScrollArea", 0, 0)
      
      for idx, tr_data in ipairs(g_tracks) do
        if not r.ValidatePtr(tr_data.track, "MediaTrack*") then
          tr_data.is_alive = false
        end
        
        local bg_r, bg_g, bg_b = tr_data.bg_r, tr_data.bg_g, tr_data.bg_b
        local txt_r, txt_g, txt_b = tr_data.txt_r, tr_data.txt_g, tr_data.txt_b
        
        if not tr_data.is_alive then
          bg_r, bg_g, bg_b = UI_GRAY, UI_GRAY, UI_GRAY
          txt_r, txt_g, txt_b = 0.5, 0.5, 0.5
        end
        
        local header_r, header_g, header_b = mute_rgb(bg_r, bg_g, bg_b)
        local header_col = rgba_u32(header_r, header_g, header_b, 1)
        local text_col = rgba_u32(txt_r, txt_g, txt_b, 1)
        
        local row_height = BTN_H * 3 + GAP_CONTROL_TO_ROW1 + GAP_ROW1_TO_ROW2 + 8
        
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_WindowBg(), header_col)
        if r.ImGui_BeginChild(ctx, "Header"..idx, HEADER_WIDTH, row_height) then
          if not tr_data.is_alive then
            r.ImGui_BeginDisabled(ctx, true)
          end
          
          do
            local btn_col = header_col
            local btn_hover = rgba_u32(brighten_rgb(header_r, header_g, header_b, 0.15))
            local btn_active = rgba_u32(brighten_rgb(header_r, header_g, header_b, 0.25))
            
            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), btn_col)
            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), btn_hover)
            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), btn_active)
            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), text_col)
            
            local display_name = tr_data.name
            if #display_name > 18 then display_name = display_name:sub(1,15).."..." end
            if r.ImGui_Button(ctx, display_name, HEADER_WIDTH-10, BTN_H) and tr_data.is_alive then
              r.SetOnlyTrackSelected(tr_data.track)
              r.TrackList_AdjustWindows(false)
            end
            local type_label = tr_data.type
            
            if r.ImGui_Button(ctx, type_label, HEADER_WIDTH-10, BTN_H) and tr_data.is_alive then
              if tr_data.type == "Drum" then
                r.TrackFX_SetEnabled(tr_data.track, tr_data.fx_idx, true)
                r.TrackFX_Show(tr_data.track, tr_data.fx_idx, 3)
              else
                r.TrackFX_Show(tr_data.track, tr_data.fx_idx, 3)
              end
            end
            
            local id_text = tr_data.is_alive and ("ID: "..tostring(tr_data.inst_id)) or "OFFLINE"
            local dup = tr_data.is_alive and is_dup_id(tr_data.inst_id)

            if dup then
              local tnow = r.time_precise()
              local on = (math.floor(tnow * 5) % 2) == 0
              local col = on and rgba_u32(1, 0, 0, 1) or btn_col

              r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), col)
              r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), col)
              r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), col)
              r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), rgba_u32(1,1,1,1))

              if r.ImGui_Button(ctx, id_text.."##dup_idbtn"..idx, HEADER_WIDTH-10, BTN_H) then
                dup_popup_track = tr_data
                dup_popup_id = tr_data.inst_id
                dup_popup_center_next = true
                dup_popup_request = true
              end

              r.ImGui_PopStyleColor(ctx, 4)
            else
              r.ImGui_Button(ctx, id_text.."##idbtn"..idx, HEADER_WIDTH-10, BTN_H)
            end

            r.ImGui_PopStyleColor(ctx, 4)
          end
          
          if not tr_data.is_alive then
            r.ImGui_EndDisabled(ctx)
          end
          
          r.ImGui_EndChild(ctx)
        end
        r.ImGui_PopStyleColor(ctx)
        
        r.ImGui_SameLine(ctx, 0, GAP)
        
        if r.ImGui_BeginChild(ctx, "Buttons"..idx, 0, row_height) then
          -- Determine active state based on track type
          local active_tab = nil
          local active_prog = nil
          
          if tr_data.is_alive then
            if tr_data.type == "Arp" then
              active_prog = find_active_prog(tr_data.track, cur)
            else
              active_tab = find_active_tab(tr_data.track, cur)
            end
          end
          
          if not tr_data.is_alive then
            r.ImGui_BeginDisabled(ctx, true)
          end
          
          -- Branch by instrument type
          if tr_data.type == "Arp" then
            -- ARP Layout: Sequential 0-127, 2 rows
            draw_arp_interface(active_prog, tr_data, cur, idx)
          else
            -- DRUM Layout: Existing section-based layout
            draw_partial_row_0(active_tab, tr_data, cur, idx)
            r.ImGui_SameLine(ctx, nil, GAP)
            
            local blue_r, blue_g, blue_b = 0.25, 0.55, 1.0
            if not tr_data.is_alive then
              blue_r, blue_g, blue_b = UI_GRAY, UI_GRAY, UI_GRAY
            end
            local blue_col = rgba_u32(blue_r, blue_g, blue_b, 1)
            local blue_hover = rgba_u32(brighten_rgb(blue_r, blue_g, blue_b, 0.15))
            local blue_active = rgba_u32(brighten_rgb(blue_r, blue_g, blue_b, 0.25))
            
            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), blue_col)
            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), blue_hover)
            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), blue_active)
            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), rgba_u32(1,1,1,1))
            
            if r.ImGui_Button(ctx, "Clear##clr"..idx, SECT_W, BTN_H) then
              r.Undo_BeginBlock()
              clear_all_on_track(tr_data.track)
              r.Undo_EndBlock("N2N: Clear " .. tr_data.name, -1)
            end
            
            r.ImGui_SameLine(ctx, nil, GAP)
            
            if r.ImGui_Button(ctx, "Process R##prc"..idx, SECT_W, BTN_H) then
              r.Undo_BeginBlock()
              process_regions_for_track(tr_data.track, measure_bank)
              r.Undo_EndBlock("N2N: Process " .. tr_data.name, -1)
            end
            r.ImGui_PopStyleColor(ctx, 4)
            
            draw_tab_row(1, active_tab, tr_data, cur, idx)
            draw_tab_row(2, active_tab, tr_data, cur, idx)
          end
          
          if not tr_data.is_alive then
            r.ImGui_EndDisabled(ctx)
          end
          
          r.ImGui_EndChild(ctx)
        end
        r.ImGui_Separator(ctx)
      end
      
      r.ImGui_EndChild(ctx)
    end

    do
      local vp = r.ImGui_GetMainViewport(ctx)
      local cx, cy = r.ImGui_Viewport_GetCenter(vp)
      r.ImGui_SetNextWindowPos(ctx, cx, cy, r.ImGui_Cond_Appearing(), 0.5, 0.5)
    end

    local modal_vis
    modal_vis, dup_modal_open = r.ImGui_BeginPopupModal(
      ctx,
      "N2N ID Conflict",
      dup_modal_open,
      r.ImGui_WindowFlags_AlwaysAutoResize()
    )

    if modal_vis then
      r.ImGui_TextWrapped(ctx,
        "Each N2N JSFX needs its own unique ID. This conflict generally occurs when a user duplicates\n" .. 
        "a track with the effect or copy-pastes the track or the effect itself.\n \n" .. 
        "Now worries... Just open one of the N2N JSFXs and change it's INST:ID to a number not in use."
      )
      r.ImGui_Spacing(ctx)

      if dup_popup_track and dup_popup_track.is_alive then
        r.ImGui_Text(ctx, "Track: " .. (dup_popup_track.name or "(unknown)"))
        r.ImGui_Text(ctx, "Conflicting ID: " .. tostring(dup_popup_id))
      end

      r.ImGui_Spacing(ctx)

      if r.ImGui_Button(ctx, "Close - User should fix", 200, 30) then
        r.ImGui_CloseCurrentPopup(ctx)
        dup_modal_open = false
        dup_popup_track = nil
        dup_popup_id = 0
      end

      r.ImGui_EndPopup(ctx)
    end

    if not dup_modal_open then
      dup_popup_track = nil
      dup_popup_id = 0
    end

    r.ImGui_PopFont(ctx) 
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
