--desc:N2NCue
--version: 4.0.0
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
local GMEM_INFO_BASE = 8200000

----------------------------------------------------------------
-- CONFIG
----------------------------------------------------------------
local TARGET_FX_NAMES = {
  ["N2N Drum Arranger.jsfx"] = "Drum",
  ["N2N Arp.jsfx"] = "Arp"
}

local TRACK_SWING = "N2N Nashville # Chart"

local CH_PC   = 15
local CH_SWNG = 15
local CC_BANK_MSB = 0
local CC_SWING    = 119
local DEFAULT_SWING = 0

local GAP = 6
local BTN_H = 20
local HEADER_WIDTH = 140
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
local last_full_refresh_time = 0

local cache_active_tabs = {}
local CACHE_DURATION = 0.1
local last_dup_check = 0
local last_gmem_write = 0
local pending_gmem_write = false

local dup_ids = {}
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
  
  local ok, r_val, g_val, b_val = pcall(r.ColorFromNative, native)
  if ok and r_val and g_val and b_val then
    local rr = r_val / 255
    local gg = g_val / 255
    local bb = b_val / 255
    local lum = 0.299*rr + 0.587*gg + 0.114*bb
    local tr, tg, tb = 1, 1, 1
    if lum > 0.6 then tr, tg, tb = 0, 0, 0 end
    return rr, gg, bb, tr, tg, tb
  end
  
  native = tonumber(native) or 0
  if native == 0 then return 0.4, 0.4, 0.4, 1, 1, 1 end
  native = native & 0xFFFFFF
  local rr = (native % 256) / 255
  local gg = (math.floor(native / 256) % 256) / 255
  local bb = (math.floor(native / 65536) % 256) / 255
  local lum = 0.299*rr + 0.587*gg + 0.114*bb
  local tr, tg, tb = 1, 1, 1
  if lum > 0.6 then tr, tg, tb = 0, 0, 0 end
  return rr, gg, bb, tr, tg, tb
end

----------------------------------------------------------------
-- TIME
----------------------------------------------------------------
local function qn64() return 1/16 end

local function get_timesig_at_time(t)
  if r.TimeMap2_GetTimeSigAtTime then
    local ok, rv, num, den = pcall(r.TimeMap2_GetTimeSigAtTime, 0, t)
    if ok and num and den and den ~= 0 then return num, den end
  end
  return 4, 4
end

local function beats_to_qn_at_time(t, beats)
  local _, den = get_timesig_at_time(t)
  local beat_qn = 4 / (den or 4)
  return (beats or 4) * beat_qn
end
 
local PC_PREROLL_64THS = 8

local function stamp_time_64_or_zero(cursor_time)
  local preroll_qn = (PC_PREROLL_64THS or 1) * qn64()
  local qn = r.TimeMap2_timeToQN(0, cursor_time) - preroll_qn
  local t  = r.TimeMap2_QNToTime(0, qn)
  if t < 0 then t = 0 end
  return t
end

----------------------------------------------------------------
-- TAB DEFINITIONS (UNIFIED FOR 3 ROWS)
----------------------------------------------------------------
local W_TAB = 36
local W_SECT = (W_TAB * 2) + GAP
local W_OFF = 48
local W_HWW = 44

local tabs_drum = {}
local tabs_arp = {}

local function td(id, row, name, w, rr, gg, bb, prog)
  table.insert(tabs_drum, {id=id, row=row, name=name, w=w, r=rr, g=gg, b=bb, prog=prog})
end

local function ta(id, row, name, w, rr, gg, bb, prog)
  table.insert(tabs_arp, {id=id, row=row, name=name, w=w, r=rr, g=gg, b=bb, prog=prog})
end

local function add_tab(id, row, d_name, a_name, d_w, a_w, rr, gg, bb, prog)
  td(id, row, d_name, d_w, rr, gg, bb, prog)
  ta(id, row, a_name, a_w, rr, gg, bb, prog)
end

-- ROW 1
add_tab( 0, 1, "Off", "Off", W_OFF, W_OFF, 0.5, 0.5, 0.5, 24)
add_tab( 1, 1, "Intro", "Intro", W_SECT, W_SECT, 0.2, 1.0, 1.0, 32)
add_tab( 2, 1, "B", "B", W_TAB, W_TAB, 0.2, 1.0, 1.0, 33)
add_tab( 3, 1, "C", "C", W_TAB, W_TAB, 0.2, 1.0, 1.0, 34)
add_tab( 4, 1, "D", "D", W_TAB, W_TAB, 0.2, 1.0, 1.0, 35)
add_tab( 5, 1, "Verse 1", "Verse 1", W_SECT, W_SECT, 0.5, 0.7, 1.0, 36)
add_tab( 6, 1, "B", "B", W_TAB, W_TAB, 0.5, 0.7, 1.0, 37)
add_tab( 7, 1, "C", "C", W_TAB, W_TAB, 0.5, 0.7, 1.0, 38)
add_tab( 8, 1, "D", "D", W_TAB, W_TAB, 0.5, 0.7, 1.0, 39)
add_tab( 9, 1, "Pre 1", "Pre 1", W_SECT, W_SECT, 0.8, 0.5, 1.0, 48)
add_tab(10, 1, "B", "B", W_TAB, W_TAB, 0.8, 0.5, 1.0, 49)
add_tab(11, 1, "C", "C", W_TAB, W_TAB, 0.8, 0.5, 1.0, 50)
add_tab(12, 1, "D", "D", W_TAB, W_TAB, 0.8, 0.5, 1.0, 51)
add_tab(13, 1, "Chorus 1", "Chorus 1", W_SECT, W_SECT, 1.0, 0.4, 0.4, 60)
add_tab(14, 1, "B", "B", W_TAB, W_TAB, 1.0, 0.4, 0.4, 61)
add_tab(15, 1, "C", "C", W_TAB, W_TAB, 1.0, 0.4, 0.4, 62)
add_tab(16, 1, "D", "D", W_TAB, W_TAB, 1.0, 0.4, 0.4, 63)
add_tab(17, 1, "Bridge", "Bridge", W_SECT, W_SECT, 1.0, 0.9, 0.2, 72)
add_tab(18, 1, "B", "B", W_TAB, W_TAB, 1.0, 0.9, 0.2, 73)
add_tab(19, 1, "C", "C", W_TAB, W_TAB, 1.0, 0.9, 0.2, 74)
add_tab(20, 1, "D", "D", W_TAB, W_TAB, 1.0, 0.9, 0.2, 75)
add_tab(21, 1, "H1", "21", W_HWW, W_TAB, 0.8, 0.8, 0.8, 20)
add_tab(22, 1, "H2", "22", W_HWW, W_TAB, 0.8, 0.8, 0.8, 21)
add_tab(23, 1, "1<", "23", W_HWW, W_TAB, 0.8, 0.5, 1.0, 26)
add_tab(24, 1, "1=", "24", W_HWW, W_TAB, 0.8, 0.5, 1.0, 27)
add_tab(25, 1, "1>", "25", W_HWW, W_TAB, 0.8, 0.5, 1.0, 28)

-- ROW 2
add_tab(26, 2, "Def", "Def", W_OFF, W_OFF, 0.7, 0.7, 0.9, 25)
add_tab(27, 2, "1", "1", W_TAB, W_TAB, 0.8, 0.8, 0.8, 1)
add_tab(28, 2, "2", "2", W_TAB, W_TAB, 0.8, 0.8, 0.8, 2)
add_tab(29, 2, "3", "3", W_TAB, W_TAB, 0.8, 0.8, 0.8, 3)
add_tab(30, 2, "4", "4", W_TAB, W_TAB, 0.8, 0.8, 0.8, 4)
add_tab(31, 2, "5", "5", W_TAB, W_TAB, 0.8, 0.8, 0.8, 5)
add_tab(32, 2, "Verse 2", "Verse 2", W_SECT, W_SECT, 0.5, 0.7, 1.0, 40)
add_tab(33, 2, "B", "B", W_TAB, W_TAB, 0.5, 0.7, 1.0, 41)
add_tab(34, 2, "C", "C", W_TAB, W_TAB, 0.5, 0.7, 1.0, 42)
add_tab(35, 2, "D", "D", W_TAB, W_TAB, 0.5, 0.7, 1.0, 43)
add_tab(36, 2, "Pre 2", "Pre 2", W_SECT, W_SECT, 0.8, 0.5, 1.0, 52)
add_tab(37, 2, "B", "B", W_TAB, W_TAB, 0.8, 0.5, 1.0, 53)
add_tab(38, 2, "C", "C", W_TAB, W_TAB, 0.8, 0.5, 1.0, 54)
add_tab(39, 2, "D", "D", W_TAB, W_TAB, 0.8, 0.5, 1.0, 55)
add_tab(40, 2, "Chorus 2", "Chorus 2", W_SECT, W_SECT, 1.0, 0.4, 0.4, 64)
add_tab(41, 2, "B", "B", W_TAB, W_TAB, 1.0, 0.4, 0.4, 65)
add_tab(42, 2, "C", "C", W_TAB, W_TAB, 1.0, 0.4, 0.4, 66)
add_tab(43, 2, "D", "D", W_TAB, W_TAB, 1.0, 0.4, 0.4, 67)
add_tab(44, 2, "Solo", "Solo", W_SECT, W_SECT, 1.0, 0.6, 0.3, 76)
add_tab(45, 2, "B", "B", W_TAB, W_TAB, 1.0, 0.6, 0.3, 77)
add_tab(46, 2, "C", "C", W_TAB, W_TAB, 1.0, 0.6, 0.3, 78)
add_tab(47, 2, "D", "D", W_TAB, W_TAB, 1.0, 0.6, 0.3, 79)
add_tab(48, 2, "H3", "48", W_HWW, W_TAB, 0.8, 0.8, 0.8, 22)
add_tab(49, 2, "H4", "49", W_HWW, W_TAB, 0.8, 0.8, 0.8, 23)
add_tab(50, 2, "2<", "50", W_HWW, W_TAB, 0.9, 0.4, 1.0, 29)
add_tab(51, 2, "2=", "51", W_HWW, W_TAB, 0.9, 0.4, 1.0, 30)
add_tab(52, 2, "2>", "52", W_HWW, W_TAB, 0.9, 0.4, 1.0, 31)

-- ROW 3
add_tab(53, 3, "Min", "Min", W_OFF, W_OFF, 0.9, 0.7, 0.7, 19)
add_tab(54, 3, "6", "6", W_TAB, W_TAB, 0.8, 0.8, 0.8, 6)
add_tab(55, 3, "7", "7", W_TAB, W_TAB, 0.8, 0.8, 0.8, 7)
add_tab(56, 3, "8", "8", W_TAB, W_TAB, 0.8, 0.8, 0.8, 8)
add_tab(57, 3, "9", "9", W_TAB, W_TAB, 0.8, 0.8, 0.8, 9)
add_tab(58, 3, "10", "10", W_TAB, W_TAB, 0.8, 0.8, 0.8, 10)
add_tab(59, 3, "Verse 3", "Verse 3", W_SECT, W_SECT, 0.5, 0.7, 1.0, 44)
add_tab(60, 3, "B", "B", W_TAB, W_TAB, 0.5, 0.7, 1.0, 45)
add_tab(61, 3, "C", "C", W_TAB, W_TAB, 0.5, 0.7, 1.0, 46)
add_tab(62, 3, "D", "D", W_TAB, W_TAB, 0.5, 0.7, 1.0, 47)
add_tab(63, 3, "Pre 3", "Pre 3", W_SECT, W_SECT, 0.8, 0.5, 1.0, 56)
add_tab(64, 3, "B", "B", W_TAB, W_TAB, 0.8, 0.5, 1.0, 57)
add_tab(65, 3, "C", "C", W_TAB, W_TAB, 0.8, 0.5, 1.0, 58)
add_tab(66, 3, "D", "D", W_TAB, W_TAB, 0.8, 0.5, 1.0, 59)
add_tab(67, 3, "Chorus 3", "Chorus 3", W_SECT, W_SECT, 1.0, 0.4, 0.4, 68)
add_tab(68, 3, "B", "B", W_TAB, W_TAB, 1.0, 0.4, 0.4, 69)
add_tab(69, 3, "C", "C", W_TAB, W_TAB, 1.0, 0.4, 0.4, 70)
add_tab(70, 3, "D", "D", W_TAB, W_TAB, 1.0, 0.4, 0.4, 71)
add_tab(71, 3, "Outro", "Outro", W_SECT, W_SECT, 0.5, 0.8, 0.7, 80)
add_tab(72, 3, "B", "B", W_TAB, W_TAB, 0.5, 0.8, 0.7, 81)
add_tab(73, 3, "C", "C", W_TAB, W_TAB, 0.5, 0.8, 0.7, 82)
add_tab(74, 3, "D", "D", W_TAB, W_TAB, 0.5, 0.8, 0.7, 83)
add_tab(75, 3, "rsv", "75", W_HWW, W_TAB, 0.8, 0.8, 0.8, 84)
add_tab(76, 3, "rsv", "76", W_HWW, W_TAB, 0.8, 0.8, 0.8, 85)
add_tab(77, 3, "rsv", "77", W_HWW, W_TAB, 0.9, 0.4, 1.0, 86)
add_tab(78, 3, "rsv", "78", W_HWW, W_TAB, 0.9, 0.4, 1.0, 87)
add_tab(79, 3, "rsv", "79", W_HWW, W_TAB, 0.9, 0.4, 1.0, 88)

local prog_to_tabid = {}
local prog_to_color = {}
local prog_to_name  = {}
for _,tb in ipairs(tabs_drum) do
  prog_to_tabid[tb.prog] = tb.id
  prog_to_color[tb.prog] = {tb.r, tb.g, tb.b}
  prog_to_name[tb.prog]  = tb.name
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
        local normalized = buf:lower()
        for fx_name, track_type in pairs(TARGET_FX_NAMES) do
          local name_without_ext = fx_name:gsub("%.jsfx$", ""):lower()
          local name_with_ext = fx_name:lower()
          local matches = (
            normalized:find(name_with_ext, 1, true) or
            normalized:find(name_without_ext, 1, true) or
            normalized:find("js: " .. name_without_ext, 1, true)
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
          local normalized = name:lower()
          for fx_name, _ in pairs(TARGET_FX_NAMES) do
            local name_without_ext = fx_name:gsub("%.jsfx$", ""):lower()
            local name_with_ext = fx_name:lower()
            local matches = (
              normalized:find(name_with_ext, 1, true) or
              normalized:find(name_without_ext, 1, true) or
              normalized:find("js: " .. name_without_ext, 1, true)
            )
            
            if matches then
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
      local normalized = buf:lower()
      
      for fx_name, _ in pairs(TARGET_FX_NAMES) do
        local name_without_ext = fx_name:gsub("%.jsfx$", ""):lower()
        local name_with_ext = fx_name:lower()
        local matches = (
          normalized:find(name_with_ext, 1, true) or
          normalized:find(name_without_ext, 1, true) or
          normalized:find("js: " .. name_without_ext, 1, true)
        )
        if matches then
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
            local norm = name:lower()
            for fx_name, _ in pairs(TARGET_FX_NAMES) do
              local name_without_ext = fx_name:gsub("%.jsfx$", ""):lower()
              local name_with_ext = fx_name:lower()
              local matches = (
                norm:find(name_with_ext, 1, true) or
                norm:find(name_without_ext, 1, true) or
                norm:find("js: " .. name_without_ext, 1, true)
              )
              if matches then
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
  for _, ct in ipairs(current_tracks) do current_keys[ct.key] = true end
  for key, _ in pairs(cache_active_tabs) do
    if not current_keys[key] then cache_active_tabs[key] = nil end
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

local function write_track_info_to_gmem()
  r.gmem_attach(GMEM_NAMESPACE)
  
  for _, tr_data in ipairs(g_tracks) do
    if tr_data.is_alive and r.ValidatePtr(tr_data.track, "MediaTrack*") and tr_data.inst_id >= 1 and tr_data.inst_id <= 512 then
      local track_num = math.floor(r.GetMediaTrackInfo_Value(tr_data.track, "IP_TRACKNUMBER"))
      local native_col = r.GetTrackColor(tr_data.track)
      local col_r, col_g, col_b = 0.5, 0.5, 0.5
      
      if native_col and native_col ~= 0 then
        local ok, r_val, g_val, b_val = pcall(r.ColorFromNative, native_col)
        if ok and r_val and g_val and b_val then
          col_r = r_val / 255; col_g = g_val / 255; col_b = b_val / 255
        else
          native_col = native_col & 0xFFFFFF
          col_r = (native_col % 256) / 255
          col_g = (math.floor(native_col / 256) % 256) / 255
          col_b = (math.floor(native_col / 65536) % 256) / 255
        end
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
  
  if gmem_step == 0 then step_validate_and_refresh(false); gmem_step = 1
  elseif gmem_step == 1 then step_read_instance_ids(); gmem_step = 2
  elseif gmem_step == 2 then step_read_gmem_packet(0); gmem_step = 3
  elseif gmem_step == 3 then step_read_gmem_packet(1); gmem_step = 4
  elseif gmem_step == 4 then step_read_gmem_packet(2); gmem_step = 5
  elseif gmem_step == 5 then step_read_gmem_packet(3); gmem_step = 6
  elseif gmem_step == 6 then step_finalize() end
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
  return prog_to_name[prog] or ("Pattern " .. tostring(prog))
end

----------------------------------------------------------------
-- ITEM HELPERS
----------------------------------------------------------------

local function force_focus_fx(track, fx_idx)
  if not track or not r.ValidatePtr(track, "MediaTrack*") or fx_idx < 0 then return end
  
  -- Force the plugin to be enabled just in case it was bypassed
  r.TrackFX_SetEnabled(track, fx_idx, true)
  
  -- If it's already floating, close it first. 
  -- Reopening it instantly forces the OS to pull it to the absolute front.
  if r.TrackFX_GetFloatingWindow(track, fx_idx) then
    r.TrackFX_Show(track, fx_idx, 2) -- Hide floating window
  end
  
  -- Show floating window (gains focus)
  r.TrackFX_Show(track, fx_idx, 3) 
end

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
-- SCAN: nearest preceding Program Change (Unified for Drum & Arp)
----------------------------------------------------------------
local function find_active_prog(track, cursor)
  if not track or not r.ValidatePtr(track, "MediaTrack*") then return nil end
  
  local track_key = tostring(track)
  local now = r.time_precise()
  local cached = cache_active_tabs[track_key]
  if cached and (now - cached.time) < CACHE_DURATION then
    return cached.prog
  end
  
  local best_ppq, best_prog
  for i=0, r.CountTrackMediaItems(track)-1 do
    local it = r.GetTrackMediaItem(track,i)
    local tk = r.GetActiveTake(it)
    if tk and r.TakeIsMIDI(tk) then
      local _, notecnt, cccnt, _ = r.MIDI_CountEvts(tk)
      if cccnt > 0 then
        local cur_ppq = r.MIDI_GetPPQPosFromProjTime(tk, cursor)
        for j=0, cccnt-1 do
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

  cache_active_tabs[track_key] = {prog = best_prog, time = now}
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
            if is_pc and chan == CH_PC then should_delete = true; break end
            if is_cc and (msg2 == CC_BANK_MSB) then should_delete = true; break end
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
      force_focus_fx(tr_data.track, tr_data.fx_idx)
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
    end
  end
  r.Undo_EndBlock("N2N Multi-Track: Process Regions", -1)
end

----------------------------------------------------------------
-- IMGUI
----------------------------------------------------------------
local ctx = r.ImGui_CreateContext("N2N Multi-Track Layout Tool")

local font = r.ImGui_CreateFont("Arial", 18)
r.ImGui_Attach(ctx, font)

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
    r.ImGui_DrawList_AddRectFilled(
      draw_list, 
      x + INDICATOR_MARGIN, 
      y + INDICATOR_MARGIN,
      x + INDICATOR_MARGIN + INDICATOR_SIZE + 5, 
      y + INDICATOR_MARGIN + INDICATOR_SIZE,
      rgba_u32(1, 1, 1, 1))    
    r.ImGui_DrawList_AddRectFilled(
      draw_list, 
      x + INDICATOR_MARGIN, 
      y + INDICATOR_MARGIN + 14,
      x + INDICATOR_MARGIN + INDICATOR_SIZE + 5, 
      y + INDICATOR_MARGIN + INDICATOR_SIZE + 14,
      rgba_u32(1, 1, 1, 1))     
  end
end

local function draw_tab_row(row, active_prog, tr_data, cursor, track_idx, tabs_array)
  local first = true
  local tr = tr_data.track
  
  for _,tb in ipairs(tabs_array) do
    if tb.row == row then
      if not first then
        r.ImGui_SameLine(ctx, nil, GAP)
      else
        first = false
      end
      
      local r0,g0,b0 = mute_rgb(tb.r, tb.g, tb.b)
      if not tr_data.is_alive then
        r0,g0,b0 = UI_GRAY, UI_GRAY, UI_GRAY
      end

      local is_active = (active_prog == tb.prog)
      local txt_col = is_active and rgba_u32(0,0,0,1) or rgba_u32(1,1,1,1)
      if is_active then
        r0, g0, b0 = brighten_rgb(r0, g0, b0, 0.4)
      end

      r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(),        rgba_u32(r0,g0,b0,1))
      r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), rgba_u32(brighten_rgb(r0,g0,b0,0.20)))
      r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(),  rgba_u32(brighten_rgb(r0,g0,b0,0.30)))
      r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(),          txt_col)

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

local function loop()
  local now = r.time_precise()
  
  process_gmem_state_machine()
  
  if now - last_dup_check > 0.5 then
    compute_duplicate_ids()
    last_dup_check = now
  end
  
  if r.ImGui_IsKeyPressed(ctx, r.ImGui_Key_Space()) then
    step_validate_and_refresh(true)
  end
  
  r.ImGui_SetNextWindowSize(ctx, 1510, 500, r.ImGui_Cond_Appearing())
  r.ImGui_SetNextWindowSizeConstraints(ctx, 1510, 202, 9999, 9999) 
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

      local rr2,gg2,bb2 = mute_rgb(0.45,0.45,0.45)
      r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), rgba_u32(rr2,gg2,bb2,1))
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
        if ui_btn("Set Swing", 94, BTN_H, "ctl_sw") then
          stamp_swing(tr_swing, swing_value, cur)
        end
        r.ImGui_PopStyleColor(ctx,2)
      end

      r.ImGui_SameLine(ctx,nil,GAP)

      do
        local rr,gg,bb = mute_rgb(0.30,0.30,0.30)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), rgba_u32(rr,gg,bb,1))
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), rgba_u32(1,1,1,1))
        if ui_btn("Process Regions", 144, BTN_H, "ctl_pr") then
          process_regions_all(g_tracks, measure_bank)
        end
        r.ImGui_PopStyleColor(ctx,2)
      end
    end

    r.ImGui_Separator(ctx)
    r.ImGui_Text(ctx, string.format("Found %d N2N instrument(s)", #g_tracks))
    
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
        
        local row_height = BTN_H * 4 + GAP * 3 + 8 -- Increased to 4 rows
        
        -- LEFT COLUMN / HEADER
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_WindowBg(), header_col)
        if r.ImGui_BeginChild(ctx, "Header"..idx, HEADER_WIDTH, row_height) then
          if not tr_data.is_alive then
            r.ImGui_BeginDisabled(ctx, true)
          end
          
          local btn_hover = rgba_u32(brighten_rgb(header_r, header_g, header_b, 0.15))
          local btn_active = rgba_u32(brighten_rgb(header_r, header_g, header_b, 0.25))
          
          r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), header_col)
          r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), btn_hover)
          r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), btn_active)
          r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), text_col)
          
          -- ROW 1: Track Name
          local display_name = tr_data.name
          if #display_name > 18 then display_name = display_name:sub(1,15).."..." end
          if r.ImGui_Button(ctx, display_name, HEADER_WIDTH-10, BTN_H) and tr_data.is_alive then
            r.SetOnlyTrackSelected(tr_data.track)
            r.TrackList_AdjustWindows(false)
          end
          
-- ROW 2: Type and Inst
          local half_w = (HEADER_WIDTH - 10 - GAP) / 2
          
          -- The Arp / Drum Button
          if r.ImGui_Button(ctx, tr_data.type, half_w, BTN_H) and tr_data.is_alive then
            force_focus_fx(tr_data.track, tr_data.fx_idx)
          end
          
          r.ImGui_SameLine(ctx, nil, GAP)
          
          -- The Inst Button
          if r.ImGui_Button(ctx, "Inst", half_w, BTN_H) and tr_data.is_alive then
             local inst_idx = r.TrackFX_GetInstrument(tr_data.track)
             
             if inst_idx >= 0 and inst_idx ~= tr_data.fx_idx then
                 -- If there is a dedicated VSTi instrument, focus it
                 force_focus_fx(tr_data.track, inst_idx)
             else
                 -- Otherwise, just grab the next plugin in the chain
                 local count = r.TrackFX_GetCount(tr_data.track)
                 for i = tr_data.fx_idx + 1, count - 1 do
                     force_focus_fx(tr_data.track, i)
                     break
                 end
             end
          end
          if r.ImGui_IsItemHovered(ctx) then
             r.ImGui_SetTooltip(ctx, "Open/Focus Next Instrument/FX Plugin")
          end
          
          -- ROW 3: ID
          local id_text = tr_data.is_alive and ("ID: "..tostring(tr_data.inst_id)) or "OFFLINE"
          local dup = tr_data.is_alive and is_dup_id(tr_data.inst_id)

          if dup then
            local tnow = r.time_precise()
            local on = (math.floor(tnow * 5) % 2) == 0
            local col = on and rgba_u32(1, 0, 0, 1) or header_col
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

          -- ROW 4: Clear and Process R
          local blue_r, blue_g, blue_b = 0.25, 0.55, 1.0
          if not tr_data.is_alive then blue_r, blue_g, blue_b = UI_GRAY, UI_GRAY, UI_GRAY end
          r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), rgba_u32(blue_r, blue_g, blue_b, 1))
          r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), rgba_u32(brighten_rgb(blue_r, blue_g, blue_b, 0.15)))
          r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), rgba_u32(brighten_rgb(blue_r, blue_g, blue_b, 0.25)))
          r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), rgba_u32(1,1,1,1))
          
          if r.ImGui_Button(ctx, "Clear", half_w, BTN_H) and tr_data.is_alive then
             r.Undo_BeginBlock()
             clear_all_on_track(tr_data.track)
             r.Undo_EndBlock("N2N: Clear " .. tr_data.name, -1)
          end
          r.ImGui_SameLine(ctx, nil, GAP)
          if r.ImGui_Button(ctx, "Proc R", half_w, BTN_H) and tr_data.is_alive then
             r.Undo_BeginBlock()
             process_regions_for_track(tr_data.track, measure_bank)
             r.Undo_EndBlock("N2N: Process " .. tr_data.name, -1)
          end
          if r.ImGui_IsItemHovered(ctx) then
             r.ImGui_SetTooltip(ctx, "Process Regions for this track")
          end
          r.ImGui_PopStyleColor(ctx, 4)

          if not tr_data.is_alive then
            r.ImGui_EndDisabled(ctx)
          end
          
          r.ImGui_EndChild(ctx)
        end
        r.ImGui_PopStyleColor(ctx)
        
        r.ImGui_SameLine(ctx, 0, GAP)
        
        -- RIGHT COLUMN / TABS
        if r.ImGui_BeginChild(ctx, "Buttons"..idx, 0, row_height) then
          local active_prog = nil
          if tr_data.is_alive then
            active_prog = find_active_prog(tr_data.track, cur)
          end
          
          if not tr_data.is_alive then
            r.ImGui_BeginDisabled(ctx, true)
          end
          
          local tabs_array = (tr_data.type == "Arp") and tabs_arp or tabs_drum
          
          draw_tab_row(1, active_prog, tr_data, cur, idx, tabs_array)
          draw_tab_row(2, active_prog, tr_data, cur, idx, tabs_array)
          draw_tab_row(3, active_prog, tr_data, cur, idx, tabs_array)
          
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
