-- @description N2N Topline
-- @version 5.4-dev.5
-- @author Rock Kennedy and Gemini 4 Hydrogen (which did an absolutely fabulous job of transforming the vision into solid Lua code)
-- @about
--   Numbers2Notes Topline Melody Editor (1200x640 minimum):
--   - Cross-platform Windows & macOS dark frameless window move/resize + minimum size enforcement
--   - Proportional multi-note tail resizing with temporary floor
--   - 3-Layer NNS diatonic/chromatic roll + gmem Harmony, Groove (5000000..5000031), 8th Swing (gmem[2])
--   - 4-Node MPE ([Green, Black, White, Red] chains), true-lane snap + Alt chromatic, Vibrato patterns (<, >, <>)
--   - Section-owned hidden clips, Commit / Recommit* with lossless Track Reload & Export Topline (.mid)

--------------------------------------------------------------------------------
-- 1. UTILITIES & SERIALIZATION
--------------------------------------------------------------------------------
local OS_STR = reaper.GetOS()
local IS_MAC = (OS_STR:match("OSX") ~= nil) or (OS_STR:match("macOS") ~= nil)

local function clamp(v, lo, hi) return (v < lo) and lo or ((v > hi) and hi or v) end
local function lerp(a, b, t) return a + (b - a) * t end
local function is_finite(x) return type(x) == "number" and x == x and math.abs(x) < 1e9 end
local function trim(s) return (s or ""):match("^%s*(.-)%s*$") end
local function round_guide_start_to_32nd(qn) return (qn <= 0.001) and 0.0 or (math.floor((qn + 0.03125) / 0.125 + 0.5) * 0.125) end
local function hex_to_rgb(h) h=h:gsub("#",""); return {tonumber(h:sub(1,2),16)/255, tonumber(h:sub(3,4),16)/255, tonumber(h:sub(5,6),16)/255} end
local function mix_rgb(c1, c2, t) return { lerp(c1[1], c2[1], t), lerp(c1[2], c2[2], t), lerp(c1[3], c2[3], t) } end
local function contrast_text_col(rgb) return ((0.299*rgb[1]+0.587*rgb[2]+0.114*rgb[3]) > 0.58) and {0.08,0.09,0.12} or {0.98,0.98,0.99} end
local function pack_color(r, g, b) return math.floor(r*255) + math.floor(g*255)*256 + math.floor(b*255)*65536 end

local function serialize_val(v)
  local tv = type(v)
  if tv == "number" then return (v ~= v) and "0" or string.format("%.6g", v)
  elseif tv == "boolean" then return v and "true" or "false"
  elseif tv == "string" then return string.format("%q", v)
  elseif tv == "table" then
    local parts, is_arr = { "{" }, (#v > 0)
    if is_arr then for i = 1, #v do parts[#parts+1] = serialize_val(v[i]) .. "," end end
    for k, val in pairs(v) do
      if not (is_arr and type(k) == "number" and k >= 1 and k <= #v and k % 1 == 0) then
        local ks = (type(k) == "string" and k:match("^[%a_][%w_]*$")) and (k.."=") or (type(k)=="number" and ("["..k.."]=") or ("["..string.format("%q",tostring(k)).."]="))
        parts[#parts+1] = ks .. serialize_val(val) .. ","
      end
    end
    parts[#parts+1] = "}"; return table.concat(parts)
  end
  return "nil"
end

local function deserialize_table(str)
  if not str or str == "" then return nil end
  local fn = load("return " .. str, "n2n_state", "t", {}); if not fn then return nil end
  local ok, res = pcall(fn); return (ok and type(res) == "table") and res or nil
end

--------------------------------------------------------------------------------
-- 2. CONFIGURATION
--------------------------------------------------------------------------------
local WIN_TITLE           = "N2N Topline"
local MIN_WIN_W, MIN_WIN_H = 1400, 640
local GMEM_NAMESPACE      = "N2N_Ecosystem_RSKennedy"
local GMEM_CHORD_BASE     = 3000000
local GMEM_SCALE_BASE     = 3100000
local GMEM_GROOVE_BASE    = 5000000
local HIDDEN_TRACK_NAME   = "__N2N_Topline_Hidden"
local LEGACY_HIDDEN_NAME  = "__N2N_Melody_Engine_Hidden"
local DEFAULT_OUT_TRACK   = "N2N Topline"
local EXT_GLOBAL_SEC      = "N2N_MIDI_EDITOR_PREFS"
local EXT_PROJ_SEC        = "N2N_MIDI_EDITOR_PROJ"
local EXT_PROJ_KEY        = "STATE_V4"
-- Transient launch/navigation mailbox, separate from saved draft data.
local HUB_EXT_SEC = "N2N_TOPLINE_HUB"
local owner_project = reaper.EnumProjects(-1,"")
local owner_project_key = tostring(owner_project)
local hub_token = owner_project_key.."\t"..tostring(reaper.time_precise())
local hub_exited = false
local MOD_CHOICES         = { "None", "Shift", "Ctrl", "Alt", "Ctrl+Shift" }

local CONFIG = {
  step_definitions = {
    [0]={nns="1",diatonic=true,hex="#FF0000"},  [1]={nns="b2",diatonic=false,hex="#842500"},
    [2]={nns="2",diatonic=true,hex="#FFA400"},  [3]={nns="b3",diatonic=false,hex="#945900"},
    [4]={nns="3",diatonic=true,hex="#FFE400"},  [5]={nns="4",diatonic=true,hex="#00FF00"},
    [6]={nns="b5",diatonic=false,hex="#00626D"}, [7]={nns="5",diatonic=true,hex="#6491FF"},
    [8]={nns="b6",diatonic=false,hex="#5514B5"}, [9]={nns="6",diatonic=true,hex="#B80AFF"},
    [10]={nns="b7",diatonic=false,hex="#80006D"},[11]={nns="7",diatonic=true,hex="#FF00D0"},
  },
  modes = {
    {name="Major (Ionian)",center_step=0,nns_center="1"}, {name="Dorian",center_step=2,nns_center="2"},
    {name="Phrygian",center_step=4,nns_center="3"},       {name="Lydian",center_step=5,nns_center="4"},
    {name="Mixolydian",center_step=7,nns_center="5"},     {name="Minor (Aeolian)",center_step=9,nns_center="6"},
    {name="Locrian",center_step=11,nns_center="7"},
  },
  curve_shapes = {
    {id="s_curve",label="S-Curve"}, {id="inv_s",label="Inv S"}, {id="ease_in",label="Ease-In"},
    {id="ease_out",label="Ease-Out"}, {id="linear",label="Linear"},
  },
  vib_patterns = {
    {id="consistent",btn="Pat:Const",menu="Consistent"}, {id="cresc",btn="Pat: <",menu="Fade In (<)"},
    {id="decresc",btn="Pat: >",menu="Fade Out (>)"},     {id="swell",btn="Pat: <>",menu="Swell (<>)"},
  },
  note_names = { "C","C#","D","Eb","E","F","F#","G","Ab","A","Bb","B" },
  dark_mode = true,
  bend_ranges = { 2, 12, 24, 48 },
  grid_options = { {label="1",qn=4.0},{label="1/2",qn=2.0},{label="1/4",qn=1.0},{label="1/8",qn=0.5},{label="1/16",qn=0.25},{label="1/32",qn=0.125} },
  harmony_sources = {
    {id="gmem",label="N2N Preference (All Octaves)"}, {id="clip_pulled",label="Pulled Clip (All Octaves)"},
    {id="diatonic",label="Parent Major Diatonic"},    {id="triad_1",label="Tonic Triad (1-3-5)"}, {id="manual",label="Manual Paint Only"},
  },
}

local STEP_COLORS = {}
for s = 0, 11 do STEP_COLORS[s] = { active = hex_to_rgb(CONFIG.step_definitions[s].hex) } end

local function get_step_colors(rel_step)
  local active, is_dia = STEP_COLORS[rel_step].active, CONFIG.step_definitions[rel_step].diatonic
  if CONFIG.dark_mode then
    local base = { 0.11, 0.12, 0.15 }
    return { active=active, bg=mix_rgb(base,active,0.14), harmony=mix_rgb(base,active,0.34),
      harmony_dash=is_dia and mix_rgb(base,active,0.80) or mix_rgb(active,{0.92,0.94,0.98},0.58),
      key_mid=mix_rgb(base,active,0.42), key_bright=mix_rgb(base,active,0.86) }
  else
    local white = { 0.99, 0.99, 0.99 }
    return { active=active, bg=mix_rgb(white,active,0.11), harmony=mix_rgb(white,active,0.30),
      harmony_dash=is_dia and mix_rgb(white,active,0.65) or mix_rgb(active,{0.98,0.98,0.99},0.54),
      key_mid=mix_rgb(white,active,0.40), key_bright=mix_rgb(white,active,0.88) }
  end
end

--------------------------------------------------------------------------------
-- 3. STATE
--------------------------------------------------------------------------------
local state = {
  hwnd=nil, use_frameless=true, frameless=false, titlebar_h=0, should_close=false,
  win_x=80, win_y=60, win_w=1380, win_h=780, has_saved_win_pos=false,
  hidden_track=nil, section_items={}, output_track=nil, output_track_guid="",
  auto_arm_preview=false, saved_track_states={}, track_note_names={},
  commit_state="none", audition_mode="draft",

  sections={}, next_section_seq=1, selected_section_uid=nil, selected_phrase=nil,
  phrase_paste_mode="replace", section_clipboard={}, phrase_clipboard={},
  section_glow_uid=nil, section_glow_until=0, section_glow_held=false, last_region_poll=0,

  nns_chart_items={}, letter_chart_items={}, has_nns_chart=false, has_letter_chart=false, chord_lane_h=24, last_chart_poll=0,
  view_mode="diatonic", tonic_pc=0, mode_idx=1, sync_key_from_gmem=true,
  gmem_tonic_pc=0, gmem_modal_center=0, gmem_has_key=false,
  in_scale_h=34, harmony_border_style="dotted", piano_keys=false,

  notes={}, next_note_id=1, clipboard={}, undo_stack={}, redo_stack={},
  harmony_source="gmem", gmem_guides={}, gmem_song_end_qn=0, clip_guides={},
  manual_harmony_notes={}, next_harm_id=1, gmem_sig="", last_gmem_poll=0,

  groove_enabled=true, groove_data={}, groove_unit="auto", swing_from_gmem=true, swing_pct=0, swing_div=0.5,
  grid_idx=3, triplet=false, snap=true, auto_scroll=true, tool="draw", default_vel=100,
  wheel_mods={ v_scroll="None", h_scroll="Shift", h_zoom="Ctrl", v_zoom="Alt" },

  mpe_enabled=true, mpe_bend_range=48, instrument_bend_verified=false,
  mpe_release_tail_ms=500, mpe_chan_min=1, mpe_chan_max=15,

  toolbar_h=50, regions_h=56, reserved_h=14, ruler_h=24, keyboard_w=152, hscroll_h=18, vscroll_w=18,
  vel_lane_h=68, param_bar_h=38, transport_h=44,
  show_vel_lane=true, show_drawer=false, drawer_w=340,

  scroll_x_qn=0, scroll_y_px=0, px_per_qn=110, v_scale=1.0, has_saved_view=false,
  row_y={}, row_h={}, total_h=0,
  drag=nil, marquee=nil, hover_pitch=nil, hover_alt_seam=nil, last_mouse_cap=0,
  ui_controls={}, active_slider=nil, hscroll_geom=nil, vscroll_geom=nil, curve_handles={},
  previews={}, kbd_held_pitch=nil, kbd_held_chan=0, status_msg="Ready", section_hover=nil, last_view_save=0,
}
for i = 1, 32 do state.groove_data[i] = 0.0 end

--------------------------------------------------------------------------------
-- 4. GLOBAL & PROJECT PERSISTENCE
--------------------------------------------------------------------------------
-- Capture live geometry before gfx.quit destroys the native window.
function state.capture_window()
  if gfx.w<1 or gfx.h<1 or gfx.dock(-1)~=0 then return end
  state.win_w,state.win_h=math.max(MIN_WIN_W,gfx.w),math.max(MIN_WIN_H,gfx.h)
  local _,x,y=gfx.dock(-1,0,0,0,0)
  if type(x)=="number" and type(y)=="number" then
    state.win_x,state.win_y=x,y;state.has_saved_win_pos=true
  end
end
-- Session view is keyed to the original project, independent of draft serialization.
function state.view_key()
  return "view:"..owner_project_key
end
function state.save_session_view()
  reaper.SetExtState(EXT_GLOBAL_SEC,state.view_key(),table.concat({state.px_per_qn,state.v_scale,state.scroll_x_qn,state.scroll_y_px}," "),false)
end
function state.load_session_view()
  local a,b,c,d=reaper.GetExtState(EXT_GLOBAL_SEC,state.view_key()):match("^(%S+) (%S+) (%S+) (%S+)$")
  a,b,c,d=tonumber(a),tonumber(b),tonumber(c),tonumber(d)
  if a and b and c and d then
    state.px_per_qn=clamp(a,20,480);state.v_scale=clamp(b,.45,3)
    state.scroll_x_qn=math.max(0,c);state.scroll_y_px=math.max(0,d);state.has_saved_view=true
  end
end
local function save_global_prefs()
  local s = function(k, v) reaper.SetExtState(EXT_GLOBAL_SEC, k, tostring(v), true) end
  s("dark_mode", CONFIG.dark_mode and "1" or "0"); s("auto_scroll", state.auto_scroll and "1" or "0")
  s("use_frameless", state.use_frameless and "1" or "0"); s("phrase_paste_mode", state.phrase_paste_mode)
  s("show_vel_lane", state.show_vel_lane and "1" or "0"); s("show_drawer", state.show_drawer and "1" or "0")
  s("harmony_border_style", state.harmony_border_style); s("grid_idx", state.grid_idx)
  s("triplet", state.triplet and "1" or "0"); s("snap", state.snap and "1" or "0")
  s("mpe_release_tail_ms", state.mpe_release_tail_ms); s("in_scale_h", state.in_scale_h)
  s("view_mode", state.view_mode); s("mpe_enabled", state.mpe_enabled and "1" or "0"); s("mpe_bend_range", state.mpe_bend_range)
  s("win_x", state.win_x); s("win_y", state.win_y); s("win_w", state.win_w); s("win_h", state.win_h)
  s("win_pos_v3", state.has_saved_win_pos and "1" or "0")
  s("piano_keys",state.piano_keys and "1" or "0")
  s("px_per_qn",state.px_per_qn);s("v_scale",state.v_scale)
  state.save_session_view()
  s("mod_vscroll", state.wheel_mods.v_scroll); s("mod_hscroll", state.wheel_mods.h_scroll)
  s("mod_hzoom", state.wheel_mods.h_zoom); s("mod_vzoom", state.wheel_mods.v_zoom)
end

local function load_global_prefs()
  local g = function(k) return reaper.GetExtState(EXT_GLOBAL_SEC, k) end
  if g("dark_mode")=="0" then CONFIG.dark_mode=false elseif g("dark_mode")=="1" then CONFIG.dark_mode=true end
  if g("auto_scroll")=="0" then state.auto_scroll=false elseif g("auto_scroll")=="1" then state.auto_scroll=true end
  if g("use_frameless")=="0" then state.use_frameless=false elseif g("use_frameless")=="1" then state.use_frameless=true end
  if g("phrase_paste_mode")=="merge" or g("phrase_paste_mode")=="replace" then state.phrase_paste_mode=g("phrase_paste_mode") end
  if g("show_vel_lane")=="0" then state.show_vel_lane=false end
  if g("show_drawer")=="1" then state.show_drawer=true end
  if g("harmony_border_style")=="solid" or g("harmony_border_style")=="dotted" then state.harmony_border_style=g("harmony_border_style") end
  local gi=tonumber(g("grid_idx")); if gi and gi>=1 and gi<=#CONFIG.grid_options then state.grid_idx=math.floor(gi) end
  if g("triplet")=="1" then state.triplet=true end; if g("snap")=="0" then state.snap=false end
  local rt=tonumber(g("mpe_release_tail_ms")); if rt and rt>=50 and rt<=5000 then state.mpe_release_tail_ms=math.floor(rt) end
  local ih=tonumber(g("in_scale_h")); if ih and ih>=16 and ih<=64 then state.in_scale_h=math.floor(ih) end
  if g("view_mode")=="diatonic" or g("view_mode")=="chromatic" then state.view_mode=g("view_mode") end
  if g("mpe_enabled")=="0" then state.mpe_enabled=false elseif g("mpe_enabled")=="1" then state.mpe_enabled=true end
  local mbr=tonumber(g("mpe_bend_range")); if mbr and (mbr==2 or mbr==12 or mbr==24 or mbr==48) then state.mpe_bend_range=mbr end
  local wx, wy, ww, wh = tonumber(g("win_x")), tonumber(g("win_y")), tonumber(g("win_w")), tonumber(g("win_h"))
  if g("win_pos_v3") == "1" and wx and wy then state.win_x, state.win_y = math.floor(wx), math.floor(wy); state.has_saved_win_pos = true end
  if ww and wh then state.win_w, state.win_h = math.max(MIN_WIN_W, math.floor(ww)), math.max(MIN_WIN_H, math.floor(wh)) end
  state.piano_keys=g("piano_keys")=="1"
  state.px_per_qn=clamp(tonumber(g("px_per_qn")) or state.px_per_qn,20,480)
  state.v_scale=clamp(tonumber(g("v_scale")) or state.v_scale,0.45,3.0)
  local function rm(k, d) local v=g(k); return (v and v~="") and v or d end
  state.wheel_mods.v_scroll=rm("mod_vscroll","None"); state.wheel_mods.h_scroll=rm("mod_hscroll","Shift")
  state.wheel_mods.h_zoom=rm("mod_hzoom","Ctrl"); state.wheel_mods.v_zoom=rm("mod_vzoom","Alt")
end

local function make_default_note(args)
  local vib = args.vibrato or { enabled=false, rate=5.5, depth_cents=35, delay=0.15, ramp=0.25, curve=0.0, pattern="consistent" }
  if not vib.pattern then vib.pattern = "consistent" end
  return {
    id=args.id, selected=args.selected or false, muted=args.muted or false,
    start_qn=args.start_qn, end_qn=args.end_qn, pitch=args.pitch, vel=args.vel or 100, chan=args.chan or 1,
    section_uid=args.section_uid, section_override=args.section_override or false,
    t1=args.t1 or 0.05, pre_st=args.pre_st or 0.0, t2=args.t2 or 0.35, t3=args.t3 or 0.65, t4=args.t4 or 0.95, out_st=args.out_st or 0.0,
    pre_shape=args.pre_shape or "s_curve", pre_tension=args.pre_tension or 0.0,
    out_shape=args.out_shape or "s_curve", out_tension=args.out_tension or 0.0,
    connect_to_id=args.connect_to_id, vibrato=vib,
  }
end

local function serialize_note(n)
  return {
    id=n.id, muted=n.muted, start_qn=n.start_qn, end_qn=n.end_qn, pitch=n.pitch, vel=n.vel, chan=n.chan,
    section_uid=n.section_uid, section_override=n.section_override, t1=n.t1, pre_st=n.pre_st, t2=n.t2, t3=n.t3, t4=n.t4, out_st=n.out_st,
    pre_shape=n.pre_shape, pre_tension=n.pre_tension, out_shape=n.out_shape, out_tension=n.out_tension, connect_to_id=n.connect_to_id, vibrato=n.vibrato,
  }
end

local function save_project_state()
  local sec_data, note_data = {}, {}
  for _, s in ipairs(state.sections) do table.insert(sec_data, {uid=s.uid,markrgn_num=s.markrgn_num,name=s.name,start_qn=s.start_qn,end_qn=s.end_qn,bar_qn=s.bar_qn,rgb=s.rgb,deleted=s.deleted}) end
  for _, n in ipairs(state.notes) do table.insert(note_data, serialize_note(n)) end
  reaper.SetProjExtState(owner_project, EXT_PROJ_SEC, EXT_PROJ_KEY, serialize_val({
    next_note_id=state.next_note_id, next_section_seq=state.next_section_seq,
    selected_section_uid=state.selected_section_uid, output_track_guid=state.output_track_guid,
    auto_arm_preview=state.auto_arm_preview, commit_state=state.commit_state, audition_mode=state.audition_mode,
    mpe_enabled=state.mpe_enabled, mpe_bend_range=state.mpe_bend_range, instrument_bend_verified=state.instrument_bend_verified,
    view_mode=state.view_mode, tonic_pc=state.tonic_pc, mode_idx=state.mode_idx, sync_key_from_gmem=state.sync_key_from_gmem,
    in_scale_h=state.in_scale_h, groove_enabled=state.groove_enabled, groove_unit=state.groove_unit,
    swing_from_gmem=state.swing_from_gmem, swing_pct=state.swing_pct, swing_div=state.swing_div,
    harmony_source=state.harmony_source, clip_guides=state.clip_guides,
    scroll_x_qn=state.scroll_x_qn, scroll_y_px=state.scroll_y_px, px_per_qn=state.px_per_qn, v_scale=state.v_scale,
    sections=sec_data, notes=note_data, manual_harmony_notes=state.manual_harmony_notes,
  }))
end

local function load_project_state()
  local ok, str = reaper.GetProjExtState(0, EXT_PROJ_SEC, EXT_PROJ_KEY)
  if ok == 0 or not str or str == "" then return false end
  local data = deserialize_table(str); if not data then return false end
  state.next_note_id=data.next_note_id or 1; state.next_section_seq=data.next_section_seq or 1
  state.selected_section_uid=data.selected_section_uid; state.output_track_guid=data.output_track_guid or ""
  state.auto_arm_preview=(data.auto_arm_preview==true)
  if data.commit_state then state.commit_state=data.commit_state end; if data.audition_mode then state.audition_mode=data.audition_mode end
  if data.mpe_enabled~=nil then state.mpe_enabled=data.mpe_enabled end; if data.mpe_bend_range then state.mpe_bend_range=data.mpe_bend_range end
  state.instrument_bend_verified=(data.instrument_bend_verified==true)
  if data.view_mode then state.view_mode=data.view_mode end; if data.tonic_pc~=nil then state.tonic_pc=data.tonic_pc end
  if data.mode_idx~=nil then state.mode_idx=data.mode_idx end; if data.sync_key_from_gmem~=nil then state.sync_key_from_gmem=data.sync_key_from_gmem end
  if data.in_scale_h then state.in_scale_h=data.in_scale_h end
  if data.groove_enabled~=nil then state.groove_enabled=data.groove_enabled end; if data.groove_unit then state.groove_unit=data.groove_unit end
  if data.swing_from_gmem~=nil then state.swing_from_gmem=data.swing_from_gmem end
  if data.swing_pct~=nil then state.swing_pct=data.swing_pct end; if data.swing_div~=nil then state.swing_div=data.swing_div end
  if data.harmony_source then state.harmony_source=data.harmony_source end; if data.clip_guides then state.clip_guides=data.clip_guides end
  if data.scroll_x_qn then state.scroll_x_qn=data.scroll_x_qn; state.has_saved_view=true end
  if data.scroll_y_px then state.scroll_y_px=data.scroll_y_px; state.has_saved_view=true end
  if data.px_per_qn then state.px_per_qn=clamp(data.px_per_qn,20,480) end; if data.v_scale then state.v_scale=clamp(data.v_scale,0.45,3.0) end
  state.sections={}
  if data.sections then for _, s in ipairs(data.sections) do
    table.insert(state.sections,{uid=s.uid,markrgn_num=s.markrgn_num,name=s.name or "Section",start_qn=s.start_qn or 0,end_qn=s.end_qn or 16,
      prev_start_qn=s.start_qn or 0,prev_end_qn=s.end_qn or 16,pos_sec=reaper.TimeMap2_QNToTime(0,s.start_qn or 0),bar_qn=s.bar_qn or 4.0,rgb=s.rgb or {0.45,0.52,0.62},deleted=s.deleted or false,overflow_cnt=0})
  end end
  state.notes={}
  if data.notes then for _, n in ipairs(data.notes) do
    local out_st = n.out_st or ((n.bend_st or 0) + (n.bend_cents or 0)/100.0)
    table.insert(state.notes, make_default_note({id=n.id,muted=n.muted,start_qn=n.start_qn,end_qn=n.end_qn,pitch=n.pitch,vel=n.vel,chan=n.chan,
      section_uid=n.section_uid,section_override=n.section_override,t1=n.t1 or 0.05,pre_st=n.pre_st or 0.0,t2=n.t2 or 0.35,t3=n.t3 or 0.65,t4=n.t4 or 0.95,out_st=out_st,
      pre_shape=n.pre_shape or "s_curve",pre_tension=n.pre_tension or 0.0,out_shape=n.out_shape or "s_curve",out_tension=n.out_tension or 0.0,connect_to_id=n.connect_to_id,vibrato=n.vibrato}))
    if n.id >= state.next_note_id then state.next_note_id = n.id + 1 end
  end end
  if data.manual_harmony_notes then state.manual_harmony_notes = data.manual_harmony_notes end
  return true
end

--------------------------------------------------------------------------------
-- 5. LAYOUT, NNS, SONG LENGTH & COORDINATES
--------------------------------------------------------------------------------
local function set_col(col, a) gfx.set(col[1], col[2], col[3], a or 1.0) end
local function get_chord_lanes_total_h() return (state.has_nns_chart and state.chord_lane_h or 0) + (state.has_letter_chart and state.chord_lane_h or 0) end
local function get_ruler_y() return state.titlebar_h + state.toolbar_h + state.regions_h + get_chord_lanes_total_h() + state.reserved_h end
local function get_top_area_y() return get_ruler_y() + state.ruler_h end
local function get_grid_right_x(canvas_w) return canvas_w - state.vscroll_w - 2 end
local function get_rel_step(pitch) return (pitch - state.tonic_pc) % 12 end
local function is_pitch_diatonic(pitch) return CONFIG.step_definitions[get_rel_step(pitch)].diatonic end
local function get_effective_lane_h() return math.max(12, math.floor(state.in_scale_h * state.v_scale + 0.5)) end
local function get_harmony_visual_h() return math.max(8, math.floor(get_effective_lane_h() * 0.72 + 0.5)) end
local function get_note_visual_h() return math.max(6, math.floor(get_effective_lane_h() * 0.52 + 0.5)) end

local function rebuild_row_layout()
  local y = 0
  for p = 127, 0, -1 do
    local h = (CONFIG.step_definitions[get_rel_step(p)].diatonic or state.view_mode ~= "diatonic") and get_effective_lane_h() or 0
    state.row_y[p] = y; state.row_h[p] = h; y = y + h
  end
  state.total_h = math.max(1, y)
end

local function get_grid_qn() local b = CONFIG.grid_options[state.grid_idx].qn; return state.triplet and (b * 2 / 3) or b end
local function snap_qn(qn) if not state.snap then return math.max(0, qn) end; local g = get_grid_qn(); return math.max(0, math.floor(qn/g + 0.5)*g) end
local function snap_floor_qn(qn) local g = get_grid_qn(); return math.max(0, math.floor(qn/g + 1e-6)*g) end

local function get_key_left_right_labels(pitch)
  local nns = CONFIG.step_definitions[get_rel_step(pitch)].nns
  local nn = CONFIG.note_names[(pitch % 12) + 1] .. (math.floor(pitch / 12) - 1)
  local custom = state.track_note_names[pitch]
  return (custom and custom ~= "") and string.format("%s (%s)", custom, nn) or nn, nns
end

local function pitch_to_screen_y(pitch) return get_top_area_y() + (state.row_y[pitch] or 0) - state.scroll_y_px end
local function pitch_center_screen_y(pitch) return pitch_to_screen_y(pitch) + (state.row_h[pitch] or 0) * 0.5 end

local function pitch_float_to_screen_y(pitch_f)
  pitch_f = clamp(pitch_f, 0.0, 127.0)
  local p_lo = math.floor(pitch_f); local p_hi = math.min(127, p_lo + 1); local frac = pitch_f - p_lo
  if frac < 1e-4 then return pitch_center_screen_y(p_lo) end
  return lerp(pitch_center_screen_y(p_lo), pitch_center_screen_y(p_hi), frac)
end

local function screen_y_to_pitch(sy, allow_zero_alt)
  local cy = sy - get_top_area_y() + state.scroll_y_px
  if state.view_mode == "diatonic" and allow_zero_alt then
    local bp, bd = nil, 9.0
    for p = 127, 0, -1 do if state.row_h[p] == 0 then local d = math.abs(cy - state.row_y[p]); if d < bd then bd=d; bp=p end end end
    if bp then return bp end
  end
  for p = 127, 0, -1 do local ry, rh = state.row_y[p], state.row_h[p]; if rh > 0 and cy >= ry and cy < ry + rh then return p end end
  return nil
end

local function qn_to_screen_x(qn) return state.keyboard_w + (qn - state.scroll_x_qn) * state.px_per_qn end
local function screen_x_to_qn(sx) return state.scroll_x_qn + (sx - state.keyboard_w) / state.px_per_qn end

local function get_max_timeline_qn()
  local _, _, cml = reaper.TimeMap2_timeToBeats(0, 0); local bar_qn = (cml and cml > 0) and cml or 4.0
  local four_bars, song_end = bar_qn * 4.0, state.gmem_song_end_qn or 0
  if song_end <= 0 then for _, s in ipairs(state.sections) do if not s.deleted and s.end_qn > song_end then song_end = s.end_qn end end end
  if song_end <= 0 then
    for _, g in ipairs(state.gmem_guides) do if g.end_qn > song_end then song_end = g.end_qn end end
    for _, g in ipairs(state.clip_guides) do if g.end_qn > song_end then song_end = g.end_qn end end
  end
  if song_end <= 0 then song_end = four_bars end
  local te = song_end + four_bars
  for _, n in ipairs(state.notes) do if n.end_qn + bar_qn > te then te = n.end_qn + bar_qn end end
  return te
end

local function get_section_by_uid(uid) if not uid then return nil end; for _, s in ipairs(state.sections) do if s.uid == uid then return s end end; return nil end
local function find_section_at_qn(qn) for _, s in ipairs(state.sections) do if not s.deleted and qn >= s.start_qn - 1e-4 and qn < s.end_qn - 1e-4 then return s end end; return nil end

--------------------------------------------------------------------------------
-- 6. MPE MODEL, VIBRATO PATTERNS (<, >, <>), CHAINS & GROOVE/SWING
--------------------------------------------------------------------------------
local function get_note_by_id(id) if not id then return nil end; for _, n in ipairs(state.notes) do if n.id == id then return n end end; return nil end
local function get_incoming_note(note_id) if not note_id then return nil end; for _, n in ipairs(state.notes) do if n.connect_to_id == note_id then return n end end; return nil end
local function get_chain_root(note) local c,g=note,0; while c and g<64 do local i=get_incoming_note(c.id); if not i then return c end; c=i; g=g+1 end; return note end
local function get_chain_nodes(root) local ns,s,c={},{},root; while c and not s[c.id] do s[c.id]=true; table.insert(ns,c); c=get_note_by_id(c.connect_to_id) end; return ns end
local function is_green_positioned(n) return math.abs(n.pre_st or 0.0) > 0.01 or math.abs((n.t1 or 0.05) - 0.05) > 0.005 end
local function is_red_positioned(n)   return math.abs(n.out_st or 0.0) > 0.01 or math.abs((n.t4 or 0.95) - 0.95) > 0.005 end
local function reset_pre_bend(n) n.t1=0.05; n.pre_st=0.0; n.pre_tension=0.0; n.pre_shape="s_curve"; n.t2=math.min(0.35,(n.t3 or 0.65)-0.04) end
local function reset_bend_out(n) n.t4=0.95; n.out_st=0.0; n.out_tension=0.0; n.out_shape="s_curve"; n.t3=math.max(0.65,(n.t2 or 0.35)+0.04) end

local function validate_chain_bend_range(root)
  for i, node in ipairs(get_chain_nodes(root)) do
    local bd = node.pitch - root.pitch
    if math.abs(bd) > state.mpe_bend_range + 1e-4 then return false, bd end
    if i == 1 and math.abs(bd + (node.pre_st or 0)) > state.mpe_bend_range + 1e-4 then return false, bd + (node.pre_st or 0) end
    if not node.connect_to_id and math.abs(bd + (node.out_st or 0)) > state.mpe_bend_range + 1e-4 then return false, bd + (node.out_st or 0) end
  end
  return true, 0.0
end

local function can_connect_notes(src, dst)
  if not src or not dst or src.id == dst.id then return false, "Invalid note" end
  if dst.start_qn < src.start_qn then return false, "Destination precedes source" end
  if get_incoming_note(dst.id) ~= nil then return false, "Destination already connected" end
  local root = get_chain_root(src)
  for _, rn in ipairs(get_chain_nodes(root)) do if rn.id == dst.id then return false, "Cycle not allowed" end end
  for _, dn in ipairs(get_chain_nodes(dst)) do
    local disp = dn.pitch - root.pitch
    if math.abs(disp) > state.mpe_bend_range + 1e-4 then return false, string.format("Accumulated bend (%.1f st) exceeds ±%d st", disp, state.mpe_bend_range) end
    if not dn.connect_to_id and math.abs(disp + (dn.out_st or 0)) > state.mpe_bend_range + 1e-4 then return false, string.format("Accumulated bend exceeds ±%d st", state.mpe_bend_range) end
  end
  return true, nil
end

local function connect_notes(src, dst) src.connect_to_id = dst.id; src.out_st = 0.0; dst.pre_st = 0.0; dst.t2 = 0.0 end
local function disconnect_note_outgoing(src)
  local dst = get_note_by_id(src.connect_to_id); src.connect_to_id = nil; src.t4 = 0.95; src.out_st = 0.0
  if dst then dst.t1 = 0.05; dst.pre_st = 0.0; if (dst.t2 or 0) < 0.15 then dst.t2 = math.min(0.35, (dst.t3 or 0.65) - 0.06) end end
end
local function get_chain_span_qn(root) local ns = get_chain_nodes(root); return root.start_qn, math.max(root.end_qn, ns[#ns].end_qn) end

local function eval_curve_shape(u, shape, tension)
  u = clamp(u, 0.0, 1.0); local ten = clamp(tension or 0.0, -1.0, 1.0); shape = shape or "s_curve"
  if shape == "linear" then return u
  elseif shape == "ease_in" then return u ^ clamp(2.0 + ten * 1.4, 1.05, 3.8)
  elseif shape == "ease_out" then return 1.0 - ((1.0 - u) ^ clamp(2.0 - ten * 1.4, 1.05, 3.8))
  elseif shape == "inv_s" then local exp = clamp(2.0 + ten * 1.4, 1.05, 3.8); return (u < 0.5) and (0.5*(1.0-(1.0-2.0*u)^exp)) or (0.5+0.5*((2.0*u-1.0)^exp))
  else local exp = clamp(2.0 + ten * 1.4, 1.05, 3.8); return (u < 0.5) and (0.5*((2.0*u)^exp)) or (1.0-0.5*((2.0*(1.0-u))^exp)) end
end

local function eval_vibrato_pattern_env(pattern, t_active)
  t_active = clamp(t_active, 0.0, 1.0)
  if pattern == "cresc" then return t_active elseif pattern == "decresc" then return 1.0 - t_active elseif pattern == "swell" then return math.sin(math.pi * t_active) end
  return 1.0
end

local function get_note_node_qns(n, has_inc, dst)
  local q1 = lerp(n.start_qn, n.end_qn, clamp(n.t1 or 0.05, 0.0, 0.90))
  local min_t2 = has_inc and 0.0 or ((n.t1 or 0.05) + 0.04)
  local q2 = lerp(n.start_qn, n.end_qn, clamp(n.t2 or (has_inc and 0.0 or 0.35), min_t2, 0.94))
  local q3 = lerp(n.start_qn, n.end_qn, clamp(n.t3 or 0.65, math.max(min_t2, n.t2 or 0) + 0.04, dst and 0.99 or 0.95))
  local q4 = dst and math.max(q3 + 0.04, lerp(dst.start_qn, dst.end_qn, clamp(dst.t2 or 0.0, 0.0, (dst.t3 or 0.65) - 0.04)))
    or lerp(n.start_qn, n.end_qn, clamp(n.t4 or 0.95, (n.t3 or 0.65) + 0.04, 1.0))
  return q1, q2, q3, q4
end

local function eval_chain_bend_at_qn(root, qn, chain_start_qn, chain_end_qn)
  local nodes, base_st = get_chain_nodes(root), 0.0
  for i = 1, #nodes do
    local cur, dst = nodes[i], nodes[i + 1]; local cur_base = cur.pitch - root.pitch; local q1, q2, q3, q4 = get_note_node_qns(cur, i > 1, dst)
    if i == 1 and qn < q2 then
      local pre = cur.pre_st or 0.0
      base_st = (math.abs(pre) > 1e-4) and ((qn <= q1) and (cur_base + pre) or (cur_base + pre * (1.0 - eval_curve_shape((qn - q1) / math.max(1e-4, q2 - q1), cur.pre_shape, cur.pre_tension)))) or cur_base
      break
    elseif qn <= q3 then base_st = cur_base; break
    elseif qn <= q4 then base_st = lerp(cur_base, dst and (dst.pitch - root.pitch) or (cur_base + (cur.out_st or 0.0)), eval_curve_shape((qn - q3) / math.max(1e-4, q4 - q3), cur.out_shape, cur.out_tension)); break
    elseif not dst then base_st = cur_base + (cur.out_st or 0.0); break end
  end
  local vib, vib_st = root.vibrato, 0.0
  if vib and vib.enabled and vib.depth_cents > 0 then
    local t = clamp((qn - chain_start_qn) / math.max(0.05, chain_end_qn - chain_start_qn), 0.0, 1.0)
    if t >= vib.delay then
      local t_act = clamp((t - vib.delay) / math.max(1e-4, 1.0 - vib.delay), 0.0, 1.0)
      local env = eval_vibrato_pattern_env(vib.pattern or "consistent", t_act)
      if (vib.pattern == "consistent" or not vib.pattern) and vib.ramp > 1e-4 then env = env * eval_curve_shape((t - vib.delay) / vib.ramp, "s_curve", vib.curve) end
      local dur_sec = math.max(0.05, reaper.TimeMap2_QNToTime(0, chain_end_qn) - reaper.TimeMap2_QNToTime(0, chain_start_qn))
      vib_st = (vib.depth_cents / 100.0) * env * math.sin(2.0 * math.pi * vib.rate * (t - vib.delay) * dur_sec)
    end
  end
  return base_st + vib_st
end

local function note_or_chain_has_bend(root)
  return #get_chain_nodes(root) > 1 or (root.vibrato and root.vibrato.enabled) or math.abs(root.pre_st or 0) > 0.01 or math.abs(root.out_st or 0) > 0.01
end

local function reallocate_all_mpe_channels()
  if not state.mpe_enabled then for _, n in ipairs(state.notes) do n.chan = 0 end; return end
  local roots = {}; for _, n in ipairs(state.notes) do if get_incoming_note(n.id) == nil then table.insert(roots, n) end end
  table.sort(roots, function(a, b) return a.start_qn < b.start_qn end)
  local tail_sec, ch_busy_until, ch_tail_until, ch_bent, exhausted = (state.mpe_release_tail_ms or 500) / 1000.0, {}, {}, {}, false
  for _, root in ipairs(roots) do
    local s_qn, e_qn = get_chain_span_qn(root); local s_sec, e_sec = reaper.TimeMap2_QNToTime(0, s_qn), reaper.TimeMap2_QNToTime(0, e_qn); local chosen = nil
    for ch = state.mpe_chan_min, state.mpe_chan_max do if (ch_tail_until[ch] or -1) <= s_sec + 1e-4 then chosen = ch break end end
    if not chosen then for ch = state.mpe_chan_min, state.mpe_chan_max do if (ch_busy_until[ch] or -1) <= s_sec + 1e-4 then chosen = ch break end end end
    if not chosen then
      exhausted = true
      for ch = state.mpe_chan_min, state.mpe_chan_max do if not ch_bent[ch] then chosen = ch break end end
      if not chosen then local be = math.huge; for ch = state.mpe_chan_min, state.mpe_chan_max do if (ch_busy_until[ch] or 0) < be then be = ch_busy_until[ch] or 0; chosen = ch end end end
    end
    ch_busy_until[chosen] = e_sec; ch_tail_until[chosen] = e_sec + (note_or_chain_has_bend(root) and tail_sec or 0.02)
    if note_or_chain_has_bend(root) then ch_bent[chosen] = true end
    for _, node in ipairs(get_chain_nodes(root)) do node.chan = chosen end
  end
  if exhausted then state.status_msg = "Warning: 15-ch MPE pool saturated; reused least-conflicting channel" end
end

local function read_gmem_groove_and_swing()
  local changed = false; reaper.gmem_attach(GMEM_NAMESPACE)
  for i = 1, 32 do local v = reaper.gmem_read(GMEM_GROOVE_BASE + (i - 1)); if is_finite(v) and math.abs(v - (state.groove_data[i] or 0)) > 1e-5 then state.groove_data[i] = v; changed = true end end
  if state.swing_from_gmem then
    local sw = reaper.gmem_read(2)
    if not is_finite(sw) or sw <= 0 then reaper.gmem_attach(""); local sw_g = reaper.gmem_read(2); reaper.gmem_attach(GMEM_NAMESPACE); if is_finite(sw_g) and sw_g > 0 and sw_g <= 100 then sw = sw_g end end
    if is_finite(sw) and sw >= 0 and sw <= 100 then local sw_i = math.floor(sw + 0.5); if sw_i ~= state.swing_pct then state.swing_pct = sw_i; changed = true end end
  end
  return changed
end

local function compute_groove_swing_offset_qn(start_qn)
  local offset = 0.0
  if state.swing_pct and state.swing_pct > 0 then
    local div = state.swing_div or 0.5
    if math.abs((start_qn % (div * 2.0)) - div) < div * 0.25 then offset = offset + (state.swing_pct / 100.0) * (div / 3.0) end
  end
  if state.groove_enabled then
    local step_f = (start_qn % 4.0) / 0.125; local s1 = (math.floor(step_f) % 32) + 1
    local raw_g = lerp(state.groove_data[s1] or 0.0, state.groove_data[(s1 % 32) + 1] or 0.0, step_f - math.floor(step_f))
    if math.abs(raw_g) > 1e-5 then
      local unit = state.groove_unit
      if unit == "auto" then local ma = 0; for i = 1, 32 do ma = math.max(ma, math.abs(state.groove_data[i] or 0)) end; unit = (ma > 0.5) and "pct32" or "qn" end
      offset = offset + ((unit == "qn") and raw_g or ((raw_g / 100.0) * 0.125))
    end
  end
  return offset
end

--------------------------------------------------------------------------------
-- 7. HIDDEN TRACK, COMMIT, LOSSLESS TRACK IMPORT & .mid EXPORT
--------------------------------------------------------------------------------
local function find_track_by_name(tn) for i = 0, reaper.CountTracks(0) - 1 do local tr = reaper.GetTrack(0, i); local _, nm = reaper.GetTrackName(tr); if trim(nm) == tn then return tr end end; return nil end

local function ensure_hidden_track()
  local tr = state.hidden_track
  if not tr or not reaper.ValidatePtr2(0, tr, "MediaTrack*") then
    tr = find_track_by_name(HIDDEN_TRACK_NAME) or find_track_by_name(LEGACY_HIDDEN_NAME)
    if tr then reaper.GetSetMediaTrackInfo_String(tr, "P_NAME", HIDDEN_TRACK_NAME, true)
    else local idx = reaper.CountTracks(0); reaper.InsertTrackAtIndex(idx, false); tr = reaper.GetTrack(0, idx); reaper.GetSetMediaTrackInfo_String(tr, "P_NAME", HIDDEN_TRACK_NAME, true) end
    state.hidden_track = tr
  end
  reaper.SetMediaTrackInfo_Value(tr, "B_SHOWINTCP", 0); reaper.SetMediaTrackInfo_Value(tr, "B_SHOWINMIXER", 0)
  reaper.SetMediaTrackInfo_Value(tr, "B_MAINSEND", 0); reaper.SetMediaTrackInfo_Value(tr, "I_RECARM", 0)
  reaper.SetMediaTrackInfo_Value(tr, "I_FREEMODE", 1); reaper.TrackList_AdjustWindows(false); return tr
end

local function apply_audition_mute_routing()
  local htr = ensure_hidden_track(); local is_draft = (state.commit_state == "none") or (state.audition_mode == "draft")
  reaper.SetMediaTrackInfo_Value(htr, "B_MUTE", is_draft and 0 or 1)
  if state.output_track and reaper.ValidatePtr2(0, state.output_track, "MediaTrack*") then
    for i = 0, reaper.CountTrackMediaItems(state.output_track) - 1 do
      local it = reaper.GetTrackMediaItem(state.output_track, i); local ok, cuid = reaper.GetSetMediaItemInfo_String(it, "P_EXT:N2N_COMMITTED_UID", "", false)
      if ok and cuid ~= "" then reaper.SetMediaItemInfo_Value(it, "B_MUTE", is_draft and 1 or 0) end
    end
  end
end

local function update_hidden_track_send()
  local htr = ensure_hidden_track(); while reaper.GetTrackNumSends(htr, 0) > 0 do reaper.RemoveTrackSend(htr, 0, 0) end
  local dst = state.output_track
  if dst and reaper.ValidatePtr2(0, dst, "MediaTrack*") and dst ~= htr then
    local sidx = reaper.CreateTrackSend(htr, dst)
    if sidx >= 0 then reaper.SetTrackSendInfo_Value(htr, 0, sidx, "I_SRCCHAN", -1); reaper.SetTrackSendInfo_Value(htr, 0, sidx, "I_MIDIFLAGS", 0) end
  end
  apply_audition_mute_routing()
end

local function write_section_clips_to_track(target_track, ext_key, store_lossless_meta)
  if not target_track or not reaper.ValidatePtr2(0, target_track, "MediaTrack*") then return end
  local existing_by_uid = {}
  for i = 0, reaper.CountTrackMediaItems(target_track) - 1 do
    local it = reaper.GetTrackMediaItem(target_track, i); local ok, uid = reaper.GetSetMediaItemInfo_String(it, ext_key, "", false); if ok and uid ~= "" then existing_by_uid[uid] = it end
  end
  local roots_by_sec, notes_by_sec, used_keys, all_roots = {}, {}, {}, {}
  for _, sec in ipairs(state.sections) do roots_by_sec[sec.uid] = {}; notes_by_sec[sec.uid] = {}; used_keys[sec.uid] = true end
  roots_by_sec["__unassigned"] = {}; notes_by_sec["__unassigned"] = {}
  for _, n in ipairs(state.notes) do
    local key = (n.section_uid and roots_by_sec[n.section_uid]) and n.section_uid or "__unassigned"
    table.insert(notes_by_sec[key], n); if get_incoming_note(n.id) == nil then table.insert(roots_by_sec[key], n); table.insert(all_roots, n) end
  end
  if #roots_by_sec["__unassigned"] > 0 then used_keys["__unassigned"] = true end

  local ch_starts = {}
  for _, r in ipairs(all_roots) do
    local sq = get_chain_span_qn(r); local ss = reaper.TimeMap2_QNToTime(0, math.max(0, sq + compute_groove_swing_offset_qn(sq)))
    ch_starts[r.chan] = ch_starts[r.chan] or {}; table.insert(ch_starts[r.chan], ss)
  end
  for _, list in pairs(ch_starts) do table.sort(list) end
  local tail_sec = (state.mpe_release_tail_ms or 500) / 1000.0
  local function find_next_start_sec(chan, after_sec) for _, st in ipairs(ch_starts[chan] or {}) do if st > after_sec + 1e-4 then return st end end; return nil end

  reaper.PreventUIRefresh(1)
  for uid, it in pairs(existing_by_uid) do if not used_keys[uid] and reaper.ValidatePtr2(0, it, "MediaItem*") then reaper.DeleteTrackMediaItem(target_track, it); existing_by_uid[uid] = nil end end

  for key, roots in pairs(roots_by_sec) do
    if used_keys[key] then
      local sec = get_section_by_uid(key)
      local min_sec, max_sec, root_timings = sec and sec.pos_sec or math.huge, sec and reaper.TimeMap2_QNToTime(0, sec.end_qn) or 0, {}
      for _, r in ipairs(roots) do
        local rs, re = get_chain_span_qn(r); local off = compute_groove_swing_offset_qn(rs)
        local osq, oeq = math.max(0, rs + off), math.max(0.05, re + off)
        local oss, oes = reaper.TimeMap2_QNToTime(0, osq), reaper.TimeMap2_QNToTime(0, oeq); local reset_sec = oes
        if note_or_chain_has_bend(r) then
          local nxt_s = find_next_start_sec(r.chan, oes - 0.005)
          reset_sec = nxt_s and math.max(oes + 0.002, math.min(oes + tail_sec, nxt_s - 0.012)) or (oes + tail_sec)
        end
        root_timings[r.id] = { s_qn=rs, e_qn=re, out_s_qn=osq, out_e_qn=oeq, out_s_sec=oss, out_e_sec=oes, reset_sec=reset_sec }
        min_sec = math.min(min_sec, oss); max_sec = math.max(max_sec, reset_sec + 0.04)
      end
      if min_sec == math.huge then min_sec = 0 end; if max_sec <= min_sec then max_sec = min_sec + 1.0 end

      local it = existing_by_uid[key]
      if not it or not reaper.ValidatePtr2(0, it, "MediaItem*") then it = reaper.CreateNewMIDIItemInProj(target_track, min_sec, max_sec, false); reaper.GetSetMediaItemInfo_String(it, ext_key, key, true)
      else reaper.SetMediaItemInfo_Value(it, "D_POSITION", min_sec); reaper.SetMediaItemInfo_Value(it, "D_LENGTH", max_sec - min_sec) end
      if sec and sec.rgb then reaper.SetMediaItemInfo_Value(it, "I_CUSTOMCOLOR", reaper.ColorToNative(clamp(math.floor(sec.rgb[1]*255+0.5),0,255), clamp(math.floor(sec.rgb[2]*255+0.5),0,255), clamp(math.floor(sec.rgb[3]*255+0.5),0,255)) | 0x1000000) end
      if store_lossless_meta then local ser = {}; for _, sn in ipairs(notes_by_sec[key]) do table.insert(ser, serialize_note(sn)) end; reaper.GetSetMediaItemInfo_String(it, "P_EXT:N2N_TOPLINE_NOTES", serialize_val(ser), true) end

      local tk = reaper.GetActiveTake(it)
      if tk and reaper.TakeIsMIDI(tk) then
        reaper.MIDI_DisableSort(tk)
        local _, nc, cc = reaper.MIDI_CountEvts(tk)
        for i = nc - 1, 0, -1 do reaper.MIDI_DeleteNote(tk, i) end
        for i = cc - 1, 0, -1 do local ok, _, _, _, cm = reaper.MIDI_GetCC(tk, i); if ok and (cm & 0xF0) == 0xE0 then reaper.MIDI_DeleteCC(tk, i) end end
        for _, root in ipairs(roots) do
          local rt = root_timings[root.id]; local sp, ep = reaper.MIDI_GetPPQPosFromProjQN(tk, rt.out_s_qn), reaper.MIDI_GetPPQPosFromProjQN(tk, rt.out_e_qn)
          reaper.MIDI_InsertNote(tk, false, root.muted, sp, ep, root.chan, root.pitch, clamp(root.vel, 1, 127), true)
          if note_or_chain_has_bend(root) then
            local steps = clamp(math.floor(math.max(0.02, rt.out_e_sec - rt.out_s_sec) * 80), 24, 240)
            for step = 0, steps do
              local t = step / steps; local st = eval_chain_bend_at_qn(root, lerp(rt.s_qn, rt.e_qn, t), rt.s_qn, rt.e_qn)
              local v14 = clamp(math.floor(8192 + clamp(st / state.mpe_bend_range, -1, 1) * 8191 + 0.5), 0, 16383)
              reaper.MIDI_InsertCC(tk, false, false, reaper.MIDI_GetPPQPosFromProjQN(tk, lerp(rt.out_s_qn, rt.out_e_qn, t)), 0xE0, root.chan, v14 & 0x7F, (v14 >> 7) & 0x7F)
            end
            reaper.MIDI_InsertCC(tk, false, false, math.max(ep + 1, reaper.MIDI_GetPPQPosFromProjQN(tk, reaper.TimeMap2_timeToQN(0, rt.reset_sec))), 0xE0, root.chan, 0, 64)
          end
        end
        reaper.MIDI_Sort(tk); reaper.UpdateItemInProject(it); reaper.MarkTrackItemsDirty(target_track, it)
      end
    end
  end
  reaper.PreventUIRefresh(-1); reaper.UpdateTimeline()
end

local function sync_section_clips()
  local htr = ensure_hidden_track(); reallocate_all_mpe_channels()
  write_section_clips_to_track(htr, "P_EXT:N2N_SECTION_UID", false)
  if state.commit_state == "committed" then state.commit_state = "dirty"; state.audition_mode = "draft" end
  apply_audition_mute_routing(); save_project_state()
end

local function commit_clips_to_output_track()
  if not state.output_track or not reaper.ValidatePtr2(0, state.output_track, "MediaTrack*") then state.status_msg = "Select an Output Track first"; return false end
  reaper.Undo_BeginBlock(); reallocate_all_mpe_channels()
  write_section_clips_to_track(state.output_track, "P_EXT:N2N_COMMITTED_UID", true)
  state.commit_state = "committed"; state.audition_mode = "committed"; apply_audition_mute_routing(); save_project_state()
  reaper.Undo_EndBlock("N2N Topline: Commit Section Clips", -1)
  local _, tn = reaper.GetTrackName(state.output_track); state.status_msg = "Committed clips -> [" .. tn .. "]"; return true
end

local function clear_committed_clips_from_output_track()
  if not state.output_track or not reaper.ValidatePtr2(0, state.output_track, "MediaTrack*") then return end
  reaper.Undo_BeginBlock(); local rem = 0
  for i = reaper.CountTrackMediaItems(state.output_track) - 1, 0, -1 do
    local it = reaper.GetTrackMediaItem(state.output_track, i); local ok, cuid = reaper.GetSetMediaItemInfo_String(it, "P_EXT:N2N_COMMITTED_UID", "", false)
    if ok and cuid ~= "" then reaper.DeleteTrackMediaItem(state.output_track, it); rem = rem + 1 end
  end
  state.commit_state = "none"; state.audition_mode = "draft"; apply_audition_mute_routing(); save_project_state(); reaper.UpdateTimeline()
  reaper.Undo_EndBlock("N2N Topline: Clear Committed Clips", -1); state.status_msg = string.format("Cleared %d N2N committed clip(s)", rem)
end

local function load_midi_from_track(tr, mode)
  if not tr or not reaper.ValidatePtr2(0, tr, "MediaTrack*") then return end
  local imported, lossless_cnt = {}, 0
  for i = 0, reaper.CountTrackMediaItems(tr) - 1 do
    local it = reaper.GetTrackMediaItem(tr, i); local ok_m, m_str = reaper.GetSetMediaItemInfo_String(it, "P_EXT:N2N_TOPLINE_NOTES", "", false)
    local m_tbl = (ok_m and m_str ~= "") and deserialize_table(m_str) or nil
    if m_tbl and #m_tbl > 0 then
      local id_remap, batch = {}, {}
      for _, mn in ipairs(m_tbl) do
        local nid = state.next_note_id; state.next_note_id = state.next_note_id + 1; id_remap[mn.id] = nid
        table.insert(batch, make_default_note({ id=nid, selected=true, muted=mn.muted, start_qn=mn.start_qn, end_qn=mn.end_qn, pitch=mn.pitch, vel=mn.vel, chan=mn.chan,
          section_uid=mn.section_uid, section_override=mn.section_override, t1=mn.t1, pre_st=mn.pre_st, t2=mn.t2, t3=mn.t3, t4=mn.t4, out_st=mn.out_st,
          pre_shape=mn.pre_shape, pre_tension=mn.pre_tension, out_shape=mn.out_shape, out_tension=mn.out_tension, connect_to_id=mn.connect_to_id, vibrato=mn.vibrato }))
      end
      for _, nn in ipairs(batch) do if nn.connect_to_id then nn.connect_to_id = id_remap[nn.connect_to_id] end; table.insert(imported, nn) end
      lossless_cnt = lossless_cnt + #batch
    else
      local ok_c, cuid = reaper.GetSetMediaItemInfo_String(it, "P_EXT:N2N_COMMITTED_UID", "", false); local tk = reaper.GetActiveTake(it)
      if tk and reaper.TakeIsMIDI(tk) then
        local _, nc, cc = reaper.MIDI_CountEvts(tk); local pb_ev = {}
        for ci = 0, cc - 1 do local cok, _, _, ppq, cm, ch, m2, m3 = reaper.MIDI_GetCC(tk, ci); if cok and (cm & 0xF0) == 0xE0 then table.insert(pb_ev, {qn=reaper.MIDI_GetProjQNFromPPQPos(tk,ppq),ch=ch,st=(((m3<<7)|m2)-8192)/8191.0*state.mpe_bend_range}) end end
        for ni = 0, nc - 1 do
          local nok, _, muted, sp, ep, chan, pitch, vel = reaper.MIDI_GetNote(tk, ni)
          if nok then
            local sq = reaper.MIDI_GetProjQNFromPPQPos(tk, sp); local eq = math.max(sq + 0.0625, reaper.MIDI_GetProjQNFromPPQPos(tk, ep))
            local sec = (ok_c and cuid ~= "" and get_section_by_uid(cuid)) or find_section_at_qn(sq); local ps, os = 0.0, 0.0
            for _, pb in ipairs(pb_ev) do if pb.ch == chan then if math.abs(pb.qn - sq) < 0.05 then ps = pb.st end; if math.abs(pb.qn - eq) < 0.05 then os = pb.st end end end
            table.insert(imported, make_default_note({ id=state.next_note_id, selected=true, muted=muted, start_qn=sq, end_qn=eq, pitch=pitch, vel=clamp(vel,1,127), chan=chan,
              section_uid=sec and sec.uid or state.selected_section_uid, section_override=(ok_c and cuid ~= "" and sec ~= nil), pre_st=math.floor(ps*4+0.5)*0.25, out_st=math.floor(os*4+0.5)*0.25 }))
            state.next_note_id = state.next_note_id + 1
          end
        end
      end
    end
  end
  if #imported == 0 then state.status_msg = "No MIDI notes found on track"; return end
  if mode == "replace" then state.notes = imported else for _, n in ipairs(imported) do table.insert(state.notes, n) end end
  local _, tn = reaper.GetTrackName(tr); compute_section_overflows(); sync_section_clips()
  state.status_msg = string.format("Loaded %d note(s) (%s%s) from [%s]", #imported, mode, lossless_cnt > 0 and ", lossless MPE" or "", tn)
end

local function write_vlq(val)
  val = math.max(0, math.floor(val + 0.5)); local bytes = { val & 0x7F }; val = val >> 7
  while val > 0 do table.insert(bytes, 1, (val & 0x7F) | 0x80); val = val >> 7 end
  local out = {}; for i = 1, #bytes do out[i] = string.char(bytes[i]) end; return table.concat(out)
end
local function u32_be(v) return string.char((v>>24)&0xFF, (v>>16)&0xFF, (v>>8)&0xFF, v&0xFF) end
local function u16_be(v) return string.char((v>>8)&0xFF, v&0xFF) end

local function export_topline_mid()
  local fp = ""
  if reaper.JS_Dialog_BrowseForSaveFile then local ok, fn = reaper.JS_Dialog_BrowseForSaveFile("Export Topline MIDI (.mid)", "", "N2N_Topline_Melody.mid", "MIDI Files (*.mid)\0*.mid\0"); if not ok or fn == "" then return end; fp = fn
  else local ok, fn = reaper.GetUserInputs("Export Topline .mid", 1, "Output .mid path:,extrawidth=200", reaper.GetProjectPath("") .. "/N2N_Topline_Melody.mid"); if not ok or fn == "" then return end; fp = fn end
  if not fp:lower():match("%.mid$") then fp = fp .. ".mid" end
  reallocate_all_mpe_channels()
  local PPQ, events = 480, {}
  local function add_ev(qn, order, bytes) table.insert(events, { tick = math.max(0, math.floor(qn * PPQ + 0.5)), order = order, bytes = bytes }) end
  local upq = math.floor(60000000 / math.max(20, reaper.Master_GetTempo()) + 0.5)
  add_ev(0, 0, string.char(0xFF, 0x51, 0x03, (upq>>16)&0xFF, (upq>>8)&0xFF, upq&0xFF))
  local _, num, denom = reaper.TimeMap_GetTimeSigAtTime(0, 0)
  add_ev(0, 0, string.char(0xFF, 0x58, 0x04, math.floor(num or 4), math.floor(math.log(math.max(1, denom or 4))/math.log(2)+0.5), 24, 8))

  local roots, ch_starts = {}, {}
  for _, n in ipairs(state.notes) do if not n.muted and get_incoming_note(n.id) == nil then table.insert(roots, n) end end
  for _, r in ipairs(roots) do local sq = get_chain_span_qn(r); local ss = reaper.TimeMap2_QNToTime(0, math.max(0, sq + compute_groove_swing_offset_qn(sq))); ch_starts[r.chan] = ch_starts[r.chan] or {}; table.insert(ch_starts[r.chan], ss) end
  for _, l in pairs(ch_starts) do table.sort(l) end
  local tail_sec = (state.mpe_release_tail_ms or 500) / 1000.0

  for _, root in ipairs(roots) do
    local s_qn, e_qn = get_chain_span_qn(root); local off = compute_groove_swing_offset_qn(s_qn)
    local out_s, out_e, ch = math.max(0, s_qn + off), math.max(0.05, e_qn + off), clamp(root.chan, 0, 15)
    add_ev(out_s, 3, string.char(0x90 + ch, clamp(root.pitch, 0, 127), clamp(root.vel, 1, 127)))
    add_ev(out_e, 2, string.char(0x80 + ch, clamp(root.pitch, 0, 127), 0))
    if note_or_chain_has_bend(root) then
      local s_sec, e_sec = reaper.TimeMap2_QNToTime(0, out_s), reaper.TimeMap2_QNToTime(0, out_e)
      local steps = clamp(math.floor(math.max(0.02, e_sec - s_sec) * 80), 24, 240)
      for step = 0, steps do
        local t = step / steps; local st = eval_chain_bend_at_qn(root, lerp(s_qn, e_qn, t), s_qn, e_qn)
        local v14 = clamp(math.floor(8192 + clamp(st / state.mpe_bend_range, -1, 1) * 8191 + 0.5), 0, 16383)
        add_ev(lerp(out_s, out_e, t), 1, string.char(0xE0 + ch, v14 & 0x7F, (v14 >> 7) & 0x7F))
      end
      local nxt_s = nil; for _, st in ipairs(ch_starts[root.chan] or {}) do if st > e_sec - 0.004 then nxt_s = st break end end
      local reset_sec = nxt_s and math.max(e_sec + 0.002, math.min(e_sec + tail_sec, nxt_s - 0.012)) or (e_sec + tail_sec)
      add_ev(math.max(out_e + 0.005, reaper.TimeMap2_timeToQN(0, reset_sec)), 1, string.char(0xE0 + ch, 0, 64))
    end
  end
  table.sort(events, function(a, b) if a.tick == b.tick then return a.order < b.order end; return a.tick < b.tick end)
  local trk, prev_tick = {}, 0
  for _, ev in ipairs(events) do trk[#trk + 1] = write_vlq(ev.tick - prev_tick) .. ev.bytes; prev_tick = ev.tick end
  trk[#trk + 1] = write_vlq(0) .. string.char(0xFF, 0x2F, 0x00)
  local td = table.concat(trk); local f = io.open(fp, "wb"); if not f then state.status_msg = "Failed to write .mid"; return end
  f:write("MThd" .. u32_be(6) .. u16_be(0) .. u16_be(1) .. u16_be(PPQ) .. "MTrk" .. u32_be(#td) .. td); f:close()
  state.status_msg = "Exported Topline -> " .. fp:match("[^/\\]+$")
end

local function migrate_legacy_hidden_clip_if_needed()
  local htr = find_track_by_name(HIDDEN_TRACK_NAME) or find_track_by_name(LEGACY_HIDDEN_NAME); if not htr then return end
  local migrated = false
  for i = reaper.CountTrackMediaItems(htr) - 1, 0, -1 do
    local it = reaper.GetTrackMediaItem(htr, i); local ok, uid = reaper.GetSetMediaItemInfo_String(it, "P_EXT:N2N_SECTION_UID", "", false)
    if not ok or uid == "" then
      local tk = reaper.GetActiveTake(it)
      if tk and reaper.TakeIsMIDI(tk) then
        local _, nc = reaper.MIDI_CountEvts(tk)
        for ni = 0, nc - 1 do
          local nok, _, muted, sp, ep, chan, pitch, vel = reaper.MIDI_GetNote(tk, ni)
          if nok then
            local sq, eq = reaper.MIDI_GetProjQNFromPPQPos(tk, sp), reaper.MIDI_GetProjQNFromPPQPos(tk, ep); local sec = find_section_at_qn(sq)
            table.insert(state.notes, make_default_note({ id=state.next_note_id, muted=muted, start_qn=sq, end_qn=math.max(sq+0.125, eq), pitch=pitch, vel=clamp(vel,1,127), chan=chan, section_uid=sec and sec.uid or state.selected_section_uid }))
            state.next_note_id = state.next_note_id + 1
          end
        end
      end
      reaper.DeleteTrackMediaItem(htr, it); migrated = true
    end
  end
  if migrated then sync_section_clips() end
end

--------------------------------------------------------------------------------
-- 8. SECTIONS, CHORD CHARTS & OUTPUT TRACK
--------------------------------------------------------------------------------
local function compute_section_overflows()
  for _, sec in ipairs(state.sections) do local ov = 0; for _, n in ipairs(state.notes) do if n.section_uid == sec.uid and n.end_qn > sec.end_qn + 1e-4 then ov = ov + 1 end end; sec.overflow_cnt = ov end
end

local function refresh_regions_and_sections()
  local reaper_regs, idx = {}, 0
  while true do
    local retval, isrgn, pos_sec, rgnend_sec, name, markrgn_num, color = reaper.EnumProjectMarkers3(0, idx)
    if retval == 0 then break end
    if isrgn and rgnend_sec > pos_sec then
      local _, _, cml = reaper.TimeMap2_timeToBeats(0, pos_sec); local rgb = { 0.42, 0.50, 0.62 }
      if color and color ~= 0 then local r, g, b = reaper.ColorFromNative(color); rgb = { r/255, g/255, b/255 } end
      table.insert(reaper_regs, { markrgn_num=markrgn_num, start_qn=reaper.TimeMap2_timeToQN(0, pos_sec), end_qn=reaper.TimeMap2_timeToQN(0, rgnend_sec), pos_sec=pos_sec, bar_qn=(cml and cml>0) and cml or 4.0, name=(name and name~="") and name or ("Region "..tostring(markrgn_num)), rgb=rgb })
    end
    idx = idx + 1
  end
  table.sort(reaper_regs, function(a, b) return a.start_qn < b.start_qn end)

  local notes_shifted, shortened_warn, matched_sec = false, nil, {}
  for _, rr in ipairs(reaper_regs) do
    local found_s = nil
    for _, s in ipairs(state.sections) do if not matched_sec[s.uid] and s.markrgn_num == rr.markrgn_num then found_s = s break end end
    if not found_s then local bd = 1e9; for _, s in ipairs(state.sections) do if not matched_sec[s.uid] and s.name == rr.name then local d = math.abs(s.start_qn-rr.start_qn); if d<bd then bd=d; found_s=s end end end end
    if found_s then
      matched_sec[found_s.uid] = true; local delta = rr.start_qn - (found_s.prev_start_qn or found_s.start_qn)
      if math.abs(delta) > 1e-4 then
        for _, n in ipairs(state.notes) do if n.section_uid == found_s.uid then n.start_qn = math.max(0, n.start_qn + delta); n.end_qn = math.max(n.start_qn + 0.0625, n.end_qn + delta) end end
        notes_shifted = true
      end
      local prev_len = (found_s.prev_end_qn or found_s.end_qn) - (found_s.prev_start_qn or found_s.start_qn)
      found_s.name, found_s.start_qn, found_s.end_qn, found_s.prev_start_qn, found_s.prev_end_qn = rr.name, rr.start_qn, rr.end_qn, rr.start_qn, rr.end_qn
      found_s.pos_sec, found_s.bar_qn, found_s.rgb, found_s.deleted = rr.pos_sec, rr.bar_qn, rr.rgb, false
      if (rr.end_qn - rr.start_qn) < prev_len - 1e-4 then shortened_warn = found_s end
    else
      local uid = "sec_" .. tostring(state.next_section_seq) .. "_" .. tostring(rr.markrgn_num); state.next_section_seq = state.next_section_seq + 1; matched_sec[uid] = true
      table.insert(state.sections, { uid=uid, markrgn_num=rr.markrgn_num, name=rr.name, start_qn=rr.start_qn, end_qn=rr.end_qn, prev_start_qn=rr.start_qn, prev_end_qn=rr.end_qn, pos_sec=rr.pos_sec, bar_qn=rr.bar_qn, rgb=rr.rgb, deleted=false, overflow_cnt=0 })
    end
  end
  for i = #state.sections, 1, -1 do
    local s = state.sections[i]; if not matched_sec[s.uid] then local hn = false; for _, n in ipairs(state.notes) do if n.section_uid == s.uid then hn = true break end end; if hn then s.deleted = true else table.remove(state.sections, i) end end
  end
  table.sort(state.sections, function(a, b) return a.start_qn < b.start_qn end); compute_section_overflows()
  if shortened_warn and shortened_warn.overflow_cnt > 0 then state.status_msg = string.format("Warning: '%s' shortened; %d note(s) overflow", shortened_warn.name, shortened_warn.overflow_cnt) end
  if notes_shifted then sync_section_clips() end
  local ok_sel = false; for _, s in ipairs(state.sections) do if not s.deleted and s.uid == state.selected_section_uid then ok_sel = true break end end
  if not ok_sel then state.selected_section_uid = nil; for _, s in ipairs(state.sections) do if not s.deleted then state.selected_section_uid = s.uid break end end end
end

local function read_text_items_from_track(tr)
  local list, tc = {}, reaper.GetTrackColor(tr); local tr_rgb = { 0.45, 0.52, 0.62 }
  if tc ~= 0 then local r, g, b = reaper.ColorFromNative(tc); tr_rgb = { r/255, g/255, b/255 } end
  for i = 0, reaper.CountTrackMediaItems(tr) - 1 do
    local it = reaper.GetTrackMediaItem(tr, i); local p, l = reaper.GetMediaItemInfo_Value(it, "D_POSITION"), reaper.GetMediaItemInfo_Value(it, "D_LENGTH")
    local _, txt = reaper.GetSetMediaItemInfo_String(it, "P_NOTES", "", false); local ci = reaper.GetMediaItemInfo_Value(it, "I_CUSTOMCOLOR"); local rgb = tr_rgb
    if ci ~= 0 then local r, g, b = reaper.ColorFromNative(ci); rgb = { r/255, g/255, b/255 } end
    table.insert(list, { start_qn=reaper.TimeMap2_timeToQN(0,p), end_qn=reaper.TimeMap2_timeToQN(0,p+l), text=trim(txt):gsub("\r?\n"," "), rgb=rgb })
  end
  table.sort(list, function(a, b) return a.start_qn < b.start_qn end); return list
end

local function refresh_chord_charts()
  state.has_nns_chart, state.has_letter_chart, state.nns_chart_items, state.letter_chart_items = false, false, {}, {}
  for i = 0, reaper.CountTracks(0) - 1 do
    local tr = reaper.GetTrack(0, i); local _, name = reaper.GetTrackName(tr); local c = trim(name)
    if c == "N2N Nashville # Chart" then state.has_nns_chart = true; state.nns_chart_items = read_text_items_from_track(tr)
    elseif c == "N2N Letter Chart" then state.has_letter_chart = true; state.letter_chart_items = read_text_items_from_track(tr) end
  end
end

local function load_track_note_names(tr)
  state.track_note_names = {}; if not tr or not reaper.ValidatePtr2(0, tr, "MediaTrack*") then return end
  for p = 0, 127 do local nm = reaper.GetTrackMIDINoteNameEx(0, tr, p, 0); if nm and nm ~= "" then state.track_note_names[p] = nm end end
end

local function restore_auto_arm_track()
  for tr, s in pairs(state.saved_track_states) do
    if reaper.ValidatePtr2(owner_project, tr, "MediaTrack*") then reaper.SetMediaTrackInfo_Value(tr, "I_RECARM", s.recarm); reaper.SetMediaTrackInfo_Value(tr, "I_RECMON", s.recmon); reaper.SetMediaTrackInfo_Value(tr, "I_RECINPUT", s.recinput) end
  end
  state.saved_track_states = {}
end

local function apply_auto_arm_if_enabled(tr)
  restore_auto_arm_track(); if not state.auto_arm_preview or not tr or not reaper.ValidatePtr2(0, tr, "MediaTrack*") then return end
  state.saved_track_states[tr] = { recarm=reaper.GetMediaTrackInfo_Value(tr,"I_RECARM"), recmon=reaper.GetMediaTrackInfo_Value(tr,"I_RECMON"), recinput=reaper.GetMediaTrackInfo_Value(tr,"I_RECINPUT") }
  if reaper.GetMediaTrackInfo_Value(tr, "I_RECINPUT") < 4096 then reaper.SetMediaTrackInfo_Value(tr, "I_RECINPUT", 4096 | (63 << 5)) end
  reaper.SetMediaTrackInfo_Value(tr, "I_RECMON", 1); reaper.SetMediaTrackInfo_Value(tr, "I_RECARM", 1)
end

local function select_output_track(tr)
  if tr and reaper.ValidatePtr2(0, tr, "MediaTrack*") then local _, tn = reaper.GetTrackName(tr); if tn == HIDDEN_TRACK_NAME then return end end
  if not tr or not reaper.ValidatePtr2(0, tr, "MediaTrack*") then
    restore_auto_arm_track(); state.output_track = nil; state.output_track_guid = ""; state.track_note_names = {}; update_hidden_track_send(); save_project_state(); return
  end
  state.output_track = tr; state.output_track_guid = reaper.GetTrackGUID(tr)
  ensure_hidden_track(); update_hidden_track_send(); apply_auto_arm_if_enabled(tr); load_track_note_names(tr)
  local _, tr_name = reaper.GetTrackName(tr); state.status_msg = "Output Track -> [" .. tr_name .. "]"; save_project_state()
end

local function send_bend_range_rpn(semitones)
  local st = clamp(math.floor(semitones), 0, 127)
  for ch = (state.mpe_enabled and state.mpe_chan_min or 0), (state.mpe_enabled and state.mpe_chan_max or 0) do
    reaper.StuffMIDIMessage(0, 0xB0+ch, 101, 0); reaper.StuffMIDIMessage(0, 0xB0+ch, 100, 0); reaper.StuffMIDIMessage(0, 0xB0+ch, 6, st); reaper.StuffMIDIMessage(0, 0xB0+ch, 38, 0)
  end
  state.status_msg = string.format("Sent RPN 0,0 (±%d st); verify instrument matches", st)
end

--------------------------------------------------------------------------------
-- 9. PREVIEW & gmem HARMONY
--------------------------------------------------------------------------------
local function send_midi_note_on(pitch, vel, chan) reaper.StuffMIDIMessage(0, 0x90+clamp(math.floor(chan or 0),0,15), clamp(math.floor(pitch),0,127), clamp(math.floor(vel or 100),1,127)) end
local function send_midi_note_off(pitch, chan) reaper.StuffMIDIMessage(0, 0x80+clamp(math.floor(chan or 0),0,15), clamp(math.floor(pitch),0,127), 0) end

local function check_preview_arm_hint()
  if state.output_track and reaper.ValidatePtr2(0, state.output_track, "MediaTrack*") and not state.auto_arm_preview then
    if reaper.GetMediaTrackInfo_Value(state.output_track, "I_RECARM") == 0 or reaper.GetMediaTrackInfo_Value(state.output_track, "I_RECMON") == 0 then
      state.status_msg = "Hint: Arm & Monitor output track (or enable Auto-Arm in Out:) for click sound"
    end
  end
end

local function trigger_preview_note(pitch, vel, chan, duration)
  chan = chan or 0
  for i = #state.previews, 1, -1 do local pr = state.previews[i]; if pr.pitch == pitch and pr.chan == chan then send_midi_note_off(pr.pitch, pr.chan); table.remove(state.previews, i) end end
  send_midi_note_on(pitch, vel or 100, chan); table.insert(state.previews, { pitch=pitch, chan=chan, expire=reaper.time_precise()+(duration or 0.22) }); check_preview_arm_hint()
end

local function update_previews()
  local now = reaper.time_precise()
  for i = #state.previews, 1, -1 do if now >= state.previews[i].expire then send_midi_note_off(state.previews[i].pitch, state.previews[i].chan); table.remove(state.previews, i) end end
end

local function on_script_exit()
  if hub_exited then return end
  hub_exited=true
  if reaper.GetExtState(HUB_EXT_SEC,"owner")==hub_token then
    reaper.DeleteExtState(HUB_EXT_SEC,"owner",false)
    reaper.DeleteExtState(HUB_EXT_SEC,"heartbeat",false)
    reaper.DeleteExtState(HUB_EXT_SEC,"focus",false)
  end
  for _, pr in ipairs(state.previews) do send_midi_note_off(pr.pitch, pr.chan) end; state.previews = {}
  if state.kbd_held_pitch then send_midi_note_off(state.kbd_held_pitch, state.kbd_held_chan); state.kbd_held_pitch = nil end
  save_global_prefs()
  -- The original project may have been closed. Never save into a different tab.
  local i=0
  while true do
    local p=reaper.EnumProjects(i,"")
    if not p then break end
    if p==owner_project then restore_auto_arm_track(); save_project_state(); break end
    i=i+1
  end
end

local function apply_n2n_default_key()
  state.tonic_pc = clamp(math.floor(state.gmem_tonic_pc or 0), 0, 11)
  local step = (clamp(math.floor(state.gmem_modal_center or 0), 0, 11) - state.tonic_pc) % 12
  for i, m in ipairs(CONFIG.modes) do if m.center_step == step then state.mode_idx = i break end end; rebuild_row_layout()
end

local function read_gmem_harmony(force_report)
  reaper.gmem_attach(GMEM_NAMESPACE)
  local raw_cnt, rel_tonic, modal_center = reaper.gmem_read(GMEM_CHORD_BASE+1), reaper.gmem_read(GMEM_CHORD_BASE+2), reaper.gmem_read(GMEM_CHORD_BASE+3)
  local scale_cnt, rev_word = reaper.gmem_read(GMEM_SCALE_BASE+1), reaper.gmem_read(GMEM_CHORD_BASE+4)
  if not is_finite(raw_cnt) then return false end
  local count = math.floor(raw_cnt); if count < 0 or count > 32768 then return false end
  if is_finite(rel_tonic) and rel_tonic >= 0 and rel_tonic <= 11 then state.gmem_tonic_pc = math.floor(rel_tonic); state.gmem_has_key = true end
  if is_finite(modal_center) and modal_center >= 0 and modal_center <= 11 then state.gmem_modal_center = math.floor(modal_center) end
  local f_p, f_s = (count > 0) and reaper.gmem_read(GMEM_CHORD_BASE+10) or -1, (count > 0) and reaper.gmem_read(GMEM_CHORD_BASE+11) or -1
  local l_idx = GMEM_CHORD_BASE + 10 + math.max(0, count-1)*4
  local sig = string.format("%d:%d:%d:%.2f:%.2f:%.2f:%.2f:%.2f:%d", count, state.gmem_tonic_pc, state.gmem_modal_center, rev_word or 0, f_p, f_s, (count>0) and reaper.gmem_read(l_idx) or -1, (count>0) and reaper.gmem_read(l_idx+2) or -1, math.floor(scale_cnt or 0))
  if not force_report and sig == state.gmem_sig then return false end; state.gmem_sig = sig

  local guides, max_end_qn, idx = {}, 0, GMEM_CHORD_BASE + 10
  for i = 0, count - 1 do
    local pitch, raw_s, raw_e = reaper.gmem_read(idx), reaper.gmem_read(idx+1), reaper.gmem_read(idx+2); idx = idx + 4
    if is_finite(pitch) and is_finite(raw_s) and is_finite(raw_e) then
      local p = math.floor(pitch + 0.5)
      if p >= 0 and p <= 127 and raw_e > raw_s then local sq = round_guide_start_to_32nd(raw_s); local eq = math.max(sq + 0.125, raw_e); if eq > max_end_qn then max_end_qn = eq end; table.insert(guides, {pitch=p,pc=p%12,start_qn=sq,end_qn=eq}) end
    end
  end
  if is_finite(scale_cnt) and scale_cnt > 0 and scale_cnt <= 8192 then local ls = reaper.gmem_read(GMEM_SCALE_BASE+2+(math.floor(scale_cnt)-1)*2); if is_finite(ls) and ls > max_end_qn then max_end_qn = ls end end
  state.gmem_guides, state.gmem_song_end_qn = guides, max_end_qn
  if state.sync_key_from_gmem and state.gmem_has_key then apply_n2n_default_key() end
  if count > 0 then state.status_msg = string.format("N2N Pref: %d harmony guides (1=%s)", #guides, CONFIG.note_names[state.gmem_tonic_pc+1]) end; return true
end

local function pull_clip_as_harmony_guides()
  local item = reaper.GetSelectedMediaItem(0, 0); local tk = item and reaper.GetActiveTake(item)
  if not tk or not reaper.TakeIsMIDI(tk) then local ed = reaper.MIDIEditor_GetActive(); tk = ed and reaper.MIDIEditor_GetTake(ed) end
  if not tk or not reaper.TakeIsMIDI(tk) then state.status_msg = "No MIDI clip selected" return false end
  local guides, _, nc = {}, reaper.MIDI_CountEvts(tk)
  for i = 0, nc - 1 do
    local ok, _, muted, sp, ep, _, pitch = reaper.MIDI_GetNote(tk, i)
    if ok and not muted then local rs, re = reaper.MIDI_GetProjQNFromPPQPos(tk, sp), reaper.MIDI_GetProjQNFromPPQPos(tk, ep); if re > rs then local sq = round_guide_start_to_32nd(rs); table.insert(guides, {pitch=pitch,pc=pitch%12,start_qn=sq,end_qn=math.max(sq+0.125, re)}) end end
  end
  state.clip_guides, state.harmony_source = guides, "clip_pulled"; save_project_state(); state.status_msg = string.format("Pulled %d Mid-Layer harmony guides", #guides); return true
end

--------------------------------------------------------------------------------
-- 10. EDITING, UNDO/REDO, OWNERSHIP, REPETITION & PHRASE COPY/PASTE
--------------------------------------------------------------------------------
local function clone_notes_list(list)
  local out = {}
  for _, n in ipairs(list) do
    local vc = { enabled=n.vibrato.enabled, rate=n.vibrato.rate, depth_cents=n.vibrato.depth_cents, delay=n.vibrato.delay, ramp=n.vibrato.ramp, curve=n.vibrato.curve, pattern=n.vibrato.pattern or "consistent" }
    table.insert(out, make_default_note({ id=n.id, selected=n.selected, muted=n.muted, start_qn=n.start_qn, end_qn=n.end_qn, pitch=n.pitch, vel=n.vel, chan=n.chan,
      section_uid=n.section_uid, section_override=n.section_override, t1=n.t1, pre_st=n.pre_st, t2=n.t2, t3=n.t3, t4=n.t4, out_st=n.out_st,
      pre_shape=n.pre_shape, pre_tension=n.pre_tension, out_shape=n.out_shape, out_tension=n.out_tension, connect_to_id=n.connect_to_id, vibrato=vc }))
  end
  return out
end

local function push_undo() table.insert(state.undo_stack, clone_notes_list(state.notes)); if #state.undo_stack > 60 then table.remove(state.undo_stack, 1) end; state.redo_stack = {} end
local function pop_undo() if #state.undo_stack == 0 then return end; table.insert(state.redo_stack, clone_notes_list(state.notes)); state.notes = table.remove(state.undo_stack); compute_section_overflows(); sync_section_clips(); state.status_msg = "Undo" end
local function pop_redo() if #state.redo_stack == 0 then return end; table.insert(state.undo_stack, clone_notes_list(state.notes)); state.notes = table.remove(state.redo_stack); compute_section_overflows(); sync_section_clips(); state.status_msg = "Redo" end
local function get_selected_notes() local r = {}; for _, n in ipairs(state.notes) do if n.selected then table.insert(r, n) end end; return r end
local function deselect_all() for _, n in ipairs(state.notes) do n.selected = false end end
local function select_all() for _, n in ipairs(state.notes) do n.selected = true end end

local function toggle_mute_selected()
  local sel = get_selected_notes(); if #sel == 0 then return end; push_undo()
  local any_unmuted = false; for _, n in ipairs(sel) do if not n.muted then any_unmuted = true break end end
  for _, n in ipairs(sel) do n.muted = any_unmuted end; sync_section_clips()
  state.status_msg = any_unmuted and string.format("Muted %d note(s)", #sel) or string.format("Unmuted %d note(s)", #sel)
end

local function remove_note_by_index(idx)
  local v = state.notes[idx]; if not v then return end
  if v.connect_to_id then disconnect_note_outgoing(v) end; local inc = get_incoming_note(v.id); if inc then disconnect_note_outgoing(inc) end; table.remove(state.notes, idx)
end

local function get_repetition_start_qns(base_qn, sec, use_shift, use_ctrl)
  local out = { base_qn }; if not sec or (not use_shift and not use_ctrl) then return out end
  local bar_qn, seen = sec.bar_qn or 4.0, {}
  local function add_qn(q) local k = math.floor(q*1000+0.5); if not seen[k] and q >= sec.start_qn-1e-4 and q < sec.end_qn-1e-4 then seen[k]=true; table.insert(out, q) end end
  add_qn(base_qn)
  if use_shift then local q = sec.start_qn + ((base_qn - sec.start_qn) % bar_qn); while q < sec.end_qn - 1e-4 do add_qn(q); q = q + bar_qn end end
  if use_ctrl then local s4 = bar_qn*4; local q = sec.start_qn + ((base_qn - sec.start_qn) % s4); while q < sec.end_qn - 1e-4 do add_qn(q); q = q + s4 end end
  table.sort(out); return out
end

local function delete_selected()
  if #get_selected_notes() == 0 then return end; push_undo()
  local rem = 0; for i = #state.notes, 1, -1 do if state.notes[i].selected then remove_note_by_index(i); rem = rem + 1 end end
  compute_section_overflows(); sync_section_clips(); state.status_msg = string.format("Deleted %d note(s)", rem)
end

local function clear_all_content()
  if reaper.ShowMessageBox("Clear all notes and manual harmony guides in N2N Topline?\n\n(You can undo this with Ctrl+Z.)", "N2N Topline — Confirm Clear All", 4) ~= 6 then return end
  push_undo(); state.notes = {}; state.manual_harmony_notes = {}; compute_section_overflows(); sync_section_clips(); state.status_msg = "Cleared all content"
end

local function copy_notes_to_buf(src_notes, ref_qn)
  local buf, id_to_idx = {}, {}; for i, n in ipairs(src_notes) do id_to_idx[n.id] = i end
  for _, n in ipairs(src_notes) do
    local vc = { enabled=n.vibrato.enabled, rate=n.vibrato.rate, depth_cents=n.vibrato.depth_cents, delay=n.vibrato.delay, ramp=n.vibrato.ramp, curve=n.vibrato.curve, pattern=n.vibrato.pattern or "consistent" }
    table.insert(buf, { rel_start=n.start_qn-ref_qn, dur=n.end_qn-n.start_qn, pitch=n.pitch, vel=n.vel, t1=n.t1, pre_st=n.pre_st, t2=n.t2, t3=n.t3, t4=n.t4, out_st=n.out_st,
      pre_shape=n.pre_shape, pre_tension=n.pre_tension, out_shape=n.out_shape, out_tension=n.out_tension, connect_to_idx=id_to_idx[n.connect_to_id], section_override=n.section_override, vibrato=vc })
  end
  return buf
end

local function copy_selected()
  local sel = get_selected_notes(); if #sel == 0 then return end
  local mq = math.huge; for _, n in ipairs(sel) do mq = math.min(mq, n.start_qn) end
  state.clipboard = copy_notes_to_buf(sel, mq); state.status_msg = string.format("Copied %d note(s)", #state.clipboard)
end

local function paste_items_at_base(items, base_qn, target_sec_uid, sec_bounds)
  if #items == 0 then return 0 end; local created = {}
  for i, c in ipairs(items) do
    local sq = math.max(0, base_qn + c.rel_start); local own_uid, is_ov = target_sec_uid, false
    if not own_uid then local sec = find_section_at_qn(sq); own_uid = sec and sec.uid or state.selected_section_uid
    elseif sec_bounds then is_ov = (c.section_override or sq < sec_bounds.start_qn - 1e-4 or sq >= sec_bounds.end_qn - 1e-4) end
    local vc = { enabled=c.vibrato.enabled, rate=c.vibrato.rate, depth_cents=c.vibrato.depth_cents, delay=c.vibrato.delay, ramp=c.vibrato.ramp, curve=c.vibrato.curve, pattern=c.vibrato.pattern or "consistent" }
    local n = make_default_note({ id=state.next_note_id, selected=true, start_qn=sq, end_qn=sq+c.dur, pitch=c.pitch, vel=c.vel, section_uid=own_uid, section_override=is_ov,
      t1=c.t1, pre_st=c.pre_st, t2=c.t2, t3=c.t3, t4=c.t4, out_st=c.out_st, pre_shape=c.pre_shape, pre_tension=c.pre_tension, out_shape=c.out_shape, out_tension=c.out_tension, vibrato=vc })
    state.next_note_id = state.next_note_id + 1; table.insert(state.notes, n); created[i] = n
  end
  for i, c in ipairs(items) do if c.connect_to_idx and created[c.connect_to_idx] then created[i].connect_to_id = created[c.connect_to_idx].id end end
  return #created
end

local function paste_notes(target_qn)
  if #state.clipboard == 0 then return end; push_undo(); deselect_all()
  local cnt = paste_items_at_base(state.clipboard, target_qn or snap_qn(state.scroll_x_qn + 1), nil, nil)
  compute_section_overflows(); sync_section_clips(); state.status_msg = string.format("Pasted %d note(s)", cnt)
end

local function duplicate_selected()
  local sel = get_selected_notes(); if #sel == 0 then return end
  local min_qn, max_qn = math.huge, -math.huge; for _, n in ipairs(sel) do min_qn = math.min(min_qn, n.start_qn); max_qn = math.max(max_qn, n.end_qn) end
  copy_selected(); paste_notes(min_qn + math.max(get_grid_qn(), snap_qn(max_qn - min_qn)))
end

local function count_section_notes(sec_uid) local c=0; for _,n in ipairs(state.notes) do if n.section_uid==sec_uid then c=c+1 end end; return c end
local function copy_section_notes(sec)
  local owned = {}; for _, n in ipairs(state.notes) do if n.section_uid == sec.uid then table.insert(owned, n) end end
  state.section_clipboard = copy_notes_to_buf(owned, sec.start_qn); state.status_msg = string.format("Copied %d note(s) owned by [%s]", #state.section_clipboard, sec.name)
end
local function paste_section_notes(sec)
  if #state.section_clipboard == 0 then return end; push_undo(); deselect_all(); state.selected_section_uid = sec.uid
  local cnt = paste_items_at_base(state.section_clipboard, sec.start_qn, sec.uid, sec); compute_section_overflows(); sync_section_clips()
  state.status_msg = string.format("Pasted %d note(s) into [%s]", cnt, sec.name)
end

local function get_phrase_owned_notes(sec, p_start_qn, p_end_qn, is_first, is_last)
  local list = {}
  for _, n in ipairs(state.notes) do
    local in_win = (n.start_qn >= p_start_qn - 1e-4 and n.start_qn < p_end_qn - 1e-4)
    local is_pickup = is_first and (n.section_uid == sec.uid and n.start_qn < sec.start_qn - 1e-4)
    local is_trailing = is_last and (n.section_uid == sec.uid and n.start_qn >= sec.end_qn - 1e-4)
    if is_pickup or is_trailing then table.insert(list, n)
    elseif in_win and not (n.section_override and n.section_uid ~= sec.uid) and (n.section_uid == sec.uid or n.section_uid == nil) then table.insert(list, n) end
  end
  return list
end

local function copy_phrase_notes(sec, ps, pe, is_f, is_l, lbl)
  state.phrase_clipboard = copy_notes_to_buf(get_phrase_owned_notes(sec, ps, pe, is_f, is_l), ps)
  state.status_msg = string.format("Copied %d phrase note(s) [%s]", #state.phrase_clipboard, lbl)
end

local function paste_phrase_notes(sec, ps, pe, is_f, is_l, lbl, mode)
  if #state.phrase_clipboard == 0 then return end; mode = mode or state.phrase_paste_mode; push_undo(); deselect_all()
  if mode == "replace" then
    local drop = {}; for _, n in ipairs(get_phrase_owned_notes(sec, ps, pe, is_f, is_l)) do drop[n.id] = true end
    for k = #state.notes, 1, -1 do if drop[state.notes[k].id] then remove_note_by_index(k) end end
  end
  local cnt = paste_items_at_base(state.phrase_clipboard, ps, sec.uid, sec); compute_section_overflows(); sync_section_clips()
  state.status_msg = string.format("Pasted (%s) %d note(s) -> [%s]", mode, cnt, lbl)
end

local function quantize_selected()
  local sel = get_selected_notes(); if #sel == 0 then sel = state.notes end; if #sel == 0 then return end; push_undo(); local g = get_grid_qn()
  for _, n in ipairs(sel) do
    local dur = n.end_qn - n.start_qn; n.start_qn = snap_qn(n.start_qn); n.end_qn = math.max(n.start_qn + g*0.25, n.start_qn + dur)
    if not n.section_override then local s = find_section_at_qn(n.start_qn); if s then n.section_uid = s.uid end end
  end
  compute_section_overflows(); sync_section_clips(); state.status_msg = "Quantized notes to grid"
end

local function step_pitch_diatonic(pitch, dir) local p = pitch + dir; while p >= 0 and p <= 127 do if is_pitch_diatonic(p) then return p end; p = p + dir end; return pitch end

local function move_selected_by_arrows(d_pitch, d_grid, shift_held, alt_held, ctrl_held)
  local sel = get_selected_notes(); if #sel == 0 then return end; push_undo()
  local g, preview_target, rejected = get_grid_qn(), nil, false
  for _, n in ipairs(sel) do
    local old_p = n.pitch
    if d_pitch ~= 0 then
      if ctrl_held then n.pitch = clamp(n.pitch + (d_pitch > 0 and 12 or -12), 0, 127)
      elseif state.view_mode == "diatonic" and not alt_held then n.pitch = step_pitch_diatonic(n.pitch, d_pitch > 0 and 1 or -1)
      else n.pitch = clamp(n.pitch + d_pitch, 0, 127) end
      if not validate_chain_bend_range(get_chain_root(n)) then n.pitch = old_p; rejected = true else preview_target = n end
    end
    if shift_held and d_grid ~= 0 then n.end_qn = math.max(n.start_qn + g*0.25, n.end_qn + d_grid*g)
    elseif d_grid ~= 0 then
      local dur = n.end_qn - n.start_qn; n.start_qn = math.max(0, n.start_qn + d_grid*g); n.end_qn = n.start_qn + dur
      if not n.section_override then local s = find_section_at_qn(n.start_qn); if s then n.section_uid = s.uid end end; preview_target = n
    end
  end
  if rejected then state.status_msg = string.format("Blocked: exceeds ±%d st range", state.mpe_bend_range)
  elseif preview_target then trigger_preview_note(preview_target.pitch, preview_target.vel, preview_target.chan, 0.22) end
  compute_section_overflows(); sync_section_clips()
end

--------------------------------------------------------------------------------
-- 11. VECTOR & ANTI-ALIASED CURVE PRIMITIVES
--------------------------------------------------------------------------------
local function draw_filled_roundrect(x, y, w, h, r)
  x, y, w, h = math.floor(x+0.5), math.floor(y+0.5), math.floor(w+0.5), math.floor(h+0.5); if w <= 0 or h <= 0 then return end
  r = math.floor(math.min(r or 5, w/2, h/2)); if r <= 1 then gfx.rect(x, y, w, h, 1); return end
  gfx.rect(x+r, y, w-2*r, h, 1); gfx.rect(x, y+r, r, h-2*r, 1); gfx.rect(x+w-r, y+r, r, h-2*r, 1)
  gfx.circle(x+r, y+r, r, 1, 1); gfx.circle(x+w-r-1, y+r, r, 1, 1); gfx.circle(x+r, y+h-r-1, r, 1, 1); gfx.circle(x+w-r-1, y+h-r-1, r, 1, 1)
end

local function draw_bordered_roundrect(x, y, w, h, r, bp, bcol, fcol, fa)
  set_col(bcol, fa or 1.0); draw_filled_roundrect(x, y, w, h, r); local b = bp or 1.5
  if w > b*2+2 and h > b*2+2 then set_col(fcol, fa or 1.0); draw_filled_roundrect(x+b, y+b, w-b*2, h-b*2, math.max(1, r-b)) end
end

local function draw_dashed_line(x1, y1, x2, y2, dash, gap)
  local dx, dy = x2-x1, y2-y1; local len = math.sqrt(dx*dx+dy*dy); if len < 1 then return end; local ux, uy, pos = dx/len, dy/len, 0
  while pos < len do local pe = math.min(pos+dash, len); gfx.line(x1+ux*pos, y1+uy*pos, x1+ux*pe, y1+uy*pe, 1); pos = pos+dash+gap end
end

local function draw_dashed_roundrect(x, y, w, h, r, dash, gap)
  r = math.min(r or 5, w/2, h/2); dash = dash or 5; gap = gap or 4
  draw_dashed_line(x+r, y, x+w-r, y, dash, gap); draw_dashed_line(x+r, y+h, x+w-r, y+h, dash, gap)
  draw_dashed_line(x, y+r, x, y+h-r, dash, gap); draw_dashed_line(x+w, y+r, x+w, y+h-r, dash, gap)
  gfx.arc(x+r, y+r, r, -math.pi/2, 0, 1); gfx.arc(x+w-r, y+r, r, 0, math.pi/2, 1)
  gfx.arc(x+w-r, y+h-r, r, math.pi/2, math.pi, 1); gfx.arc(x+r, y+h-r, r, math.pi, 1.5*math.pi, 1)
end

local function draw_thick_aa_curve(pts, col, alpha)
  if #pts < 2 then return end
  set_col(col, (alpha or 1.0) * 0.28)
  for i = 1, #pts - 1 do local x1,y1,x2,y2=pts[i][1],pts[i][2],pts[i+1][1],pts[i+1][2]; local dx,dy=x2-x1,y2-y1; local l=math.sqrt(dx*dx+dy*dy); if l>0.2 then local nx,ny=(-dy/l)*1.4,(dx/l)*1.4; gfx.line(x1+nx,y1+ny,x2+nx,y2+ny,1); gfx.line(x1-nx,y1-ny,x2-nx,y2-ny,1) end end
  set_col(col, alpha or 1.0)
  for i = 1, #pts - 1 do local x1,y1,x2,y2=pts[i][1],pts[i][2],pts[i+1][1],pts[i+1][2]; local dx,dy=x2-x1,y2-y1; local l=math.sqrt(dx*dx+dy*dy); if l>0.2 then local nx,ny=(-dy/l)*0.7,(dx/l)*0.7; gfx.line(x1,y1,x2,y2,1); gfx.line(x1+nx,y1+ny,x2+nx,y2+ny,1); gfx.line(x1-nx,y1-ny,x2-nx,y2-ny,1) end end
end

local function draw_text_centered(str, x, y, w, h) local tw, th = gfx.measurestr(str); gfx.x, gfx.y = math.floor(x+(w-tw)*0.5), math.floor(y+(h-th)*0.5); gfx.drawstr(str, 0, x+w, y+h) end
local function draw_text_left(str, x, y, w, h) local _, th = gfx.measurestr(str); gfx.x, gfx.y = math.floor(x), math.floor(y+(h-th)*0.5); gfx.drawstr(str, 0, x+w, y+h) end
local function draw_text_right(str, x, y, w, h) local tw, th = gfx.measurestr(str); gfx.x, gfx.y = math.floor(x+w-tw), math.floor(y+(h-th)*0.5); gfx.drawstr(str, 0, x+w, y+h) end

local function register_btn(id, x, y, w, h, label, active, on_click, custom_active_bg, custom_rest_bg, on_right_click)
  local bx, by, bw, bh = x, y, w, h
  table.insert(state.ui_controls, { id=id, x=bx, y=by, w=bw, h=bh, on_click=on_click and function() on_click(bx,by,bw,bh) end or nil, on_right_click=on_right_click and function() on_right_click(bx,by,bw,bh) end or nil })
  local hov = gfx.mouse_x >= bx and gfx.mouse_x <= bx + bw and gfx.mouse_y >= by and gfx.mouse_y <= by + bh
  local act_col = custom_active_bg or {0.22, 0.45, 0.78}
  local rest_col = custom_rest_bg or (CONFIG.dark_mode and {0.20, 0.22, 0.26} or {0.93, 0.94, 0.96})
  local hov_col = custom_rest_bg and mix_rgb(custom_rest_bg, {1,1,1}, 0.14) or (CONFIG.dark_mode and {0.25, 0.27, 0.32} or {0.88, 0.90, 0.94})
  local bg = active and act_col or (hov and hov_col or rest_col)
  set_col(bg); draw_filled_roundrect(bx, by, bw, bh, 6)
  set_col((active or custom_rest_bg) and contrast_text_col(bg) or (CONFIG.dark_mode and {0.88,0.90,0.94} or {0.18,0.21,0.26}))
  gfx.setfont(1, "Segoe UI", 14); draw_text_centered(label, bx, by, bw, bh)
end

local function draw_slider(id, x, y, w, h, val, min_v, max_v, label, fmt, on_change)
  table.insert(state.ui_controls, { id=id, x=x, y=y, w=w, h=h, is_slider=true, min_v=min_v, max_v=max_v, on_change=on_change })
  local t = clamp((val - min_v) / (max_v - min_v), 0, 1)
  set_col(CONFIG.dark_mode and {0.22,0.24,0.29} or {0.88,0.90,0.93}); draw_filled_roundrect(x, y, w, h, 5)
  set_col({0.26,0.52,0.85}, 0.85); draw_filled_roundrect(x, y, math.max(6, w*t), h, 5)
  set_col(CONFIG.dark_mode and {0.92,0.94,0.97} or {0.16,0.18,0.22}); gfx.setfont(1, "Segoe UI", 13)
  draw_text_left(string.format(fmt or "%s: %.2f", label, val), x+7, y, w-14, h)
end

--------------------------------------------------------------------------------
-- 12. UI SECTIONS
--------------------------------------------------------------------------------
local function apply_window_frame_style()
  if not state.hwnd or not reaper.JS_Window_SetStyle then return end
  if state.use_frameless and gfx.dock(-1) == 0 then
    -- Windows SIZEBOX creates a native non-client border above the custom bar.
    -- Our own resize grip handles resizing without that bright strip.
    reaper.JS_Window_SetStyle(state.hwnd, IS_MAC and "POPUP,SIZEBOX" or "POPUP")
    state.frameless = true; state.titlebar_h = 28
  else
    reaper.JS_Window_SetStyle(state.hwnd, "CAPTION,SIZEBOX,SYSMENU,MAXIMIZEBOX,MINIMIZEBOX")
    state.frameless = false; state.titlebar_h = 0
  end
end

local function draw_custom_titlebar_and_resize_grip()
  if not state.frameless or state.titlebar_h <= 0 then return end
  local h = state.titlebar_h
  set_col(CONFIG.dark_mode and {0.08,0.09,0.11} or {0.90,0.91,0.94}); gfx.rect(0, 0, gfx.w, h, 1)
  set_col(CONFIG.dark_mode and {0.20,0.22,0.26} or {0.80,0.82,0.86}); gfx.line(0, h - 1, gfx.w, h - 1)
  gfx.setfont(1, "Segoe UI", 13); set_col(CONFIG.dark_mode and {0.78,0.82,0.88} or {0.22,0.24,0.28})
  draw_text_left(WIN_TITLE, 12, 0, gfx.w - 80, h)
  local cx, cy = gfx.w - 18, h * 0.5
  local hov = math.abs(gfx.mouse_x - cx) <= 8 and math.abs(gfx.mouse_y - cy) <= 8
  table.insert(state.ui_controls, { id = "win_close", x = cx - 9, y = cy - 9, w = 18, h = 18, on_click = function() state.should_close = true end })
  set_col(hov and {0.95,0.35,0.35} or {0.85,0.29,0.29}); gfx.circle(cx, cy, 7, 1, 1)
  set_col(CONFIG.dark_mode and {0.50,0.54,0.62} or {0.55,0.58,0.64}, 0.75)
  gfx.line(gfx.w - 13, gfx.h - 3, gfx.w - 3, gfx.h - 13); gfx.line(gfx.w - 9, gfx.h - 3, gfx.w - 3, gfx.h - 9); gfx.line(gfx.w - 5, gfx.h - 3, gfx.w - 3, gfx.h - 5)
end

local function draw_toolbar()
  local ty = state.titlebar_h
  set_col(CONFIG.dark_mode and {0.13,0.14,0.17} or {0.98,0.98,0.99}); gfx.rect(0, ty, gfx.w, state.toolbar_h, 1)
  set_col(CONFIG.dark_mode and {0.22,0.24,0.28} or {0.86,0.88,0.91}); gfx.line(0, ty + state.toolbar_h - 1, gfx.w, ty + state.toolbar_h - 1)
  local x, y, h = 8, ty + 12, 26

  register_btn("file_menu", x, y, 50, h, "File", false, function(bx, by, bw, bh)
    gfx.x, gfx.y = bx, by + bh; local tracks, rep_sub, mrg_sub = {}, "", ""
    for i = 0, reaper.CountTracks(0) - 1 do local tr = reaper.GetTrack(0, i); local _, tn = reaper.GetTrackName(tr); if tn ~= HIDDEN_TRACK_NAME then table.insert(tracks, tr); local l = string.format("%d: %s|", i+1, tn); rep_sub = rep_sub..l; mrg_sub = mrg_sub..l end end
    local ch = gfx.showmenu(">Load MIDI from Track (Replace)|" .. rep_sub .. "<|>Load MIDI from Track (Merge)|" .. mrg_sub .. "<|Export Topline (.mid)...||Clear All Content...")
    local n_tr = #tracks
    if ch >= 1 and ch <= n_tr then push_undo(); load_midi_from_track(tracks[ch], "replace")
    elseif ch >= n_tr + 1 and ch <= n_tr * 2 then push_undo(); load_midi_from_track(tracks[ch - n_tr], "merge")
    elseif ch == n_tr * 2 + 1 then export_topline_mid() elseif ch == n_tr * 2 + 2 then clear_all_content() end
  end); x = x + 54

  local out_lbl = "Out: None"
  if state.output_track and reaper.ValidatePtr2(0, state.output_track, "MediaTrack*") then local _, tn = reaper.GetTrackName(state.output_track); out_lbl = "Out: " .. tn:sub(1, 11) end
  register_btn("out_track", x, y, 114, h, out_lbl, state.output_track ~= nil, function(bx, by, bw, bh)
    gfx.x, gfx.y = bx, by + bh; local menu = (state.output_track == nil and "!" or "") .. "None (Clear Send)|" .. (state.auto_arm_preview and "!" or "") .. "Auto-Arm Out Track for Click Preview|>Select Output Track|"; local tracks = {}
    for i = 0, reaper.CountTracks(0) - 1 do local tr = reaper.GetTrack(0, i); local _, tn = reaper.GetTrackName(tr); if tn ~= HIDDEN_TRACK_NAME then table.insert(tracks, tr); menu = menu .. (state.output_track == tr and "!" or "") .. string.format("%d: %s|", i+1, tn) end end
    local choice = gfx.showmenu(menu .. "<")
    if choice == 1 then select_output_track(nil) elseif choice == 2 then state.auto_arm_preview = not state.auto_arm_preview; apply_auto_arm_if_enabled(state.output_track); save_project_state()
    elseif choice >= 3 and choice <= #tracks + 2 then select_output_track(tracks[choice - 2]) end
  end); x = x + 118

  local cm_lbl, cm_col, cm_act = "Commit", nil, false
  if state.commit_state == "committed" then cm_lbl = (state.audition_mode == "draft") and "Draft Audition" or "Committed ✓"; cm_col = (state.audition_mode == "draft") and {0.22,0.45,0.78} or {0.18,0.56,0.34}; cm_act = true
  elseif state.commit_state == "dirty" then cm_lbl, cm_col, cm_act = "Recommit*", {0.78,0.48,0.14}, true end
  local function open_commit_menu(bx, by, bw, bh)
    gfx.x, gfx.y = bx, by + bh
    local c = gfx.showmenu(string.format("%s|>Audition Playback|%sDraft (Hidden Track)|%sCommitted (Output Track)|<|Clear N2N Committed Clips from Output Track",
      (state.commit_state == "none") and "Commit Clips to Output Track" or "Recommit Updated Clips to Output Track",
      (state.audition_mode == "draft" or state.commit_state == "none") and "!" or "", (state.audition_mode == "committed" and state.commit_state ~= "none") and "!" or ""))
    if c == 1 then commit_clips_to_output_track() elseif c == 2 then state.audition_mode = "draft"; apply_audition_mute_routing(); save_project_state(); state.status_msg = "Auditioning Draft (Hidden Track)"
    elseif c == 3 then state.audition_mode = "committed"; apply_audition_mute_routing(); save_project_state(); state.status_msg = "Auditioning Committed Track Clips" elseif c == 4 then clear_committed_clips_from_output_track() end
  end
  register_btn("commit_btn", x, y, 90, h, cm_lbl, cm_act, function(bx, by, bw, bh) if state.commit_state == "committed" then open_commit_menu(bx, by, bw, bh) else commit_clips_to_output_track() end end, cm_col, nil, open_commit_menu); x = x + 94

  local is_dia = (state.view_mode == "diatonic")
  register_btn("mode_btn", x, y, 78, h, is_dia and "Diatonic" or "Chromatic", is_dia, function() state.view_mode = is_dia and "chromatic" or "diatonic"; rebuild_row_layout(); save_global_prefs(); save_project_state() end); x = x + 82

  register_btn("nns_key", x, y, 72, h, (state.sync_key_from_gmem and "N2N " or "") .. string.format("1=%s", CONFIG.note_names[state.tonic_pc + 1]), state.sync_key_from_gmem, function(bx, by, bw, bh)
    gfx.x, gfx.y = bx, by + bh
    local n2n_str = state.gmem_has_key and string.format("Numbers2Notes Default Key (gmem 1=%s)", CONFIG.note_names[state.gmem_tonic_pc + 1]) or "Numbers2Notes Default Key (from gmem)"
    local menu = (state.sync_key_from_gmem and "!" or "") .. n2n_str .. "|>Manual Tonic (1 = Major Root)|"
    for pc = 0, 11 do menu = menu .. ((not state.sync_key_from_gmem and state.tonic_pc == pc) and "!" or "") .. CONFIG.note_names[pc + 1] .. " Major|" end
    menu = menu .. "<|>Manual Relative Mode (NNS Center)|"
    for i, m in ipairs(CONFIG.modes) do menu = menu .. ((not state.sync_key_from_gmem and state.mode_idx == i) and "!" or "") .. string.format("%s [%s/%s]|", m.name, m.nns_center, CONFIG.note_names[(state.tonic_pc + m.center_step)%12 + 1]) end
    local c = gfx.showmenu(menu .. "<")
    if c == 1 then state.sync_key_from_gmem = true; read_gmem_harmony(true); apply_n2n_default_key()
    elseif c >= 2 and c <= 13 then state.sync_key_from_gmem = false; state.tonic_pc = c - 2; rebuild_row_layout()
    elseif c >= 14 and c <= 13 + #CONFIG.modes then state.sync_key_from_gmem = false; state.mode_idx = c - 13 end
    save_project_state()
  end); x = x + 76

  for _, tl in ipairs({{id="draw",label="Draw"},{id="select",label="Select"},{id="harmony",label="Harmony"},{id="mpe",label="MPE"}}) do
    register_btn("tool_" .. tl.id, x, y, 56, h, tl.label, state.tool == tl.id, function() state.tool = tl.id end); x = x + 60
  end

  local g_lbl = "Grid:" .. CONFIG.grid_options[state.grid_idx].label .. (state.triplet and "T" or "") .. (state.snap and "" or " (Free)")
  local g_w = state.snap and 72 or 100
  register_btn("grid_menu", x, y, g_w, h, g_lbl, false, function(bx, by, bw, bh)
    gfx.x, gfx.y = bx, by + bh; local menu = ""
    for i, opt in ipairs(CONFIG.grid_options) do menu = menu .. (state.grid_idx == i and "!" or "") .. opt.label .. "|" end
    local ch = gfx.showmenu(menu .. "|" .. (state.triplet and "!" or "") .. "Triplet (T)|" .. (state.snap and "!" or "") .. "Snap to Grid")
    if ch >= 1 and ch <= #CONFIG.grid_options then state.grid_idx = ch elseif ch == #CONFIG.grid_options + 1 then state.triplet = not state.triplet elseif ch == #CONFIG.grid_options + 2 then state.snap = not state.snap end
    save_global_prefs()
  end); x = x + g_w + 4

  register_btn("triplet_btn", x, y, 26, h, "T", state.triplet, function() state.triplet = not state.triplet; save_global_prefs() end); x = x + 30

  local play_teal = { 20/255, 102/255, 102/255 }
  register_btn("bend_range_btn", x, y, 60, h, string.format("±%dst%s", state.mpe_bend_range, state.instrument_bend_verified and "✓" or "?"), false, function(bx, by, bw, bh)
    gfx.x, gfx.y = bx, by + bh; local menu = ""
    for _, br in ipairs(CONFIG.bend_ranges) do menu = menu .. (state.mpe_bend_range == br and "!" or "") .. string.format("Bend Range: ±%d st|", br) end
    local c = gfx.showmenu(menu .. "|Send RPN 0,0 (±" .. state.mpe_bend_range .. " st) to Instrument|" .. (state.instrument_bend_verified and "!" or "") .. "Confirm Instrument Matches ±" .. state.mpe_bend_range .. " st")
    if c >= 1 and c <= #CONFIG.bend_ranges then if CONFIG.bend_ranges[c] ~= state.mpe_bend_range then state.mpe_bend_range = CONFIG.bend_ranges[c]; state.instrument_bend_verified = false; save_global_prefs(); sync_section_clips() end
    elseif c == #CONFIG.bend_ranges + 1 then send_bend_range_rpn(state.mpe_bend_range) elseif c == #CONFIG.bend_ranges + 2 then state.instrument_bend_verified = not state.instrument_bend_verified; save_project_state() end
  end, play_teal, play_teal); x = x + 64

  register_btn("autoscroll_btn", x, y, 74, h, "AutoScroll", state.auto_scroll, function() state.auto_scroll = not state.auto_scroll; save_global_prefs() end); x = x + 78
  register_btn("clear_sel_btn", x, y, 66, h, "Clear Sel", false, function() deselect_all(); state.status_msg = "Selection cleared" end); x = x + 70
  register_btn("open_instrument", x, y, 116, h, "Open Instrument", false, function()
    local tr=state.output_track
    if tr and reaper.ValidatePtr2(owner_project,tr,"MediaTrack*") then
      local fx=reaper.TrackFX_GetInstrument(tr)
      if fx>=0 then reaper.TrackFX_Show(tr,fx,3);return end
    end
    state.status_msg="Select an output track with an instrument first."
  end); x=x+120

  local deleted_secs = {}; for _, s in ipairs(state.sections) do if s.deleted then table.insert(deleted_secs, s) end end
  if #deleted_secs > 0 then
    register_btn("orphan_btn", x, y, 80, h, "Orphan(" .. #deleted_secs .. ")", true, function(bx, by, bw, bh)
      gfx.x, gfx.y = bx, by + bh; local dsec = deleted_secs[1]
      local c = gfx.showmenu(string.format("#Deleted Region: %s (%d notes)|Keep Orphaned|Reassign to Auto|Delete Notes & Clip", dsec.name, count_section_notes(dsec.uid)))
      if c == 3 then push_undo(); for _, n in ipairs(state.notes) do if n.section_uid == dsec.uid then local t = find_section_at_qn(n.start_qn); n.section_uid = t and t.uid or nil; n.section_override = false end end; for k = #state.sections, 1, -1 do if state.sections[k].uid == dsec.uid then table.remove(state.sections, k) break end end; sync_section_clips()
      elseif c == 4 then push_undo(); for k = #state.notes, 1, -1 do if state.notes[k].section_uid == dsec.uid then remove_note_by_index(k) end end; for k = #state.sections, 1, -1 do if state.sections[k].uid == dsec.uid then table.remove(state.sections, k) break end end; sync_section_clips() end
    end, {0.82, 0.25, 0.25})
  end

  register_btn("drawer_btn", gfx.w - 94, y, 86, h, "Preferences", state.show_drawer, function() state.show_drawer = not state.show_drawer; save_global_prefs() end)
end

local function draw_regions_bar(canvas_w)
  local ry, left_x, right_x = state.titlebar_h + state.toolbar_h, state.keyboard_w, get_grid_right_x(canvas_w)
  local border = CONFIG.dark_mode and {0.22,0.24,0.28} or {0.86,0.88,0.91}
  set_col(CONFIG.dark_mode and {0.14,0.15,0.19} or {0.95,0.96,0.98}); gfx.rect(0, ry, canvas_w, state.regions_h, 1)
  gfx.setfont(1, "Segoe UI", 12); set_col(CONFIG.dark_mode and {0.72,0.76,0.84} or {0.36,0.40,0.46})
  draw_text_centered("Active Section", 4, ry + 2, left_x - 8, state.regions_h * 0.5)
  draw_text_centered("4-Bar Phrases", 4, ry + state.regions_h * 0.5, left_x - 8, state.regions_h * 0.5 - 2)

  local prev_right = -1
  for i, sec in ipairs(state.sections) do
    if not sec.deleted then
      local sx, ex = qn_to_screen_x(sec.start_qn), qn_to_screen_x(sec.end_qn)
      if ex > left_x and sx < right_x then
        local cx, ce = math.max(left_x, sx), math.min(right_x, ex); local cw = ce - cx
        if cw >= 4 then
          local ovs = (cx < prev_right - 1) and 4 or 0; local btn_y, btn_h = ry + 2 + ovs, state.regions_h - 4 - ovs
          local top_half_h = math.floor(btn_h * 0.5); local sub_y, sub_h = btn_y + top_half_h + 1, btn_h - top_half_h - 3
          local is_sel = (state.selected_section_uid == sec.uid)
          local hov = gfx.mouse_x >= cx and gfx.mouse_x <= cx + cw and gfx.mouse_y >= btn_y and gfx.mouse_y <= btn_y + top_half_h

          table.insert(state.ui_controls, {
            id = "sec_" .. i, x = cx, y = btn_y, w = cw, h = btn_h,
            on_click = function()
              local shifted=(gfx.mouse_cap&8)~=0
              state.cue_section(sec,shifted and 1 or 0,shifted)
            end,
            on_right_click = function()
              gfx.x, gfx.y = gfx.mouse_x, gfx.mouse_y; local r_cnt, sel_cnt = count_section_notes(sec.uid), #get_selected_notes()
              local ch = gfx.showmenu(string.format("Set REAPER Loop to Section [%s]|Copy Section Owned Notes (%d)|%sPaste Copied Notes to Section (%d)|%sAssign Selected Notes (%d) to Section [Override]|Select All Notes Owned by Section (%d)|Clear Notes in Section",
                sec.name, r_cnt, (#state.section_clipboard==0) and "#" or "", #state.section_clipboard, (sel_cnt==0) and "#" or "", sel_cnt, r_cnt))
              if ch == 1 then reaper.GetSet_LoopTimeRange(true, true, sec.pos_sec, reaper.TimeMap2_QNToTime(0, sec.end_qn), false); reaper.GetSetRepeat(1); state.status_msg = "Looped Section -> [" .. sec.name .. "]"
              elseif ch == 2 then copy_section_notes(sec) elseif ch == 3 then paste_section_notes(sec)
              elseif ch == 4 then push_undo(); for _, n in ipairs(state.notes) do if n.selected then n.section_uid = sec.uid; n.section_override = true end end; compute_section_overflows(); sync_section_clips()
              elseif ch == 5 then deselect_all(); for _, n in ipairs(state.notes) do if n.section_uid == sec.uid then n.selected = true end end
              elseif ch == 6 and r_cnt > 0 then push_undo(); for k = #state.notes, 1, -1 do if state.notes[k].section_uid == sec.uid then remove_note_by_index(k) end end; compute_section_overflows(); sync_section_clips() end
            end
          })

          if hov then state.hover_section(sec,cx,btn_y,cw,top_half_h) end
          local fill_col = hov and mix_rgb(sec.rgb, {1,1,1}, 0.16) or sec.rgb
          draw_bordered_roundrect(cx + 1, btn_y, cw - 2, btn_h, 7, is_sel and 2.5 or 1.0, is_sel and (CONFIG.dark_mode and {1,0.90,0.35} or {0.10,0.12,0.16}) or mix_rgb(sec.rgb,{0,0,0},0.25), fill_col, is_sel and 1.0 or 0.86)
          if cw > 26 then
            local tc = contrast_text_col(fill_col); set_col(tc); gfx.setfont(1, "Segoe UI", is_sel and 14 or 13)
            local cnt = count_section_notes(sec.uid); local warn = (sec.overflow_cnt and sec.overflow_cnt > 0) and " [!]" or ""
            draw_text_centered((cnt>0 and cw>96) and string.format("%s (%d)%s", sec.name, cnt, warn) or (sec.name .. warn), cx+6, btn_y+1, cw-12, top_half_h)
            if is_sel and cw > 40 then set_col(tc, 0.95); gfx.circle(cx + 11, btn_y + 1 + top_half_h * 0.5, 3.5, 1, 1) end
          end

          local bar_qn = sec.bar_qn or 4.0; local phrase_qn = bar_qn * 4.0; local total_phrases = math.max(1, math.ceil((sec.end_qn - sec.start_qn - 1e-4) / phrase_qn))
          local p_start, pidx = sec.start_qn, 1
          while p_start < sec.end_qn - 1e-4 do
            local p_end = math.min(sec.end_qn, p_start + phrase_qn); local is_f, is_l = (pidx==1), (pidx==total_phrases)
            local psx, pex = qn_to_screen_x(p_start), qn_to_screen_x(p_end)
            if pex > left_x and psx < right_x then
              local pcx, pcw = math.max(left_x+2, psx+2), math.min(right_x-2, pex-2) - math.max(left_x+2, psx+2)
              if pcw >= 8 and sub_h >= 12 then
                local bar_a = (pidx - 1) * 4 + 1; local bar_b = bar_a + math.max(1, math.floor((p_end - p_start) / bar_qn + 0.5)) - 1
                local p_lbl = (bar_a == bar_b) and tostring(bar_a) or string.format("%d-%d", bar_a, bar_b); local full_lbl = string.format("%s [%s]", sec.name, p_lbl)
                local p_hov = gfx.mouse_x >= pcx and gfx.mouse_x <= pcx + pcw and gfx.mouse_y >= sub_y and gfx.mouse_y <= sub_y + sub_h
                local is_ps = state.selected_phrase and state.selected_phrase.section_uid == sec.uid and math.abs(state.selected_phrase.start_qn - p_start) < 1e-4
                local csec, cs, ce2, cf, cl, clbl = sec, p_start, p_end, is_f, is_l, full_lbl
                table.insert(state.ui_controls, {
                  id = string.format("phr_%d_%d", i, pidx), x = pcx, y = sub_y, w = pcw, h = sub_h,
                  on_click = function()
                    state.selected_phrase = { section_uid=csec.uid, start_qn=cs, end_qn=ce2, label=clbl }; reaper.SetEditCurPos(reaper.TimeMap2_QNToTime(0, cs), true, true)
                    state.status_msg = string.format("Selected Phrase %s (%d owned notes)", clbl, #get_phrase_owned_notes(csec, cs, ce2, cf, cl))
                  end,
                  on_right_click = function()
                    gfx.x, gfx.y = gfx.mouse_x, gfx.mouse_y; state.selected_phrase = { section_uid=csec.uid, start_qn=cs, end_qn=ce2, label=clbl }
                    local pn = get_phrase_owned_notes(csec, cs, ce2, cf, cl); local pf = (#state.phrase_clipboard==0) and "#" or ""
                    local ch = gfx.showmenu(string.format("Set REAPER Loop to Phrase %s|Copy Phrase %s (%d)|%sPaste Phrase (Replace - %d)|%sPaste Phrase (Merge - %d)|>%s|!%s|%s<|Select Phrase Notes (%d)|Clear Phrase Notes",
                      clbl, clbl, #pn, pf, #state.phrase_clipboard, pf, #state.phrase_clipboard, "Default Paste: "..(state.phrase_paste_mode=="replace" and "Replace" or "Merge"),
                      state.phrase_paste_mode=="replace" and "Replace (Default)" or "Merge", state.phrase_paste_mode=="replace" and "Merge" or "Replace (Default)", #pn))
                    if ch==1 then reaper.GetSet_LoopTimeRange(true, true, reaper.TimeMap2_QNToTime(0, cs), reaper.TimeMap2_QNToTime(0, ce2), false); reaper.GetSetRepeat(1); state.status_msg = "Looped Phrase -> " .. clbl
                    elseif ch==2 then copy_phrase_notes(csec,cs,ce2,cf,cl,clbl) elseif ch==3 then paste_phrase_notes(csec,cs,ce2,cf,cl,clbl,"replace")
                    elseif ch==4 then paste_phrase_notes(csec,cs,ce2,cf,cl,clbl,"merge") elseif ch==5 or ch==6 then state.phrase_paste_mode=(state.phrase_paste_mode=="replace") and "merge" or "replace"; save_global_prefs()
                    elseif ch==7 then deselect_all(); for _,n in ipairs(pn) do n.selected=true end
                    elseif ch==8 and #pn>0 then push_undo(); local d={}; for _,n in ipairs(pn) do d[n.id]=true end; for k=#state.notes,1,-1 do if d[state.notes[k].id] then remove_note_by_index(k) end end; compute_section_overflows(); sync_section_clips() end
                  end
                })
                local sfill = is_ps and mix_rgb(sec.rgb,{1,1,1},0.35) or (p_hov and mix_rgb(sec.rgb,{1,1,1},0.22) or mix_rgb(sec.rgb,{0,0,0},0.14))
                draw_bordered_roundrect(pcx, sub_y, pcw, sub_h, 4, is_ps and 2.0 or 1.0, is_ps and {1,0.90,0.25} or mix_rgb(sec.rgb,{1,1,1},0.35), sfill, 0.95)
                if pcw > 20 then set_col(contrast_text_col(sfill)); gfx.setfont(1, "Segoe UI", 11); draw_text_centered(p_lbl, pcx+2, sub_y, pcw-4, sub_h) end
              end
            end
            p_start = p_end; pidx = pidx + 1
          end
          prev_right = ce
        end
      end
    end
  end
  set_col(border, 0.75); gfx.line(0, ry + state.regions_h - 1, canvas_w, ry + state.regions_h - 1)
end

local function draw_chord_lanes_and_reserved(canvas_w)
  local y, left_x, right_x = state.titlebar_h + state.toolbar_h + state.regions_h, state.keyboard_w, get_grid_right_x(canvas_w)
  local border, bg_lane = CONFIG.dark_mode and {0.22,0.24,0.28} or {0.86,0.88,0.91}, CONFIG.dark_mode and {0.13,0.14,0.18} or {0.96,0.97,0.98}
  local function draw_chart(title, items)
    set_col(bg_lane); gfx.rect(0, y, canvas_w, state.chord_lane_h, 1)
    gfx.setfont(1, "Segoe UI", 12); set_col(CONFIG.dark_mode and {0.72,0.76,0.84} or {0.36,0.40,0.46}); draw_text_left(title, 8, y, left_x - 14, state.chord_lane_h)
    for _, it in ipairs(items) do
      local sx, ex = qn_to_screen_x(it.start_qn), qn_to_screen_x(it.end_qn)
      if ex > left_x and sx < right_x then
        local cx = math.max(left_x, sx); local cw = math.min(right_x - 2, ex) - cx
        if cw >= 6 then set_col(it.rgb, 0.92); draw_filled_roundrect(cx+1, y+2, cw-2, state.chord_lane_h-4, 4); if it.text ~= "" and cw > 18 then set_col(contrast_text_col(it.rgb)); gfx.setfont(1, "Segoe UI", 13); draw_text_centered(it.text, cx+4, y+2, cw-8, state.chord_lane_h-4) end end
      end
    end
    set_col(border, 0.7); gfx.line(0, y + state.chord_lane_h - 1, canvas_w, y + state.chord_lane_h - 1); y = y + state.chord_lane_h
  end
  if state.has_nns_chart then draw_chart("N2N # Chart", state.nns_chart_items) end
  if state.has_letter_chart then draw_chart("N2N Letters", state.letter_chart_items) end
  set_col(CONFIG.dark_mode and {0.12,0.13,0.16} or {0.97,0.97,0.99}); gfx.rect(0, y, canvas_w, state.reserved_h, 1)
  set_col(border, 0.7); gfx.line(0, y + state.reserved_h - 1, canvas_w, y + state.reserved_h - 1)
end

local function draw_ruler(canvas_w)
  local ry, right_x = get_ruler_y(), get_grid_right_x(canvas_w)
  local bg, txt = CONFIG.dark_mode and {0.16,0.17,0.21} or {0.95,0.95,0.97}, CONFIG.dark_mode and {0.75,0.78,0.84} or {0.35,0.38,0.44}
  set_col(bg); gfx.rect(state.keyboard_w, ry, right_x - state.keyboard_w, state.ruler_h, 1)
  if state.selected_phrase then local psx, pex = math.max(state.keyboard_w, qn_to_screen_x(state.selected_phrase.start_qn)), math.min(right_x, qn_to_screen_x(state.selected_phrase.end_qn)); if pex > psx then set_col({0.95,0.78,0.18}, 0.28); gfx.rect(psx, ry, pex-psx, state.ruler_h, 1) end end
  gfx.setfont(1, "Segoe UI", 13)
  for qn = math.max(0, math.floor(state.scroll_x_qn)), math.ceil(screen_x_to_qn(right_x) + 1) do
    local sx = qn_to_screen_x(qn)
    if sx >= state.keyboard_w and sx <= right_x then local is_bar = (qn % 4 == 0); set_col(txt, is_bar and 0.9 or 0.45); gfx.line(sx, ry + (is_bar and 3 or 12), sx, ry + state.ruler_h); if is_bar then gfx.x, gfx.y = sx + 5, ry + 2; gfx.drawstr(tostring(math.floor(qn / 4) + 1)) end end
  end
  set_col(bg); gfx.rect(0, ry, state.keyboard_w, state.ruler_h, 1)
  set_col(txt, 0.85); draw_text_left("Pitch", 12, ry, 70, state.ruler_h); draw_text_right("NNS", 12, ry, state.keyboard_w - 24, state.ruler_h)
end

local function draw_keyboard(grid_bottom_y)
  local top_area = get_top_area_y(); gfx.setfont(1, "Segoe UI", 13)
  for p = 127, 0, -1 do
    local rh = state.row_h[p]
    if rh > 0 then
      local sy = pitch_to_screen_y(p); local cy1, cy2 = math.max(top_area, sy + 1), math.min(grid_bottom_y - 1, sy + rh - 1)
      if cy2 > cy1 then
        local cols = get_step_colors(get_rel_step(p)); local is_hov = (state.hover_pitch == p or state.kbd_held_pitch == p); local kw, kf = state.keyboard_w - 10, (is_hov and cols.key_bright or cols.key_mid)
        if state.piano_keys then
          local black=not is_pitch_diatonic(p)
          kw=black and math.floor(kw*.72) or kw
          kf=black and (is_hov and {0.28,0.28,0.30} or {0.12,0.12,0.14}) or (is_hov and {0.78,0.83,0.88} or {0.91,0.91,0.91})
        end
        set_col(kf); draw_filled_roundrect(4, cy1, kw, cy2 - cy1, 4); set_col(cols.active, 1.0); draw_filled_roundrect(4, cy1 + 1, 6, math.max(2, cy2 - cy1 - 2), 2)
        if is_hov then set_col(CONFIG.dark_mode and {1,1,1} or {0.12,0.14,0.18}, 0.95); gfx.roundrect(4, cy1, kw, cy2 - cy1, 4, 1); gfx.roundrect(5, cy1 + 1, kw - 2, math.max(1, cy2 - cy1 - 2), 3, 1) end
        if cy2 - cy1 >= 14 and sy >= top_area - 4 then local ll, rl = get_key_left_right_labels(p); set_col(contrast_text_col(kf)); draw_text_left(ll, 14, cy1, kw - 38, cy2 - cy1); draw_text_right(rl, 14, cy1, kw - 20, cy2 - cy1) end
      end
    end
  end
end

local function draw_harmony_span_block(cx, hy, cw, h_vis, cols, top_area, grid_bottom_y)
  local cy1, cy2 = math.max(top_area, hy), math.min(grid_bottom_y - 1, hy + h_vis); if cy2 <= cy1 + 2 then return end
  set_col(cols.harmony, 0.88); draw_filled_roundrect(cx, cy1, cw, cy2 - cy1, 5); set_col(cols.harmony_dash, 0.95)
  if state.harmony_border_style == "solid" then gfx.roundrect(math.floor(cx+0.5), math.floor(cy1+0.5), math.floor(cw+0.5), math.floor((cy2-cy1)+0.5), 5, 1) else draw_dashed_roundrect(cx, cy1, cw, cy2 - cy1, 5, 4, 3) end
end

local function draw_3_layer_grid_and_notes(canvas_w, grid_bottom_y)
  local top_area, left_x, right_x = get_top_area_y(), state.keyboard_w, get_grid_right_x(canvas_w)
  local grid_qn, view_start_qn, view_end_qn = get_grid_qn(), math.max(0, screen_x_to_qn(left_x)), screen_x_to_qn(right_x)
  local min_qn, max_qn = math.max(0, snap_floor_qn(view_start_qn)), view_end_qn + grid_qn

  for p = 127, 0, -1 do local rh = state.row_h[p]; if rh > 0 then local sy = pitch_to_screen_y(p); local cy1, cy2 = math.max(top_area, sy + 1), math.min(grid_bottom_y - 1, sy + rh - 1); if cy2 > cy1 then set_col(get_step_colors(get_rel_step(p)).bg); draw_filled_roundrect(left_x + 2, cy1, right_x - left_x - 4, cy2 - cy1, 5) end end end
  if state.selected_phrase then local psx, pex = math.max(left_x, qn_to_screen_x(state.selected_phrase.start_qn)), math.min(right_x, qn_to_screen_x(state.selected_phrase.end_qn)); if pex > psx then set_col({1.0,0.85,0.25}, 0.06); gfx.rect(psx, top_area, pex - psx, grid_bottom_y - top_area, 1) end end
  for _, sec in ipairs(state.sections) do if not sec.deleted then local rx = qn_to_screen_x(sec.start_qn); if rx >= left_x and rx <= right_x then set_col(sec.rgb, 0.36); gfx.line(rx, top_area, rx, grid_bottom_y) end end end
  local g_start, g_end = math.floor(min_qn / grid_qn), math.ceil(max_qn / grid_qn)
  for gi = g_start, g_end do local qn = gi * grid_qn; local sx = qn_to_screen_x(qn); if sx >= left_x and sx <= right_x then set_col(CONFIG.dark_mode and {1,1,1} or {0.42,0.44,0.48}, (math.abs(qn%4)<1e-4) and 0.26 or ((math.abs(qn%1)<1e-4) and 0.14 or 0.06)); gfx.line(sx, top_area, sx, grid_bottom_y) end end
  if state.view_mode == "diatonic" and state.hover_alt_seam then
    local sp = state.hover_alt_seam; local sy = pitch_to_screen_y(sp)
    if sy >= top_area and sy <= grid_bottom_y then
      local cols = get_step_colors(get_rel_step(sp)); set_col(cols.active, 0.85); draw_dashed_line(left_x+4, sy, right_x-4, sy, 6, 4)
      gfx.setfont(1, "Segoe UI", 13); draw_filled_roundrect(left_x+6, sy-11, 114, 22, 4); set_col(contrast_text_col(cols.active)); local ll, rl = get_key_left_right_labels(sp); draw_text_centered("Alt: " .. rl .. " " .. ll, left_x+6, sy-11, 114, 22)
    end
  end

  local h_vis = get_harmony_visual_h()
  local guide_list = (state.harmony_source == "gmem") and state.gmem_guides or ((state.harmony_source == "clip_pulled") and state.clip_guides or nil)
  local vis_guides, vis_manual = {}, {}
  if guide_list then for _, g in ipairs(guide_list) do if g.end_qn > view_start_qn and g.start_qn < view_end_qn then table.insert(vis_guides, g) end end end
  for _, mh in ipairs(state.manual_harmony_notes) do if mh.end_qn > view_start_qn and mh.start_qn < view_end_qn then table.insert(vis_manual, mh) end end
  local function draw_h_pass(zero_h)
    for p = 127, 0, -1 do
      local rh = state.row_h[p]
      if (zero_h and rh == 0) or (not zero_h and rh > 0) then
        local hy = pitch_center_screen_y(p) - h_vis * 0.5
        if hy + h_vis > top_area and hy < grid_bottom_y then
          local pc, cols = p % 12, get_step_colors(get_rel_step(p))
          if guide_list then
            for _, g in ipairs(vis_guides) do if g.pc == pc then local cx = math.max(left_x+2, qn_to_screen_x(g.start_qn)+2); local cw = math.min(right_x-2, qn_to_screen_x(g.end_qn)-2) - cx; if cw > 3 then draw_harmony_span_block(cx, hy, cw, h_vis, cols, top_area, grid_bottom_y) end end end
          elseif state.harmony_source == "diatonic" or state.harmony_source == "triad_1" then
            local rel = get_rel_step(p); if (state.harmony_source == "diatonic" and is_pitch_diatonic(p)) or (state.harmony_source == "triad_1" and (rel==0 or rel==4 or rel==7)) then
              for gi = g_start, g_end - 1 do local sx = qn_to_screen_x(gi * grid_qn) + 3; local cx = math.max(left_x+2, sx); local cw = math.min(right_x-2, sx + grid_qn*state.px_per_qn - 6) - cx; if cw > 4 then draw_harmony_span_block(cx, hy, cw, h_vis, cols, top_area, grid_bottom_y) end end
            end
          end
          for _, mh in ipairs(vis_manual) do if mh.pc == pc then local cx = math.max(left_x+2, qn_to_screen_x(mh.start_qn)+2); local cw = math.min(right_x-2, qn_to_screen_x(mh.end_qn)-2) - cx; if cw > 3 then draw_harmony_span_block(cx, hy, cw, h_vis, cols, top_area, grid_bottom_y) end end end
        end
      end
    end
  end
  draw_h_pass(false); draw_h_pass(true)

  local n_vis, now_t = get_note_visual_h(), reaper.time_precise()
  local glow_active_uid = (state.section_glow_held or now_t < state.section_glow_until) and state.section_glow_uid or nil
  local outline_default, outline_sel = CONFIG.dark_mode and {0.96,0.96,0.98} or {0.99,0.98,0.97}, {1.0, 0.82, 0.22}

  for _, n in ipairs(state.notes) do
    local cy = pitch_center_screen_y(n.pitch); local ny1, ny2 = math.max(top_area, cy - n_vis * 0.5), math.min(grid_bottom_y - 1, cy + n_vis * 0.5)
    if ny2 > ny1 + 2 then
      local sx, ex = qn_to_screen_x(n.start_qn), qn_to_screen_x(n.end_qn); local nw = math.max(6, ex - sx)
      if sx + nw >= left_x and sx <= right_x then
        local cx, cw = math.max(left_x, sx), math.min(right_x, sx + nw) - math.max(left_x, sx)
        if cw >= 2 then
          local cols, is_st = get_step_colors(get_rel_step(n.pitch)), (get_incoming_note(n.id) ~= nil)
          if glow_active_uid and n.section_uid == glow_active_uid then
            local sec = get_section_by_uid(glow_active_uid); local ga = state.section_glow_held and 0.65 or clamp((state.section_glow_until - now_t) / 0.65, 0, 1) * 0.65
            set_col(mix_rgb((sec and sec.rgb) or {1,0.92,0.45}, {1,1,1}, 0.5), ga * 0.45); draw_filled_roundrect(cx - 4, ny1 - 4, cw + 8, (ny2 - ny1) + 8, 8)
            set_col({1,1,1}, ga); gfx.roundrect(math.floor(cx-2), math.floor(ny1-2), math.floor(cw+4), math.floor((ny2-ny1)+4), 6, 1)
          end
          draw_bordered_roundrect(cx, ny1, cw, ny2-ny1, 5, (n.selected or is_st) and 2 or 1.5, n.selected and outline_sel or (is_st and {0.40,0.85,1.0} or outline_default), cols.active, n.muted and 0.34 or (is_st and 0.78 or 1.0))
          if is_st and cw > 14 then set_col(contrast_text_col(cols.active), 0.9); gfx.setfont(1, "Segoe UI", 11); draw_text_left("→", cx+3, ny1, cw-6, ny2-ny1) end
          if not is_st and cw >= 10 and (ny2 - ny1) >= 8 then
            local bw, by = math.max(4, cw - 8), math.floor((ny1 + ny2) * 0.5 - 1.5)
            set_col({0,0,0}, 0.45); draw_filled_roundrect(cx + 4, by, bw, 3, 1); set_col({1,1,1}, n.muted and 0.45 or 0.92); draw_filled_roundrect(cx + 4, by, math.max(2, bw * clamp(n.vel/127.0, 0.06, 1.0)), 3, 1)
          end
        end
      end
    end
  end

  state.curve_handles = {}
  local show_nodes = (state.tool == "mpe")
  local col_green, col_black, col_white, col_red = {0.12,0.78,0.30}, {0.08,0.09,0.11}, {0.96,0.97,0.99}, {0.90,0.18,0.20}
  local function draw_node_dot(nx, ny, fill, border_col, kind, note, dst, is_conn)
    if not show_nodes or nx < left_x or nx > right_x or ny < top_area or ny > grid_bottom_y then return end
    table.insert(state.curve_handles, { kind=kind, note=note, dst=dst, is_connection=is_conn, x=nx, y=ny })
    set_col(fill); gfx.circle(nx, ny, 5.2, 1, 1); set_col(border_col); gfx.circle(nx, ny, 5.2, 0, 1)
  end

  for _, n in ipairs(state.notes) do
    local dst, inc = get_note_by_id(n.connect_to_id), get_incoming_note(n.id); local q1, q2, q3, q4 = get_note_node_qns(n, inc ~= nil, dst)
    local base_y = pitch_center_screen_y(n.pitch); local pre_y, out_y = pitch_float_to_screen_y(n.pitch + (n.pre_st or 0.0)), dst and pitch_center_screen_y(dst.pitch) or pitch_float_to_screen_y(n.pitch + (n.out_st or 0.0))
    if not inc and math.abs(n.pre_st or 0.0) > 0.02 then
      local pts = {}; for s = 0, 20 do local u = s/20; local x, y = qn_to_screen_x(lerp(q1,q2,u)), lerp(pre_y,base_y,eval_curve_shape(u,n.pre_shape,n.pre_tension)); if x>=left_x and x<=right_x and y>=top_area and y<=grid_bottom_y then table.insert(pts,{x,y}) end end
      draw_thick_aa_curve(pts, {0.25,0.92,0.50}, 0.95); draw_node_dot(qn_to_screen_x(lerp(q1,q2,0.5)), lerp(pre_y,base_y,eval_curve_shape(0.5,n.pre_shape,n.pre_tension)), {0.85,0.95,0.88}, col_black, "pre_mid", n, nil, false)
    end
    if dst or math.abs(n.out_st or 0.0) > 0.02 then
      local pts = {}; for s = 0, 28 do local u = s/28; local x, y = qn_to_screen_x(lerp(q3,q4,u)), lerp(base_y,out_y,eval_curve_shape(u,n.out_shape,n.out_tension)); if x>=left_x and x<=right_x and y>=top_area and y<=grid_bottom_y then table.insert(pts,{x,y}) end end
      local ccol = dst and {1.0,0.86,0.25} or {0.95,0.45,0.45}; draw_thick_aa_curve(pts, ccol, 0.96)
      draw_node_dot(qn_to_screen_x(lerp(q3,q4,0.5)), lerp(base_y,out_y,eval_curve_shape(0.5,n.out_shape,n.out_tension)), ccol, col_black, "out_mid", n, dst, dst ~= nil)
    end
    if n.vibrato and n.vibrato.enabled then
      local sx, ex = qn_to_screen_x(n.start_qn), qn_to_screen_x(n.end_qn); local nw, pts, pat = math.max(6, ex - sx), {}, n.vibrato.pattern or "consistent"
      for s = 0, 36 do local t = s/36; local px, amp = sx + 4 + (nw - 8)*t, 0; if t >= n.vibrato.delay then amp = eval_vibrato_pattern_env(pat, clamp((t - n.vibrato.delay)/math.max(1e-4, 1.0 - n.vibrato.delay), 0, 1)) * (n_vis * 0.38) end
        local py = base_y - amp * math.sin(t * n.vibrato.rate * 6.0); if px >= left_x and px <= right_x and py >= top_area and py <= grid_bottom_y then table.insert(pts, {px, py}) end end
      draw_thick_aa_curve(pts, {1, 1, 1}, 0.88)
    end
    if show_nodes then
      local dt = state.drag and state.drag.type == "node4_drag" and state.drag.note == n
      if not inc then draw_node_dot(qn_to_screen_x(q1), pre_y, col_green, col_black, "n1", n, nil, false) end
      if (inc ~= nil) or is_green_positioned(n) or (dt and (state.drag.kind == "n1" or state.drag.kind == "n2")) then draw_node_dot(qn_to_screen_x(q2), base_y, col_black, col_white, "n2", n, nil, false) end
      if (dst ~= nil) or is_red_positioned(n)   or (dt and (state.drag.kind == "n3" or state.drag.kind == "n4")) then draw_node_dot(qn_to_screen_x(q3), base_y, col_white, col_black, "n3", n, dst, dst ~= nil) end
      if not dst then draw_node_dot(qn_to_screen_x(q4), out_y, col_red, col_black, "n4", n, nil, false) end
    end
  end

  if state.drag and state.drag.type == "node4_drag" and state.drag.hover_dst then
    local ok, msg = can_connect_notes(state.drag.note, state.drag.hover_dst)
    draw_thick_aa_curve({ {state.drag.start_x, state.drag.start_y}, {gfx.mouse_x, gfx.mouse_y} }, ok and {0.25,0.90,0.45} or {0.95,0.25,0.25}, 0.95)
    if msg then gfx.setfont(1, "Segoe UI", 12); set_col(ok and {0.3,0.9,0.5} or {1,0.35,0.35}); draw_text_left(msg, gfx.mouse_x+12, gfx.mouse_y-10, 260, 20) end
  end
  if state.marquee then
    local mx1, my1 = math.min(state.marquee.x1, state.marquee.x2), math.min(state.marquee.y1, state.marquee.y2)
    local mw, mh = math.abs(state.marquee.x2 - state.marquee.x1), math.abs(state.marquee.y2 - state.marquee.y1)
    set_col({0.25,0.52,0.88}, 0.16); gfx.rect(mx1, my1, mw, mh, 1); set_col({0.25,0.52,0.88}, 0.85); gfx.rect(mx1, my1, mw, mh, 0)
  end
  local play_sec = ((reaper.GetPlayState() & 1) == 1) and reaper.GetPlayPosition() or reaper.GetCursorPosition()
  local px = qn_to_screen_x(reaper.TimeMap2_timeToQN(0, play_sec))
  if px >= left_x and px <= right_x then set_col(((reaper.GetPlayState()&1)==1) and {0.92,0.22,0.22} or {0.35,0.55,0.90}, 0.9); gfx.line(px, state.titlebar_h + state.toolbar_h, px, grid_bottom_y) end
end

local function draw_horizontal_scrollbar(canvas_w, scroll_y)
  set_col(CONFIG.dark_mode and {0.10,0.11,0.14} or {0.98,0.98,0.99}); gfx.rect(0, scroll_y, canvas_w, state.hscroll_h + 4, 1)
  local sx, right_x = state.keyboard_w, get_grid_right_x(canvas_w); local sw = right_x - sx; if sw <= 40 then return end
  set_col(CONFIG.dark_mode and {0.15,0.16,0.20} or {0.91,0.92,0.94}); draw_filled_roundrect(sx, scroll_y + 3, sw, state.hscroll_h - 6, 5)
  local visible_qn = sw / state.px_per_qn; local max_qn = math.max(get_max_timeline_qn(), state.scroll_x_qn + visible_qn)
  local thumb_w = clamp((visible_qn / max_qn) * sw, 30, sw); local thumb_x = sx + math.max(0, sw - thumb_w) * ((max_qn > visible_qn) and clamp(state.scroll_x_qn / (max_qn - visible_qn), 0, 1) or 0)
  local hov = gfx.mouse_x >= thumb_x and gfx.mouse_x <= thumb_x + thumb_w and gfx.mouse_y >= scroll_y and gfx.mouse_y <= scroll_y + state.hscroll_h
  local act = state.drag and (state.drag.type == "hscroll_pan" or state.drag.type == "hscroll_left" or state.drag.type == "hscroll_right")
  set_col((hov or act) and (CONFIG.dark_mode and {0.42,0.46,0.55} or {0.55,0.60,0.68}) or (CONFIG.dark_mode and {0.30,0.33,0.40} or {0.72,0.75,0.81})); draw_filled_roundrect(thumb_x, scroll_y + 3, thumb_w, state.hscroll_h - 6, 5)
  local cy, cr = scroll_y + state.hscroll_h * 0.5, 5.5
  set_col(CONFIG.dark_mode and {0.82,0.86,0.94} or {0.98,0.99,1.0}, 0.92); gfx.circle(thumb_x+6, cy, cr, 1, 1); gfx.circle(thumb_x+thumb_w-6, cy, cr, 1, 1)
  set_col({0.18,0.20,0.26}, 0.7); gfx.circle(thumb_x+6, cy, cr, 0, 1); gfx.circle(thumb_x+thumb_w-6, cy, cr, 0, 1)
  state.hscroll_geom = { x=sx, y=scroll_y, w=sw, h=state.hscroll_h, thumb_x=thumb_x, thumb_w=thumb_w, max_qn=max_qn, visible_qn=visible_qn }
end

local function draw_vertical_scrollbar(canvas_w, grid_bottom_y)
  local top_area = get_top_area_y(); local vx, vw, vh = get_grid_right_x(canvas_w) + 2, state.vscroll_w - 2, grid_bottom_y - top_area; if vh <= 40 then return end
  set_col(CONFIG.dark_mode and {0.15,0.16,0.20} or {0.91,0.92,0.94}); draw_filled_roundrect(vx + 3, top_area, vw - 4, vh, 5)
  local total_h = math.max(vh, state.total_h); local thumb_h = clamp((vh / total_h) * vh, 30, vh)
  local thumb_y = top_area + math.max(0, vh - thumb_h) * clamp(state.scroll_y_px / math.max(0.001, total_h - vh), 0, 1)
  local hov = gfx.mouse_x >= vx and gfx.mouse_x <= vx + vw and gfx.mouse_y >= thumb_y and gfx.mouse_y <= thumb_y + thumb_h
  local act = state.drag and (state.drag.type == "vscroll_pan" or state.drag.type == "vscroll_top" or state.drag.type == "vscroll_bot")
  set_col((hov or act) and (CONFIG.dark_mode and {0.42,0.46,0.55} or {0.55,0.60,0.68}) or (CONFIG.dark_mode and {0.30,0.33,0.40} or {0.72,0.75,0.81})); draw_filled_roundrect(vx + 3, thumb_y, vw - 4, thumb_h, 5)
  local cx, cr = vx + vw * 0.5 + 1, 5.5
  set_col(CONFIG.dark_mode and {0.82,0.86,0.94} or {0.98,0.99,1.0}, 0.92); gfx.circle(cx, thumb_y+6, cr, 1, 1); gfx.circle(cx, thumb_y+thumb_h-6, cr, 1, 1)
  set_col({0.18,0.20,0.26}, 0.7); gfx.circle(cx, thumb_y+6, cr, 0, 1); gfx.circle(cx, thumb_y+thumb_h-6, cr, 0, 1)
  state.vscroll_geom = { x=vx, y=top_area, w=vw, h=vh, thumb_y=thumb_y, thumb_h=thumb_h, total_h=total_h }
end

local function draw_bottom_controls(canvas_w)
  local param_y = gfx.h - state.transport_h - state.param_bar_h
  local vel_y = param_y - (state.show_vel_lane and state.vel_lane_h or 0)
  local right_x = get_grid_right_x(canvas_w)
  local bg, border = CONFIG.dark_mode and {0.14,0.15,0.19} or {0.96,0.97,0.98}, CONFIG.dark_mode and {0.24,0.26,0.30} or {0.84,0.86,0.90}

  if state.show_vel_lane then
    set_col(bg); gfx.rect(0, vel_y, canvas_w, state.vel_lane_h, 1); set_col(border); gfx.line(0, vel_y, canvas_w, vel_y)
    local left_x, lane_w = state.keyboard_w, right_x - state.keyboard_w
    if lane_w > 40 then
      set_col(CONFIG.dark_mode and {0.11,0.12,0.15} or {0.99,0.99,1.0}); draw_filled_roundrect(left_x+2, vel_y+4, lane_w-4, state.vel_lane_h-6, 6)
      set_col(CONFIG.dark_mode and {0.65,0.68,0.75} or {0.42,0.45,0.50}); gfx.setfont(1, "Segoe UI", 13); draw_text_centered("VELOCITY", 6, vel_y+4, left_x-12, state.vel_lane_h-6)
      local uh = state.vel_lane_h - 16
      for _, n in ipairs(state.notes) do if get_incoming_note(n.id) == nil then local sx = qn_to_screen_x(n.start_qn); if sx >= left_x + 2 and sx <= right_x - 4 then local bh = (n.vel/127.0)*uh; set_col(get_step_colors(get_rel_step(n.pitch)).active, n.selected and 1.0 or 0.72); draw_filled_roundrect(sx-3, vel_y+state.vel_lane_h-5-bh, 7, math.max(4,bh), 3) end end end
    end
  end

  set_col(bg); gfx.rect(0, param_y, canvas_w, state.param_bar_h, 1); set_col(border, 0.75); gfx.line(0, param_y, canvas_w, param_y)
  local cx = 8
  register_btn("show_vel_btn", cx, param_y + 5, 72, 28, "Show Vel", state.show_vel_lane, function() state.show_vel_lane = not state.show_vel_lane; save_global_prefs() end); cx = cx + 76
  register_btn("mpe_toggle", cx, param_y + 5, 68, 28, "MPE:" .. (state.mpe_enabled and "ON" or "OFF"), state.mpe_enabled, function() state.mpe_enabled = not state.mpe_enabled; save_global_prefs(); sync_section_clips() end); cx = cx + 72

  local sel = get_selected_notes(); local target = sel[1]
  gfx.setfont(1, "Segoe UI", 13); set_col(CONFIG.dark_mode and {0.88,0.90,0.94} or {0.20,0.22,0.26})

  if not target then
    draw_text_left("Select note(s) for Section & MPE | Right-click empty=Clear, Right-drag=Box Select, M=Mute, Ctrl+Z/Y=Undo/Redo", cx + 4, param_y + 5, math.max(100, canvas_w - cx - 180), 28)
  else
    local first_uid, mixed_s, any_ov = target.section_uid, false, target.section_override
    for _, n in ipairs(sel) do if n.section_uid ~= first_uid then mixed_s = true end; if n.section_override ~= any_ov then any_ov = true end end
    local sec_lbl = mixed_s and "Section: Mixed" or (first_uid and ("Section: " .. (get_section_by_uid(first_uid) and get_section_by_uid(first_uid).name:sub(1,10) or "?") .. (any_ov and "*" or "")) or "Section: None")
    register_btn("sel_sec_assign", cx, param_y + 5, 138, 28, sec_lbl, any_ov, function(bx, by, bw, bh)
      gfx.x, gfx.y = bx, by + bh; local active_secs = {}; for _, s in ipairs(state.sections) do if not s.deleted then table.insert(active_secs, s) end end
      local menu = "Reset to Auto Ownership|None (Unassigned)|"
      for _, s in ipairs(active_secs) do menu = menu .. (((not mixed_s and first_uid == s.uid) and "!" or "") .. s.name .. "|") end
      local ch = gfx.showmenu(menu)
      if ch == 1 then push_undo(); for _, n in ipairs(sel) do n.section_override=false; local s=find_section_at_qn(n.start_qn); n.section_uid=s and s.uid or nil end; compute_section_overflows(); sync_section_clips()
      elseif ch == 2 then push_undo(); for _, n in ipairs(sel) do n.section_uid=nil; n.section_override=true end; compute_section_overflows(); sync_section_clips()
      elseif ch >= 3 and ch <= #active_secs + 2 then local c=active_secs[ch-2]; push_undo(); for _, n in ipairs(sel) do n.section_uid=c.uid; n.section_override=true end; compute_section_overflows(); sync_section_clips() end
    end); cx = cx + 142

    draw_slider("sel_vel", cx, param_y + 5, 64, 28, target.vel, 1, 127, "Vel", "%s:%d", function(v) for _, n in ipairs(sel) do n.vel = math.floor(v+0.5) end end); cx = cx + 68
    local br = state.mpe_bend_range
    draw_slider("sel_pre_st", cx, param_y + 5, 72, 28, target.pre_st or 0, -br, br, "Pre", "%s:%+.1f", function(v) local rv = math.floor(v*2+0.5)*0.5; for _, n in ipairs(sel) do if not get_incoming_note(n.id) then n.pre_st = rv end end end); cx = cx + 76
    draw_slider("sel_out_st", cx, param_y + 5, 72, 28, target.out_st or 0, -br, br, "Out", "%s:%+.1f", function(v) local rv = math.floor(v*2+0.5)*0.5; for _, n in ipairs(sel) do if not n.connect_to_id then n.out_st = rv end end end); cx = cx + 76

    local cur_sh = "S-Curve"; for _, cs in ipairs(CONFIG.curve_shapes) do if cs.id == (target.out_shape or "s_curve") then cur_sh = cs.label break end end
    register_btn("sel_shape", cx, param_y + 5, 64, 28, cur_sh, false, function(bx, by, bw, bh)
      gfx.x, gfx.y = bx, by + bh; local menu = ""; for _, cs in ipairs(CONFIG.curve_shapes) do menu = menu .. (((target.out_shape or "s_curve") == cs.id) and "!" or "") .. cs.label .. "|" end
      local c = gfx.showmenu(menu); if c >= 1 and c <= #CONFIG.curve_shapes then push_undo(); for _, n in ipairs(sel) do n.out_shape = CONFIG.curve_shapes[c].id; n.pre_shape = CONFIG.curve_shapes[c].id end; sync_section_clips() end
    end); cx = cx + 68
    draw_slider("sel_curve", cx, param_y + 5, 70, 28, target.out_tension or 0, -1.0, 1.0, "Tens", "%s:%+.2f", function(v) for _, n in ipairs(sel) do n.out_tension = v; n.pre_tension = v end end); cx = cx + 74

    if #sel >= 2 then
      register_btn("conn_sel", cx, param_y + 5, 64, 28, "Connect", false, function()
        table.sort(sel, function(a, b) return a.start_qn < b.start_qn end); push_undo(); local cc = 0
        for i = 1, #sel - 1 do local ok, err = can_connect_notes(sel[i], sel[i + 1]); if ok then connect_notes(sel[i], sel[i + 1]); cc = cc + 1 else state.status_msg = err or "Rejected" end end
        if cc > 0 then sync_section_clips() end
      end); cx = cx + 68
    elseif target.connect_to_id or get_incoming_note(target.id) then
      register_btn("disconn_sel", cx, param_y + 5, 54, 28, "Unlink", true, function()
        push_undo(); if target.connect_to_id then disconnect_note_outgoing(target) end; local inc = get_incoming_note(target.id); if inc then disconnect_note_outgoing(inc) end; sync_section_clips()
      end, {0.76,0.34,0.22}); cx = cx + 58
    end

    register_btn("vib_toggle", cx, param_y + 5, 58, 28, "Vib:" .. (target.vibrato.enabled and "ON" or "OFF"), target.vibrato.enabled, function()
      push_undo(); local nv = not target.vibrato.enabled; for _, n in ipairs(sel) do n.vibrato.enabled = nv end; sync_section_clips()
    end); cx = cx + 62

    if target.vibrato.enabled then
      local pat_btn = "Pat:Const"; for _, vp in ipairs(CONFIG.vib_patterns) do if vp.id == (target.vibrato.pattern or "consistent") then pat_btn = vp.btn break end end
      register_btn("vib_pat", cx, param_y + 5, 68, 28, pat_btn, false, function(bx, by, bw, bh)
        gfx.x, gfx.y = bx, by + bh; local menu = ""; for _, vp in ipairs(CONFIG.vib_patterns) do menu = menu .. (((target.vibrato.pattern or "consistent") == vp.id) and "!" or "") .. vp.menu .. "|" end
        local c = gfx.showmenu(menu); if c >= 1 and c <= #CONFIG.vib_patterns then push_undo(); for _, n in ipairs(sel) do n.vibrato.pattern = CONFIG.vib_patterns[c].id end; sync_section_clips() end
      end); cx = cx + 72
      if cx + 130 < canvas_w - 140 then
        draw_slider("vib_rate", cx, param_y + 5, 62, 28, target.vibrato.rate, 1.0, 12.0, "Hz", "%s:%.1f", function(v) for _, n in ipairs(sel) do n.vibrato.rate = v end end); cx = cx + 66
        draw_slider("vib_depth", cx, param_y + 5, 66, 28, target.vibrato.depth_cents, 0, 120, "Dep", "%s:%d", function(v) for _, n in ipairs(sel) do n.vibrato.depth_cents = math.floor(v+0.5) end end); cx = cx + 70
      end
    end
  end

  local act_sec = get_section_by_uid(state.selected_section_uid); local act_w = clamp(canvas_w - cx - 8, 110, 175)
  if act_w >= 100 then
    local act_x = canvas_w - act_w - 8; local pcol = act_sec and act_sec.rgb or (CONFIG.dark_mode and {0.22,0.24,0.28} or {0.88,0.90,0.93})
    draw_bordered_roundrect(act_x, param_y + 5, act_w, 28, 6, 1.5, mix_rgb(pcol,{0,0,0},0.2), pcol, 0.9)
    set_col(contrast_text_col(pcol)); gfx.setfont(1, "Segoe UI", 13)
    draw_text_centered(act_sec and string.format("Active: %s (%d)", act_sec.name, count_section_notes(act_sec.uid)) or "Active: None", act_x + 4, param_y + 5, act_w - 8, 28)
  end
end

-- Transport colors and icon geometry match N2N Mix.
function state.transport_button(id,x,y,w,h,label,active,accent,action,icon)
  local hov=gfx.mouse_x>=x and gfx.mouse_x<=x+w and gfx.mouse_y>=y and gfx.mouse_y<=y+h
  local pressed=hov and (gfx.mouse_cap&1)~=0
  local bg=pressed and {0.29,0.29,0.29} or hov and {0.224,0.224,0.224} or active and {0.20,0.20,0.20} or {0.145,0.145,0.145}
  local fg=active and accent or accent and id=="tr_2" and {0.73,0.52,0.52} or {0.80,0.80,0.80}
  draw_bordered_roundrect(x,y,w,h,4,1,active and accent or {0.318,0.318,0.318},bg)
  set_col(fg);gfx.setfont(1,"Segoe UI",13)
  if icon then icon(x+w/2,y+h/2) else draw_text_centered(label,x,y,w,h) end
  table.insert(state.ui_controls,{id=id,x=x,y=y,w=w,h=h,on_click=action})
end
function state.transport_icon(i,x,y)
  local function ln(a,b,c,d) gfx.line(x+a,y+b,x+c,y+d,1) end
  local function rect(a,b,c,d) gfx.rect(x+a,y+b,c-a,d-b,1) end
  local function tri(a,b,c,d,e,f) gfx.triangle(x+a,y+b,x+c,y+d,x+e,y+f) end
  if i==1 then rect(-1,-6,1,1);gfx.circle(x,y+5,1.3,1,1)
  elseif i==2 then gfx.circle(x,y,5.5,1,1)
  elseif i==3 then tri(-4,-6,-4,6,6,0)
  elseif i==4 then rect(-5,-5,5,5)
  elseif i==5 then rect(-5,-6,-1,6);rect(1,-6,5,6)
  elseif i==6 then ln(-6,0,-6,-4);ln(-6,-4,4,-4);ln(1,-7,4,-4);ln(1,-1,4,-4);ln(6,0,6,4);ln(6,4,-4,4);ln(-1,1,-4,4);ln(-1,7,-4,4)
  elseif i==7 then rect(-7,-6,-5,6);tri(4,-6,4,6,-4,0)
  elseif i==8 then ln(5,0,-5,0);ln(-5,0,0,-5);ln(-5,0,0,5)
  elseif i==9 then ln(-5,0,5,0);ln(5,0,0,-5);ln(5,0,0,5)
  elseif i==10 then rect(5,-6,7,6);tri(-4,-6,-4,6,4,0) end
end
function state.raise_window(hwnd)
  if not hwnd then return end
  if reaper.JS_Window_IsWindow and not reaper.JS_Window_IsWindow(hwnd) then return end
  if reaper.JS_Window_IsVisible and not reaper.JS_Window_IsVisible(hwnd) and reaper.JS_Window_Show then reaper.JS_Window_Show(hwnd,"SHOW") end
  if reaper.JS_Window_SetZOrder then reaper.JS_Window_SetZOrder(hwnd,"TOP") end
  if reaper.JS_Window_SetForeground then reaper.JS_Window_SetForeground(hwnd) end
  if reaper.JS_Window_SetFocus then reaper.JS_Window_SetFocus(hwnd) end
end
function state.open_numbers2notes()
  local sec="N2N_EDITOR_WINDOWS"
  local hb=tonumber(reaper.GetExtState(sec,"numbers2notes:heartbeat"))
  local hwnd=reaper.JS_Window_Find and reaper.JS_Window_Find("Numbers2Notes - Nashville Number Charts for Reaper",true)
  if hb and math.abs(reaper.time_precise()-hb)<3 then
    reaper.SetExtState(sec,"numbers2notes:focus",tostring(reaper.time_precise()),false);state.raise_window(hwnd);return
  end
  if hwnd then state.raise_window(hwnd);return end
  local src=debug.getinfo(1,"S").source:gsub("^@",""):gsub("\\","/")
  local dir=src:match("^(.*[/])")
  -- Existing older registrations can contain Notes2Numbers/../.
  if dir then dir=dir:gsub("Notes2Numbers/%.%./","") end
  local path=dir and dir.."Notes2Numbers/Numbers2Notes.lua"
  local f=path and io.open(path,"rb")
  if not f then state.status_msg="Numbers2Notes.lua not found.";return end
  f:close()
  local cmd=reaper.AddRemoveReaScript(true,0,path,true)
  if cmd and cmd>0 then reaper.Main_OnCommand(cmd,0) else state.status_msg="Could not launch Numbers2Notes." end
end
function state.cue_section(sec,bars,play)
  if (reaper.GetPlayState()&4)~=0 then state.status_msg="Stop recording before cueing.";return end
  if reaper.GetPlayState()~=0 then reaper.Main_OnCommand(1016,0) end
  local q=math.max(0,sec.start_qn-bars*(sec.bar_qn or 4))
  reaper.SetEditCurPos(reaper.TimeMap2_QNToTime(0,q),true,false)
  state.selected_section_uid=sec.uid;state.selected_phrase=nil
  state.section_glow_uid=sec.uid;state.section_glow_until=reaper.time_precise()+.65
  state.scroll_x_qn=q
  state.status_msg="Active Section: "..sec.name
  state.section_hover=nil
  if play then reaper.Main_OnCommand(1007,0) end
  save_project_state()
end
function state.hover_section(sec,x,y,w,h)
  if (gfx.mouse_cap&3)~=0 then return end
  local old=state.section_hover
  if old and old.popup then
    local p=old.popup
    if gfx.mouse_x>=p.x and gfx.mouse_x<=p.x+p.w and gfx.mouse_y>=p.y and gfx.mouse_y<=p.y+p.h then return end
  end
  state.section_hover={sec=sec,x=x,y=y,w=w,h=h,expires=reaper.time_precise()+.45}
end
function state.draw_section_popup(canvas_w)
  local h=state.section_hover;if not h then return end
  local w,ph=96,30
  local x=clamp(h.x-6,0,math.max(0,canvas_w-w))
  local y=h.y-ph-2
  if y<state.titlebar_h then y=h.y+h.h+2 end
  local hover=gfx.mouse_x>=x and gfx.mouse_x<=x+w and gfx.mouse_y>=y and gfx.mouse_y<=y+ph
  if hover then h.expires=reaper.time_precise()+.45 end
  if reaper.time_precise()>h.expires then state.section_hover=nil;return end
  h.popup={x=x,y=y,w=w,h=ph}
  draw_bordered_roundrect(x,y,w,ph,4,1,{.32,.32,.32},{.10,.10,.10})
  for i=1,3 do
    state.transport_button("section_play_"..i,x+3+(i-1)*30,y+3,28,24,i==1 and "-2" or i==2 and "-1" or "",false,nil,function() state.cue_section(h.sec,3-i,true) end,i==3 and function(cx,cy) state.transport_icon(3,cx,cy) end or nil)
  end
end
function state.transport_action(i)
  local cmds={40349,1013,1007,1016,1008,0,40042,40172,40173,40043}
  if i==6 then reaper.GetSetRepeat(reaper.GetSetRepeat(-1)==1 and 0 or 1)
  else reaper.Main_OnCommand(cmds[i],0);if i==4 then reaper.Main_OnCommand(40349,0) end end
end
local function draw_transport_bar(canvas_w)
  local trans_y=gfx.h-state.transport_h
  set_col(CONFIG.dark_mode and {.12,.13,.17} or {.95,.96,.98});gfx.rect(0,trans_y,canvas_w,state.transport_h,1)
  set_col(CONFIG.dark_mode and {.24,.26,.30} or {.84,.86,.90});gfx.line(0,trans_y,canvas_w,trans_y)
  local ps=reaper.GetPlayState()
  local tx,ty,th=10,trans_y+16,26
  local labels={"!","F9","F10","F11","F12","","Home","Pg ↓","Pg ↑","End"}
  for i=1,10 do
    local active=(i==2 and (ps&4)~=0) or (i==3 and (ps&1)~=0 and (ps&2)==0) or (i==5 and (ps&2)~=0) or (i==6 and reaper.GetSetRepeat(-1)==1)
    local accent=i==2 and {.81,.47,.47} or i==3 and {.62,.78,.65} or {.83,.72,.43}
    gfx.setfont(1,"Segoe UI",11);set_col({.88,.88,.88});draw_text_centered(labels[i],tx,trans_y+1,30,14)
    state.transport_button("tr_"..i,tx,ty,30,th,"",active,accent,function() state.transport_action(i) end,function(x,y) state.transport_icon(i,x,y) end)
    tx=tx+((i==1 or i==6) and 36 or 33)
  end
  tx=tx+9
  state.transport_button("open_n2n",tx,ty,156,th,"Open Numbers2Notes",false,nil,state.open_numbers2notes)
  tx=tx+168
  for i,sec in ipairs(state.sections) do
    if not sec.deleted and tx+32<=canvas_w-160 then
      register_btn("jmp_"..i,tx,ty,30,th,sec.name:sub(1,1):upper(),true,function()
        local shifted=(gfx.mouse_cap&8)~=0;state.cue_section(sec,shifted and 1 or 0,shifted)
      end,sec.rgb)
      if gfx.mouse_x>=tx and gfx.mouse_x<=tx+30 and gfx.mouse_y>=ty and gfx.mouse_y<=ty+th then state.hover_section(sec,tx,ty,30,th) end
      tx=tx+34
    end
  end
  gfx.setfont(1,"Segoe UI",12);set_col(CONFIG.dark_mode and {.64,.68,.75} or {.42,.45,.52});draw_text_right(state.status_msg,tx+6,ty,math.max(0,canvas_w-tx-22),th)
end

local function draw_lanes_drawer()
  if not state.show_drawer then return end
  local dx, dy, dh = gfx.w - state.drawer_w, state.titlebar_h + state.toolbar_h, gfx.h - (state.titlebar_h + state.toolbar_h)
  set_col(CONFIG.dark_mode and {0.15,0.16,0.20} or {0.97,0.97,0.99}); gfx.rect(dx, dy, state.drawer_w, dh, 1)
  set_col(CONFIG.dark_mode and {0.25,0.27,0.32} or {0.84,0.86,0.90}); gfx.line(dx, dy, dx, gfx.h)
  gfx.setfont(1, "Segoe UI", 15); set_col(CONFIG.dark_mode and {0.92,0.94,0.97} or {0.16,0.18,0.22}); draw_text_left("Preferences", dx + 14, dy + 6, state.drawer_w - 28, 22)

  local y, hw = dy + 32, (state.drawer_w - 34) * 0.5
  draw_slider("in_scale_h", dx + 14, y, state.drawer_w - 28, 22, state.in_scale_h, 16, 64, "Lane Height (Locked)", "%s: %d px", function(v) state.in_scale_h = math.floor(v + 0.5); rebuild_row_layout() end); y = y + 25
  draw_slider("mpe_tail_ms", dx + 14, y, state.drawer_w - 28, 22, state.mpe_release_tail_ms, 50, 2500, "MPE Release Tail", "%s: %d ms", function(v) state.mpe_release_tail_ms = math.floor(v/10+0.5)*10 end); y = y + 25

  register_btn("theme_btn", dx + 14, y, hw, 23, "Theme: " .. (CONFIG.dark_mode and "Dark" or "Light"), CONFIG.dark_mode, function() CONFIG.dark_mode = not CONFIG.dark_mode; save_global_prefs() end)
  register_btn("frameless_btn", dx + 20 + hw, y, hw, 23, "Dark Bar: " .. (state.use_frameless and "ON" or "OFF"), state.use_frameless, function() state.use_frameless = not state.use_frameless; apply_window_frame_style(); save_global_prefs() end); y = y + 26
  register_btn("harm_border_style", dx + 14, y, hw, 23, "Mid: " .. (state.harmony_border_style == "dotted" and "Dotted" or "Solid"), state.harmony_border_style == "solid", function() state.harmony_border_style = (state.harmony_border_style == "dotted") and "solid" or "dotted"; save_global_prefs() end)
  register_btn("phrase_mode_btn", dx + 20 + hw, y, hw, 23, "Paste: " .. (state.phrase_paste_mode == "replace" and "Replace" or "Merge"), state.phrase_paste_mode == "replace", function() state.phrase_paste_mode = (state.phrase_paste_mode == "replace") and "merge" or "replace"; save_global_prefs() end); y = y + 26

  register_btn("piano_keys", dx+14,y,state.drawer_w-28,23,"Number Keys: "..(state.piano_keys and "Piano" or "Color"),state.piano_keys,function() state.piano_keys=not state.piano_keys;save_global_prefs() end);y=y+26

  local h_lbl = "Harmony View: N2N Pref"
  if state.harmony_source == "clip_pulled" then h_lbl = "Harmony View: Pulled Clip" elseif state.harmony_source == "diatonic" then h_lbl = "Harmony View: Diatonic"
  elseif state.harmony_source == "triad_1" then h_lbl = "Harmony View: Triad 1-3-5" elseif state.harmony_source == "manual" then h_lbl = "Harmony View: Manual" end
  register_btn("harm_src", dx + 14, y, state.drawer_w - 28, 24, h_lbl, false, function(bx, by, bw, bh)
    gfx.x, gfx.y = bx, by + bh; local menu = ""; for _, hs in ipairs(CONFIG.harmony_sources) do menu = menu .. (state.harmony_source == hs.id and "!" or "") .. hs.label .. "|" end
    local c = gfx.showmenu(menu .. "|Refresh N2N gmem Now|Pull Selected Clip as Harmony Guides|Clear Manual Harmony Notes")
    if c >= 1 and c <= #CONFIG.harmony_sources then state.harmony_source = CONFIG.harmony_sources[c].id; if state.harmony_source == "gmem" then read_gmem_harmony(true) end; save_project_state()
    elseif c == #CONFIG.harmony_sources + 1 then state.harmony_source = "gmem"; read_gmem_harmony(true); save_project_state()
    elseif c == #CONFIG.harmony_sources + 2 then pull_clip_as_harmony_guides() elseif c == #CONFIG.harmony_sources + 3 then state.manual_harmony_notes = {}; save_project_state() end
  end); y = y + 28

  gfx.setfont(1, "Segoe UI", 12); set_col(CONFIG.dark_mode and {0.85,0.88,0.94} or {0.20,0.22,0.26}); draw_text_left("Clip Groove & 8th Swing (gmem)", dx + 14, y, state.drawer_w - 28, 16); y = y + 18
  register_btn("groove_en", dx + 14, y, hw, 23, "Groove: " .. (state.groove_enabled and "ON" or "OFF"), state.groove_enabled, function() state.groove_enabled = not state.groove_enabled; sync_section_clips() end)
  register_btn("swing_src_btn", dx + 20 + hw, y, hw, 23, "Swing: " .. (state.swing_from_gmem and "gmem[2]" or "Manual"), state.swing_from_gmem, function() state.swing_from_gmem = not state.swing_from_gmem; read_gmem_groove_and_swing(); sync_section_clips() end); y = y + 26
  draw_slider("swing_pct", dx + 14, y, state.drawer_w - 28, 22, state.swing_pct, 0, 100, "8th Swing", "%s: %d%% (100=Triplet)", function(v) state.swing_from_gmem = false; state.swing_pct = math.floor(v + 0.5) end); y = y + 26

  gfx.setfont(1, "Segoe UI", 12); set_col(CONFIG.dark_mode and {0.85,0.88,0.94} or {0.20,0.22,0.26}); draw_text_left("Scroll & Zoom Wheel Modifiers (Grid)", dx + 14, y, state.drawer_w - 28, 16); y = y + 18
  for idx, mi in ipairs({{key="v_scroll",label="V-Scroll"},{key="h_scroll",label="H-Scroll"},{key="h_zoom",label="H-Zoom"},{key="v_zoom",label="V-Zoom"}}) do
    local bx, by = dx + 14 + ((idx-1)%2)*(hw+6), y + math.floor((idx-1)/2)*25
    register_btn("mod_"..mi.key, bx, by, hw, 22, mi.label..": "..state.wheel_mods[mi.key], false, function(cbx, cby, cbw, cbh)
      gfx.x, gfx.y = cbx, cby + cbh; local menu = ""; for _, mc in ipairs(MOD_CHOICES) do menu = menu .. (state.wheel_mods[mi.key] == mc and "!" or "") .. mc .. "|" end
      local c = gfx.showmenu(menu); if c >= 1 and c <= #MOD_CHOICES then state.wheel_mods[mi.key] = MOD_CHOICES[c]; save_global_prefs() end
    end)
  end
  y = y + 54

  gfx.setfont(1, "Segoe UI", 12); set_col(CONFIG.dark_mode and {0.78,0.82,0.88} or {0.30,0.33,0.38}); draw_text_left("NNS Colors 7 → 1 (1 = " .. CONFIG.note_names[state.tonic_pc + 1] .. ")", dx + 14, y, state.drawer_w - 28, 16); y = y + 18
  for row = 0, 5 do for col = 0, 1 do
    local s = 11 - (col * 6 + row); local def, cols = CONFIG.step_definitions[s], get_step_colors(s); local sx, sy = dx + 14 + col * (hw + 6), y + row * 21
    set_col(cols.active); draw_filled_roundrect(sx, sy, 26, 18, 4); set_col(contrast_text_col(cols.active)); gfx.setfont(1, "Segoe UI", 11); draw_text_centered(def.nns, sx, sy, 26, 18)
    set_col(CONFIG.dark_mode and {0.88,0.90,0.94} or {0.20,0.22,0.26}); draw_text_left(string.format("%s (%s)", CONFIG.note_names[(state.tonic_pc + s)%12 + 1], def.hex), sx + 30, sy, hw - 32, 18)
  end end
end

--------------------------------------------------------------------------------
-- 13. INPUT HANDLING
--------------------------------------------------------------------------------
local function match_wheel_mod(mod_name, ctrl, shift, alt)
  if mod_name == "None" then return not ctrl and not shift and not alt elseif mod_name == "Shift" then return shift and not ctrl and not alt
  elseif mod_name == "Ctrl" then return ctrl and not shift and not alt elseif mod_name == "Alt" then return alt and not ctrl and not shift
  elseif mod_name == "Ctrl+Shift" then return ctrl and shift and not alt end; return false
end

local function update_auto_scroll(canvas_w)
  if not state.auto_scroll or (reaper.GetPlayState() & 1) ~= 1 then return end
  if state.drag and (state.drag.type == "hscroll_pan" or state.drag.type == "hscroll_left" or state.drag.type == "hscroll_right") then return end
  local grid_w = get_grid_right_x(canvas_w) - state.keyboard_w; if grid_w <= 40 then return end
  local vqn, pqn = grid_w / state.px_per_qn, reaper.TimeMap2_timeToQN(0, reaper.GetPlayPosition())
  if pqn > state.scroll_x_qn + vqn * (2.0/3.0) then state.scroll_x_qn = math.max(0, pqn - vqn * (2.0/3.0))
  elseif pqn < state.scroll_x_qn then state.scroll_x_qn = math.max(0, pqn - vqn * 0.15) end
end

local function find_note_at(sx, sy)
  local hh = get_note_visual_h() * 0.5 + 2
  for i = #state.notes, 1, -1 do local n = state.notes[i]; local cy = pitch_center_screen_y(n.pitch); if sy >= cy - hh and sy <= cy + hh then local x1, x2 = qn_to_screen_x(n.start_qn), qn_to_screen_x(n.end_qn); if sx >= x1 - 3 and sx <= x2 + 3 then return n, (sx >= x2 - 7) and "right" or "body" end end end
  return nil, nil
end

local function find_manual_harmony_at(sx, sy)
  local hh = get_harmony_visual_h() * 0.5 + 2
  for i = #state.manual_harmony_notes, 1, -1 do local mh = state.manual_harmony_notes[i]; local cy = pitch_center_screen_y(mh.pitch); if sy >= cy - hh and sy <= cy + hh then local x1, x2 = qn_to_screen_x(mh.start_qn), qn_to_screen_x(mh.end_qn); if sx >= x1 - 3 and sx <= x2 + 3 then return mh, i, (sx >= x2 - 7) and "right" or "body" end end end
  return nil, nil, nil
end

local function find_curve_handle_at(sx, sy)
  if state.tool ~= "mpe" then return nil end
  for i = #state.curve_handles, 1, -1 do local h = state.curve_handles[i]; if math.abs(sx - h.x) <= 8 and math.abs(sy - h.y) <= 8 then return h end end
  return nil
end

local function handle_mouse()
  local mx, my, cap = gfx.mouse_x, gfx.mouse_y, gfx.mouse_cap
  local l_down, r_down, m_down = (cap&1)==1, (cap&2)==2, (cap&64)==64
  local l_prev, r_prev = (state.last_mouse_cap&1)==1, (state.last_mouse_cap&2)==2
  local l_pressed, l_released = l_down and not l_prev, not l_down and l_prev
  local r_pressed, r_released = r_down and not r_prev, not r_down and r_prev
  local m_pressed = m_down and not ((state.last_mouse_cap&64)==64)
  local ctrl, shift, alt = (cap&4)==4, (cap&8)==8, (cap&16)==16

  if state.section_glow_held and not l_down then state.section_glow_held = false; state.section_glow_until = reaper.time_precise() + 0.35 end
  local canvas_w = state.show_drawer and (gfx.w - state.drawer_w) or gfx.w
  local canvas_h = gfx.h - state.transport_h - state.param_bar_h - (state.show_vel_lane and state.vel_lane_h or 0)
  local grid_bottom_y, ruler_y, top_area, right_x = canvas_h - state.hscroll_h, get_ruler_y(), get_top_area_y(), get_grid_right_x(canvas_w)

  state.hover_pitch, state.hover_alt_seam = nil, nil
  if my >= top_area and my < grid_bottom_y and mx < right_x then
    local p = screen_y_to_pitch(my, alt); state.hover_pitch = p
    if state.view_mode == "diatonic" and alt and p and state.row_h[p] == 0 then state.hover_alt_seam = p end
  end

  if gfx.mouse_wheel ~= 0 then
    local steps = gfx.mouse_wheel / 120.0; gfx.mouse_wheel = 0
    local gw, gh = math.max(40, right_x - state.keyboard_w), math.max(40, grid_bottom_y - top_area)
    if mx < state.keyboard_w then state.scroll_y_px = clamp(state.scroll_y_px - steps * 36, 0, math.max(0, state.total_h - gh))
    elseif match_wheel_mod(state.wheel_mods.h_zoom, ctrl, shift, alt) then local c = state.scroll_x_qn + (gw*0.5)/state.px_per_qn; state.px_per_qn = clamp(state.px_per_qn*(1.15^steps), 20, 480); state.scroll_x_qn = math.max(0, c - (gw*0.5)/state.px_per_qn)
    elseif match_wheel_mod(state.wheel_mods.v_zoom, ctrl, shift, alt) then local cf = (state.scroll_y_px + gh*0.5)/math.max(1, state.total_h); state.v_scale = clamp(state.v_scale*(1.1^steps), 0.45, 3.0); rebuild_row_layout(); state.scroll_y_px = clamp(cf*state.total_h - gh*0.5, 0, math.max(0, state.total_h - gh))
    elseif match_wheel_mod(state.wheel_mods.h_scroll, ctrl, shift, alt) then state.auto_scroll = false; state.scroll_x_qn = math.max(0, state.scroll_x_qn - steps * 2.0)
    elseif match_wheel_mod(state.wheel_mods.v_scroll, ctrl, shift, alt) then state.scroll_y_px = clamp(state.scroll_y_px - steps * 36, 0, math.max(0, state.total_h - gh)) end
  end

  if state.active_slider then
    if l_down then local sl = state.active_slider; sl.on_change(lerp(sl.min_v, sl.max_v, clamp((mx-sl.x)/sl.w, 0, 1)))
    else
      local sid = state.active_slider.id
      if sid == "mpe_tail_ms" then save_global_prefs(); sync_section_clips()
      elseif sid:match("^sel_") or sid:match("^vib_") or sid == "swing_pct" then sync_section_clips()
      elseif sid == "in_scale_h" then save_global_prefs(); save_project_state() end
      state.active_slider = nil
    end
    state.last_mouse_cap = cap; return
  end

  if l_pressed or r_pressed then
    for i = #state.ui_controls, 1, -1 do
      local c = state.ui_controls[i]
      if mx >= c.x and mx <= c.x + c.w and my >= c.y and my <= c.y + c.h then
        if l_pressed then
          if c.is_slider then if c.id:match("^sel_") or c.id:match("^vib_") then push_undo() end; state.active_slider = c; c.on_change(lerp(c.min_v, c.max_v, clamp((mx-c.x)/c.w, 0, 1)))
          elseif c.on_click then c.on_click() end
        elseif r_pressed and c.on_right_click then c.on_right_click() end
        state.last_mouse_cap = cap; return
      end
    end
  end

  -- Bottom-right corner resize grip (cross-platform Windows & macOS via JS_Window_Resize)
  if l_pressed and state.frameless and mx >= gfx.w - 18 and my >= gfx.h - 18 and state.hwnd and reaper.JS_Window_GetRect and reaper.JS_Window_Resize then
    local _, wx, wt, wr, wb = reaper.JS_Window_GetRect(state.hwnd); local smx, smy = reaper.GetMousePosition()
    local ow, oh = math.abs(wr - wx), math.abs(wb - wt)
    state.drag = { type="win_resize", smx=smx, smy=smy, wx=wx, top=wt, ww=ow, wh=oh, fw=math.max(0, ow - gfx.w), fh=math.max(0, oh - gfx.h) }
    state.last_mouse_cap = cap; return
  end

  -- Frameless Dark Title Bar Move (uses Cocoa bottom-left Y on macOS, top-left Y on Windows/Linux)
  if l_pressed and state.frameless and my < state.titlebar_h and state.hwnd and reaper.JS_Window_GetRect and reaper.JS_Window_Move then
    local _, wx, wt, wr, wb = reaper.JS_Window_GetRect(state.hwnd); local smx, smy = reaper.GetMousePosition()
    state.drag = { type="win_move", smx=smx, smy=smy, wx=wx, wy=(IS_MAC and wb or wt) }
    state.last_mouse_cap = cap; return
  end

  if l_pressed and mx >= state.keyboard_w and mx < right_x and my >= ruler_y and my < top_area then
    reaper.SetEditCurPos(reaper.TimeMap2_QNToTime(0, math.max(0, snap_qn(screen_x_to_qn(mx)))), true, true)
    state.drag = { type="ruler_scrub" }; state.last_mouse_cap = cap; return
  end

  if l_pressed and state.hscroll_geom then
    local hs = state.hscroll_geom
    if mx >= hs.x and mx <= hs.x + hs.w and my >= hs.y and my <= hs.y + hs.h then
      state.auto_scroll = false; local edge = 12
      if mx >= hs.thumb_x and mx <= hs.thumb_x + edge then state.drag = { type="hscroll_left", hs=hs, right_qn=state.scroll_x_qn+hs.visible_qn, grid_w=right_x-state.keyboard_w }
      elseif mx >= hs.thumb_x+hs.thumb_w-edge and mx <= hs.thumb_x+hs.thumb_w then state.drag = { type="hscroll_right", hs=hs, left_qn=state.scroll_x_qn, grid_w=right_x-state.keyboard_w }
      elseif mx > hs.thumb_x+edge and mx < hs.thumb_x+hs.thumb_w-edge then state.drag = { type="hscroll_pan", hs=hs, start_mx=mx, orig_scroll=state.scroll_x_qn }
      else state.scroll_x_qn = clamp((mx-hs.x-hs.thumb_w*0.5)/math.max(1,hs.w-hs.thumb_w),0,1)*math.max(0,hs.max_qn-hs.visible_qn) end
      state.last_mouse_cap = cap; return
    end
  end

  if l_pressed and state.vscroll_geom then
    local vs = state.vscroll_geom
    if mx >= vs.x and mx <= vs.x + vs.w and my >= vs.y and my <= vs.y + vs.h then
      local edge, base_total_h = 12, state.total_h / state.v_scale
      if my >= vs.thumb_y and my <= vs.thumb_y + edge then state.drag = { type="vscroll_top", vs=vs, bottom_frac=clamp((state.scroll_y_px+vs.h)/vs.total_h,0.05,1.0), base_total_h=base_total_h }
      elseif my >= vs.thumb_y+vs.thumb_h-edge and my <= vs.thumb_y+vs.thumb_h then state.drag = { type="vscroll_bot", vs=vs, top_frac=clamp(state.scroll_y_px/vs.total_h,0.0,0.95), base_total_h=base_total_h }
      elseif my > vs.thumb_y+edge and my < vs.thumb_y+vs.thumb_h-edge then state.drag = { type="vscroll_pan", vs=vs, start_my=my, orig_scroll=state.scroll_y_px }
      else state.scroll_y_px = clamp((my-vs.y-vs.thumb_h*0.5)/math.max(1,vs.h-vs.thumb_h),0,1)*math.max(0,vs.total_h-vs.h) end
      state.last_mouse_cap = cap; return
    end
  end

  if m_pressed then state.auto_scroll = false; state.drag = { type="pan", start_mx=mx, start_my=my, orig_sx=state.scroll_x_qn, orig_sy=state.scroll_y_px } end

  if l_pressed and mx < state.keyboard_w and my >= top_area and my < grid_bottom_y then
    local p = screen_y_to_pitch(my, alt)
    if p then state.kbd_held_pitch = p; state.kbd_held_chan = 0; send_midi_note_on(p, state.default_vel, 0); check_preview_arm_hint(); state.drag = { type="keyboard" } end
  end

  if l_pressed and state.show_vel_lane and my >= canvas_h and my <= canvas_h + state.vel_lane_h and mx >= state.keyboard_w and mx < right_x then
    push_undo(); state.drag = { type="vel_lane", lane_top=canvas_h+4, lane_bottom=canvas_h+state.vel_lane_h-6 }
  end

  if mx >= state.keyboard_w and mx < right_x and my >= top_area and my < grid_bottom_y then
    if l_pressed then
      local hit_hnd = find_curve_handle_at(mx, my)
      if hit_hnd then
        push_undo(); deselect_all(); hit_hnd.note.selected = true
        state.drag = { type="node4_drag", kind=hit_hnd.kind, note=hit_hnd.note, dst=hit_hnd.dst, start_x=hit_hnd.x, start_y=hit_hnd.y, start_my=my,
          orig_pre_t=hit_hnd.note.pre_tension or 0, orig_out_t=hit_hnd.note.out_tension or 0, hover_dst=nil }
        state.last_mouse_cap = cap; return
      end
      if state.tool == "harmony" then
        local hit_h, _, edge = find_manual_harmony_at(mx, my)
        if hit_h then state.drag = (edge=="right") and {type="h_resize",note=hit_h,orig_end=hit_h.end_qn,start_mx=mx} or {type="h_move",note=hit_h,orig_s=hit_h.start_qn,orig_e=hit_h.end_qn,start_mx=mx}
        else
          local p, qn = screen_y_to_pitch(my, alt), snap_floor_qn(screen_x_to_qn(mx))
          if p and qn >= 0 then
            local mh = {id=state.next_harm_id,pitch=p,pc=p%12,start_qn=qn,end_qn=qn+get_grid_qn()}; state.next_harm_id=state.next_harm_id+1
            table.insert(state.manual_harmony_notes, mh); save_project_state(); state.drag={type="h_create",note=mh,anchor_qn=qn}
          end
        end
      else
        local hit_note, hit_edge = find_note_at(mx, my)
        if hit_note then
          push_undo(); if not shift and not hit_note.selected then deselect_all() end; hit_note.selected = true
          local orig = {}; for _, n in ipairs(state.notes) do if n.selected then orig[n.id] = { s=n.start_qn, e=n.end_qn, dur=n.end_qn - n.start_qn, p=n.pitch } end end
          if hit_edge == "right" then
            state.drag = { type="resize", anchor=hit_note, orig_end=hit_note.end_qn, orig_dur=hit_note.end_qn - hit_note.start_qn, start_mx=mx, orig=orig }
          else
            trigger_preview_note(hit_note.pitch, hit_note.vel, hit_note.chan, 0.20)
            state.drag = { type="move", anchor=hit_note, start_mx=mx, orig=orig, last_preview_p=hit_note.pitch }
          end
        elseif state.tool == "draw" then
          local p, qn = screen_y_to_pitch(my, alt), snap_floor_qn(screen_x_to_qn(mx))
          if p and qn >= 0 then
            push_undo(); deselect_all()
            local g, owner_sec = get_grid_qn(), find_section_at_qn(qn)
            local sec_uid = owner_sec and owner_sec.uid or state.selected_section_uid; local is_ov = (owner_sec==nil and sec_uid~=nil)
            local batch, primary = {}, nil
            for _, t_qn in ipairs(get_repetition_start_qns(qn, owner_sec, shift, ctrl)) do
              local nn = make_default_note({ id=state.next_note_id, selected=(math.abs(t_qn-qn)<1e-4), start_qn=t_qn, end_qn=t_qn+g, pitch=p, vel=state.default_vel, section_uid=sec_uid, section_override=is_ov })
              state.next_note_id = state.next_note_id + 1; table.insert(state.notes, nn); table.insert(batch, nn)
              if math.abs(t_qn-qn)<1e-4 then primary = nn end
            end
            primary = primary or batch[1]; trigger_preview_note(p, primary.vel, primary.chan, 0.22)
            state.drag = { type="create_batch", primary=primary, batch=batch, anchor_qn=qn }
          end
        else
          if not shift then deselect_all() end
          state.marquee = { x1=mx, y1=my, x2=mx, y2=my }; state.drag = { type="marquee" }
        end
      end
    elseif r_pressed then
      local hit_hnd = find_curve_handle_at(mx, my)
      if hit_hnd then
        if hit_hnd.kind == "n1" then push_undo(); reset_pre_bend(hit_hnd.note); sync_section_clips(); state.status_msg = "Reset pre-bend (Green/Black)"; state.last_mouse_cap = cap; return
        elseif hit_hnd.kind == "n4" then push_undo(); reset_bend_out(hit_hnd.note); sync_section_clips(); state.status_msg = "Reset bend-out (White/Red)"; state.last_mouse_cap = cap; return
        elseif hit_hnd.kind == "out_mid" or hit_hnd.kind == "pre_mid" then
          gfx.x, gfx.y = mx, my; local n = hit_hnd.note; local is_pre = (hit_hnd.kind == "pre_mid"); local menu = ""
          local cur_sh = is_pre and (n.pre_shape or "s_curve") or (n.out_shape or "s_curve")
          for _, cs in ipairs(CONFIG.curve_shapes) do menu = menu .. (cur_sh == cs.id and "!" or "") .. cs.label .. "|" end
          if hit_hnd.is_connection then menu = menu .. "|Disconnect Slide" end
          local c = gfx.showmenu(menu)
          if c >= 1 and c <= #CONFIG.curve_shapes then push_undo(); if is_pre then n.pre_shape=CONFIG.curve_shapes[c].id else n.out_shape=CONFIG.curve_shapes[c].id end; sync_section_clips()
          elseif hit_hnd.is_connection and c == #CONFIG.curve_shapes + 1 then push_undo(); disconnect_note_outgoing(n); sync_section_clips() end
          state.last_mouse_cap = cap; return
        end
      end

      if state.tool == "harmony" then
        local hh, hi = find_manual_harmony_at(mx, my)
        if hh and hi then table.remove(state.manual_harmony_notes, hi); save_project_state()
        else state.drag = { type="marquee_r", start_x=mx, start_y=my, moved=false } end
      else
        local hn = find_note_at(mx, my)
        if hn then
          push_undo()
          if (shift or ctrl) and hn.section_uid then
            local del_qns = get_repetition_start_qns(hn.start_qn, get_section_by_uid(hn.section_uid), shift, ctrl)
            for k = #state.notes, 1, -1 do
              local cand = state.notes[k]
              if cand.section_uid == hn.section_uid and cand.pitch == hn.pitch then
                for _, dq in ipairs(del_qns) do if math.abs(cand.start_qn - dq) < 1e-3 then remove_note_by_index(k) break end end
              end
            end
          else for i, n in ipairs(state.notes) do if n.id == hn.id then remove_note_by_index(i) break end end end
          compute_section_overflows(); sync_section_clips()
        else
          state.drag = { type="marquee_r", start_x=mx, start_y=my, moved=false }
        end
      end
    end
  end

  if state.drag then
    local d = state.drag
    if d.type == "win_move" and l_down then
      local smx, smy = reaper.GetMousePosition()
      reaper.JS_Window_Move(state.hwnd, d.wx + (smx - d.smx), d.wy + (smy - d.smy))
    elseif d.type == "win_resize" and l_down then
      local smx, smy = reaper.GetMousePosition()
      local dx = smx - d.smx
      local dy = IS_MAC and (d.smy - smy) or (smy - d.smy) -- macOS GetMousePosition Y is bottom-to-top!
      local new_w = math.max(MIN_WIN_W + d.fw, d.ww + dx)
      local new_h = math.max(MIN_WIN_H + d.fh, d.wh + dy)
      if IS_MAC and reaper.JS_Window_SetPosition then
        -- Cocoa Y increases upward. Preserve the original top edge while extending downward.
        reaper.JS_Window_SetPosition(state.hwnd, d.wx, d.top - new_h, new_w, new_h)
      else
        reaper.JS_Window_Resize(state.hwnd, new_w, new_h)
      end
    elseif d.type == "ruler_scrub" and l_down then
      reaper.SetEditCurPos(reaper.TimeMap2_QNToTime(0, math.max(0, snap_qn(screen_x_to_qn(mx)))), true, true)
    elseif d.type == "hscroll_pan" and l_down then
      state.scroll_x_qn = clamp(d.orig_scroll + ((mx-d.start_mx)/d.hs.w)*d.hs.max_qn, 0, math.max(0, d.hs.max_qn-d.hs.visible_qn))
    elseif d.type == "hscroll_left" and l_down then
      local nl = clamp(((mx-d.hs.x)/d.hs.w)*d.hs.max_qn, 0, d.right_qn - math.max(1.0, d.grid_w/480.0))
      state.px_per_qn = clamp(d.grid_w/(d.right_qn-nl), 20, 480); state.scroll_x_qn = math.max(0, d.right_qn - d.grid_w/state.px_per_qn)
    elseif d.type == "hscroll_right" and l_down then
      local nr = clamp(((mx-d.hs.x)/d.hs.w)*d.hs.max_qn, d.left_qn + math.max(1.0, d.grid_w/480.0), d.hs.max_qn*1.4)
      state.px_per_qn = clamp(d.grid_w/(nr-d.left_qn), 20, 480)
    elseif d.type == "vscroll_pan" and l_down then
      state.scroll_y_px = clamp(d.orig_scroll + ((my-d.start_my)/d.vs.h)*d.vs.total_h, 0, math.max(0, d.vs.total_h-d.vs.h))
    elseif d.type == "vscroll_top" and l_down then
      local nt = clamp((my-d.vs.y)/d.vs.h, 0.0, d.bottom_frac-0.06)
      state.v_scale = clamp(d.vs.h/((d.bottom_frac-nt)*d.base_total_h), 0.45, 3.0); rebuild_row_layout()
      state.scroll_y_px = clamp(d.bottom_frac*state.total_h - d.vs.h, 0, math.max(0, state.total_h-d.vs.h))
    elseif d.type == "vscroll_bot" and l_down then
      local nb = clamp((my-d.vs.y)/d.vs.h, d.top_frac+0.06, 1.0)
      state.v_scale = clamp(d.vs.h/((nb-d.top_frac)*d.base_total_h), 0.45, 3.0); rebuild_row_layout()
      state.scroll_y_px = clamp(d.top_frac*state.total_h, 0, math.max(0, state.total_h-d.vs.h))
    elseif d.type == "pan" and m_down then
      state.scroll_x_qn = math.max(0, d.orig_sx - (mx-d.start_mx)/state.px_per_qn)
      state.scroll_y_px = clamp(d.orig_sy - (my-d.start_my), 0, math.max(0, state.total_h-(grid_bottom_y-top_area)))
    elseif d.type == "keyboard" and l_down then
      local p = screen_y_to_pitch(my, alt)
      if p and p ~= state.kbd_held_pitch then
        if state.kbd_held_pitch then send_midi_note_off(state.kbd_held_pitch,0) end
        state.kbd_held_pitch=p; send_midi_note_on(p,state.default_vel,0); check_preview_arm_hint()
      end
    elseif (d.type == "h_create" or d.type == "h_resize") and l_down then
      d.note.end_qn = math.max(((d.type=="h_create") and d.anchor_qn or d.note.start_qn) + get_grid_qn()*0.25, snap_qn(screen_x_to_qn(mx)))
    elseif d.type == "h_move" and l_down then
      d.note.start_qn = math.max(0, snap_qn(d.orig_s + (mx-d.start_mx)/state.px_per_qn)); d.note.end_qn = d.note.start_qn + (d.orig_e-d.orig_s)
      local np = screen_y_to_pitch(my, alt); if np then d.note.pitch=np; d.note.pc=np%12 end
    elseif d.type == "vel_lane" and l_down then
      local qn = screen_x_to_qn(mx); local nv = clamp(math.floor(((d.lane_bottom-my)/math.max(10,d.lane_bottom-d.lane_top))*127+0.5),1,127)
      for _, n in ipairs(state.notes) do if get_incoming_note(n.id)==nil and math.abs(n.start_qn-qn)*state.px_per_qn<14 then n.vel=nv end end
    elseif d.type == "node4_drag" and l_down then
      local n, qn = d.note, screen_x_to_qn(mx)
      local frac = (qn - n.start_qn) / math.max(0.01, n.end_qn - n.start_qn)
      local has_inc = (get_incoming_note(n.id) ~= nil)
      if d.kind == "n1" then
        n.t1 = clamp(frac, 0.0, (n.t2 or 0.35) - 0.04)
        local tp = screen_y_to_pitch(my, alt)
        if tp then
          local old_st = n.pre_st; n.pre_st = clamp(tp - n.pitch, -state.mpe_bend_range, state.mpe_bend_range)
          if not validate_chain_bend_range(get_chain_root(n)) then n.pre_st = old_st end
          state.status_msg = string.format("Pre-Bend: %s (%+.1f st)%s", get_key_left_right_labels(n.pitch + n.pre_st), n.pre_st, alt and " [Alt:Chromatic]" or "")
        end
      elseif d.kind == "n2" then n.t2 = clamp(frac, has_inc and 0.0 or ((n.t1 or 0.05) + 0.04), (n.t3 or 0.65) - 0.04)
      elseif d.kind == "n3" then n.t3 = clamp(frac, (n.t2 or 0.0) + 0.04, d.dst and 0.99 or ((n.t4 or 0.95) - 0.04))
      elseif d.kind == "n4" then
        local cand = find_note_at(mx, my)
        if cand and cand.id ~= n.id then d.hover_dst = cand
        else
          d.hover_dst = nil; n.t4 = clamp(frac, (n.t3 or 0.65) + 0.04, 1.0)
          local tp = screen_y_to_pitch(my, alt)
          if tp then
            local old_st = n.out_st; n.out_st = clamp(tp - n.pitch, -state.mpe_bend_range, state.mpe_bend_range)
            if not validate_chain_bend_range(get_chain_root(n)) then n.out_st = old_st end
            state.status_msg = string.format("Out-Bend: %s (%+.1f st)%s", get_key_left_right_labels(n.pitch + n.out_st), n.out_st, alt and " [Alt:Chromatic]" or "")
          end
        end
      elseif d.kind == "pre_mid" then n.pre_tension = clamp(d.orig_pre_t + (d.start_my - my) / 50.0, -1.0, 1.0)
      elseif d.kind == "out_mid" then n.out_tension = clamp(d.orig_out_t + (d.start_my - my) / 50.0, -1.0, 1.0) end
    elseif d.type == "create_batch" and l_down then
      -- One full cell on click; extend by whole cells as the cursor enters them.
      -- Snapping the endpoint to the nearest grid line used to collapse new notes
      -- to a quarter-cell length on the first mouse-held frame.
      local g = get_grid_qn()
      local cells = math.floor((screen_x_to_qn(mx) - d.anchor_qn) / g + 1e-6) + 1
      local nd = math.max(g, cells * g)
      for _, bn in ipairs(d.batch) do bn.end_qn = bn.start_qn + nd end
    elseif d.type == "resize" and l_down then
      -- Scale from the mouse-down originals on EVERY frame, never from
      -- temporarily clamped lengths (so dragging back out fully restores them).
      local dqn = (mx - d.start_mx) / state.px_per_qn
      local g = get_grid_qn()
      local resize_step = g * 0.25
      local step_count = math.floor(dqn / resize_step + 0.5)
      local selected_count = 0
      for _ in pairs(d.orig) do selected_count = selected_count + 1 end
      -- One note: quarter of current grid. Multiple: 1/32 or 1/32T.
      local floor_qn = (selected_count > 1) and (state.triplet and (1/12) or (1/8)) or resize_step
      local anchor_floor = math.min(d.orig_dur, floor_qn)
      local new_anchor_dur = math.max(anchor_floor, d.orig_dur + step_count * resize_step)
      local ratio = new_anchor_dur / math.max(1e-5, d.orig_dur)
      local cnt = 0
      for _, n in ipairs(state.notes) do
        local o = d.orig[n.id]
        if o then
          local n_floor = math.min(o.dur, floor_qn)
          n.end_qn = o.s + math.max(n_floor, o.dur * ratio)
          cnt = cnt + 1
        end
      end
      if cnt > 1 then state.status_msg = string.format("Resize (%d notes): %.2fx", cnt, ratio) end
    elseif d.type == "move" and l_down then
      local dqn, tp, ao = (mx-d.start_mx)/state.px_per_qn, screen_y_to_pitch(my, alt) or d.anchor.pitch, d.orig[d.anchor.id]
      local adqn, dp = snap_qn(ao.s+dqn) - ao.s, tp - ao.p
      for _, n in ipairs(state.notes) do
        local o = d.orig[n.id]
        if o then
          local old_p = n.pitch; n.start_qn = math.max(0, o.s + adqn); n.end_qn = n.start_qn + (o.e - o.s)
          local np = clamp(o.p + dp, 0, 127)
          if state.view_mode == "diatonic" and not alt and not is_pitch_diatonic(np) then np = step_pitch_diatonic(np, dp>=0 and 1 or -1) end
          n.pitch = np; if not validate_chain_bend_range(get_chain_root(n)) then n.pitch = old_p end
          if not n.section_override then local s = find_section_at_qn(n.start_qn); if s then n.section_uid = s.uid end end
        end
      end
      if d.anchor.pitch ~= d.last_preview_p then d.last_preview_p = d.anchor.pitch; trigger_preview_note(d.anchor.pitch, d.anchor.vel, d.anchor.chan, 0.20) end
    elseif d.type == "marquee" and l_down then
      state.marquee.x2, state.marquee.y2 = mx, my
    elseif d.type == "marquee_r" and r_down then
      if not d.moved and (math.abs(mx - d.start_x) > 4 or math.abs(my - d.start_y) > 4) then d.moved = true end
      if d.moved then state.marquee = { x1 = d.start_x, y1 = d.start_y, x2 = mx, y2 = my } end
    end

    local released = (d.type=="pan" and not m_down) or (d.type=="marquee_r" and r_released) or (d.type~="pan" and d.type~="marquee_r" and l_released)
    if released then
      if d.type == "win_move" or d.type == "win_resize" then
        save_global_prefs()
      elseif d.type == "keyboard" and state.kbd_held_pitch then
        send_midi_note_off(state.kbd_held_pitch, 0); state.kbd_held_pitch = nil
      elseif d.type == "node4_drag" then
        if d.kind == "n4" and d.hover_dst then
          local ok, msg = can_connect_notes(d.note, d.hover_dst)
          if ok then connect_notes(d.note, d.hover_dst); state.status_msg = "Connected note slide"
          else state.status_msg = msg or "Connection rejected" end
        end
        compute_section_overflows(); sync_section_clips()
      elseif d.type == "h_create" or d.type == "h_resize" or d.type == "h_move" then
        save_project_state()
      elseif d.type == "marquee" or d.type == "marquee_r" then
        if d.type == "marquee_r" and not d.moved then
          deselect_all(); state.status_msg = "Selection cleared"
        elseif state.marquee then
          if d.type == "marquee_r" and not shift then deselect_all() end
          local x1, x2 = math.min(state.marquee.x1, state.marquee.x2), math.max(state.marquee.x1, state.marquee.x2)
          local y1, y2 = math.min(state.marquee.y1, state.marquee.y2), math.max(state.marquee.y1, state.marquee.y2)
          local hh = get_note_visual_h() * 0.5
          for _, n in ipairs(state.notes) do
            local nx1, nx2, cy = qn_to_screen_x(n.start_qn), qn_to_screen_x(n.end_qn), pitch_center_screen_y(n.pitch)
            if nx2>=x1 and nx1<=x2 and cy+hh>=y1 and cy-hh<=y2 then n.selected=true end
          end
        end
        state.marquee = nil
      elseif d.type == "create_batch" or d.type == "resize" or d.type == "move" or d.type == "vel_lane" then
        compute_section_overflows(); sync_section_clips()
      end
      state.drag = nil
    end
  end
  state.last_mouse_cap = cap
end

local function handle_keyboard()
  local char = gfx.getchar()
  if char < 0 or state.should_close then return false end
  if char == 0 then return true end
  local cap = gfx.mouse_cap; local ctrl, shift, alt = (cap&4)==4, (cap&8)==8, (cap&16)==16
  if char == 27 then deselect_all(); state.status_msg = "Selection cleared"
  elseif char == 30064 then move_selected_by_arrows(1, 0, shift, alt, ctrl)
  elseif char == 1685026670 then move_selected_by_arrows(-1, 0, shift, alt, ctrl)
  elseif char == 1818584692 then move_selected_by_arrows(0, -1, shift, alt, false)
  elseif char == 1919379572 then move_selected_by_arrows(0, 1, shift, alt, false)
  elseif char == 6579564 or char == 8 then delete_selected()
  elseif char == 32 then reaper.Main_OnCommand(40044, 0)
  elseif char == 26169 then state.transport_action(2)
  elseif char == 6697264 then state.transport_action(3)
  elseif char == 6697265 then state.transport_action(4)
  elseif char == 6697266 then state.transport_action(5)
  elseif char == 33 then state.transport_action(1)
  elseif char == 0x686f6d65 then state.transport_action(7)
  elseif char == 0x7067646e then state.transport_action(8)
  elseif char == 0x70677570 then state.transport_action(9)
  elseif char == 0x656e64 then state.transport_action(10)
  elseif not ctrl and not alt and (char == 109 or char == 77) then toggle_mute_selected()
  elseif char == 1 or (ctrl and (char == 65 or char == 97)) then select_all()
  elseif char == 3 or (ctrl and (char == 67 or char == 99)) then copy_selected()
  elseif char == 22 or (ctrl and (char == 86 or char == 118)) then paste_notes()
  elseif char == 4 or (ctrl and (char == 68 or char == 100)) then duplicate_selected()
  elseif (char == 26 and shift) or char == 25 or (ctrl and (char == 89 or char == 121)) then pop_redo()
  elseif char == 26 or (ctrl and (char == 90 or char == 122)) then pop_undo()
  elseif char == 113 or char == 81 then quantize_selected() end
  return true
end

--------------------------------------------------------------------------------
-- 14. MAIN LOOP & INIT
--------------------------------------------------------------------------------
local function read_hub_request()
  local raw=reaper.GetExtState(HUB_EXT_SEC,"request")
  if raw=="" then return end
  local project,guid,region,stamp=raw:match("^([^\t]+)\t([^\t]+)\t([^\t]+)\t([^\t]+)$")
  if project~=owner_project_key then return end
  reaper.DeleteExtState(HUB_EXT_SEC,"request",false)
  if not tonumber(stamp) or math.abs(reaper.time_precise()-tonumber(stamp))>15 then return end
  for i=0,reaper.CountTracks(owner_project)-1 do
    local tr=reaper.GetTrack(owner_project,i)
    if reaper.GetTrackGUID(tr)==guid then return tr,tonumber(region) end
  end
end
local function apply_hub_request(tr,region)
  if not tr or not reaper.ValidatePtr2(owner_project,tr,"MediaTrack*") then return end
  local guid=reaper.GetTrackGUID(tr)
  if state.output_track_guid~="" and state.output_track_guid~=guid
      or state.output_track_guid=="" and (#state.notes>0 or state.commit_state~="none") then
    reaper.MB("Topline currently has one draft per project. It is already associated with another track (or an unassigned draft). No notes or routing have been changed. Independent Topline tracks are not yet supported.","N2N Topline",0)
    return
  end
  if state.output_track~=tr then select_output_track(tr) end
  reaper.GetSetMediaTrackInfo_String(tr,"P_EXT:N2N:TOPLINE","1",true)
  if region and region>=0 then
    refresh_regions_and_sections()
    for _,sec in ipairs(state.sections) do
      if not sec.deleted and sec.markrgn_num==region then
        state.selected_section_uid=sec.uid
        state.selected_phrase=nil
        state.scroll_x_qn=math.max(0,sec.start_qn)
        state.auto_scroll=false
        state.section_glow_uid=sec.uid
        state.section_glow_until=reaper.time_precise()+.65
        state.status_msg="Jumped to ["..sec.name.."]"
        break
      end
    end
  end
  state.raise_window(state.hwnd)
end
local function main()
  if reaper.EnumProjects(-1,"")~=owner_project then state.capture_window();on_script_exit();gfx.quit();return end
  reaper.SetExtState(HUB_EXT_SEC,"heartbeat",tostring(reaper.time_precise()),false)
  if reaper.GetExtState(HUB_EXT_SEC,"focus")~="" then
    reaper.DeleteExtState(HUB_EXT_SEC,"focus",false)
    if reaper.JS_Window_Find and reaper.JS_Window_SetFocus then
      state.hwnd=state.hwnd or reaper.JS_Window_Find(WIN_TITLE,true)
      state.raise_window(state.hwnd)
    end
  end
  if not state.drag and (gfx.mouse_cap&3)==0 then
    local requested,region=read_hub_request()
    if requested then apply_hub_request(requested,region) end
  end
  state.ui_controls = {}
  update_previews()
  if not handle_keyboard() then on_script_exit();gfx.quit();return end

  -- Cross-platform minimum size enforcement (1200x640 client area via JS_Window_Resize)
  if gfx.dock(-1) == 0 and (gfx.w < MIN_WIN_W or gfx.h < MIN_WIN_H) and (not state.drag or state.drag.type ~= "win_resize") then
    if not state.hwnd and reaper.JS_Window_Find then state.hwnd = reaper.JS_Window_Find(WIN_TITLE, true) end
    if state.hwnd and reaper.JS_Window_Resize and reaper.JS_Window_GetRect then
      local _, wx, wt, wr, wb = reaper.JS_Window_GetRect(state.hwnd)
      if wx and wr then
        local ow, oh = math.abs(wr - wx), math.abs(wb - wt)
        local fw, fh = math.max(0, ow - gfx.w), math.max(0, oh - gfx.h)
        local new_w, new_h = math.max(MIN_WIN_W + fw, ow), math.max(MIN_WIN_H + fh, oh)
        if IS_MAC and reaper.JS_Window_SetPosition then
          reaper.JS_Window_SetPosition(state.hwnd, wx, wt - new_h, new_w, new_h)
        else
          reaper.JS_Window_Resize(state.hwnd, new_w, new_h)
        end
      end
    end
  end

  local now = reaper.time_precise()
  state.capture_window()
  if now-state.last_view_save>2 then
    state.last_view_save=now
    local sig=table.concat({state.win_x,state.win_y,state.win_w,state.win_h,state.px_per_qn,state.v_scale,state.scroll_x_qn,state.scroll_y_px},":")
    if state.view_sig~=sig then state.view_sig=sig;save_global_prefs() end
  end
  if now - state.last_region_poll > 0.75 then state.last_region_poll = now; refresh_regions_and_sections() end
  if now - state.last_chart_poll > 0.75 then state.last_chart_poll = now; refresh_chord_charts() end
  if state.harmony_source == "gmem" and (now - state.last_gmem_poll > 0.35) then
    state.last_gmem_poll = now; read_gmem_harmony(false)
    if (state.groove_enabled or state.swing_from_gmem) and read_gmem_groove_and_swing() then sync_section_clips() end
  end

  local canvas_w = state.show_drawer and (gfx.w - state.drawer_w) or gfx.w
  local canvas_h = gfx.h - state.transport_h - state.param_bar_h - (state.show_vel_lane and state.vel_lane_h or 0)
  local grid_bottom_y = canvas_h - state.hscroll_h
  update_auto_scroll(canvas_w)

  gfx.clear = pack_color(table.unpack(CONFIG.dark_mode and {0.10,0.11,0.14} or {0.98,0.98,0.99}))
  draw_3_layer_grid_and_notes(canvas_w, grid_bottom_y)
  draw_keyboard(grid_bottom_y)
  draw_regions_bar(canvas_w)
  draw_chord_lanes_and_reserved(canvas_w)
  draw_ruler(canvas_w)
  draw_horizontal_scrollbar(canvas_w, grid_bottom_y)
  draw_vertical_scrollbar(canvas_w, grid_bottom_y)
  draw_bottom_controls(canvas_w)
  draw_transport_bar(canvas_w)
  draw_lanes_drawer()
  draw_toolbar()
  draw_custom_titlebar_and_resize_grip()
  state.draw_section_popup(canvas_w)

  handle_mouse()
  gfx.update()
  reaper.defer(main)
end

local function restore_output_track_by_guid_or_default()
  if state.output_track_guid and state.output_track_guid ~= "" then
    for i = 0, reaper.CountTracks(0) - 1 do
      local tr = reaper.GetTrack(0, i)
      if reaper.GetTrackGUID(tr) == state.output_track_guid then
        local _, tn = reaper.GetTrackName(tr); if tn ~= HIDDEN_TRACK_NAME then select_output_track(tr); return end
      end
    end
  end
  local def_tr = find_track_by_name(DEFAULT_OUT_TRACK)
  if def_tr then select_output_track(def_tr); return end
  local sel_tr = reaper.GetSelectedTrack(0, 0)
  if sel_tr then local _, tn = reaper.GetTrackName(sel_tr); if tn ~= HIDDEN_TRACK_NAME then select_output_track(sel_tr) end end
end

local function setup_frameless_dark_titlebar()
  if reaper.JS_Window_Find then
    state.hwnd = reaper.JS_Window_Find(WIN_TITLE, true)
    apply_window_frame_style()
    -- gfx.init restores client size and screen location in a single call.
  end
end

local function init()
  local previous=reaper.GetExtState(HUB_EXT_SEC,"owner")
  local heartbeat=tonumber(reaper.GetExtState(HUB_EXT_SEC,"heartbeat"))
  if previous~="" and heartbeat and math.abs(reaper.time_precise()-heartbeat)<2 then return end
  reaper.SetExtState(HUB_EXT_SEC,"owner",hub_token,false)
  reaper.SetExtState(HUB_EXT_SEC,"heartbeat",tostring(reaper.time_precise()),false)
  load_global_prefs()
  local had_proj_state = load_project_state()
  state.load_session_view()
  local requested,region=read_hub_request()
  if requested then
    local guid=reaper.GetTrackGUID(requested)
    local hidden=find_track_by_name(HIDDEN_TRACK_NAME) or find_track_by_name(LEGACY_HIDDEN_NAME)
    local unassigned=state.output_track_guid=="" and
      (#state.notes>0 or state.commit_state~="none" or (hidden and reaper.CountTrackMediaItems(hidden)>0))
    if (state.output_track_guid~="" and state.output_track_guid~=guid) or unassigned then
      reaper.DeleteExtState(HUB_EXT_SEC,"owner",false)
      reaper.DeleteExtState(HUB_EXT_SEC,"heartbeat",false)
      reaper.MB("This project already has a Topline draft associated with another track (or an unassigned draft). Open the original track to continue. Independent Topline tracks are not yet supported.","N2N Topline",0)
      return
    end
  end
  refresh_regions_and_sections()
  if not had_proj_state then migrate_legacy_hidden_clip_if_needed() end
  refresh_chord_charts()
  read_gmem_harmony(true)
  read_gmem_groove_and_swing()
  rebuild_row_layout()

  ensure_hidden_track()
  -- For a fresh empty editor, bind the requested track before any default
  -- selection. For an existing draft, restore its owner and validate request.
  if requested then
    select_output_track(requested)
  else
    restore_output_track_by_guid_or_default()
  end
  if requested then apply_hub_request(requested,region) end
  update_hidden_track_send()
  compute_section_overflows()
  sync_section_clips()

  if not state.has_saved_view then state.scroll_y_px = math.max(0, (state.row_y[72] or 450)) end
  gfx.ext_retina = 1.0
  if state.has_saved_win_pos then
    gfx.init(WIN_TITLE, math.max(MIN_WIN_W,state.win_w),math.max(MIN_WIN_H,state.win_h),0,state.win_x,state.win_y)
  else gfx.init(WIN_TITLE,math.max(MIN_WIN_W,state.win_w),math.max(MIN_WIN_H,state.win_h),0) end
  setup_frameless_dark_titlebar()
  reaper.atexit(on_script_exit)
  main()
end

init()
