-- @description Spiral Tempo Theory
-- @version 1.0.1
-- @author Rock Kennedy / ChatGPT (Thanks Chat, I would have had no idea how to draw a spiral!) 
-- @about
--   Visual tempo-node spiral inspired by the Airwindows Nodal Tempo Guide.
--   Click/drag the spiral to change the targeted tempo marker.
--   Shift locks the current spiral lane.
--   Alt snaps click/drag to the nearest node.
--   Press M to place/update a tempo marker.
-- @provides
--   [main] .

--[[
Spiral Tempo Theory - Airwindows Nodal Tempo Guide visualizer
Lua ReaScript for REAPER + ReaImGui

Formula:
  BPM(x) = 20 + pi*x + x^pi / 60

Node phases:
  x.00 = Serene / Flow      = North = bluegreen
  x.25 = Lively / Groove    = East  = yellow
  x.50 = Intense / Edgy     = South = red
  x.75 = Swagger / Attitude = West  = purple

Click anywhere in the spiral area to change the nearest previous tempo marker,
or the marker exactly at the edit/play position if one exists.
Drag while holding the left mouse button to accelerate/decelerate that same marker smoothly.
Click a tempo/word button on the left to jump the targeted tempo marker to that tempo.
Press M, or click Place Tempo Marker, to insert/update a tempo marker using the current spiral tempo.
]]--

local SCRIPT_NAME = "Spiral Tempo Theory"

if not reaper.ImGui_CreateContext then
  reaper.MB("This script requires ReaImGui. Install it from ReaPack first.", SCRIPT_NAME, 0)
  return
end

local ctx = reaper.ImGui_CreateContext(SCRIPT_NAME)
local PI = math.pi

-- Slightly larger UI font. If the user's ReaImGui build does not support font attachment,
-- the script still runs using the default font.
local FONT_SIZE = 16
local TITLE_FONT_SIZE = 24
local UI_FONT = nil
local TITLE_FONT = nil
if reaper.ImGui_CreateFont and reaper.ImGui_Attach then
  UI_FONT = reaper.ImGui_CreateFont("sans-serif", FONT_SIZE)
  TITLE_FONT = reaper.ImGui_CreateFont("sans-serif", TITLE_FONT_SIZE)
  reaper.ImGui_Attach(ctx, UI_FONT)
  reaper.ImGui_Attach(ctx, TITLE_FONT)
end

-- ------------------------------------------------------------
-- User tweak section
-- ------------------------------------------------------------

local DEFAULT_X_MIN = 9.0
local DEFAULT_X_MAX = 18.0
local VIEW_CYCLES = DEFAULT_X_MAX - DEFAULT_X_MIN

-- TWEAK THIS to make the spiral band thicker/thinner.
local SPIRAL_THICKNESS = 3.0

local DOT_RADIUS = 7.0
local NODE_HIGHLIGHT_RADIUS = 24.0
local NODE_GLOW_EPS = 0.006 -- how close current_x must be to a node before the dot takes on node color/glow
local LANE_SWITCH_THRESHOLD = 0.70 -- higher = harder to change spiral lanes while dragging
local MIN_CANVAS_H = 340

-- TWEAK THIS to change the width of the left button/list panel.
-- Example: 202 is 10% narrower than the previous 224.
local SIDE_PANEL_W = 202

-- TWEAK THIS to change the width of the tempo-node buttons.
local BUTTON_W = SIDE_PANEL_W * 0.85

-- TWEAK THIS to change the width of the three permanent action buttons.
-- 0.95 is about 12% wider than the earlier 0.85 setting.
local ACTION_BUTTON_W = SIDE_PANEL_W * 0.95

local GAP = 10

-- Muted equal-lightness-ish HSL palette.
-- Hue changes, saturation/lightness stay constant.
local HSL_SAT = 0.48
local HSL_LIGHT = 0.54

local NODE_PHASES = {
  { phase = 0.00, hue = 176 / 360, label = "Serene / Flow",      display = "Serene / Flow",    short = "Flow",    compass = "N" },
  { phase = 0.25, hue =  52 / 360, label = "Lively / Groove",    display = "Lively\nGroove",    short = "Groove",  compass = "E" },
  { phase = 0.50, hue =   0 / 360, label = "Intense / Edgy",     display = "Intense / Edgy",    short = "Edgy",    compass = "S" },
  { phase = 0.75, hue = 270 / 360, label = "Swagger / Attitude", display = "Swagger\nAttitude", short = "Swagger", compass = "W" },
}

-- Word-association labels from the reference image.
-- Keys are quarter-step indices: x * 4.
local WORDS = {
  [36] = "flow",         [37] = "groove",      [38] = "edgy",       [39] = "attitude",
  [40] = "stable",       [41] = "striving",    [42] = "unstable",   [43] = "attaining",
  [44] = "serenity",     [45] = "intensifies", [46] = "huge",       [47] = "excessive",
  [48] = "relaxed",      [49] = "testify",     [50] = "trample",    [51] = "swagger",
  [52] = "statement",    [53] = "groove",      [54] = "forceful",   [55] = "agitated",
  [56] = "confident",    [57] = "ebullient",   [58] = "cranked",    [59] = "levitating",
  [60] = "weightless",   [61] = "sparkling",   [62] = "haste",      [63] = "effortless",
  [64] = "dizzying",     [65] = "sillyfast",   [66] = "flailing",   [67] = "luminous",
  [68] = "transcendent", [69] = "above",       [70] = "beyond",     [71] = "Penultimate",
  [72] = "Ultimate",
}

local AIRWINDOWS_URL = "https://www.airwindows.com/airwindows-nodal-tempo-guide/"

-- ------------------------------------------------------------
-- Math helpers
-- ------------------------------------------------------------

local function clamp(v, lo, hi)
  if v < lo then return lo end
  if v > hi then return hi end
  return v
end

local function frac(v)
  return v - math.floor(v)
end

local function bpm_from_x(x)
  x = math.max(0, x)
  return 20 + PI * x + (x ^ PI) / 60
end

local function x_from_bpm(bpm)
  bpm = math.max(1, bpm or 120)

  local lo, hi = 0.0, 40.0
  while bpm_from_x(hi) < bpm do
    hi = hi * 1.5
    if hi > 1000 then break end
  end

  for _ = 1, 70 do
    local mid = (lo + hi) * 0.5
    if bpm_from_x(mid) < bpm then
      lo = mid
    else
      hi = mid
    end
  end

  return (lo + hi) * 0.5
end

local function title_case_word(s)
  return (tostring(s):gsub("(%a)([%w']*)", function(a, b)
    return string.upper(a) .. string.lower(b)
  end))
end

local function nearest_node_info(x)
  local phase = frac(x)
  local best_i, best_d = 1, 999

  for i = 1, #NODE_PHASES do
    local d = math.abs(phase - NODE_PHASES[i].phase)
    d = math.min(d, 1 - d)
    if d < best_d then
      best_i, best_d = i, d
    end
  end

  return NODE_PHASES[best_i].label, NODE_PHASES[best_i].short, best_d, best_i
end

local function word_for_x(x)
  local q = math.floor(x * 4 + 0.5)
  if WORDS[q] then return WORDS[q] end
  local _, short = nearest_node_info(x)
  return short
end

-- ------------------------------------------------------------
-- Color helpers
-- ------------------------------------------------------------

local function rgba(r, g, b, a)
  return reaper.ImGui_ColorConvertDouble4ToU32(r, g, b, a or 1)
end

local COL_BG       = rgba(0.075, 0.075, 0.080, 1.00)
local COL_PANEL    = rgba(0.140, 0.140, 0.150, 1.00)
local COL_GRID     = rgba(0.36,  0.36,  0.38,  0.25)
local COL_TEXT     = rgba(0.86,  0.86,  0.86,  1.00)
local COL_CORNER   = rgba(0.94,  0.94,  0.95,  0.95)
local COL_DIM      = rgba(0.72,  0.72,  0.74,  0.82)
local COL_DOT      = rgba(0.95,  0.95,  0.95,  1.00)
local COL_DOT_EDGE = rgba(0.02,  0.02,  0.02,  1.00)
local COL_PREVIEW  = rgba(0.68,  0.68,  0.70,  0.86)
local COL_LABEL_BG = rgba(0.00,  0.00,  0.00,  0.62)
local COL_BUTTON   = rgba(0.18,  0.18,  0.20,  1.00)
local COL_BUTTON_H = rgba(0.26,  0.26,  0.29,  1.00)
local COL_BUTTON_A = rgba(0.30,  0.30,  0.34,  1.00)
local COL_PLACE    = rgba(0.16,  0.24,  0.34,  1.00)
local COL_PLACE_H  = rgba(0.20,  0.31,  0.44,  1.00)

local function hsl_to_rgb(h, s, l)
  h = frac(h)

  if s <= 0 then return l, l, l end

  local function hue_to_rgb(p, q, t)
    t = frac(t)
    if t < 1/6 then return p + (q - p) * 6 * t end
    if t < 1/2 then return q end
    if t < 2/3 then return p + (q - p) * (2/3 - t) * 6 end
    return p
  end

  local q = l < 0.5 and (l * (1 + s)) or (l + s - l * s)
  local p = 2 * l - q

  return hue_to_rgb(p, q, h + 1/3), hue_to_rgb(p, q, h), hue_to_rgb(p, q, h - 1/3)
end

local function lerp_hue_shortest(a, b, t)
  local d = b - a
  if d > 0.5 then d = d - 1 end
  if d < -0.5 then d = d + 1 end
  return frac(a + d * t)
end

local function hue_for_phase(phase)
  phase = frac(phase)

  local n = #NODE_PHASES
  for i = 1, n do
    local a = NODE_PHASES[i]
    local b = NODE_PHASES[i + 1] or NODE_PHASES[1]
    local a_phase = a.phase
    local b_phase = b.phase
    if i == n then b_phase = 1.0 end

    if phase >= a_phase and phase <= b_phase then
      local t = (phase - a_phase) / (b_phase - a_phase)
      return lerp_hue_shortest(a.hue, b.hue, t)
    end
  end

  return NODE_PHASES[1].hue
end

local function color_for_x(x, alpha)
  local h = hue_for_phase(frac(x))
  local r, g, b = hsl_to_rgb(h, HSL_SAT, HSL_LIGHT)
  return rgba(r, g, b, alpha or 1)
end

-- ------------------------------------------------------------
-- Tempo marker helpers
-- ------------------------------------------------------------

local function is_playing_or_recording()
  local state = reaper.GetPlayState()
  return state == 1 or state == 4 or state == 5
end

local function marker_time_position()
  if is_playing_or_recording() then
    return reaper.GetPlayPosition()
  end
  return reaper.GetCursorPosition()
end

local function tempo_at_position(pos)
  if reaper.TimeMap_GetDividedBpmAtTime then
    local ok, bpm = pcall(reaper.TimeMap_GetDividedBpmAtTime, 0, pos)
    if ok and bpm and bpm > 0 then return bpm end
  end

  local bpm = reaper.Master_GetTempo()
  if not bpm or bpm <= 0 then bpm = 120 end
  return bpm
end

local function exact_tempo_marker_at(pos)
  local count = reaper.CountTempoTimeSigMarkers(0)
  local eps = 0.0000005

  for i = 0, count - 1 do
    local ok, timepos = reaper.GetTempoTimeSigMarker(0, i)
    if ok and math.abs(timepos - pos) <= eps then
      return i
    end
  end

  return -1
end

local function nearest_previous_tempo_marker(pos)
  local count = reaper.CountTempoTimeSigMarkers(0)
  local eps = 0.0000005
  local best_i = -1
  local best_t = -math.huge

  for i = 0, count - 1 do
    local ok, timepos = reaper.GetTempoTimeSigMarker(0, i)
    if ok then
      if math.abs(timepos - pos) <= eps then
        return i
      end
      if timepos <= pos + eps and timepos > best_t then
        best_t = timepos
        best_i = i
      end
    end
  end

  return best_i
end

local function set_tempo_marker_bpm(marker_idx, bpm)
  bpm = clamp(bpm, 1, 999)

  if marker_idx and marker_idx >= 0 then
    local ok, timepos, measurepos, beatpos, old_bpm, ts_num, ts_den, linear = reaper.GetTempoTimeSigMarker(0, marker_idx)
    if ok then
      reaper.SetTempoTimeSigMarker(0, marker_idx, timepos, measurepos, beatpos, bpm, ts_num, ts_den, linear)
      reaper.UpdateTimeline()
      return true
    end
  end

  -- Fallback: changes the project tempo without adding a tempo marker.
  reaper.SetCurrentBPM(0, bpm, false)
  reaper.UpdateTimeline()
  return false
end

local function target_marker_label(marker_idx)
  if marker_idx and marker_idx >= 0 then
    local ok, timepos = reaper.GetTempoTimeSigMarker(0, marker_idx)
    if ok then return string.format("marker at %.3fs", timepos) end
  end
  return "project tempo"
end

-- ------------------------------------------------------------
-- Spiral projection helpers
-- ------------------------------------------------------------

local function make_view_range(initial_x)
  -- The default view matches the published 65-ish through 221-ish region.
  if initial_x >= DEFAULT_X_MIN and initial_x <= DEFAULT_X_MAX then
    return DEFAULT_X_MIN, DEFAULT_X_MAX
  end

  local x_min = math.floor(initial_x - VIEW_CYCLES * 0.5)
  if x_min < 0 then x_min = 0 end
  local x_max = x_min + VIEW_CYCLES
  if initial_x > x_max then
    x_max = math.ceil(initial_x + 1)
    x_min = math.max(0, x_max - VIEW_CYCLES)
  end
  return x_min, x_max
end

local current_bpm = tempo_at_position(marker_time_position())
local current_x = x_from_bpm(current_bpm)
local view_x_min, view_x_max = make_view_range(current_x)
local dragging = false
local changed_while_dragging = false
local drag_marker_idx = -2
local status_msg = ""
local status_time = 0
local last_autoscroll_q = nil

local function radius_for_x(x, r_min, r_max)
  local t = (x - view_x_min) / (view_x_max - view_x_min)
  return r_min + t * (r_max - r_min)
end

local function angle_for_x(x)
  -- x.00 north, x.25 east, x.50 south, x.75 west
  return -PI * 0.5 + 2 * PI * frac(x)
end

local function point_for_x(x, cx, cy, r_min, r_max)
  local r = radius_for_x(x, r_min, r_max)
  local a = angle_for_x(x)
  return cx + math.cos(a) * r, cy + math.sin(a) * r
end

local function direct_x_from_mouse(mx, my, cx, cy, r_min, r_max)
  local dx, dy = mx - cx, my - cy
  local radius = math.sqrt(dx * dx + dy * dy)
  local angle = math.atan(dy, dx)

  -- Convert angle back into the 0..1 phase where 0 is north.
  local phase = frac((angle + PI * 0.5) / (2 * PI))

  -- Estimate which ring the mouse is closest to radially.
  local radial_t = (radius - r_min) / (r_max - r_min)
  local radial_x = view_x_min + radial_t * (view_x_max - view_x_min)

  -- Choose the nearest full cycle that has this angular phase.
  local cycle = math.floor(radial_x - phase + 0.5)
  local best_x = cycle + phase
  local best_d2 = math.huge

  -- Check neighboring cycles too, then keep the closest actual spiral point.
  for k = -2, 2 do
    local cand_x = clamp(cycle + k + phase, view_x_min, view_x_max)
    local px, py = point_for_x(cand_x, cx, cy, r_min, r_max)
    local ddx, ddy = mx - px, my - py
    local d2 = ddx * ddx + ddy * ddy
    if d2 < best_d2 then
      best_d2 = d2
      best_x = cand_x
    end
  end

  return clamp(best_x, view_x_min, view_x_max), phase, radial_x
end

local function snap_x_to_nearest_node(x)
  return clamp(math.floor(x * 4 + 0.5) / 4, view_x_min, view_x_max)
end

local function x_from_mouse_hysteresis(mx, my, cx, cy, r_min, r_max, reference_x, lock_lane)
  local direct_x, phase, radial_x = direct_x_from_mouse(mx, my, cx, cy, r_min, r_max)
  reference_x = reference_x or current_x

  -- Start from the lane nearest the current/previous dot position.
  local cycle = math.floor(reference_x - phase + 0.5)
  local lane_x = cycle + phase

  -- SHIFT lane lock: ignore radial lane switching completely.
  -- This still lets the dot move around the same spiral turn, including across north.
  if lock_lane then
    return clamp(lane_x, view_x_min, view_x_max), direct_x
  end

  -- Without SHIFT, keep the current spiral lane until the mouse has moved 70%
  -- of the way toward the neighboring lane. This makes accidental lane changes harder.
  while radial_x > lane_x + LANE_SWITCH_THRESHOLD do
    cycle = cycle + 1
    lane_x = cycle + phase
  end

  while radial_x < lane_x - LANE_SWITCH_THRESHOLD do
    cycle = cycle - 1
    lane_x = cycle + phase
  end

  return clamp(lane_x, view_x_min, view_x_max), direct_x
end

local function set_current_x(x, marker_idx_override, make_undo)
  current_x = clamp(x, view_x_min, view_x_max)
  current_bpm = bpm_from_x(current_x)

  local marker_idx = marker_idx_override
  if not marker_idx or marker_idx == -2 then
    marker_idx = nearest_previous_tempo_marker(marker_time_position())
  end

  set_tempo_marker_bpm(marker_idx, current_bpm)

  if make_undo then
    reaper.Undo_OnStateChangeEx("Set tempo from Spiral Tempo Theory", -1, -1)
  end
end

local function build_node_entries()
  local entries = {}
  local q_start = math.ceil(view_x_min * 4)
  local q_end = math.floor(view_x_max * 4)

  for q = q_start, q_end do
    local x = q / 4
    local bpm = bpm_from_x(x)
    entries[#entries + 1] = {
      q = q,
      x = x,
      bpm = bpm,
      word = WORDS[q] or "node",
    }
  end

  return entries
end

local function nearest_visible_node_key(mx, my, cx, cy, r_min, r_max, entries)
  local best_q = nil
  local best_d2 = NODE_HIGHLIGHT_RADIUS * NODE_HIGHLIGHT_RADIUS

  for _, entry in ipairs(entries) do
    local px, py = point_for_x(entry.x, cx, cy, r_min, r_max)
    local dx, dy = mx - px, my - py
    local d2 = dx * dx + dy * dy
    if d2 < best_d2 then
      best_d2 = d2
      best_q = entry.q
    end
  end

  return best_q
end

-- ------------------------------------------------------------
-- REAPER action helpers
-- ------------------------------------------------------------

local function place_tempo_marker()
  local pos = marker_time_position()
  local exact_idx = exact_tempo_marker_at(pos)

  reaper.Undo_BeginBlock()

  if exact_idx >= 0 then
    set_tempo_marker_bpm(exact_idx, current_bpm)
    status_msg = string.format("Updated tempo marker: %.3f BPM", current_bpm)
  else
    reaper.AddTempoTimeSigMarker(0, pos, current_bpm, 0, 0, false)
    reaper.UpdateTimeline()
    status_msg = string.format("Placed tempo marker: %.3f BPM", current_bpm)
  end

  reaper.Undo_EndBlock("Place tempo marker from Spiral Tempo Theory", -1)
  status_time = reaper.time_precise()
end

local function delete_target_tempo_marker()
  local pos = marker_time_position()
  local marker_idx = nearest_previous_tempo_marker(pos)

  if marker_idx < 0 then
    status_msg = "No tempo marker found at or before this position"
    status_time = reaper.time_precise()
    return
  end

  reaper.Undo_BeginBlock()
  reaper.DeleteTempoTimeSigMarker(0, marker_idx)
  reaper.UpdateTimeline()
  reaper.Undo_EndBlock("Delete tempo marker from Spiral Tempo Theory", -1)

  current_bpm = tempo_at_position(pos)
  current_x = x_from_bpm(current_bpm)
  status_msg = "Deleted tempo marker"
  status_time = reaper.time_precise()
end

local function delete_all_tempo_markers()
  local count = reaper.CountTempoTimeSigMarkers(0)
  if count <= 0 then
    status_msg = "No tempo markers to delete"
    status_time = reaper.time_precise()
    return
  end

  reaper.Undo_BeginBlock()
  for i = count - 1, 0, -1 do
    reaper.DeleteTempoTimeSigMarker(0, i)
  end
  reaper.UpdateTimeline()
  reaper.Undo_EndBlock("Delete all tempo markers from Spiral Tempo Theory", -1)

  current_bpm = tempo_at_position(marker_time_position())
  current_x = x_from_bpm(current_bpm)
  status_msg = "Deleted all tempo markers"
  status_time = reaper.time_precise()
end

local function is_key_pressed(key)
  if not key then return false end

  local ok, pressed = pcall(reaper.ImGui_IsKeyPressed, ctx, key, false)
  if ok then return pressed end

  ok, pressed = pcall(reaper.ImGui_IsKeyPressed, ctx, key)
  return ok and pressed
end

local KEY_M = reaper.ImGui_Key_M and reaper.ImGui_Key_M()

-- ------------------------------------------------------------
-- URL / Help helpers
-- ------------------------------------------------------------

local function open_url(url)
  if reaper.CF_ShellExecute then
    reaper.CF_ShellExecute(url)
    return
  end

  local os_name = reaper.GetOS and reaper.GetOS() or ""
  if os_name:match("Win") then
    os.execute('start "" "' .. url .. '"')
  elseif os_name:match("OSX") or os_name:match("macOS") then
    os.execute('open "' .. url .. '"')
  else
    os.execute('xdg-open "' .. url .. '"')
  end
end

local function draw_help_popup()
  -- Prevent the modal from opening as a very narrow/tall wrapped window.
  reaper.ImGui_SetNextWindowSize(ctx, 740, 440, reaper.ImGui_Cond_Appearing())

  local popup_open = true
  if reaper.ImGui_BeginPopupModal(ctx, "Spiral Tempo Theory Help", popup_open) then
    reaper.ImGui_TextWrapped(ctx, "")
    reaper.ImGui_Dummy(ctx, 30, 20)
    reaper.ImGui_SameLine(ctx)
    reaper.ImGui_TextWrapped(ctx, "TARGET is the nearest previous tempo marker.")
    reaper.ImGui_TextWrapped(ctx, "")
    reaper.ImGui_Dummy(ctx, 30, 20)
    reaper.ImGui_SameLine(ctx)
    reaper.ImGui_TextWrapped(ctx, "CLICK or DRAG on the spiral to change the BPM at the targeted tempo marker.")
    reaper.ImGui_TextWrapped(ctx, "")
    reaper.ImGui_Dummy(ctx, 30, 20)
    reaper.ImGui_SameLine(ctx)
    reaper.ImGui_TextWrapped(ctx, "SHIFT - Locks the dot to current spiral lane while dragging.")
    reaper.ImGui_TextWrapped(ctx, "")
    reaper.ImGui_Dummy(ctx, 30, 20)
    reaper.ImGui_SameLine(ctx)
    reaper.ImGui_TextWrapped(ctx, "ALT - Snaps click/drag movement to the nearest tempo node.")
    reaper.ImGui_TextWrapped(ctx, "")
    reaper.ImGui_Dummy(ctx, 30, 20)
    reaper.ImGui_SameLine(ctx)
    reaper.ImGui_TextWrapped(ctx, "M - Places or updates a tempo marker at the edit cursor, or play position while in playback.")
    reaper.ImGui_TextWrapped(ctx, "")
    reaper.ImGui_Dummy(ctx, 30, 20)
    reaper.ImGui_SameLine(ctx)
    reaper.ImGui_TextWrapped(ctx, "TEMPO BUTTONS - jump to the node and set the targeted tempo marker.")
    reaper.ImGui_TextWrapped(ctx, "")
    reaper.ImGui_Dummy(ctx, 30, 20)
    reaper.ImGui_SameLine(ctx)
    reaper.ImGui_Dummy(ctx, 280, 20)
    reaper.ImGui_SameLine(ctx)
    if reaper.ImGui_Button(ctx, "OK", 90, 0) then
      reaper.ImGui_CloseCurrentPopup(ctx)
    end

    reaper.ImGui_EndPopup(ctx)
  end
end

-- ------------------------------------------------------------
-- ImGui drawing helpers
-- ------------------------------------------------------------

local function add_text_center(draw_list, ctx, text, x, y, col)
  local tw, th = reaper.ImGui_CalcTextSize(ctx, text)
  reaper.ImGui_DrawList_AddText(draw_list, x - tw * 0.5, y - th * 0.5, col, text)
end

local function add_text_right(draw_list, ctx, text, right_x, y, col)
  local tw, th = reaper.ImGui_CalcTextSize(ctx, text)
  reaper.ImGui_DrawList_AddText(draw_list, right_x - tw, y - th * 0.5, col, text)
end

local function add_text_center_multiline(draw_list, ctx, text, x, y, col)
  local lines = {}
  for line in tostring(text):gmatch("[^\n]+") do
    lines[#lines + 1] = line
  end

  local line_h = reaper.ImGui_GetTextLineHeight(ctx)
  local total_h = #lines * line_h
  local yy = y - total_h * 0.5 + line_h * 0.5

  for _, line in ipairs(lines) do
    add_text_center(draw_list, ctx, line, x, yy, col)
    yy = yy + line_h
  end
end

local function draw_label_box_center(draw_list, ctx, text, x, y, text_col)
  local tw, th = reaper.ImGui_CalcTextSize(ctx, text)
  local pad_x, pad_y = 7, 4
  reaper.ImGui_DrawList_AddRectFilled(draw_list, x - tw * 0.5 - pad_x, y - th * 0.5 - pad_y,
                                      x + tw * 0.5 + pad_x, y + th * 0.5 + pad_y,
                                      COL_LABEL_BG, 5)
  add_text_center(draw_list, ctx, text, x, y, text_col)
end

local function draw_glow_dot(draw_list, x, y, col, core_col)
  reaper.ImGui_DrawList_AddCircleFilled(draw_list, x, y, 17, col, 32)
  reaper.ImGui_DrawList_AddCircleFilled(draw_list, x, y, 10, col, 32)
  reaper.ImGui_DrawList_AddCircleFilled(draw_list, x, y, 5, core_col or COL_DOT, 24)
end

local function draw_spiral(draw_list, cx, cy, r_min, r_max)
  local steps = math.max(360, math.floor((view_x_max - view_x_min) * 72))

  local prev_x = view_x_min
  local prev_px, prev_py = point_for_x(prev_x, cx, cy, r_min, r_max)

  for i = 1, steps do
    local t = i / steps
    local x = view_x_min + (view_x_max - view_x_min) * t
    local px, py = point_for_x(x, cx, cy, r_min, r_max)
    local col = color_for_x((prev_x + x) * 0.5, 1.0)
    reaper.ImGui_DrawList_AddLine(draw_list, prev_px, prev_py, px, py, col, SPIRAL_THICKNESS)
    prev_x, prev_px, prev_py = x, px, py
  end
end

local function draw_node_markers(draw_list, ctx, cx, cy, r_min, r_max, entries, highlight_q, button_hover_q)
  for _, entry in ipairs(entries) do
    local px, py = point_for_x(entry.x, cx, cy, r_min, r_max)
    local col = color_for_x(entry.x, 1.0)
    local rad = entry.q == highlight_q and 6.0 or 3.2
    reaper.ImGui_DrawList_AddCircleFilled(draw_list, px, py, rad, col, 18)
    if entry.q == highlight_q then
      reaper.ImGui_DrawList_AddCircle(draw_list, px, py, rad + 4, COL_DOT, 18, 1.5)
    end
    if entry.q == button_hover_q then
      draw_glow_dot(draw_list, px, py, color_for_x(entry.x, 0.24), COL_DOT)
    end
  end

  -- Compass labels
  local label_r = r_max + 25
  local labels = {
    { NODE_PHASES[1].display, cx,           cy - label_r },
    { NODE_PHASES[2].display, cx + label_r, cy           },
    { NODE_PHASES[3].display, cx,           cy + label_r },
    { NODE_PHASES[4].display, cx - label_r, cy           },
  }

  for _, item in ipairs(labels) do
    add_text_center_multiline(draw_list, ctx, item[1], item[2], item[3], COL_TEXT)
  end
end

local function draw_compass(draw_list, cx, cy, r_max)
  reaper.ImGui_DrawList_AddLine(draw_list, cx, cy - r_max, cx, cy + r_max, COL_GRID, 1)
  reaper.ImGui_DrawList_AddLine(draw_list, cx - r_max, cy, cx + r_max, cy, COL_GRID, 1)
  reaper.ImGui_DrawList_AddCircle(draw_list, cx, cy, r_max, COL_GRID, 96, 1)
end

local function draw_current_dot(draw_list, ctx, cx, cy, r_min, r_max)
  local px, py = point_for_x(current_x, cx, cy, r_min, r_max)
  local vibe_label = nearest_node_info(current_x)
  local word = word_for_x(current_x)

  local nearest_node_x = math.floor(current_x * 4 + 0.5) / 4
  local on_node = math.abs(current_x - nearest_node_x) <= NODE_GLOW_EPS
  local node_col = color_for_x(nearest_node_x, 1.0)

  if on_node then
    draw_glow_dot(draw_list, px, py, color_for_x(nearest_node_x, 0.28), node_col)
    reaper.ImGui_DrawList_AddCircleFilled(draw_list, px, py, DOT_RADIUS + 2, COL_DOT_EDGE, 24)
    reaper.ImGui_DrawList_AddCircleFilled(draw_list, px, py, DOT_RADIUS, node_col, 24)
    reaper.ImGui_DrawList_AddCircle(draw_list, px, py, DOT_RADIUS + 4, COL_DOT, 24, 2)
  else
    reaper.ImGui_DrawList_AddCircleFilled(draw_list, px, py, DOT_RADIUS + 2, COL_DOT_EDGE, 24)
    reaper.ImGui_DrawList_AddCircleFilled(draw_list, px, py, DOT_RADIUS, COL_DOT, 24)
    reaper.ImGui_DrawList_AddCircle(draw_list, px, py, DOT_RADIUS + 4, color_for_x(current_x, 1), 24, 2)
  end

  local readout = string.format("%.3f BPM  |  %s  |  %s", current_bpm, title_case_word(word), vibe_label)

  -- Around the next north node above the original chart, the dot is close enough to
  -- the Serene / Flow label that the readout is cleaner below the dot.
  local readout_y = current_bpm >= 221 and (py + 26) or (py - 24)
  draw_label_box_center(draw_list, ctx, readout, cx, readout_y, COL_TEXT)
end

local function draw_preview_dot(draw_list, x_value, cx, cy, r_min, r_max)
  local px, py = point_for_x(x_value, cx, cy, r_min, r_max)
  reaper.ImGui_DrawList_AddCircleFilled(draw_list, px, py, 5, COL_PREVIEW, 20)
  reaper.ImGui_DrawList_AddCircle(draw_list, px, py, 8, COL_PREVIEW, 20, 1.3)
end

local function push_button_text_align_left()
  if reaper.ImGui_StyleVar_ButtonTextAlign then
    local ok = pcall(reaper.ImGui_PushStyleVar, ctx, reaper.ImGui_StyleVar_ButtonTextAlign(), 0.0, 0.5)
    if ok then return true end
  end
  return false
end

local function draw_action_button(label, kind)
  if kind == "delete" then
    local red = color_for_x(14.5, 0.92)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), red)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), color_for_x(14.5, 1.00))
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(), color_for_x(14.5, 1.00))
  elseif kind == "place" then
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), COL_PLACE)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), COL_PLACE_H)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(), COL_PLACE_H)
  end

  local pushed_align = push_button_text_align_left()
  local clicked = reaper.ImGui_Button(ctx, label, ACTION_BUTTON_W, 0)
  if pushed_align then reaper.ImGui_PopStyleVar(ctx) end

  if kind == "delete" or kind == "place" then reaper.ImGui_PopStyleColor(ctx, 3) end
  return clicked
end

local function draw_side_panel(entries, spiral_highlight_q, canvas_h)
  local hovered_button_q = nil
  if not spiral_highlight_q then
    last_autoscroll_q = nil
  end

  -- These action buttons stay outside the scrollable node list so they are always visible.
  if draw_action_button("Place Tempo Marker  (M)", "place") then
    place_tempo_marker()
  end

  if draw_action_button("Delete Tempo Marker", "delete") then
    delete_target_tempo_marker()
  end

  if draw_action_button("Delete All Tempo Markers", "delete") then
    delete_all_tempo_markers()
  end

  reaper.ImGui_Text(ctx, "Tempo Nodes")
  reaper.ImGui_TextColored(ctx, COL_DIM, "Buttons change targeted mark")

  if status_msg ~= "" and reaper.time_precise() - status_time < 2.4 then
    reaper.ImGui_TextColored(ctx, COL_DIM, status_msg)
  else
    local target_idx = nearest_previous_tempo_marker(marker_time_position())
    reaper.ImGui_TextColored(ctx, COL_DIM, "Target: " .. target_marker_label(target_idx))
  end

  reaper.ImGui_Separator(ctx)

  local remaining_w, remaining_h = reaper.ImGui_GetContentRegionAvail(ctx)
  local child_h = math.max(80, remaining_h)

  local child_flags = reaper.ImGui_ChildFlags_Border and reaper.ImGui_ChildFlags_Border() or 0
  reaper.ImGui_BeginChild(ctx, "##tempo_node_list", SIDE_PANEL_W, child_h, child_flags)

  local draw_list = reaper.ImGui_GetWindowDrawList(ctx)

  for _, entry in ipairs(entries) do
    local highlighted = entry.q == spiral_highlight_q
    local selected = math.abs(entry.x - current_x) < 0.02

    if highlighted or selected then
      local node_col = color_for_x(entry.x, highlighted and 0.95 or 0.65)
      reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), node_col)
      reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), node_col)
      reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(), node_col)
    else
      reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), COL_BUTTON)
      reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), COL_BUTTON_H)
      reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(), COL_BUTTON_A)
    end

    local pushed_align = push_button_text_align_left()
    local label = string.format("%3.0f  %s", entry.bpm, title_case_word(entry.word))
    if reaper.ImGui_Button(ctx, label, BUTTON_W, 0) then
      set_current_x(entry.x, -2, true)
    end
    if pushed_align then reaper.ImGui_PopStyleVar(ctx) end

    if reaper.ImGui_IsItemHovered(ctx) then
      hovered_button_q = entry.q
    end

    local ix1, iy1 = reaper.ImGui_GetItemRectMin(ctx)
    local ix2, iy2 = reaper.ImGui_GetItemRectMax(ctx)
    reaper.ImGui_DrawList_AddRectFilled(draw_list, ix2 - 8, iy1 + 3, ix2 - 3, iy2 - 3, color_for_x(entry.x, 1), 2)

    -- When hovering a node on the spiral, bring its matching button into view.
    -- TWEAK: change 0.50 to 0.0 for top, 1.0 for bottom, or leave 0.50 to center it.
    if entry.q == spiral_highlight_q and last_autoscroll_q ~= entry.q and reaper.ImGui_SetScrollHereY then
      reaper.ImGui_SetScrollHereY(ctx, 0.50)
      last_autoscroll_q = entry.q
    end

    reaper.ImGui_PopStyleColor(ctx, 3)
  end

  reaper.ImGui_EndChild(ctx)
  return hovered_button_q
end

-- ------------------------------------------------------------
-- Main loop
-- ------------------------------------------------------------

local function loop()
  reaper.ImGui_SetNextWindowSize(ctx, 820, 720, reaper.ImGui_Cond_FirstUseEver())

  local visible, open = reaper.ImGui_Begin(ctx, SCRIPT_NAME, true)

  if visible then
    local font_pushed = false
    if UI_FONT and reaper.ImGui_PushFont then
      reaper.ImGui_PushFont(ctx, UI_FONT, FONT_SIZE)
      font_pushed = true
    end

    if is_key_pressed(KEY_M) then
      place_tempo_marker()
    end

    if TITLE_FONT and reaper.ImGui_PushFont then
      reaper.ImGui_PushFont(ctx, TITLE_FONT, TITLE_FONT_SIZE)
      reaper.ImGui_Text(ctx, "Spiral Tempo Theory")
      reaper.ImGui_PopFont(ctx)
    else
      reaper.ImGui_Text(ctx, "Spiral Tempo Theory")
    end

    reaper.ImGui_SameLine(ctx)
    local help_w = 70
    local content_w = reaper.ImGui_GetContentRegionAvail(ctx)
    reaper.ImGui_SetCursorPosX(ctx, reaper.ImGui_GetCursorPosX(ctx) + content_w - help_w)
    if reaper.ImGui_Button(ctx, "Help", help_w, 0) then
      reaper.ImGui_OpenPopup(ctx, "Spiral Tempo Theory Help")
    end
    draw_help_popup()

    reaper.ImGui_TextColored(ctx, COL_DIM, "Based on the work of Chris Johnson of Airwindows and Bo Danerius:")
    reaper.ImGui_TextColored(ctx, COL_CORNER, AIRWINDOWS_URL)
    if reaper.ImGui_IsItemHovered(ctx) then
      reaper.ImGui_SetMouseCursor(ctx, reaper.ImGui_MouseCursor_Hand())
    end
    if reaper.ImGui_IsItemClicked(ctx) then
      open_url(AIRWINDOWS_URL)
    end

    local tempo_text = string.format("Current Tempo: %.3f BPM", current_bpm)
    local tempo_w = reaper.ImGui_CalcTextSize(ctx, tempo_text)
    reaper.ImGui_SameLine(ctx)
    local avail_after_url = reaper.ImGui_GetContentRegionAvail(ctx)
    reaper.ImGui_SetCursorPosX(ctx, reaper.ImGui_GetCursorPosX(ctx) + math.max(0, avail_after_url - tempo_w))
    reaper.ImGui_TextColored(ctx, COL_CORNER, tempo_text)

    reaper.ImGui_Separator(ctx)

    local draw_list = reaper.ImGui_GetWindowDrawList(ctx)
    local base_x, base_y = reaper.ImGui_GetCursorScreenPos(ctx)
    local avail_w, avail_h = reaper.ImGui_GetContentRegionAvail(ctx)
    local mx, my = reaper.ImGui_GetMousePos(ctx)
    local shift_down = reaper.ImGui_IsKeyDown(ctx, reaper.ImGui_Key_LeftShift()) or reaper.ImGui_IsKeyDown(ctx, reaper.ImGui_Key_RightShift())
    local alt_down = reaper.ImGui_IsKeyDown(ctx, reaper.ImGui_Key_LeftAlt()) or reaper.ImGui_IsKeyDown(ctx, reaper.ImGui_Key_RightAlt())

    local usable_side_w = SIDE_PANEL_W
    if avail_w < 620 then usable_side_w = math.max(178, avail_w * 0.32) end

    local canvas_w = math.max(330, avail_w - usable_side_w - GAP)
    local canvas_h = math.max(MIN_CANVAS_H, avail_h - 8)
    local canvas_x = base_x + usable_side_w + GAP
    local canvas_y = base_y

    local pad = 62
    local cx = canvas_x + canvas_w * 0.5
    local cy = canvas_y + canvas_h * 0.5
    local r_max = math.max(80, math.min(canvas_w, canvas_h) * 0.5 - pad)
    local r_min = math.max(18, r_max * 0.085)
    local entries = build_node_entries()

    local spiral_hovered_by_rect = mx >= canvas_x and mx <= canvas_x + canvas_w and my >= canvas_y and my <= canvas_y + canvas_h
    local spiral_hover_q = spiral_hovered_by_rect and nearest_visible_node_key(mx, my, cx, cy, r_min, r_max, entries) or nil

    -- Left-side buttons first, so button hover can glow on the spiral drawn after it.
    reaper.ImGui_SetCursorScreenPos(ctx, base_x, base_y)
    local button_hover_q = draw_side_panel(entries, spiral_hover_q, canvas_h)
    local highlight_q = button_hover_q or spiral_hover_q

    -- Spiral canvas on the right.
    reaper.ImGui_SetCursorScreenPos(ctx, canvas_x, canvas_y)
    reaper.ImGui_InvisibleButton(ctx, "##tempo_spiral_canvas", canvas_w, canvas_h)

    local hovered = reaper.ImGui_IsItemHovered(ctx)
    local active = reaper.ImGui_IsItemActive(ctx)

    reaper.ImGui_DrawList_AddRectFilled(draw_list, canvas_x, canvas_y, canvas_x + canvas_w, canvas_y + canvas_h, COL_BG, 8)
    reaper.ImGui_DrawList_AddRect(draw_list, canvas_x, canvas_y, canvas_x + canvas_w, canvas_y + canvas_h, COL_PANEL, 8, nil, 1)

    draw_compass(draw_list, cx, cy, r_max)
    draw_spiral(draw_list, cx, cy, r_min, r_max)
    draw_node_markers(draw_list, ctx, cx, cy, r_min, r_max, entries, highlight_q, button_hover_q)

    local preview_x = nil
    if hovered then
      preview_x = x_from_mouse_hysteresis(mx, my, cx, cy, r_min, r_max, current_x, shift_down)
      if alt_down then preview_x = snap_x_to_nearest_node(preview_x) end
      draw_preview_dot(draw_list, preview_x, cx, cy, r_min, r_max)
    end

    draw_current_dot(draw_list, ctx, cx, cy, r_min, r_max)

    local left_down = reaper.ImGui_IsMouseDown(ctx, 0)
    local left_clicked = reaper.ImGui_IsMouseClicked(ctx, 0)
    local left_released = reaper.ImGui_IsMouseReleased(ctx, 0)

    if hovered and left_clicked then
      dragging = true
      changed_while_dragging = true
      drag_marker_idx = nearest_previous_tempo_marker(marker_time_position())
      local click_x = direct_x_from_mouse(mx, my, cx, cy, r_min, r_max)
      if alt_down then click_x = snap_x_to_nearest_node(click_x) end
      set_current_x(click_x, drag_marker_idx, false)
    end

    if dragging and left_down and active then
      local drag_x = x_from_mouse_hysteresis(mx, my, cx, cy, r_min, r_max, current_x, shift_down)
      if alt_down then drag_x = snap_x_to_nearest_node(drag_x) end
      set_current_x(drag_x, drag_marker_idx, false)
      changed_while_dragging = true
    end

    if dragging and left_released then
      dragging = false
      if changed_while_dragging then
        reaper.Undo_OnStateChangeEx("Set tempo marker from Spiral Tempo Theory", -1, -1)
      end
      changed_while_dragging = false
      drag_marker_idx = -2
    end

    -- Brighter corner readouts, on the right side.
    local min_bpm = bpm_from_x(view_x_min)
    local max_bpm = bpm_from_x(view_x_max)
    add_text_right(draw_list, ctx, string.format("Visible range: %.1f to %.1f BPM", min_bpm, max_bpm), canvas_x + canvas_w - 12, canvas_y + 22, COL_CORNER)

    if hovered and preview_x then
      local hover_bpm = bpm_from_x(preview_x)
      local hover_label = nearest_node_info(preview_x)
      local preview = string.format("%.3f BPM  |  %s  |  %s", hover_bpm, title_case_word(word_for_x(preview_x)), hover_label)
      add_text_right(draw_list, ctx, preview, canvas_x + canvas_w - 12, canvas_y + canvas_h - 20, COL_CORNER)
    else
      local target_idx = nearest_previous_tempo_marker(marker_time_position())
      add_text_right(draw_list, ctx, "Target: " .. target_marker_label(target_idx), canvas_x + canvas_w - 12, canvas_y + canvas_h - 20, COL_CORNER)
    end

    -- Restore cursor to the bottom of the two-column region so resizing/layout remains sane.
    -- ReaImGui requires a real item after SetCursorScreenPos() when it extends the window bounds.
    reaper.ImGui_SetCursorScreenPos(ctx, base_x, base_y + canvas_h + 4)
    reaper.ImGui_Dummy(ctx, 1, 1)

    if font_pushed then
      reaper.ImGui_PopFont(ctx)
    end

    reaper.ImGui_End(ctx)
  end

  if open then
    reaper.defer(loop)
  else
    -- Some ReaImGui versions do not expose DestroyContext to Lua.
    -- Letting the script end is enough for cleanup in those builds.
    if reaper.ImGui_DestroyContext then
      reaper.ImGui_DestroyContext(ctx)
    end
  end
end

reaper.defer(loop)
