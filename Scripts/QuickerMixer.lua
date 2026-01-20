--@description QuickerMixer (EasyGrid) - Whole-song grid for ON/OFF + Volumes
--@version 1.00
--@noindex

local r = reaper
local ctx = r.ImGui_CreateContext("QuickerMixer")

local font_logo = r.ImGui_CreateFont("sans-serif", 32)  -- try 36 if you want it bigger
r.ImGui_Attach(ctx, font_logo)




-- =====================================================
-- Config
-- =====================================================
local CFG = {
  cell_w = 30,
  cell_h = 22,

  row_header_w = 260,

  region_name_h = 28,
  bar_num_h     = 22,
  hdr_btn_h     = 26,

  pm_btn_w = 18,
  pm_btn_h = 18,

  rq_btn_w = 14,
  rq_btn_h = 18,
  rq_pad   = 3,

  rms_btn_w = 14,
  rms_btn_h = 18,
  rms_pad   = 3,

  sc_btn_w = 28,
  sc_btn_h = 18,
  sc_pad   = 3,

  gq_btn_w = 34,
  gq_btn_h = 26,
  gq_pad   = 10,

  gnms_btn_w = 36,
  gnms_btn_h = 24,
  gnms_pad   = 8,

  gsc_btn_w = 60,
  gsc_btn_h = 26,
  gsc_pad   = 10,

  grid_margin = 6,
  region_frame_thickness = 2.0,

  fade_early = 0.25,
  fade_late  = 0.75,

  window_w = 1400,
  window_h = 760,

  child_align_dx = -6,
  child_align_dy = -6,

  mute_eps = 0.0005,
  default_level = 6,

  hover_alpha = 36,

  -- medium gray strip for header controls
  hdr_strip = {70,70,70},
}







-- =====================================================
-- ImGui color helpers (your working method)
-- =====================================================
local ColorConvert = r.ImGui_ColorConvertDouble4ToU32 or r.ImGui_ColorConvertFloat4ToU32
if not ColorConvert then ColorConvert = function(_,_,_,_) return 0xFFFFFFFF end end

local function U32_FromRGB255(r8, g8, b8, a8)
  a8 = a8 or 255
  return ColorConvert(r8/255.0, g8/255.0, b8/255.0, a8/255.0)
end

local function StripReaperColorFlag(native)
  if not native then return 0 end
  return native & 0xFFFFFF
end

local function NativeToRGB(native)
  native = StripReaperColorFlag(native)
  if not native or native == 0 then return 0,0,0 end
  local rr, gg, bb = r.ColorFromNative(native)
  return rr or 0, gg or 0, bb or 0
end

local function NativeToU32(native)
  local rr, gg, bb = NativeToRGB(native)
  return U32_FromRGB255(rr, gg, bb, 255), rr, gg, bb
end

local function Luminance(r8, g8, b8)
  return 0.2126 * r8 + 0.7152 * g8 + 0.0722 * b8
end

local function BestTextU32(r8, g8, b8)
  if Luminance(r8, g8, b8) >= 140 then
    return U32_FromRGB255(16,16,16,255)
  else
    return U32_FromRGB255(242,242,242,255)
  end
end

local COL_BLACK = U32_FromRGB255(0,0,0,255)
local COL_DARK  = U32_FromRGB255(28,28,28,255)
local COL_WINBG = U32_FromRGB255(18,18,18,255)
local COL_HDRSTRIP = U32_FromRGB255(CFG.hdr_strip[1], CFG.hdr_strip[2], CFG.hdr_strip[3], 255)

local BTN_BG   = U32_FromRGB255(60,60,60,255)
local BTN_HOV  = U32_FromRGB255(80,80,80,255)
local BTN_ACT  = U32_FromRGB255(100,100,100,255)
local BTN_TEXT = U32_FromRGB255(245,245,245,255)

local GREEN_BG  = U32_FromRGB255(50,120,65,255)
local GREEN_HOV = U32_FromRGB255(65,145,80,255)
local GREEN_ACT = U32_FromRGB255(80,170,95,255)

local HOVER_OVER = U32_FromRGB255(255,255,255,CFG.hover_alpha)

-- =====================================================
-- Tabs + tools
-- =====================================================
local TAB_ONOFF = 1
local TAB_VOLS  = 2
local TAB_ARP = 3

local state = {
  tab = TAB_ONOFF,

  onoff_tool = "NORM", -- tool for painting: NORM / MUTE / SOLO

  vol_level = CFG.default_level,
  fade_in_tool  = false,
  fade_out_tool = false,

  arp_pc = 63,
  arp_clear_mode = false,

  tracks = {},
  bars = {},

  onoff_cells = {}, -- [guid][bar_i] = 'N'|'M'|'S'
  vol_cells   = {}, -- [guid][bar_i] = 0..10
  fade_in     = {}, -- [guid][bar_i] = true
  fade_out    = {}, -- [guid][bar_i] = true
  arp_cells   = {}, -- [guid][bar_i] = 0..127 or nil

  painting = false,
  block_paint = false,

  scroll_x = 0,
  scroll_y = 0,
}

local function ensure_guid(guid)
  if not state.onoff_cells[guid] then state.onoff_cells[guid] = {} end
  if not state.vol_cells[guid]   then state.vol_cells[guid]   = {} end
  if not state.fade_in[guid]     then state.fade_in[guid]     = {} end
  if not state.fade_out[guid]    then state.fade_out[guid]    = {} end
  if not state.arp_cells[guid]   then state.arp_cells[guid]   = {} end
end

local function latch_block_paint() state.block_paint = true end
local function update_block_paint_latch()
  if state.block_paint and r.ImGui_IsMouseReleased(ctx, 0) then state.block_paint = false end
end

-- =====================================================
-- Bars / regions (whole project)
-- =====================================================
local function get_measure_idx_at_time(proj, t)
  local _, measures = r.TimeMap2_timeToBeats(proj, t)
  if measures == nil then return 0 end
  if measures < 0 then measures = 0 end
  return measures
end

local function get_measure_timerange(proj, measure_idx)
  local t0, qn_s, qn_e = r.TimeMap_GetMeasureInfo(proj, measure_idx)
  if not t0 or not qn_e then return nil end
  local t1 = r.TimeMap2_QNToTime(proj, qn_e)
  return t0, t1
end

local function nearly(a,b,eps) eps = eps or 1e-4; return math.abs(a-b) <= eps end

local function get_region_at_time(proj, t)
  local idx = 0
  while true do
    local retval, isrgn, pos, rgnend, name, markidx, color = r.EnumProjectMarkers3(proj, idx)
    if retval == 0 then break end
    if isrgn and pos <= t and t < rgnend then
      return name or "", color or 0, pos
    end
    idx = idx + 1
  end
  return "", 0, nil
end

local function build_bars_whole_project(proj)
  local proj_len = r.GetProjectLength(proj)
  if not proj_len or proj_len <= 0 then proj_len = 60.0 end

  local bars = {}
  local m = get_measure_idx_at_time(proj, 0.0)

  local current_seg_start = 0
  local current_seg_name  = ""
  local current_seg_color_u32 = COL_BLACK
  local current_seg_rgb = {0,0,0}

  while true do
    local t0, t1 = get_measure_timerange(proj, m)
    if not t0 then break end
    if t0 >= proj_len + 1e-6 then break end

    local rname, rcol_native, rpos = get_region_at_time(proj, t0)

    local col_u32, rr, gg, bb
    if rcol_native ~= 0 then
      col_u32, rr, gg, bb = NativeToU32(rcol_native)
    else
      col_u32, rr, gg, bb = COL_BLACK, 0,0,0
    end

    local is_start = (rpos ~= nil) and nearly(rpos, t0, 1e-4) or false

    if rpos ~= nil then
      if is_start or current_seg_start == 0 then
        current_seg_start = #bars + 1
        current_seg_name  = rname
        current_seg_color_u32 = col_u32
        current_seg_rgb = {rr,gg,bb}
      end
    else
      current_seg_start = 0
      current_seg_name  = ""
      current_seg_color_u32 = COL_BLACK
      current_seg_rgb = {0,0,0}
    end

    bars[#bars+1] = {
      t0 = t0, t1 = t1,
      bar_num = m + 1,
      region = {
        name = rname,
        color_u32 = col_u32,
        rgb = {rr,gg,bb},
        has = (rpos ~= nil),
        is_start = is_start,
        seg_start = current_seg_start,
        seg_name  = current_seg_name,
        seg_color_u32 = current_seg_color_u32,
        seg_rgb = current_seg_rgb,
      }
    }

    m = m + 1
    if t1 >= proj_len + 1e-6 then break end
  end

  return bars
end

-- =====================================================
-- Tracks + defaults
-- =====================================================
local function init_defaults_for_track(guid)
  ensure_guid(guid)
  for bi = 1, #state.bars do
    if state.onoff_cells[guid][bi] == nil then state.onoff_cells[guid][bi] = 'N' end
    if state.vol_cells[guid][bi]   == nil then state.vol_cells[guid][bi]   = CFG.default_level end
  end
end

local function rebuild_model()
  local proj = 0
  state.tracks = {}

  local n = r.CountTracks(proj)
  for i = 0, n-1 do
    local tr = r.GetTrack(proj, i)
    local _, name = r.GetTrackName(tr)
    local guid = r.GetTrackGUID(tr)

    local native = r.GetTrackColor(tr)
    local col_u32, rr, gg, bb
    if native ~= 0 then
      col_u32, rr, gg, bb = NativeToU32(native)
    else
      rr, gg, bb = 80,80,80
      col_u32 = U32_FromRGB255(rr,gg,bb,255)
    end

    state.tracks[#state.tracks+1] = {
      track = tr,
      guid = guid,
      name = (name ~= "" and name) or ("Track " .. tostring(i+1)),
      color_u32 = col_u32,
      rgb = {rr,gg,bb},
    }

    ensure_guid(guid)
  end

  state.bars = build_bars_whole_project(proj)

  for _, trinfo in ipairs(state.tracks) do
    init_defaults_for_track(trinfo.guid)
  end
end

-- =====================================================
-- Envelope helpers
-- =====================================================
local function get_selected_tracks_snapshot()
  local sel = {}
  local n = r.CountSelectedTracks(0)
  for i=0, n-1 do sel[#sel+1] = r.GetSelectedTrack(0, i) end
  return sel
end

local function restore_selected_tracks(sel)
  r.Main_OnCommand(40297, 0) -- unselect all tracks
  for _, tr in ipairs(sel) do r.SetTrackSelected(tr, true) end
end

local function select_only_track(tr)
  r.Main_OnCommand(40297, 0)
  r.SetTrackSelected(tr, true)
end

local function ensure_env_visible(track, env_name)
  if env_name == "Volume" then
    r.Main_OnCommand(40406, 0) -- Track: Toggle track volume envelope visible
  elseif env_name == "Mute" then
    r.Main_OnCommand(40867, 0) -- Track: Toggle track mute envelope visible
  end
end

local function get_or_create_env(track, env_name)
  local env = r.GetTrackEnvelopeByName(track, env_name)
  if env then return env end
  local snap = get_selected_tracks_snapshot()
  select_only_track(track)
  ensure_env_visible(track, env_name)
  env = r.GetTrackEnvelopeByName(track, env_name)
  restore_selected_tracks(snap)
  return env
end

-- volume envelope name fallback (some installs expose "Volume (Pre-FX)" etc)
local function get_or_create_volume_env(track)
  local names = {"Volume", "Volume (Pre-FX)", "Trim Volume"}
  for _, nm in ipairs(names) do
    local env = r.GetTrackEnvelopeByName(track, nm)
    if env then return env end
  end
  local env = get_or_create_env(track, "Volume")
  if env then return env end
  for _, nm in ipairs(names) do
    env = r.GetTrackEnvelopeByName(track, nm)
    if env then return env end
  end
  return nil
end

local function insert_point(env, t, v, shape)
  r.InsertEnvelopePoint(env, t, v, shape or 0, 0, false, true)
end

-- =====================================================
-- Volume mapping: 0..10 == 0..100% fader travel (REAPER taper)
-- Writes amplitude directly
-- =====================================================
local function level_to_amp_from_fader_travel(lvl)
  lvl = math.max(0, math.min(10, lvl))
  if lvl == 0 then return 0.0 end
  local pos = lvl / 10.0
  local db  = r.SLIDER2DB(pos)
  local amp = 10^(db/20.0)
  if amp < 1e-12 then amp = 1e-12 end
  return amp
end

-- =====================================================
-- ON/OFF logic: REAPER Mute envelope is 0=muted, 1=unmuted
-- =====================================================
local function bar_has_solo(bi)
  for _, tr in ipairs(state.tracks) do
    if state.onoff_cells[tr.guid][bi] == 'S' then return true end
  end
  return false
end

local function compute_mute_env_value(guid, bi, hasSolo)
  local m = state.onoff_cells[guid][bi] or 'N'
  if m == 'M' then return 0 end -- muted
  if m == 'S' then return 1 end -- unmuted
  -- NORM: unmuted unless someone is soloing this bar
  if hasSolo then return 0 else return 1 end
end

local function apply_onoff_full(with_undo)
  if with_undo then r.Undo_BeginBlock() end

  for _, tr in ipairs(state.tracks) do init_defaults_for_track(tr.guid) end
  local hasSolo = {}
  for bi = 1, #state.bars do hasSolo[bi] = bar_has_solo(bi) end

  for _, trinfo in ipairs(state.tracks) do
    local env = get_or_create_env(trinfo.track, "Mute")
    if env then
      for bi = 1, #state.bars do
        local bar = state.bars[bi]
        local v = compute_mute_env_value(trinfo.guid, bi, hasSolo[bi])

        local t0 = bar.t0
        local t1 = bar.t1
        local t1m = t1 - CFG.mute_eps
        if t1m < t0 then t1m = t1 end

        r.DeleteEnvelopePointRange(env, t0, t1)
        insert_point(env, t0,  v, 1)   -- square
        insert_point(env, t1m, v, 1)
      end
      r.Envelope_SortPoints(env)
    end
  end

  if with_undo then r.Undo_EndBlock("QuickerMixer: Apply ON/OFF (full)", -1) end
end

local function apply_volume_full(with_undo)
  if with_undo then r.Undo_BeginBlock() end

  for _, tr in ipairs(state.tracks) do init_defaults_for_track(tr.guid) end

  for _, trinfo in ipairs(state.tracks) do
    local guid = trinfo.guid
    local env = get_or_create_volume_env(trinfo.track)

    if env then
      local mode = r.GetEnvelopeScalingMode(env)

      -- P writes your simple formula: 0=0.0, 1=0.1, ... 10=1.0
      -- then converts through the envelope's scaling mode.
      local function P(t, lvl)
        lvl = math.max(0, math.min(10, lvl or 0))
        local pos = lvl * 0.1
        local v = r.ScaleToEnvelopeMode(mode, pos)
        insert_point(env, t, v, 0)
      end

      for bi = 1, #state.bars do
        local bar = state.bars[bi]
        local dur = bar.t1 - bar.t0
        if dur > 0 then
          local this_lvl = state.vol_cells[guid][bi] or CFG.default_level
          local prev_lvl = (bi > 1) and (state.vol_cells[guid][bi-1] or CFG.default_level) or 0
          local next_lvl = (bi < #state.bars) and (state.vol_cells[guid][bi+1] or CFG.default_level) or 0

          local has_in  = state.fade_in[guid][bi]  == true
          local has_out = state.fade_out[guid][bi] == true

          local prev_has_out = (bi > 1) and (state.fade_out[guid][bi-1] == true) or false
          local next_has_in  = (bi < #state.bars) and (state.fade_in[guid][bi+1] == true) or false

          local start_from = prev_lvl
          if has_in and prev_has_out then
            start_from = (prev_lvl + this_lvl) * 0.5
          end

          local end_to = next_lvl
          if has_out and next_has_in then
            end_to = (this_lvl + next_lvl) * 0.5
          end

          local t_early = bar.t0 + dur * CFG.fade_early
          local t_late  = bar.t0 + dur * CFG.fade_late

          r.DeleteEnvelopePointRange(env, bar.t0, bar.t1)

          if (not has_in) and (not has_out) then
            P(bar.t0, this_lvl); P(bar.t1, this_lvl)

          elseif has_in and (not has_out) then
            P(bar.t0, start_from)
            P(t_early, this_lvl)
            P(bar.t1, this_lvl)

          elseif (not has_in) and has_out then
            P(bar.t0, this_lvl)
            P(t_late, this_lvl)
            P(bar.t1, end_to)

          else
            P(bar.t0, start_from)
            P(t_early, this_lvl)
            P(t_late, this_lvl)
            P(bar.t1, end_to)
          end
        end
      end

      r.Envelope_SortPoints(env)
    end
  end

  if with_undo then r.Undo_EndBlock("QuickerMixer: Apply Volume (full)", -1) end
end

local function apply_arp_full(with_undo)
  if with_undo then r.Undo_BeginBlock() end

  for _, trinfo in ipairs(state.tracks) do
    local track = trinfo.track
    local guid = trinfo.guid
    ensure_guid(guid)

    for bi = 1, #state.bars do
      local bar = state.bars[bi]
      local value = state.arp_cells[guid][bi]  -- nil or 0..127
      local measure_idx = bar.bar_num - 1
      local t0 = bar.t0
      local _, qn_s = r.TimeMap_GetMeasureInfo(0, measure_idx)

      local pc_qn, pc_time
      if bi == 1 then
        pc_qn = qn_s
        pc_time = t0
      else
        pc_qn = qn_s - 0.0625
        pc_time = r.TimeMap2_QNToTime(0, pc_qn)
      end

      local qtr_qn = 1.0
      local add_64th = 0.0625
      local item_end_qn = pc_qn + qtr_qn + add_64th
      local item_end_time = r.TimeMap2_QNToTime(0, item_end_qn)
      local item_len = item_end_time - pc_time

      -- Delete existing
      local tolerance = 0.015
      local delete_window_start = pc_time - tolerance
      local delete_window_end = pc_time + tolerance

      local num_items = r.CountTrackMediaItems(track)
      for ii = num_items - 1, 0, -1 do
        local item = r.GetTrackMediaItem(track, ii)
        local item_start = r.GetMediaItemInfo_Value(item, "D_POSITION")
        local item_end = item_start + r.GetMediaItemInfo_Value(item, "D_LENGTH")

        if item_end > delete_window_start and item_start < delete_window_end then
          local take = r.GetActiveTake(item)
          if take and r.TakeIsMIDI(take) then
            local _, _, _, num_events = r.MIDI_CountEvts(take)
            for ee = num_events - 1, 0, -1 do
              local _, _, _, ppqpos, _, msg = r.MIDI_GetEvt(take, ee, false, false, 0, "")
              local evt_time = item_start + r.MIDI_GetProjTimeFromPPQPos(take, ppqpos)
              if evt_time >= delete_window_start and evt_time <= delete_window_end then
                if #msg >= 2 and (msg:byte(1) & 0xF0) == 0xC0 and (msg:byte(1) & 0x0F) == 15 then
                  r.MIDI_DeleteEvt(take, ee)
                end
              end
            end
            local _, _, _, new_num_events = r.MIDI_CountEvts(take)
            if new_num_events == 0 then
              r.DeleteTrackMediaItem(track, item)
            end
          end
        end
      end

      -- Create new if value
      if value ~= nil then
        -- Create a real MIDI item
        local item = r.CreateNewMIDIItemInProj(track, pc_time, pc_time + item_len, false)
        local take = r.GetActiveTake(item)
      
        -- Name the take
        r.GetSetMediaItemTakeInfo_String(take, "P_NAME", "N2N Arp PC", true)
      
        -- PC on Channel 16 (channel index 15) at PPQ 0
        local status = 0xC0 + 15            -- Program Change, ch16
        local program = math.max(0, math.min(127, tonumber(value) or 0)) -- ensure 0..127
        local msg = string.char(status, program)
      
        r.MIDI_InsertEvt(take, false, false, 0, msg)
        r.MIDI_Sort(take)
      end
    end
  end

  if with_undo then r.Undo_EndBlock("QuickerMixer: Apply N2N Arp", -1) end
end


-- =====================================================
-- Bulk edits (grid values only)
-- =====================================================
local function paint_cell(guid, bi)
  ensure_guid(guid)
  if state.tab == TAB_ONOFF then
    local c = (state.onoff_tool == "MUTE" and 'M') or (state.onoff_tool == "SOLO" and 'S') or 'N'
    state.onoff_cells[guid][bi] = c
  elseif state.tab == TAB_VOLS then
    local lvl = math.max(0, math.min(10, state.vol_level))
    state.vol_cells[guid][bi] = lvl
    if state.fade_in_tool  then state.fade_in[guid][bi]  = true end
    if state.fade_out_tool then state.fade_out[guid][bi] = true end
  elseif state.tab == TAB_ARP then
    state.arp_cells[guid][bi] = state.arp_clear_mode and nil or state.arp_pc
  end
end

local function set_row_all(guid)
  ensure_guid(guid)
  for bi = 1, #state.bars do paint_cell(guid, bi) end
end

local function set_col_all(bi)
  for _, tr in ipairs(state.tracks) do paint_cell(tr.guid, bi) end
end

local function bump_row(guid, delta)
  ensure_guid(guid)
  for bi = 1, #state.bars do
    local v = state.vol_cells[guid][bi] or CFG.default_level
    state.vol_cells[guid][bi] = math.max(0, math.min(10, v + delta))
  end
end

local function bump_col(bi, delta)
  for _, tr in ipairs(state.tracks) do
    local guid = tr.guid
    ensure_guid(guid)
    local v = state.vol_cells[guid][bi] or CFG.default_level
    state.vol_cells[guid][bi] = math.max(0, math.min(10, v + delta))
  end
end

local function bump_all(delta)
  for _, tr in ipairs(state.tracks) do bump_row(tr.guid, delta) end
end

local function set_all_to_selected()
  for _, tr in ipairs(state.tracks) do
    local guid = tr.guid
    ensure_guid(guid)
    for bi = 1, #state.bars do
      state.vol_cells[guid][bi] = math.max(0, math.min(10, state.vol_level))
    end
  end
end

local function set_all_onoff(char) -- 'N'|'M'|'S'
  for _, tr in ipairs(state.tracks) do
    local guid = tr.guid
    ensure_guid(guid)
    for bi = 1, #state.bars do
      state.onoff_cells[guid][bi] = char
    end
  end
end

local function set_all_arp(is_set)
  for _, tr in ipairs(state.tracks) do
    local guid = tr.guid
    ensure_guid(guid)
    for bi = 1, #state.bars do
      state.arp_cells[guid][bi] = is_set and state.arp_pc or nil
    end
  end
end

-- Region segment bounds by seg_start
local function region_seg_bounds(seg_start)
  if not seg_start or seg_start <= 0 then return nil end
  local seg_name = state.bars[seg_start] and state.bars[seg_start].region.seg_name or ""
  if seg_name == "" then return nil end
  local seg_end = seg_start
  for bi = seg_start, #state.bars do
    if state.bars[bi].region.seg_start ~= seg_start then
      seg_end = bi - 1
      break
    end
    seg_end = bi
  end
  return seg_start, seg_end
end

local function set_region_seg_vol(seg_start)
  local a,b = region_seg_bounds(seg_start)
  if not a then return end
  for bi=a,b do set_col_all(bi) end
end

local function bump_region_seg_vol(seg_start, delta)
  local a,b = region_seg_bounds(seg_start)
  if not a then return end
  for bi=a,b do bump_col(bi, delta) end
end

local function set_region_seg_onoff(seg_start, mode_char)
  local a,b = region_seg_bounds(seg_start)
  if not a then return end
  for _, tr in ipairs(state.tracks) do
    local guid = tr.guid
    ensure_guid(guid)
    for bi=a,b do state.onoff_cells[guid][bi] = mode_char end
  end
end

local function set_region_seg_arp(seg_start, is_set)
  local a,b = region_seg_bounds(seg_start)
  if not a then return end
  for _, tr in ipairs(state.tracks) do
    local guid = tr.guid
    ensure_guid(guid)
    for bi=a,b do state.arp_cells[guid][bi] = is_set and state.arp_pc or nil end
  end
end

-- =====================================================
-- Button styling
-- =====================================================
local function PushButtonStyle(active)
  if not r.ImGui_Col_Button then return end
  if active then
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(),        GREEN_BG)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), GREEN_HOV)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(),  GREEN_ACT)
  else
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(),        BTN_BG)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), BTN_HOV)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(),  BTN_ACT)
  end
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), BTN_TEXT)
end

local function PopButtonStyle()
  if r.ImGui_Col_Button then r.ImGui_PopStyleColor(ctx, 4) end
end

-- =====================================================
-- UI: Tabs + toolbars
-- =====================================================
local function draw_tabs()
  if r.ImGui_BeginTabBar(ctx, "##tabs") then
    if r.ImGui_BeginTabItem(ctx, "ON/OFF", state.tab == TAB_ONOFF) then state.tab = TAB_ONOFF; r.ImGui_EndTabItem(ctx) end
    if r.ImGui_BeginTabItem(ctx, "Volumes", state.tab == TAB_VOLS) then state.tab = TAB_VOLS;  r.ImGui_EndTabItem(ctx) end
    if r.ImGui_BeginTabItem(ctx, "N2N Arp", state.tab == TAB_ARP) then state.tab = TAB_ARP;  r.ImGui_EndTabItem(ctx) end
    r.ImGui_EndTabBar(ctx)
  end
end

local function draw_toolbar()
  if state.tab == TAB_ONOFF then
    PushButtonStyle(state.onoff_tool == "NORM"); if r.ImGui_Button(ctx, "Norm") then state.onoff_tool = "NORM"; latch_block_paint() end; PopButtonStyle()
    r.ImGui_SameLine(ctx)
    PushButtonStyle(state.onoff_tool == "MUTE"); if r.ImGui_Button(ctx, "Mute") then state.onoff_tool = "MUTE"; latch_block_paint() end; PopButtonStyle()
    r.ImGui_SameLine(ctx)
    PushButtonStyle(state.onoff_tool == "SOLO"); if r.ImGui_Button(ctx, "Solo") then state.onoff_tool = "SOLO"; latch_block_paint() end; PopButtonStyle()
  elseif state.tab == TAB_VOLS then
    PushButtonStyle(state.fade_in_tool)
    if r.ImGui_Button(ctx, "FADE_IN") then state.fade_in_tool = not state.fade_in_tool; latch_block_paint() end
    PopButtonStyle()

    r.ImGui_SameLine(ctx, 0, 10); r.ImGui_Text(ctx, "|"); r.ImGui_SameLine(ctx, 0, 10)

    for i = 0, 10 do
      if i > 0 then r.ImGui_SameLine(ctx) end
      PushButtonStyle(state.vol_level == i)
      if r.ImGui_Button(ctx, tostring(i)) then state.vol_level = i; latch_block_paint() end
      PopButtonStyle()
    end

    r.ImGui_SameLine(ctx, 0, 10); r.ImGui_Text(ctx, "|"); r.ImGui_SameLine(ctx, 0, 10)

    PushButtonStyle(state.fade_out_tool)
    if r.ImGui_Button(ctx, "FADE_OUT") then state.fade_out_tool = not state.fade_out_tool; latch_block_paint() end
    PopButtonStyle()
  elseif state.tab == TAB_ARP then
    PushButtonStyle(state.arp_clear_mode)
    if r.ImGui_Button(ctx, "Clear") then state.arp_clear_mode = not state.arp_clear_mode; latch_block_paint() end
    PopButtonStyle()

    r.ImGui_SameLine(ctx, 0, 10); r.ImGui_Text(ctx, "|"); r.ImGui_SameLine(ctx, 0, 10)

    local avail_w = r.ImGui_GetContentRegionAvail(ctx)
    r.ImGui_BeginChild(ctx, "##pc_scroll", avail_w - 20, 30, 0, r.ImGui_WindowFlags_HorizontalScrollbar())
    for i = 1, 128 do
      if i > 1 then r.ImGui_SameLine(ctx, 0, 2) end
      local active = (state.arp_pc + 1 == i)
      PushButtonStyle(active)
      if r.ImGui_Button(ctx, tostring(i), 34, -1) then state.arp_pc = i - 1; latch_block_paint() end
      PopButtonStyle()
    end
    r.ImGui_EndChild(ctx)
  end

  r.ImGui_Separator(ctx)
end

-- =====================================================
-- Logo block
-- =====================================================
local function draw_logo_block(x0, y0)
  -- Big logo
  if r.ImGui_SetWindowFontScale then r.ImGui_SetWindowFontScale(ctx, 2.6) end
r.ImGui_PushFont(ctx, font_logo, 32)
r.ImGui_SetCursorScreenPos(ctx, x0 +3 , y0 -10 )
r.ImGui_Text(ctx, "QuickerMixer")
r.ImGui_PopFont(ctx)
  if r.ImGui_SetWindowFontScale then r.ImGui_SetWindowFontScale(ctx, 1.0) end

  if state.tab == TAB_VOLS then
    local bx = x0 + 10
    local by = y0 + 42

    -- medium gray strip behind global buttons
    local dl = r.ImGui_GetWindowDrawList(ctx)
    r.ImGui_DrawList_AddRectFilled(dl, bx - 4, by - 4, bx + (CFG.gq_btn_w + CFG.gq_pad)*3 - CFG.gq_pad + 4, by + CFG.gq_btn_h + 4, COL_HDRSTRIP, 4)

    PushButtonStyle(false)
    r.ImGui_SetCursorScreenPos(ctx, bx, by)
    if r.ImGui_Button(ctx, "-##global", CFG.gq_btn_w, CFG.gq_btn_h) then bump_all(-1); state.painting = true; latch_block_paint() end
    r.ImGui_SetCursorScreenPos(ctx, bx + CFG.gq_btn_w + CFG.gq_pad, by)
    if r.ImGui_Button(ctx, "Q##global", CFG.gq_btn_w, CFG.gq_btn_h) then set_all_to_selected(); state.painting = true; latch_block_paint() end
    r.ImGui_SetCursorScreenPos(ctx, bx + (CFG.gq_btn_w + CFG.gq_pad)*2, by)
    if r.ImGui_Button(ctx, "+##global", CFG.gq_btn_w, CFG.gq_btn_h) then bump_all(1); state.painting = true; latch_block_paint() end
    PopButtonStyle()
  elseif state.tab == TAB_ONOFF then
    local bx = x0 + 10
    local by = y0 + 42

    local dl = r.ImGui_GetWindowDrawList(ctx)
    r.ImGui_DrawList_AddRectFilled(dl, bx - 4, by - 4, bx + (CFG.gnms_btn_w + CFG.gnms_pad)*3 - CFG.gnms_pad + 4, by + CFG.gnms_btn_h + 4, COL_HDRSTRIP, 4)

    -- These set ALL GRID VALUES (not tool select)
    PushButtonStyle(false)
    r.ImGui_SetCursorScreenPos(ctx, bx, by)
    if r.ImGui_Button(ctx, "N##all", CFG.gnms_btn_w, CFG.gnms_btn_h) then set_all_onoff('N'); state.painting = true; latch_block_paint() end
    r.ImGui_SetCursorScreenPos(ctx, bx + CFG.gnms_btn_w + CFG.gnms_pad, by)
    if r.ImGui_Button(ctx, "M##all", CFG.gnms_btn_w, CFG.gnms_btn_h) then set_all_onoff('M'); state.painting = true; latch_block_paint() end
    r.ImGui_SetCursorScreenPos(ctx, bx + (CFG.gnms_btn_w + CFG.gnms_pad)*2, by)
    if r.ImGui_Button(ctx, "S##all", CFG.gnms_btn_w, CFG.gnms_btn_h) then set_all_onoff('S'); state.painting = true; latch_block_paint() end
    PopButtonStyle()
  elseif state.tab == TAB_ARP then
    local bx = x0 + 10
    local by = y0 + 42

    local dl = r.ImGui_GetWindowDrawList(ctx)
    r.ImGui_DrawList_AddRectFilled(dl, bx - 4, by - 4, bx + (CFG.gsc_btn_w + CFG.gsc_pad)*2 - CFG.gsc_pad + 4, by + CFG.gsc_btn_h + 4, COL_HDRSTRIP, 4)

    PushButtonStyle(false)
    r.ImGui_SetCursorScreenPos(ctx, bx, by)
    if r.ImGui_Button(ctx, "Set All##global", CFG.gsc_btn_w, CFG.gsc_btn_h) then set_all_arp(true); state.painting = true; latch_block_paint() end
    r.ImGui_SetCursorScreenPos(ctx, bx + CFG.gsc_btn_w + CFG.gsc_pad, by)
    if r.ImGui_Button(ctx, "Clr All##global", CFG.gsc_btn_w, CFG.gsc_btn_h) then set_all_arp(false); state.painting = true; latch_block_paint() end
    PopButtonStyle()
  end
end

-- =====================================================
-- Grid drawing
-- =====================================================
local function draw_grid()
  update_block_paint_latch()

  local dl = r.ImGui_GetWindowDrawList(ctx)
  local avail_w, avail_h = r.ImGui_GetContentRegionAvail(ctx)

  local header_h = CFG.region_name_h + CFG.bar_num_h + CFG.hdr_btn_h
  local left_w   = CFG.row_header_w

  local body_w = avail_w - left_w - CFG.grid_margin
  local body_h = avail_h - header_h - CFG.grid_margin
  if body_w < 80 then body_w = 80 end
  if body_h < 80 then body_h = 80 end

  local sx, sy = r.ImGui_GetCursorScreenPos(ctx)
  local x0 = sx + CFG.grid_margin
  local y0 = sy + CFG.grid_margin

  local horiz_flag = (r.ImGui_WindowFlags_HorizontalScrollbar and r.ImGui_WindowFlags_HorizontalScrollbar()) or 0

  -- Scrollable body child
  r.ImGui_SetCursorScreenPos(ctx, x0 + left_w, y0 + header_h)
  r.ImGui_BeginChild(ctx, "##grid_body", body_w, body_h, 1, horiz_flag)

  local child_top_x, child_top_y = r.ImGui_GetCursorScreenPos(ctx)
  child_top_x = child_top_x + CFG.child_align_dx
  child_top_y = child_top_y + CFG.child_align_dy

  local content_w = #state.bars * CFG.cell_w
  local content_h = #state.tracks * CFG.cell_h
  r.ImGui_InvisibleButton(ctx, "##grid_body_content", content_w, content_h)

  state.scroll_x = r.ImGui_GetScrollX(ctx)
  state.scroll_y = r.ImGui_GetScrollY(ctx)

  local body_dl = r.ImGui_GetWindowDrawList(ctx)

  local first_col = math.floor(state.scroll_x / CFG.cell_w) + 1
  local first_row = math.floor(state.scroll_y / CFG.cell_h) + 1
  local vis_cols = math.floor(body_w / CFG.cell_w) + 2
  local vis_rows = math.floor(body_h / CFG.cell_h) + 2
  local last_col = math.min(#state.bars, first_col + vis_cols)
  local last_row = math.min(#state.tracks, first_row + vis_rows)

  -- Hovered cell for highlighting
  local hovered_ti, hovered_bi = nil, nil
  do
    local mx, my = r.ImGui_GetMousePos(ctx)
    local bx0 = (x0 + left_w)
    local by0 = (y0 + header_h)
    local bx1 = bx0 + body_w
    local by1 = by0 + body_h
    if mx >= bx0 and mx < bx1 and my >= by0 and my < by1 then
      hovered_bi = math.floor((mx - bx0 + state.scroll_x) / CFG.cell_w) + 1
      hovered_ti = math.floor((my - by0 + state.scroll_y) / CFG.cell_h) + 1
      if hovered_bi < 1 or hovered_bi > #state.bars then hovered_bi = nil end
      if hovered_ti < 1 or hovered_ti > #state.tracks then hovered_ti = nil end
    end
  end

  -- Body cells + paint
  for ti = first_row, last_row do
    local tr = state.tracks[ti]
    local guid = tr.guid
    local row_txt = BestTextU32(tr.rgb[1], tr.rgb[2], tr.rgb[3])

    local cy = child_top_y + (ti-1)*CFG.cell_h
    for bi = first_col, last_col do
      local cx  = child_top_x + (bi-1)*CFG.cell_w
      local cx2 = cx + CFG.cell_w
      local cy2 = cy + CFG.cell_h

      r.ImGui_DrawList_AddRectFilled(body_dl, cx, cy, cx2, cy2, tr.color_u32, 0)

      if (hovered_ti and ti == hovered_ti) or (hovered_bi and bi == hovered_bi) then
        r.ImGui_DrawList_AddRectFilled(body_dl, cx, cy, cx2, cy2, HOVER_OVER, 0)
      end

      local frame_col = state.bars[bi].region.has and state.bars[bi].region.color_u32 or COL_BLACK
      r.ImGui_DrawList_AddRect(body_dl, cx, cy, cx2, cy2, frame_col, 0, 0, CFG.region_frame_thickness)

      if state.tab == TAB_ONOFF then
        local m = state.onoff_cells[guid][bi] or 'N'
        local ch = (m == 'N') and "-" or m
        r.ImGui_DrawList_AddText(body_dl, cx + 6, cy + 4, row_txt, ch)
      elseif state.tab == TAB_VOLS then
        local lvl = state.vol_cells[guid][bi] or CFG.default_level
        local left  = state.fade_in[guid][bi]  and "<" or ""
        local right = state.fade_out[guid][bi] and ">" or ""
        r.ImGui_DrawList_AddText(body_dl, cx + 2, cy + 4, row_txt, left .. tostring(lvl) .. right)
      elseif state.tab == TAB_ARP then
        local v = state.arp_cells[guid][bi]
        local str = v and tostring(v + 1) or ""
        r.ImGui_DrawList_AddText(body_dl, cx + 6, cy + 4, row_txt, str)
      end

      if (not state.block_paint) then
        local mx, my = r.ImGui_GetMousePos(ctx)
        if mx >= cx and mx < cx2 and my >= cy and my < cy2 and r.ImGui_IsMouseDown(ctx, 0) then
          paint_cell(guid, bi)
          state.painting = true
        end
      end
    end
  end

  r.ImGui_EndChild(ctx)

  -- Frozen top-left block
  r.ImGui_DrawList_AddRectFilled(dl, x0, y0, x0 + left_w, y0 + header_h, COL_DARK, 0)
  draw_logo_block(x0, y0)

  local y_regions = y0
  local y_barnums = y0 + CFG.region_name_h
  local y_btns    = y0 + CFG.region_name_h + CFG.bar_num_h

  -- Draw column header backgrounds + bar numbers + +/- per bar (Volumes)
  for bi = 1, #state.bars do
    local bx = x0 + left_w + (bi-1)*CFG.cell_w - state.scroll_x
    local bx2 = bx + CFG.cell_w
    if bx2 < (x0 + left_w) or bx > (x0 + left_w + body_w) then goto continue_col end

    local reg = state.bars[bi].region
    local txt = BestTextU32(reg.rgb[1], reg.rgb[2], reg.rgb[3])
    local bg  = reg.has and reg.color_u32 or COL_BLACK

    r.ImGui_DrawList_AddRectFilled(dl, bx, y_regions, bx2, y_regions + CFG.region_name_h, bg, 0)
    r.ImGui_DrawList_AddRectFilled(dl, bx, y_barnums, bx2, y_barnums + CFG.bar_num_h, bg, 0)
    r.ImGui_DrawList_AddRectFilled(dl, bx, y_btns,    bx2, y_btns    + CFG.hdr_btn_h, bg, 0)

    r.ImGui_DrawList_AddText(dl, bx + 8, y_barnums + 4, txt, tostring(state.bars[bi].bar_num))

    if state.tab == TAB_VOLS then
      -- medium gray strip behind +/- so it stays readable
      local strip_y0 = y_btns + 2
      local strip_y1 = y_btns + CFG.hdr_btn_h - 2
      r.ImGui_DrawList_AddRectFilled(dl, bx + 1, strip_y0, bx2 - 1, strip_y1, COL_HDRSTRIP, 3)

      PushButtonStyle(false)
      local by_btn = y_btns + (CFG.hdr_btn_h - CFG.pm_btn_h) * 0.5
      local bx_minus = bx + 2
      local bx_plus  = bx2 - 2 - CFG.pm_btn_w

      r.ImGui_SetCursorScreenPos(ctx, bx_minus, by_btn)
      if r.ImGui_Button(ctx, ("-##col_%d"):format(bi), CFG.pm_btn_w, CFG.pm_btn_h) then
        bump_col(bi, -1); state.painting = true; latch_block_paint()
      end

      r.ImGui_SetCursorScreenPos(ctx, bx_plus, by_btn)
      if r.ImGui_Button(ctx, ("+##col_%d"):format(bi), CFG.pm_btn_w, CFG.pm_btn_h) then
        bump_col(bi, 1); state.painting = true; latch_block_paint()
      end
      PopButtonStyle()
    end

    ::continue_col::
  end

  -- Row headers
  for ti = 1, #state.tracks do
    local ty = y0 + header_h + (ti-1)*CFG.cell_h - state.scroll_y
    local ty2 = ty + CFG.cell_h
    if ty2 < (y0 + header_h) or ty > (y0 + header_h + body_h) then goto continue_row end

    local tr = state.tracks[ti]
    local guid = tr.guid
    local row_txt = BestTextU32(tr.rgb[1], tr.rgb[2], tr.rgb[3])

    r.ImGui_DrawList_AddRectFilled(dl, x0, ty, x0 + left_w, ty2, tr.color_u32, 0)
    if hovered_ti and ti == hovered_ti then
      r.ImGui_DrawList_AddRectFilled(dl, x0, ty, x0 + left_w, ty2, HOVER_OVER, 0)
    end
    r.ImGui_DrawList_AddText(dl, x0 + 8, ty + 4, row_txt, tr.name)

    if state.tab == TAB_VOLS then
      -- strip behind row +/- buttons
      local strip_x0 = x0 + left_w - (CFG.pm_btn_w*2 + 10)
      local strip_x1 = x0 + left_w - 4
      r.ImGui_DrawList_AddRectFilled(dl, strip_x0, ty + 2, strip_x1, ty2 - 2, COL_HDRSTRIP, 3)

      PushButtonStyle(false)
      local bx_plus  = x0 + left_w - 2 - CFG.pm_btn_w
      local bx_minus = bx_plus - 2 - CFG.pm_btn_w
      local by_btn   = ty + (CFG.cell_h - CFG.pm_btn_h) * 0.5

      r.ImGui_SetCursorScreenPos(ctx, bx_minus, by_btn)
      if r.ImGui_Button(ctx, ("-##row_%d"):format(ti), CFG.pm_btn_w, CFG.pm_btn_h) then
        bump_row(guid, -1); state.painting = true; latch_block_paint()
      end

      r.ImGui_SetCursorScreenPos(ctx, bx_plus, by_btn)
      if r.ImGui_Button(ctx, ("+##row_%d"):format(ti), CFG.pm_btn_w, CFG.pm_btn_h) then
        bump_row(guid, 1); state.painting = true; latch_block_paint()
      end
      PopButtonStyle()
    end

    ::continue_row::
  end

  -- =====================================================
  -- Region segment header overlays (draw ONCE per region segment)
  -- This is what fixes the "sliver button" + missing name.
  -- =====================================================
  for bi = 1, #state.bars do
    local reg = state.bars[bi].region
    if reg.has and reg.is_start and reg.seg_start == bi and reg.seg_name ~= "" then
      local a, b = region_seg_bounds(bi)
      if a then
        local bx = x0 + left_w + (a-1)*CFG.cell_w - state.scroll_x
        local bx2 = x0 + left_w + (b)*CFG.cell_w - state.scroll_x

        -- clip to visible header area
        local clip_l = x0 + left_w
        local clip_r = x0 + left_w + body_w
        if bx2 > clip_l and bx < clip_r then
          local draw_l = math.max(bx, clip_l)
          local draw_r = math.min(bx2, clip_r)

          -- strip behind region controls + name
          r.ImGui_DrawList_AddRectFilled(dl, draw_l + 1, y_regions + 2, draw_r - 1, y_regions + CFG.region_name_h - 2, COL_HDRSTRIP, 4)

          local txt = BestTextU32(reg.seg_rgb[1], reg.seg_rgb[2], reg.seg_rgb[3])
          local rx = draw_l + 6
          local ry = y_regions + 4

          if state.tab == TAB_VOLS then
            PushButtonStyle(false)
            r.ImGui_SetCursorScreenPos(ctx, rx, ry)
            if r.ImGui_Button(ctx, ("-##rseg_%d"):format(a), CFG.rq_btn_w, CFG.rq_btn_h) then bump_region_seg_vol(a, -1); state.painting = true; latch_block_paint() end
            r.ImGui_SetCursorScreenPos(ctx, rx + (CFG.rq_btn_w + CFG.rq_pad), ry)
            if r.ImGui_Button(ctx, ("Q##rseg_%d"):format(a), CFG.rq_btn_w, CFG.rq_btn_h) then set_region_seg_vol(a); state.painting = true; latch_block_paint() end
            r.ImGui_SetCursorScreenPos(ctx, rx + (CFG.rq_btn_w + CFG.rq_pad)*2, ry)
            if r.ImGui_Button(ctx, ("+##rseg_%d"):format(a), CFG.rq_btn_w, CFG.rq_btn_h) then bump_region_seg_vol(a, 1); state.painting = true; latch_block_paint() end
            PopButtonStyle()

            local name_x = rx + (CFG.rq_btn_w + CFG.rq_pad)*3 + 8
            r.ImGui_DrawList_AddText(dl, name_x, y_regions + 6, txt, reg.seg_name)

          elseif state.tab == TAB_ONOFF then
            PushButtonStyle(false)
            r.ImGui_SetCursorScreenPos(ctx, rx, ry)
            if r.ImGui_Button(ctx, ("N##rsegon_%d"):format(a), CFG.rms_btn_w, CFG.rms_btn_h) then set_region_seg_onoff(a, 'N'); state.painting = true; latch_block_paint() end
            r.ImGui_SetCursorScreenPos(ctx, rx + (CFG.rms_btn_w + CFG.rms_pad), ry)
            if r.ImGui_Button(ctx, ("M##rsegon_%d"):format(a), CFG.rms_btn_w, CFG.rms_btn_h) then set_region_seg_onoff(a, 'M'); state.painting = true; latch_block_paint() end
            r.ImGui_SetCursorScreenPos(ctx, rx + (CFG.rms_btn_w + CFG.rms_pad)*2, ry)
            if r.ImGui_Button(ctx, ("S##rsegon_%d"):format(a), CFG.rms_btn_w, CFG.rms_btn_h) then set_region_seg_onoff(a, 'S'); state.painting = true; latch_block_paint() end
            PopButtonStyle()

            local name_x = rx + (CFG.rms_btn_w + CFG.rms_pad)*3 + 8
            r.ImGui_DrawList_AddText(dl, name_x, y_regions + 6, txt, reg.seg_name)
          elseif state.tab == TAB_ARP then
            PushButtonStyle(false)
            r.ImGui_SetCursorScreenPos(ctx, rx, ry)
            if r.ImGui_Button(ctx, ("Set##rseg_%d"):format(a), CFG.sc_btn_w, CFG.sc_btn_h) then set_region_seg_arp(a, true); state.painting = true; latch_block_paint() end
            r.ImGui_SetCursorScreenPos(ctx, rx + (CFG.sc_btn_w + CFG.sc_pad), ry)
            if r.ImGui_Button(ctx, ("Clr##rseg_%d"):format(a), CFG.sc_btn_w, CFG.sc_btn_h) then set_region_seg_arp(a, false); state.painting = true; latch_block_paint() end
            PopButtonStyle()

            local name_x = rx + (CFG.sc_btn_w + CFG.sc_pad)*2 + 8
            r.ImGui_DrawList_AddText(dl, name_x, y_regions + 6, txt, reg.seg_name)
          end
        end
      end
    end
  end

  -- =====================================================
  -- Header capture zones (this is what stops window-drag and enables drag-painting)
  -- =====================================================
  local mx, my = r.ImGui_GetMousePos(ctx)

  -- column header capture (covers full header area above body)
  r.ImGui_SetCursorScreenPos(ctx, x0 + left_w, y0)
  r.ImGui_InvisibleButton(ctx, "##cap_colhdr", body_w, header_h)
  local cap_col_active = r.ImGui_IsItemActive(ctx)

  -- row header capture (covers row headers beside body)
  r.ImGui_SetCursorScreenPos(ctx, x0, y0 + header_h)
  r.ImGui_InvisibleButton(ctx, "##cap_rowhdr", left_w, body_h)
  local cap_row_active = r.ImGui_IsItemActive(ctx)

  if (not state.block_paint) and r.ImGui_IsMouseDown(ctx, 0) then
    if cap_col_active then
      local bi = math.floor((mx - (x0 + left_w) + state.scroll_x) / CFG.cell_w) + 1
      if bi >= 1 and bi <= #state.bars then set_col_all(bi); state.painting = true end
    end
    if cap_row_active then
      local ti = math.floor((my - (y0 + header_h) + state.scroll_y) / CFG.cell_h) + 1
      if ti >= 1 and ti <= #state.tracks then set_row_all(state.tracks[ti].guid); state.painting = true end
    end
  end

  -- Apply automation on mouse release after any edit
  if state.painting and r.ImGui_IsMouseReleased(ctx, 0) then
    if state.tab == TAB_ONOFF then 
      apply_onoff_full(true) 
    elseif state.tab == TAB_VOLS then 
      apply_volume_full(true) 
    elseif state.tab == TAB_ARP then 
      apply_arp_full(true) 
    end
    state.painting = false
  end
end

-- =====================================================
-- Main loop
-- =====================================================
local function loop()
  r.ImGui_SetNextWindowPos(ctx, 50, 50, r.ImGui_Cond_FirstUseEver())
  r.ImGui_SetNextWindowSize(ctx, CFG.window_w, CFG.window_h, r.ImGui_Cond_FirstUseEver())

  if r.ImGui_Col_WindowBg then r.ImGui_PushStyleColor(ctx, r.ImGui_Col_WindowBg(), COL_WINBG) end

  local visible, open = r.ImGui_Begin(ctx, "QuickerMixer", true, 0)
  if visible then
    draw_tabs()
    draw_toolbar()
    draw_grid()
    r.ImGui_End(ctx)
  end

  if r.ImGui_Col_WindowBg then r.ImGui_PopStyleColor(ctx, 1) end

  if open then r.defer(loop) else r.ImGui_DestroyContext(ctx) end
end

-- Startup
rebuild_model()

-- Full-write on launch (no undo)
apply_onoff_full(false)
apply_volume_full(false)

r.defer(loop)
