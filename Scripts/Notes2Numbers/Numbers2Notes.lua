-- @description Numbers2Notes
-- @version  1.8.1
-- @author Rock Kennedy
-- @about
--   # Numbers2Notes 1.8.1
--   Nashville Number System Style Chord Charting for Reaper.
--   Now includes automated setup wizard and non-destructive track handling.
-- @provides
--   numbers2notes_advanced_user_setup.lua
--   numbers2notes_config.lua
--   numbers2notes_form.lua
--   numbers2notes_gmem.lua
--   numbers2notes_help.lua
--   numbers2notes_musictheory.lua
--   numbers2notes_songs.lua
--   numbers2notes_spectrum.lua

-- @changelog
--   # Major Update 1.8.1
--   + Added Groove
--   + Changed N2N Drum Arranger to N2N Drum Arranger.jsfx
--   + Changed gmem name
--   + N2N Drum Arranger search fixed for Mac

package.path = reaper.ImGui_GetBuiltinPath() .. "/?.lua"
local ImGui = require "imgui" "0.8.6" -- Version of IMGUI used during development.

local info = debug.getinfo(1, "S")
-----------------------------------------------   REQUIRED FILES
local script_path = info.source:match [[^@?(.*[\/])[^\/]-$]]
package.path = package.path .. ";" .. "?.lua"
local advanced_user_setup = require(script_path .. "numbers2notes_advanced_user_setup")
local musictheory = require(script_path .. "numbers2notes_musictheory")
local spectrum = require(script_path .. "numbers2notes_spectrum")
local songs = require(script_path .. "numbers2notes_songs")
local help = require(script_path .. "numbers2notes_help")
local form = require(script_path .. "numbers2notes_form")
local config = require(script_path .. "numbers2notes_config")
local gmem_export = require(script_path .. "numbers2notes_gmem")
reaper.gmem_attach("N2N_Ecosystem_RSKennedy")
local track_table = config.track_table
local pluginsources = config.pluginsources
local G_startup_missing_report = ""

real_song_key = "C"
processing_key = "C"

-----------------------------------------------   GUI VARIABLES AND SETUP

down_key_check = 0
last_element = 0
error_zone = ""
fade_up = true
transpar = .5
chosentheorychord = 1
chord_charting_area = ""
lead1_charting_area = ""
lead2_charting_area = ""
liveMIDI_playing_timer = 0
current_playing_tone_array = {}
last_play_root = 0
auidition_key_shift = 0
audition_track = nil
lyrics_charting_area = ""
notes_charting_area = ""
user_left_section_empty = false
the_OM_fail = ""
OM_ex_warning = ""
cancel_OM_opperation = false
OMfalsesofar = 0
the_itemOM = ""

-- GLOBAL RENDER SETTINGS
G_render_mode = 0 -- 0 = Relative (Default), 1 = Absolute
G_DRUM_CUE_PLACEMENT = "Every 4 Bars"
G_ARP_CUE_PLACEMENT  = "Every Section"


-- Optional: Load saved state for this specific project if you want it to remember
local rv1, saved_mode = reaper.GetProjExtState(0, "N2N", "RenderMode")
if rv1 > 0 then G_render_mode = tonumber(saved_mode) end

local rv2, saved_drum_cue = reaper.GetProjExtState(0, "N2N", "DrumCueMode")
if rv2 > 0 and saved_drum_cue ~= "" then G_DRUM_CUE_PLACEMENT = saved_drum_cue end

local rv3, saved_arp_cue = reaper.GetProjExtState(0, "N2N", "ArpCueMode")
if rv3 > 0 and saved_arp_cue ~= "" then G_ARP_CUE_PLACEMENT = saved_arp_cue end

-- Inject loaded states into the UI Recipe so dropdowns match upon boot
for _, tr in ipairs(config.track_recipe) do
    if tr.type == 32 and rv2 > 0 then tr.drum_arp_mode = saved_drum_cue end
    if tr.type == 33 and rv3 > 0 then tr.drum_arp_mode = saved_arp_cue end
end























-- GROOVE VARIABLES
groove_data = {}
groove_anchors = {}
for i = 1, 32 do
    groove_data[i] = 0.0
    groove_anchors[i] = false
end
-- Default anchors on beat starts for convenience
groove_anchors[1] = true
groove_anchors[9] = true
groove_anchors[17] = true
groove_anchors[25] = true

local JSFX_data_request1 = {
    "Nashville Numbers",
    "Roman Numerals",
    "Relative Letter Labels",
    "Relative Chord Grid",
    "Relative Chords",
    "Relative Chords and bass",
    "Relative Roots and 5ths",
    "Relative Roots",
    "Relative Bass",
    "Absolute Letter Labels",
    "Absolute Chord Grid",
    "Absolute Chords",
    "Absolute Chords and bass",
    "Absolute Roots and 5ths",
    "Absolute Roots",
    "Absolute Bass",
    "Preferred Letter Labels",
    "Preferred Chord Grid",
    "Preferred Chords",
    "Preferred Chords and bass",
    "Preferred Roots and 5ths",
    "Preferred Roots",
    "Preferred Bass"
}

local JSFX_data_request2 = {
    "Unset",
    "C#",
    "D#",
    "F#",
    "G#",
    "A#",
    "Db",
    "Eb",
    "Gb",
    "Ab",
    "Bb",
    "C",
    "D",
    "E",
    "F",
    "G",
    "A",
    "B"
}

header_area = [[Title: 
Writer: 
BPM: 
Key: 
Swing: 
Form: # I V C V C C O]]

chord_charting_area = [[
{#}
- -

{I}




{V}  




{C}




{B}




{O}



]]

-- Interpolate values between checked anchors
function Groove_Interpolate()
    -- 1. Find all active anchor indices
    local indices = {}
    for i = 1, 32 do
        if groove_anchors[i] then
            table.insert(indices, i)
        end
    end

    local count = #indices
    if count == 0 then
        return
    end -- Nothing to do

    -- Single anchor? Flatten the whole board to that value
    if count == 1 then
        local val = groove_data[indices[1]]
        for i = 1, 32 do
            groove_data[i] = val
        end
        Export_Groove_To_GMEM()
        return
    end

    -- 2. Loop through pairs (including the wrap-around)
    for k = 1, count do
        local start_idx = indices[k]
        local end_idx = indices[(k % count) + 1] -- Wraps back to index 1

        local start_val = groove_data[start_idx]
        local end_val = groove_data[end_idx]

        -- Calculate distance (handling wrap)
        local dist = end_idx - start_idx
        if dist < 0 then
            dist = dist + 32
        end

        if dist > 1 then
            local step_val = (end_val - start_val) / dist

            -- Fill the gaps
            for j = 1, dist - 1 do
                local target_idx = (start_idx + j - 1) % 32 + 1
                groove_data[target_idx] = start_val + (step_val * j)
            end
        end
    end

    Export_Groove_To_GMEM()
end

-- Save to GMEM (Offset 5,000,000)
function Export_Groove_To_GMEM()
    -- Ensure we are attached to the right namespace

    for i = 1, 32 do
        -- Lua arrays are 1-based, GMEM is 0-based offset
        -- Write to 5,000,000 to 5,000,031
        reaper.gmem_write(5000000 + (i - 1), groove_data[i])
    end
end

-- GROOVE I/O FUNCTIONS
function Save_Groove()
    local retval, file =
        reaper.JS_Dialog_BrowseForSaveFile("Save Groove Preset", "", "MyGroove.n2ng", "N2N Groove (*.n2ng)\0*.n2ng\0")
    if retval and file ~= "" then
        -- Add extension if missing
        if not file:match("%.n2ng$") then
            file = file .. ".n2ng"
        end

        local f = io.open(file, "w")
        if f then
            for i = 1, 32 do
                f:write(tostring(groove_data[i]) .. "\n")
            end
            f:close()
        end
    end
end

function set_the_time_sig(stk_progression)
    -- Default to 4/4 if missing
    local num = 4
    local den = 4

    local _, time_start = string.find(stk_progression, "Time:")

    if time_start then
        -- Find end of line
        local line_end = string.find(stk_progression, "\n", time_start)
        if not line_end then
            line_end = string.len(stk_progression)
        end

        -- Extract string "3/4" or "6/8"
        local time_str = string.sub(stk_progression, time_start + 1, line_end)

        -- Find the slash
        local slash = string.find(time_str, "/")

        if slash then
            -- Extract numbers
            local n_str = string.sub(time_str, 1, slash - 1)
            local d_str = string.sub(time_str, slash + 1)

            -- Clean and convert
            num = tonumber(string.match(n_str, "%d+")) or 4
            den = tonumber(string.match(d_str, "%d+")) or 4
        else
            -- Handle "3" or "4" (implied over 4)
            num = tonumber(string.match(time_str, "%d+")) or 4
        end
    end

    return num, den
end

function Load_Groove()
    local retval, file = reaper.GetUserFileNameForRead("", "Load Groove Preset", "n2ng")
    if retval then
        local f = io.open(file, "r")
        if f then
            local i = 1
            for line in f:lines() do
                if i <= 32 then
                    groove_data[i] = tonumber(line) or 0.0
                end
                i = i + 1
            end
            f:close()
        end
    end
end
-- ________________________________________________________ PLUGIN AUDIT SYSTEM

function Check_Plugins_On_Startup()
    reaper.PreventUIRefresh(1)

    local missing_log = {}
    local missing_count = 0

    -- Core Engine Plugins + Bundled VSTis required for N2N to function
    local core_plugins = {
        {name = "pad-synth", ext = ".jsfx", source = 4},
        {name = "SwingProjectMIDI", ext = "", source = 3},
        {name = "N2N Chooser", ext = ".jsfx", source = 3},
        {name = "N2N Arp", ext = ".jsfx", source = 3},
        {name = "N2N Drum Arranger", ext = ".jsfx", source = 3},
        -- Added your bundled VSTis (Fallback strings will catch VST3 vs CLAP differences)
        {name = "CLAP: Surge XT", fallback = "VST3i: Surge XT", ext = "", source = 8},
        {name = "Pro Punk Drums", fallback = "VSTi: Pro Punk Drums", ext = "", source = 10}
    }

    local track_idx = reaper.CountTracks(0)
    reaper.InsertTrackAtIndex(track_idx, false)
    local temp_track = reaper.GetTrack(0, track_idx)

    for _, plug in ipairs(core_plugins) do
        local index = reaper.TrackFX_AddByName(temp_track, plug.name, false, 1)

        -- Try extension fallback
        if index == -1 and plug.ext ~= "" then
            index = reaper.TrackFX_AddByName(temp_track, plug.name .. plug.ext, false, 1)
        end

        -- Try alternate format fallback (e.g. VST3i instead of CLAP)
        if index == -1 and plug.fallback then
            index = reaper.TrackFX_AddByName(temp_track, plug.fallback, false, 1)
        end

        if index == -1 then
            missing_count = missing_count + 1
            local source_msg = config.pluginsources[plug.source] or "Unknown Source"
            table.insert(missing_log, "CRITICAL MISSING: '" .. plug.name .. "'\nSource: " .. source_msg)
        else
            reaper.TrackFX_Delete(temp_track, index)
        end
    end

    reaper.DeleteTrack(temp_track)
    reaper.PreventUIRefresh(-1)

    if missing_count > 0 then
        G_startup_missing_report =
            "SYSTEM NOT READY: " ..
            missing_count .. " CORE COMPONENTS MISSING\n\n" .. "The script cannot operate without these plugins.\n\n"
        for _, msg in pairs(missing_log) do
            G_startup_missing_report = G_startup_missing_report .. msg .. "\n\n"
        end
        return true
    else
        return false
    end
end

-----------------------------------------------                 AUTO LOAD LAST NUMBERS2NOTES CHART
function LoadLastNumbers2NotesChart()
    local info = debug.getinfo(1, "S")
    local path = info.source:match [[^@?(.*[\/])[^\/]-$]]
    local chordchart_path = path .. "ChordCharts/"
    local filenamewillbe = "Last_Numbers2Notes_Chart.txt"
    local full_path = chordchart_path .. filenamewillbe

    -- 1. SET SAFE DEFAULTS
    if header_area == nil or header_area == "" then
        header_area = [[Title: 
Writer: 
BPM: 
Key: 
Swing: 
Form: # I V C V C B C O]]
    end

    if chord_charting_area == nil or chord_charting_area == "" then
        chord_charting_area = [[
{#}
- -

{I}




{V}  




{C}




{B}




{O}



]]
    end

    if lyrics_charting_area == nil then
        lyrics_charting_area = ""
    end
    if notes_charting_area == nil then
        notes_charting_area = ""
    end

    -- 2. ATTEMPT TO LOAD FILE
    local settings = io.open(full_path, "r")

    if settings ~= nil then
        local readfilecontents = settings:read("*all")
        settings:close()

        -- Extract the sections
        local _, header_startie = string.find(readfilecontents, "<header_area>\n")
        local header_endie, _ = string.find(readfilecontents, "\n</header_area>")

        local _, chords_startie = string.find(readfilecontents, "<chord_charting_area>\n")
        local chords_endie, _ = string.find(readfilecontents, "\n</chord_charting_area>")

        local _, lyrics_startie = string.find(readfilecontents, "<lyrics_charting_area>\n")
        local lyrics_endie, _ = string.find(readfilecontents, "\n</lyrics_charting_area>")

        local _, notes_startie = string.find(readfilecontents, "<notes_charting_area>\n")
        local notes_endie, _ = string.find(readfilecontents, "\n</notes_charting_area>")

        -- >>> GROOVE TAG FINDER <<<
        local _, gr_start = string.find(readfilecontents, "<groove_data>\n")
        local gr_end, _ = string.find(readfilecontents, "\n</groove_data>")

        -- Load content
        if header_startie and header_endie and header_endie > header_startie then
            header_area = string.sub(readfilecontents, header_startie + 1, header_endie - 1)
        end

        if chords_startie and chords_endie and chords_endie > chords_startie then
            chord_charting_area = string.sub(readfilecontents, chords_startie + 1, chords_endie - 1)
        end

        if lyrics_startie and lyrics_endie and lyrics_endie > lyrics_startie then
            lyrics_charting_area = string.sub(readfilecontents, lyrics_startie + 1, lyrics_endie - 1)
        end

        if notes_startie and notes_endie and notes_endie > notes_startie then
            notes_charting_area = string.sub(readfilecontents, notes_startie + 1, notes_endie - 1)
        end

        -- >>> GROOVE LOADING LOGIC <<<
        -- 1. Default Reset (Important for old files!)
        for i = 1, 32 do
            groove_data[i] = 0.0
        end

        -- 2. Load if tag exists
        if gr_start and gr_end and gr_end > gr_start then
            local gr_str = string.sub(readfilecontents, gr_start + 1, gr_end - 1)

            local idx = 1
            for val in string.gmatch(gr_str, "([^,]+)") do
                if idx <= 32 then
                    groove_data[idx] = tonumber(val) or 0.0
                    idx = idx + 1
                end
            end
        end
        -- 3. Send to GMEM immediately so plugins update
        Export_Groove_To_GMEM()
    end
end

function Set_Mood2Mode_Parameters(r_tonic, m_center)
    -- Calculate mode based on interval between Parent Major and Modal Center
    local interval = (m_center - r_tonic) % 12
    if interval < 0 then
        interval = interval + 12
    end

    local mode_val = 1 -- Default Major (Ionian)
    if interval == 2 then
        mode_val = 2 -- Dorian
    elseif interval == 4 then
        mode_val = 3 -- Phrygian
    elseif interval == 5 then
        mode_val = 4 -- Lydian
    elseif interval == 7 then
        mode_val = 5 -- Mixolydian
    elseif interval == 9 then
        mode_val = 6 -- Aeolian (Minor)
    elseif interval == 11 then
        mode_val = 7 -- Locrian
    end

    -- Scan all tracks in the project for JS: Mood2Mode
    local track_count = reaper.CountTracks(0)
    for i = 0, track_count - 1 do
        local track = reaper.GetTrack(0, i)

        -- BULLETPROOF FX FINDER
        local fx_idx = -1
        for j = 0, reaper.TrackFX_GetCount(track) - 1 do
            local retval, fx_name = reaper.TrackFX_GetFXName(track, j, "")
            if retval and fx_name:find("Mood2Mode") then
                fx_idx = j
                break
            end
        end

        if fx_idx >= 0 then
            -- Param 0 = Slider 1 (Mode 1-7)
            reaper.TrackFX_SetParam(track, fx_idx, 0, mode_val)
            -- Param 1 = Slider 2 (Parent Major Tonic 0-11)
            reaper.TrackFX_SetParam(track, fx_idx, 1, r_tonic)
            -- Param 2 = Slider 3 (Modal Tonic 0-11)
            reaper.TrackFX_SetParam(track, fx_idx, 2, m_center)

            -- Param 3 = Slider 4 (White vs Black Keys)
            -- Automatically detect based on the track name!
            local _, tr_name = reaper.GetSetMediaTrackInfo_String(track, "P_NAME", "", false)
    if tr_name:lower():find("black", 1, true) then
      -- Use raw value: 2 = Black Keys 1
      reaper.TrackFX_SetParam(track, fx_idx, 3, 2) 
      local actual = reaper.TrackFX_GetParam(track, fx_idx, 3)
    else
      -- Use raw value: 1 = White Keys
      reaper.TrackFX_SetParam(track, fx_idx, 3, 1) 
      local actual = reaper.TrackFX_GetParam(track, fx_idx, 3)
    end
        end
    end
end

-----------------------------------------------                 CHECK IF A PROJECT IS OPEN
local function is_project_open()
    return reaper.GetProjectName(0, "") ~= ""
end

----------------------------------------------- CHECK OR BUILD "N2N Audition" TRACK
function Ensure_Audition_Track_Exists()
    -- 1. Check if we already have it safely cached
    if audition_track and reaper.ValidatePtr(audition_track, "MediaTrack*") then
        return audition_track
    end

    -- 2. Scan project to see if it exists
    local track_count = reaper.CountTracks(0)
    for i = 0, track_count - 1 do
        local track = reaper.GetTrack(0, i)
        local _, track_name = reaper.GetSetMediaTrackInfo_String(track, "P_NAME", "", false)
        if track_name == "N2N Audition" then
            audition_track = track
            return track
        end
    end

    -- 3. Doesn't exist? Create it!
    reaper.InsertTrackAtIndex(reaper.CountTracks(0), false)
    local new_track = reaper.GetTrack(0, reaper.CountTracks(0) - 1)
    reaper.GetSetMediaTrackInfo_String(new_track, "P_NAME", "N2N Audition", true)

    -- Add FX
    reaper.TrackFX_AddByName(new_track, "pad-synth.jsfx", false, -1)
    reaper.TrackFX_AddByName(new_track, "Isolator", false, -1)

    -- Set Colors and hidden state
    local track_color = reaper.ColorToNative(222, 222, 222) | 0x10000000
    reaper.SetTrackColor(new_track, track_color)
    reaper.SetMediaTrackInfo_Value(new_track, "B_SHOWINTCP", 0)
    reaper.SetMediaTrackInfo_Value(new_track, "B_SHOWINMIXER", 0)
    reaper.SetMediaTrackInfo_Value(new_track, "I_RECARM", 1)
    reaper.SetMediaTrackInfo_Value(new_track, "I_RECMODE", 2)
    reaper.SetMediaTrackInfo_Value(new_track, "B_MUTE", 1)

    -- 4. Try Virtual Keyboard, fallback to All MIDI if not found
    local dev_id = nil
    for j = 0, 64 do
        local retval, nameout = reaper.GetMIDIInputName(j, "")
        if nameout:lower():match("virtual midi keyboard") then
            dev_id = j
            break
        end
    end

    local val = 6112 -- Safe fallback: All MIDI Inputs, All Channels
    if dev_id then
        val = 4096 + 1 + (dev_id << 5)
    end
    reaper.SetMediaTrackInfo_Value(new_track, "I_RECINPUT", val)

    audition_track = new_track
    return new_track
end

-----------------------------------------------                 GUI VARIABLES AND SETUP

render_feedback = ""
r = reaper
local ctx = r.ImGui_CreateContext("Numbers2Notes")
local main_viewport = r.ImGui_GetMainViewport(ctx)

-- DETECT OS AND SET FONT
local os_name = reaper.GetOS()
local font_name = "Consolas" -- Windows Default
local font_size = 15
local font_small_size = 10

if os_name:match("OSX") or os_name:match("macOS") then
    -- Mac Settings: Bolder, two-word font
    font_name = "Andale Mono"
    font_size = 14
    font_small_size = 9
end


local font = r.ImGui_CreateFont(font_name, font_size)
local fontsmall = r.ImGui_CreateFont(font_name, font_small_size)
r.ImGui_Attach(ctx, font)

local click_count, text = 0, ""
local window_flags = r.ImGui_WindowFlags_NoResize() | r.ImGui_WindowFlags_MenuBar()

local win_w, win_h = 1300, 705

local mainwindow = r.ImGui_GetMainViewport(ctx)
local vp_x, vp_y = r.ImGui_Viewport_GetPos(mainwindow)
local screen_w, screen_h = r.ImGui_Viewport_GetSize(mainwindow)

local x = vp_x + ((screen_w - win_w) / 2)
local y = vp_y + ((screen_h - win_h) / 2)

r.ImGui_SetNextWindowSize(ctx, win_w, win_h, r.ImGui_Cond_FirstUseEver())
r.ImGui_SetNextWindowPos(ctx, x, y, r.ImGui_Cond_FirstUseEver())
r.ImGui_SetNextWindowCollapsed(ctx, false, r.ImGui_Cond_FirstUseEver())
r.ImGui_SetNextWindowBgAlpha(ctx, 1)

GridTrueFalse = true
ChordsTrueFalse = true
ChBassTrueFalse = true
Lead1TrueFalse = true
Lead2TrueFalse = true
BassTrueFalse = true
modal_on = false
show_headers = true
feedback_zone = "Use tabs above for more info and feedback."

--                                                                 IMGUI LINK FUNCTION

function Link(url)
    if not r.CF_ShellExecute then
        r.ImGui_Text(ctx, url)
        return
    end

    local color = r.ImGui_GetStyleColor(ctx, r.ImGui_Col_CheckMark())
    r.ImGui_TextColored(ctx, color, url)
    if r.ImGui_IsItemClicked(ctx) then
        r.CF_ShellExecute(url)
    elseif r.ImGui_IsItemHovered(ctx) then
        r.ImGui_SetMouseCursor(ctx, r.ImGui_MouseCursor_Hand())
    end
end

-- ==============================================================================
-- TRACK BUILDER UI & FX CHOOSER
-- ==============================================================================

local FX_CACHE = nil
local FX_CACHE_BUILT = false

local FXC = {
    open = false,
    tr = nil,
    field = nil,
    filter = "",
    results = {},
    sel = 1,
    instruments_only = false,
    fx_only = false,
    pending_open = false,
    pending_tr = nil,
    pending_field = nil
}

local function BuildFXCache()
    if FX_CACHE_BUILT then
        return
    end
    FX_CACHE = {"Container", "Video processor"}
    for i = 0, math.huge do
        local ret, name = reaper.EnumInstalledFX(i)
        if not ret then
            break
        end
        FX_CACHE[#FX_CACHE + 1] = name
    end
    table.sort(
        FX_CACHE,
        function(a, b)
            return a:lower() < b:lower()
        end
    )
    FX_CACHE_BUILT = true
end

local function Trim(s)
    return (s or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

local function IsInstrumentFXName(name)
    return name:match("^VSTi: ") or name:match("^VST3i: ") or name:match("^AUi: ") or name:match("^CLAPi: ") or
        name:match("^LV2i: ")
end

local function FXC_TypePass(name)
    if FXC.instruments_only then
        return IsInstrumentFXName(name) ~= nil
    elseif FXC.fx_only then
        return IsInstrumentFXName(name) == nil
    end
    return true
end

local function FXC_UpdateResults()
    local f = Trim(FXC.filter):lower()
    local t = {}

    if f == "" then
        local added = 0
        for i = 1, #FX_CACHE do
            local name = FX_CACHE[i]
            if FXC_TypePass(name) then
                added = added + 1
                t[#t + 1] = {name = name, score = i}
                if added >= 500 then
                    break
                end
            end
        end
    else
        for i = 1, #FX_CACHE do
            local name = FX_CACHE[i]
            if FXC_TypePass(name) then
                local s = name:lower()
                local ok = true
                for w in f:gmatch("%S+") do
                    if not s:find(w, 1, true) then
                        ok = false
                        break
                    end
                end
                if ok then
                    t[#t + 1] = {name = name, score = (#name - #f)}
                end
            end
        end
        table.sort(
            t,
            function(a, b)
                if a.score == b.score then
                    return a.name:lower() < b.name:lower()
                end
                return a.score < b.score
            end
        )
    end

    FXC.results = t
    FXC.sel = math.max(1, math.min(FXC.sel, #t))
end

local function FXChooser_Open(tr_ref, field_name)
    BuildFXCache()
    FXC.tr = tr_ref
    FXC.field = field_name
    FXC.filter = ""
    FXC.sel = 1
    FXC.open = true
    FXC_UpdateResults()
    reaper.ImGui_OpenPopup(ctx, "Choose FX##N2N_FX_CHOOSER")
end

local function FXChooser_CommitSelection()
    local pick = FXC.results[FXC.sel] and FXC.results[FXC.sel].name
    if pick and FXC.tr and FXC.field then
        FXC.tr[FXC.field] = {
            selection_label = pick,
            search = pick,
            preset = ""
        }
    end
    FXC.open = false
    reaper.ImGui_CloseCurrentPopup(ctx)
end

local function FXChooser_Draw()
    if not FXC.open then
        return
    end

    local vp_x, vp_y = reaper.ImGui_Viewport_GetCenter(reaper.ImGui_GetMainViewport(ctx))
    reaper.ImGui_SetNextWindowPos(ctx, vp_x, vp_y, reaper.ImGui_Cond_Appearing(), 0.5, 0.5)
    reaper.ImGui_SetNextWindowSize(ctx, 680, 560, reaper.ImGui_Cond_Appearing())

    local flags = reaper.ImGui_WindowFlags_NoCollapse() | reaper.ImGui_WindowFlags_NoSavedSettings()

    local visible, open = reaper.ImGui_BeginPopupModal(ctx, "Choose FX##N2N_FX_CHOOSER", true, flags)
    if visible then
        reaper.ImGui_Text(ctx, "Type to filter. Enter = choose. Esc = cancel. Double-click = choose.")
        reaper.ImGui_Separator(ctx)

        do
            local changed
            changed, FXC.instruments_only = reaper.ImGui_Checkbox(ctx, "Instruments only", FXC.instruments_only)
            if changed and FXC.instruments_only then
                FXC.fx_only = false
            end
            reaper.ImGui_SameLine(ctx)
            changed, FXC.fx_only = reaper.ImGui_Checkbox(ctx, "FX only", FXC.fx_only)
            if changed and FXC.fx_only then
                FXC.instruments_only = false
            end
            if changed then
                FXC_UpdateResults()
            end
        end

        reaper.ImGui_SetNextItemWidth(ctx, -1)
        if reaper.ImGui_IsWindowAppearing(ctx) then
            reaper.ImGui_SetKeyboardFocusHere(ctx)
        end
        local changed
        changed, FXC.filter = reaper.ImGui_InputTextWithHint(ctx, "##fx_filter", "Search installed FX...", FXC.filter)
        if changed then
            FXC_UpdateResults()
        end

        if reaper.ImGui_BeginChild(ctx, "##fx_list", 0, -40, 0) then
            for i = 1, #FXC.results do
                local selected = (i == FXC.sel)
                if reaper.ImGui_Selectable(ctx, FXC.results[i].name, selected) then
                    FXC.sel = i
                end
                if reaper.ImGui_IsItemHovered(ctx) and reaper.ImGui_IsMouseDoubleClicked(ctx, 0) then
                    FXC.sel = i
                    FXChooser_CommitSelection()
                end
            end
            reaper.ImGui_EndChild(ctx)
        end

        if reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_Escape()) then
            FXC.open = false
            reaper.ImGui_CloseCurrentPopup(ctx)
        end
        if
            reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_Enter()) or
                reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_KeypadEnter())
         then
            FXChooser_CommitSelection()
        end

        reaper.ImGui_EndPopup(ctx)
    end
    if not open then
        FXC.open = false
    end
end

-- Safely get text label whether it's a table or a string
local function GetLabel(item)
    if type(item) == "table" then
        return item.selection_label or "Unknown"
    end
    return tostring(item)
end

-- Dropdown Drawer
local function Draw_Dropdown(id, current_val, options, tr_ref, field_name)
    local changed = false
    local new_val = current_val
    reaper.ImGui_SetNextItemWidth(ctx, 330)

    local preview_str = GetLabel(current_val)

    if reaper.ImGui_BeginCombo(ctx, id, preview_str) then
        for _, option in ipairs(options) do
            local opt_str = GetLabel(option)
            local is_selected = (preview_str == opt_str)

            if reaper.ImGui_Selectable(ctx, opt_str, is_selected) then
                if opt_str == "Select Other..." then
                    FXC.pending_open = true
                    FXC.pending_tr = tr_ref
                    FXC.pending_field = field_name
                else
                    new_val = option
                    changed = true
                end
            end
            if is_selected then
                reaper.ImGui_SetItemDefaultFocus(ctx)
            end
        end
        reaper.ImGui_EndCombo(ctx)
    end

    return changed, new_val
end

-- State tracking for Auto-Reselect logic
local last_has_drum = true
local last_has_arp = true
is_track_builder_open = false -- Global state

local track_builder_was_open = false

function Draw_Track_Builder_Modal()
    -- Only trigger OpenPopup exactly on the frame the state transitions to true
    if is_track_builder_open and not track_builder_was_open then
        reaper.ImGui_OpenPopup(ctx, "Configure N2N Tracks")
    end
    track_builder_was_open = is_track_builder_open

    if not is_track_builder_open then
        return
    end

    local track_recipe = config.track_recipe
    local mode_options = config.mode_options
    local drum_arp_mode_options = config.drum_arp_mode_options

    -- Force standard colors for the modal so it's readable
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_PopupBg(), 0x2E3440FF)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), 0xECEFF4FF)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_FrameBg(), 0x4C566AFF)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), 0x5E81ACFF)

    local vp_x, vp_y = reaper.ImGui_Viewport_GetCenter(reaper.ImGui_GetMainViewport(ctx))
    reaper.ImGui_SetNextWindowPos(ctx, vp_x, vp_y, reaper.ImGui_Cond_Appearing(), 0.5, 0.5)
    reaper.ImGui_OpenPopup(ctx, "Configure N2N Tracks")

    n2n_main_x, n2n_main_y = reaper.ImGui_GetWindowPos(ctx)
    n2n_main_w, n2n_main_h = reaper.ImGui_GetWindowSize(ctx)

    local center_x = n2n_main_x + (n2n_main_w * 0.5)
    local center_y = n2n_main_y + (n2n_main_h * 0.5)

    reaper.ImGui_SetNextWindowPos(ctx, center_x, center_y, reaper.ImGui_Cond_Appearing(), 0.5, 0.5)

    reaper.ImGui_SetNextWindowSize(ctx, 1300, 705, reaper.ImGui_Cond_Appearing())
    if reaper.ImGui_BeginPopupModal(ctx, "Configure N2N Tracks", true) then
        reaper.ImGui_Text(ctx, "Configure your N2N Tracks for this project:")
        reaper.ImGui_Separator(ctx)
        reaper.ImGui_Dummy(ctx, 0, 5)

        local has_drum_arranger = false
        local has_arp = false

        for _, tr in ipairs(track_recipe) do
            if tr.active then
                if tr.type == 31 then
                    has_drum_arranger = true
                end
                if tr.mode and (tr.mode == "Arpeggiated - N2N Arp" or tr.mode == "N2N Arp") then
                    has_arp = true
                end
            end
        end

        local drum_just_enabled = (has_drum_arranger and not last_has_drum)
        local arp_just_enabled = (has_arp and not last_has_arp)
        last_has_drum = has_drum_arranger
        last_has_arp = has_arp

        local actions = {}

        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ChildBg(), 0x242933FF)

        -- Adjusted height down to 400 so it doesn't stretch past small laptop screens!
        if reaper.ImGui_BeginChild(ctx, "track_list_scroll", 0, 580, 0) then
            for i, tr in ipairs(track_recipe) do
                reaper.ImGui_PushID(ctx, i)

                local is_drum_cue = (tr.type == 32)
                local is_arp_cue = (tr.type == 33)

                if is_drum_cue and drum_just_enabled then
                    tr.active = true
                end
                if is_arp_cue and arp_just_enabled then
                    tr.active = true
                end

                local force_disable = (is_drum_cue and not has_drum_arranger) or (is_arp_cue and not has_arp)

                if force_disable then
                    reaper.ImGui_BeginDisabled(ctx)
                    tr.active = false
                end

                if tr.IndentMIDI == -1 then
                    if tr.divider_before then
                        reaper.ImGui_Separator(ctx)
                    end
                end

                if tr.IndentMIDI == 0 then
                    if tr.divider_before then
                        reaper.ImGui_Separator(ctx)

                        -- RADIO BUTTONS FOR RENDER MODE
                        reaper.ImGui_Dummy(ctx, 150, 0)
                        reaper.ImGui_SameLine(ctx)
                        reaper.ImGui_Text(ctx, "MIDI Render Mode:")

                        reaper.ImGui_SameLine(ctx)
                        if reaper.ImGui_RadioButton(ctx, "Relative (Always C)", G_render_mode == 0) then
                            G_render_mode = 0
                            reaper.SetProjExtState(0, "N2N", "RenderMode", "0")
                        end

                        reaper.ImGui_SameLine(ctx)
                        if reaper.ImGui_RadioButton(ctx, "Absolute (Actual Key)", G_render_mode == 1) then
                            G_render_mode = 1
                            reaper.SetProjExtState(0, "N2N", "RenderMode", "1")
                        end
                        reaper.ImGui_Dummy(ctx, 0, 5)
                    end
                    reaper.ImGui_Dummy(ctx, 150, 0)
                    reaper.ImGui_SameLine(ctx)
                end

                if tr.IndentMIDI == 1 then
                    reaper.ImGui_Dummy(ctx, 150, 0)
                    reaper.ImGui_SameLine(ctx)
                end

                local rv, checked = reaper.ImGui_Checkbox(ctx, "##act", tr.active)
                if rv then
                    tr.active = checked
                end

                reaper.ImGui_SameLine(ctx)
                reaper.ImGui_SetNextItemWidth(ctx, 350) -- Trimmed text width to keep modal size clean

                -- DYNAMIC TEXT REPLACEMENT: Swap <TYPE SELECT> with the active radio button choice
                local display_label = tr.ItemLabel or ("Type " .. tostring(tr.type))
                if display_label:find("<TYPE SELECT>") then
                    local mode_str = (G_render_mode == 0) and "Relative" or "Absolute"
                    display_label = display_label:gsub("<TYPE SELECT>", mode_str)
                end

                -- Custom display: Shorten the text if it's too long, or just let it clip cleanly
                reaper.ImGui_Text(ctx, display_label)

                if force_disable then
                    reaper.ImGui_EndDisabled(ctx)
                    if reaper.ImGui_IsItemHovered(ctx, reaper.ImGui_HoveredFlags_AllowWhenDisabled()) then
                        reaper.ImGui_SetTooltip(ctx, "Requires the parent arranger track to be active.")
                    end
                end







                local dropdown_x_offset = 480

                local list = tr.vsti_list or tr.vst_list or tr.audio_list
                local field = tr.vsti_list and "vsti_choice"
                    or (tr.vst_list and "vst_choice"
                    or (tr.audio_list and "audio_choice" or nil))
                local cur = field and tr[field] or nil

                if list and field and cur then
                    reaper.ImGui_SameLine(ctx, dropdown_x_offset)
                    local changed, new_val = Draw_Dropdown("##fxpick", cur, list, tr, field)
                    if changed then
                        tr[field] = new_val
                    end
                    dropdown_x_offset = dropdown_x_offset + 340
                end

                if tr.preset_list and tr.preset_choice then
                    reaper.ImGui_SameLine(ctx, dropdown_x_offset)
                    local preset_changed, new_preset =
                        Draw_Dropdown("##presetpick", tr.preset_choice, tr.preset_list, tr, "preset_choice")
                    if preset_changed then
                        tr.preset_choice = new_preset
                    end
                    dropdown_x_offset = dropdown_x_offset + 340
                end

                if tr.drum_arp_mode then
                    reaper.ImGui_SameLine(ctx, dropdown_x_offset)
                    local arp_mode_changed, new_arp_mode =
                        Draw_Dropdown("##drum_arp", tr.drum_arp_mode, drum_arp_mode_options, tr, "drum_arp_mode")
                    if arp_mode_changed then
                        tr.drum_arp_mode = new_arp_mode
                        if tr.type == 32 then reaper.SetProjExtState(0, "N2N", "DrumCueMode", new_arp_mode) end
                        if tr.type == 33 then reaper.SetProjExtState(0, "N2N", "ArpCueMode", new_arp_mode) end
                    end
                    dropdown_x_offset = dropdown_x_offset + 340
                end

                if tr.mode then
                    reaper.ImGui_SameLine(ctx, dropdown_x_offset)
                    local mode_changed, new_mode = Draw_Dropdown("##mode", tr.mode, mode_options)
                    if mode_changed then
                        tr.mode = new_mode
                    end
                    dropdown_x_offset = dropdown_x_offset + 340
                end

                if not tr.single then
                    reaper.ImGui_SameLine(ctx, dropdown_x_offset)

                    if reaper.ImGui_Button(ctx, "+") then
                        table.insert(
                            actions,
                            {
                                action = "add",
                                index = i,
                                data = {
                                    type = tr.type,
                                    ItemLabel = tr.ItemLabel,
                                    divider_before = false,
                                    Tr_divider_before = false,
                                    active = true,
                                    single = false,
                                    vsti_choice = tr.vsti_choice,
                                    vsti_list = tr.vsti_list,
                                    vst_choice = tr.vst_choice,
                                    vst_list = tr.vst_list,
                                    audio_choice = tr.audio_choice,
                                    audio_list = tr.audio_list,
                                    preset_choice = tr.preset_choice,
                                    preset_list = tr.preset_list,
                                    mode = tr.mode,
                                    drum_arp_mode = tr.drum_arp_mode,
                                    is_clone = true,
                                    addchain = tr.addchain,
                                    IndentMIDI = tr.IndentMIDI
                                }
                            }
                        )
                    end

                    if tr.is_clone then
                        reaper.ImGui_SameLine(ctx)
                        if reaper.ImGui_Button(ctx, "-") then
                            table.insert(actions, {action = "remove", index = i})
                        end
                    end
                end












                reaper.ImGui_PopID(ctx)
            end
            reaper.ImGui_EndChild(ctx)
        end
        reaper.ImGui_PopStyleColor(ctx)

        if #actions > 0 then
            table.sort(
                actions,
                function(a, b)
                    return a.index > b.index
                end
            )
            for _, act in ipairs(actions) do
                if act.action == "add" then
                    table.insert(track_recipe, act.index + 1, act.data)
                elseif act.action == "remove" then
                    table.remove(track_recipe, act.index)
                end
            end
        end

        reaper.ImGui_Dummy(ctx, 0, 5)
        reaper.ImGui_Separator(ctx)
        reaper.ImGui_Dummy(ctx, 0, 5)

        if reaper.ImGui_Button(ctx, "Build Tracks & Render", 200, 35) then
            is_track_builder_open = false
            reaper.ImGui_CloseCurrentPopup(ctx)
            Start_Render_Coroutine()
        end

        reaper.ImGui_SameLine(ctx)
        if reaper.ImGui_Button(ctx, "Cancel", 100, 35) then
            is_track_builder_open = false
            reaper.ImGui_CloseCurrentPopup(ctx)
        end

        if FXC.pending_open then
            FXC.pending_open = false
            FXChooser_Open(FXC.pending_tr, FXC.pending_field)
            FXC.pending_tr, FXC.pending_field = nil, nil
        end

        FXChooser_Draw()
        reaper.ImGui_EndPopup(ctx)
    else
        is_track_builder_open = false
    end

    reaper.ImGui_PopStyleColor(ctx, 4) -- Pop the 4 dialog colors we pushed!
end

local last_audition_validate_time = 0

local function Ensure_Audition_Track_Valid()
    local now = reaper.time_precise()
    -- Validate at most once every 3 seconds to save CPU/prevent UI stutter
    if now - last_audition_validate_time < 3.0 then
        return
    end
    last_audition_validate_time = now
    Ensure_Audition_Track_Exists()
end

----------------------------------------------- STYLE COLOR MANAGER
local n2n_styles = {
    {reaper.ImGui_Col_WindowBg(), 0xC8CED3FF},
    {reaper.ImGui_Col_TitleBg(), 0xD5D5D5FF},
    {reaper.ImGui_Col_TitleBgActive(), 0xD5D5D5FF},
    {reaper.ImGui_Col_TitleBgCollapsed(), 0xD5D5D5FF},
    {reaper.ImGui_Col_MenuBarBg(), 0xD5D5D5FF},
    {reaper.ImGui_Col_InputTextCursor(), 0x000000FF},
    {reaper.ImGui_Col_Text(), 0x000000FF},
    {reaper.ImGui_Col_ChildBg(), 0xC8858500},
    {reaper.ImGui_Col_PopupBg(), 0x77B384F0},
    {reaper.ImGui_Col_BorderShadow(), 0x466C9000},
    {reaper.ImGui_Col_FrameBg(), 0xFFFFFFFE},
    {reaper.ImGui_Col_ScrollbarBg(), 0x82589E87},
    {reaper.ImGui_Col_Button(), 0x2A9AC0FF},
    {reaper.ImGui_Col_ButtonHovered(), 0xFFF06FCC},
    {reaper.ImGui_Col_ButtonActive(), 0xFFFFFFFF},
    {reaper.ImGui_Col_Tab(), 0xEEEFEEDC},
    {reaper.ImGui_Col_TabHovered(), 0xFFFFFFFF},
    {reaper.ImGui_Col_TabActive(), 0xFFF06FCC},
    {reaper.ImGui_Col_TabUnfocused(), 0x834568F8},
    {reaper.ImGui_Col_TableHeaderBg(), 0xC9BB00FF},
    {reaper.ImGui_Col_DockingEmptyBg(), 0x00F2FFFF},
    {reaper.ImGui_Col_TableRowBg(), 0xFF000000},
    {reaper.ImGui_Col_TableBorderLight(), 0x0000FFFF}
}

local function Push_N2N_Styles(context)
    for _, style in ipairs(n2n_styles) do
        reaper.ImGui_PushStyleColor(context, style[1], style[2])
    end
end

local function Pop_N2N_Styles(context)
    reaper.ImGui_PopStyleColor(context, #n2n_styles)
end
-----------------------------------------------                 IMGUI LOOP FUNCTION


local function Draw_Sticky_Mini_Chord_Bar(context)
    local is_ctrl_down = reaper.ImGui_IsKeyDown(context, reaper.ImGui_Mod_Ctrl())
    
    -- Helper text with custom fonts
    reaper.ImGui_SameLine(context, 190)
    reaper.ImGui_PopFont(ctx)
    reaper.ImGui_PushFont(ctx, fontsmall)
    reaper.ImGui_TextDisabled(context, "Use \"Entry\" tab for less common chords.")
    reaper.ImGui_PopFont(ctx)
    reaper.ImGui_PushFont(ctx, font)
    
    -- Start buttons cleanly on the right
    reaper.ImGui_SameLine(context, 435)
    
    local quick_chords = {
        {label="1",  val={"", "       ", {0, 4, 7}}}, 
        {label="2m", val={"m", "m      ", {0, 3, 7}}},
        {label="3m", val={"m", "m      ", {0, 3, 7}}},
        {label="4",  val={"", "       ", {0, 4, 7}}},
        {label="5",  val={"", "       ", {0, 4, 7}}},
        {label="6m", val={"m", "m      ", {0, 3, 7}}}
    }
    local quick_roots = {"1", "2", "3", "4", "5", "6"}
    
    for i, c in ipairs(quick_chords) do
        local current_root = quick_roots[i]
        local display_label = c.label
        
        local root_colors = musictheory.root_colors[current_root] or {200,200,200}
        local thecolor = reaper.ImGui_ColorConvertDouble4ToU32(
            root_colors[1]/255, root_colors[2]/255, root_colors[3]/255, 1
        )
        
        -- Push the solid background color
        reaper.ImGui_PushStyleColor(context, reaper.ImGui_Col_Button(), thecolor)
        
        -- Push the pulsing white border (Thickness 3.0)
        reaper.ImGui_PushStyleVar(context, reaper.ImGui_StyleVar_FrameBorderSize(), 0.0)
        reaper.ImGui_PushStyleColor(context, reaper.ImGui_Col_Border(), reaper.ImGui_ColorConvertDouble4ToU32(1, 1, 1, transpar or 0.8))
        
        reaper.ImGui_Button(context, display_label, 35, 18)
        
        -- Pop Border styles
        reaper.ImGui_PopStyleColor(context, 1)
        reaper.ImGui_PopStyleVar(context, 1)
        
        -- MOUSE DOWN
        if reaper.ImGui_IsItemActivated(context) then
            if is_ctrl_down then
                chord_charting_area = chord_charting_area .. current_root .. c.val[1] .. "  "
            end
            
            play_root = current_root
            last_play_root = current_root
            current_playing_tone_array = musictheory.type_table[(c.val[1] == "" and "z" or c.val[1])] or c.val[3]
            
            local root_val = musictheory.root_table[play_root] or 0
            local total_shift = (root_val + audition_key_shift) % 12
            
            if audition_track and reaper.ValidatePtr(audition_track, "MediaTrack*") then
                reaper.SetMediaTrackInfo_Value(audition_track, "B_MUTE", 0)
            end
            for _, v in pairs(current_playing_tone_array) do
                local pitch = (v + total_shift > 10) and (60 + total_shift + v - 12) or (60 + total_shift + v)
                reaper.StuffMIDIMessage(0, 144, pitch, 111)
                
                -- Doubled heavy bass notes (-12 and -24)
                if v == 0 then 
                    reaper.StuffMIDIMessage(0, 144, pitch - 12, 115)
                    reaper.StuffMIDIMessage(0, 144, pitch - 24, 120) 
                end
            end
        end
        
        -- MOUSE UP
        if reaper.ImGui_IsItemDeactivated(context) then
            local root_val = musictheory.root_table[play_root] or 0
            local total_shift = (root_val + audition_key_shift) % 12
            
            for _, v in pairs(current_playing_tone_array) do
                local pitch = (v + total_shift > 10) and (60 + total_shift + v - 12) or (60 + total_shift + v)
                reaper.StuffMIDIMessage(0, 128, pitch, 0)
                
                if v == 0 then 
                    reaper.StuffMIDIMessage(0, 128, pitch - 12, 0)
                    reaper.StuffMIDIMessage(0, 128, pitch - 24, 0) 
                end
            end
            if audition_track and reaper.ValidatePtr(audition_track, "MediaTrack*") then
                reaper.SetMediaTrackInfo_Value(audition_track, "B_MUTE", 1)
            end
        end

        reaper.ImGui_PopStyleColor(context, 1) -- Pop the background color
        if i < #quick_chords then reaper.ImGui_SameLine(context) end
    end
end



function IM_GUI_Loop()
    local rv
    local rc

    local current_audition_key = set_the_key(header_area)
    audition_key_shift = musictheory.key_table[current_audition_key] or 0

    Push_N2N_Styles(ctx)
    reaper.ImGui_PushFont(ctx, font)


    local visible, open =
        reaper.ImGui_Begin(ctx, "Numbers2Notes - Nashville Number Charts for Reaper", true, window_flags)



    reaper.ImGui_SetWindowSize(ctx, 1300, 705) 




    -- Safely ensure the audition track is built and mapped to the Global Variable
    Ensure_Audition_Track_Valid()



    if visible then
        if modal_on == true then
            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_PopupBg(), 0x2E3440FF)
            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), 0xECEFF4FF)
            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_FrameBg(), 0x4C566AFF)
            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), 0x5E81ACFF)

            r.ImGui_OpenPopup(ctx, "Status:")

            local win_x, win_y = r.ImGui_GetWindowPos(ctx)
            local win_w, win_h = r.ImGui_GetWindowSize(ctx)

            r.ImGui_SetNextWindowPos(
                ctx,
                win_x + (win_w * 0.5),
                win_y + (win_h * 0.5),
                r.ImGui_Cond_Appearing(),
                0.5,
                0.5
            )

            r.ImGui_SetNextWindowSize(ctx, 720, 460, r.ImGui_Cond_Appearing())

            if r.ImGui_BeginPopupModal(ctx, "Status:") then
                -- ERROR STATE: Show Missing Plugins
                if G_startup_missing_report ~= "" then
                    r.ImGui_TextColored(ctx, 0xFF5555FF, "MISSING DEPENDENCIES")
                    r.ImGui_Separator(ctx)

                    -- 1. Scrollable, Selectable Text Box (Allows Copying)
                    if r.ImGui_BeginChild(ctx, "error_scroll", 700, 350) then
                        r.ImGui_InputTextMultiline(
                            ctx,
                            "##report_display",
                            G_startup_missing_report,
                            -1,
                            -1,
                            r.ImGui_InputTextFlags_ReadOnly()
                        )
                        r.ImGui_EndChild(ctx)
                    end

                    r.ImGui_Separator(ctx)

                    -- 2. Buttons
                    if r.ImGui_Button(ctx, "Copy Report to Clipboard", 200, 30) then
                        r.ImGui_SetClipboardText(ctx, G_startup_missing_report)
                    end

                    r.ImGui_SameLine(ctx)

                    if r.ImGui_Button(ctx, "Refresh / Re-Scan", 200, 30) then
                        local still_broken = Check_Plugins_On_Startup()
                        if not still_broken then
                            modal_on = false
                            G_startup_missing_report = ""
                            r.ImGui_CloseCurrentPopup(ctx)
                        end
                    end

                    r.ImGui_SameLine(ctx)

                    if r.ImGui_Button(ctx, "Close Script", 120, 30) then
                        open = false
                    end
                else
                    -- NORMAL STATE: Coroutine Processing
                    r.ImGui_Text(ctx, render_status_msg .. "       \n\n")

                    -- Push the background coroutine forward 1 step per frame
                    if render_co then
                        if coroutine.status(render_co) ~= "dead" then
                            local success, msg = coroutine.resume(render_co)
                            if success then
                                if msg then
                                    render_status_msg = msg
                                end
                            else
                                reaper.ShowConsoleMsg("Render Error: " .. tostring(msg) .. "\n")
                                render_co = nil
                                modal_on = false
                                r.ImGui_CloseCurrentPopup(ctx)
                            end
                        else
                            -- Coroutine finished successfully!
                            render_co = nil
                            modal_on = false
                            r.ImGui_CloseCurrentPopup(ctx)
                        end
                    end
                end

                r.ImGui_EndPopup(ctx)
            end
            reaper.ImGui_PopStyleColor(ctx, 4) -- Clean up the styles!
        end

        -- Always center this window when appearing

reaper.ImGui_BeginGroup(ctx)
        
        -- Start the tabs but DON'T wrap the whole block in the if-statement yet
        r.ImGui_BeginTabBar(ctx, "Charting", r.ImGui_TabBarFlags_None())
        
        if r.ImGui_BeginTabItem(ctx, "Chords") then
            charting_tab_mode = 1
            work_zone = chord_charting_area
            r.ImGui_EndTabItem(ctx)
        end
        if r.ImGui_BeginTabItem(ctx, "Lyrics") then
            charting_tab_mode = 5
            work_zone = lyrics_charting_area
            r.ImGui_EndTabItem(ctx)
        end
        if r.ImGui_BeginTabItem(ctx, "Notes") then
            charting_tab_mode = 6
            work_zone = notes_charting_area
            r.ImGui_EndTabItem(ctx)
        end

        -- Draw the Sticky Chord Bar on the far right of the Tab Bar line!
        Draw_Sticky_Mini_Chord_Bar(ctx)
        
        r.ImGui_EndTabBar(ctx)

        if charting_tab_mode == 1 then
            if show_headers == true then
                if r.ImGui_Button(ctx, "Hide Header Info", nil, nil) then
                    show_headers = false
                end
                r.ImGui_SameLine(ctx)
                local changed_h, new_h =
                    r.ImGui_InputTextMultiline(
                    ctx,
                    "##header_area",
                    header_area,
                    541,
                    102,
                    reaper.ImGui_InputTextFlags_AllowTabInput()
                )
                if changed_h then
                    header_area = new_h
                end

                local changed_c, new_c =
                    r.ImGui_InputTextMultiline(
                    ctx,
                    "##chord_charting_area",
                    chord_charting_area,
                    685,
                    487,
                    reaper.ImGui_InputTextFlags_AllowTabInput()
                )
                if changed_c then
                    chord_charting_area = new_c
                end
            else
                if r.ImGui_Button(ctx, "Display Header Info", nil, nil) then
                    show_headers = true
                end
                local changed_c, new_c =
                    r.ImGui_InputTextMultiline(
                    ctx,
                    "##chord_charting_area",
                    chord_charting_area,
                    685,
                    562,
                    reaper.ImGui_InputTextFlags_AllowTabInput()
                )
                if changed_c then
                    chord_charting_area = new_c
                end
            end
            reaper.ImGui_Dummy(ctx, 230, 1)
            reaper.ImGui_Dummy(ctx, 230, 15)
            r.ImGui_SameLine(ctx)
            if r.ImGui_Button(ctx, "Setup & Render", nil, nil) then
                is_track_builder_open = true
            end

            r.ImGui_SameLine(ctx)
            if r.ImGui_Button(ctx, "Update", nil, nil) then
                -- Smart Update Logic
                Scan_Existing_Tracks()
                local has_tracks = false
                for k, v in pairs(FOUND_TRACKS) do
                    if #v > 0 then
                        has_tracks = true
                        break
                    end
                end

                -- If they hit Quick Render but have no tracks, force open the Builder!
                if has_tracks then
                    if not render_co then
                        Start_Render_Coroutine()
                    end
                else
                    is_track_builder_open = true
                end
            end
        elseif charting_tab_mode == 2 then
            local changed_l1, new_l1 =
                r.ImGui_InputTextMultiline(
                ctx,
                "##lead1_charting_area",
                lead1_charting_area,
                685,
                589,
                reaper.ImGui_InputTextFlags_AllowTabInput()
            )
            if changed_l1 then
                lead1_charting_area = new_l1
            end

            reaper.ImGui_Dummy(ctx, 250, 5)
            r.ImGui_SameLine(ctx)
            if r.ImGui_Button(ctx, "Render Lead 1 Track", nil, nil) then
                render_lead1()
            end
        elseif charting_tab_mode == 3 then
            local changed_l2, new_l2 =
                r.ImGui_InputTextMultiline(
                ctx,
                "##lead2_charting_area",
                lead2_charting_area,
                685,
                589,
                reaper.ImGui_InputTextFlags_AllowTabInput()
            )
            if changed_l2 then
                lead2_charting_area = new_l2
            end

            reaper.ImGui_Dummy(ctx, 250, 5)
            r.ImGui_SameLine(ctx)
            if r.ImGui_Button(ctx, "Render Lead 2 Track", nil, nil) then
                render_lead2()
            end
        elseif charting_tab_mode == 4 then
            local changed_b, new_b =
                r.ImGui_InputTextMultiline(
                ctx,
                "##bass_charting_area",
                bass_charting_area,
                685,
                589,
                reaper.ImGui_InputTextFlags_AllowTabInput()
            )
            if changed_b then
                bass_charting_area = new_b
            end

            reaper.ImGui_Dummy(ctx, 250, 5)
            r.ImGui_SameLine(ctx)
            if r.ImGui_Button(ctx, "Render Bass Track", nil, nil) then
                render_bass()
            end
        elseif charting_tab_mode == 5 then
            local changed_ly, new_ly =
                r.ImGui_InputTextMultiline(
                ctx,
                "##lyrics_charting_area",
                lyrics_charting_area,
                685,
                618,
                reaper.ImGui_InputTextFlags_AllowTabInput()
            )
            if changed_ly then
                lyrics_charting_area = new_ly
            end
        elseif charting_tab_mode == 6 then
            local changed_n, new_n =
                r.ImGui_InputTextMultiline(
                ctx,
                "##notes_charting_area",
                notes_charting_area,
                685,
                618,
                reaper.ImGui_InputTextFlags_AllowTabInput()
            )
            if changed_n then
                notes_charting_area = new_n
            end
        end
        -- Call the modals right before ImGui_End(ctx)
        Draw_Track_Builder_Modal()

        reaper.ImGui_EndGroup(ctx)
        r.ImGui_SameLine(ctx)
        reaper.ImGui_BeginGroup(ctx)

        if r.ImGui_BeginMenuBar(ctx) then
            if r.ImGui_BeginMenu(ctx, "File") then
                if r.ImGui_MenuItem(ctx, "New Chart") then
                    header_area = [[Title: 
Writer: 
BPM: 
Key: 
Swing: 
Form: I V C V C B C O]]
                    chord_charting_area =
                        [[
{#}
- -

{I}




{V}  




{C}




{B}




{O}




]]
                end

                if r.ImGui_MenuItem(ctx, "Open Chart") then
                    local info = debug.getinfo(1, "S")
                    local path = info.source:match [[^@?(.*[\/])[^\/]-$]]
                    local chordchart_path = path .. "ChordCharts/"

                    retval, selected_path =
                        reaper.GetUserFileNameForRead(
                        chordchart_path,
                        "Select the Chord Chart you wish to open.",
                        "txt"
                    )

                    if retval then
                        local settings = io.open(selected_path, "r")
                        if settings ~= nil then
                            local readfilecontents = settings:read("*all")
                            settings:close()

                            -- 1. RESET GROOVE TO DEFAULT (Crucial step for old files)
                            for i = 1, 32 do
                                groove_data[i] = 0.0
                            end

                            -- 2. FIND TAGS
                            local _, header_startie = string.find(readfilecontents, "<header_area>\n")
                            local header_endie, _ = string.find(readfilecontents, "\n</header_area>")

                            local _, chords_startie = string.find(readfilecontents, "<chord_charting_area>\n")
                            local chords_endie, _ = string.find(readfilecontents, "\n</chord_charting_area>")

                            local _, lyrics_startie = string.find(readfilecontents, "<lyrics_charting_area>\n")
                            local lyrics_endie, _ = string.find(readfilecontents, "\n</lyrics_charting_area>")

                            local _, notes_startie = string.find(readfilecontents, "<notes_charting_area>\n")
                            local notes_endie, _ = string.find(readfilecontents, "\n</notes_charting_area>")

                            -- >>> FIND GROOVE DATA <<<
                            local _, gr_start = string.find(readfilecontents, "<groove_data>\n")
                            local gr_end, _ = string.find(readfilecontents, "\n</groove_data>")

                            -- 3. LOAD CONTENT
                            if header_startie and header_endie and header_endie > header_startie then
                                header_area = string.sub(readfilecontents, header_startie + 1, header_endie - 1)
                            end

                            if chords_startie and chords_endie and chords_endie > chords_startie then
                                chord_charting_area = string.sub(readfilecontents, chords_startie + 1, chords_endie - 1)
                            end

                            if lyrics_startie and lyrics_endie and lyrics_endie > lyrics_startie then
                                lyrics_charting_area =
                                    string.sub(readfilecontents, lyrics_startie + 1, lyrics_endie - 1)
                            end

                            if notes_startie and notes_endie and notes_endie > notes_startie then
                                notes_charting_area = string.sub(readfilecontents, notes_startie + 1, notes_endie - 1)
                            end

                            -- >>> LOAD GROOVE DATA <<<
                            if gr_start and gr_end and gr_end > gr_start then
                                local gr_str = string.sub(readfilecontents, gr_start + 1, gr_end - 1)
                                local idx = 1
                                for val in string.gmatch(gr_str, "([^,]+)") do
                                    if idx <= 32 then
                                        groove_data[idx] = tonumber(val) or 0.0
                                        idx = idx + 1
                                    end
                                end
                            end

                            -- 4. SYNC TO SYSTEM (Update Arp/Drums immediately)
                            Export_Groove_To_GMEM()
                        end
                    end
                end

                if r.ImGui_MenuItem(ctx, "Save") then -- MENU ITEMS
                    Autosave()

                    SaveLastNumbers2NotesChart()
                end

                if r.ImGui_MenuItem(ctx, "Save as...") then
                    _, quit_title_startso = string.find(header_area, "Title: ")
                    quit_title_endso, _ = string.find(header_area, "Writer:")

                    quittitlefound = string.sub(header_area, quit_title_startso + 1, quit_title_endso - 2)
                    thetime = os.date("%Y-%m-%d %H-%M-%S")

                    if string.len(quittitlefound) < 30 and quittitlefound ~= nil then
                        filenamewillbe = quittitlefound .. " " .. thetime .. ".txt"
                    else
                        filenamewillbe = "N2Nautobackup " .. thetime .. ".txt"
                    end

                    local info = debug.getinfo(1, "S")
                    local path = info.source:match [[^@?(.*[\/])[^\/]-$]]
                    local chordchart_path = path .. "ChordCharts/"

                    retval, fileName =
                        reaper.JS_Dialog_BrowseForSaveFile(
                        "Save Chord Chart as...",
                        chordchart_path,
                        filenamewillbe,
                        ".txt"
                    )

                    if retval and fileName ~= "" then
                        -- >>> PREPARE GROOVE STRING <<<
                        local groove_str = ""
                        for i = 1, 32 do
                            groove_str = groove_str .. tostring(groove_data[i]) .. ","
                        end

                        -- WRITE FILE
                        write_path = io.open(fileName, "w")
                        if write_path then
                            write_path:write(
                                "<Numbers2NotesProject>\n<header_area>\n" ..
                                    header_area ..
                                        "\n</header_area>\n<chord_charting_area>\n" ..
                                            chord_charting_area ..
                                                "\n</chord_charting_area>\n<lyrics_charting_area>\n" ..
                                                    lyrics_charting_area ..
                                                        "\n</lyrics_charting_area>\n<notes_charting_area>\n" ..
                                                            notes_charting_area ..
                                                                "\n</notes_charting_area>\n<groove_data>\n" ..
                                                                    groove_str ..
                                                                        "\n</groove_data>\n</Numbers2NotesProject>"
                            )
                            write_path:close()
                        end
                    end
                end

                --if r.ImGui_MenuItem(ctx, "Quit") then
                --r.ShowConsoleMsg("Quitting...\n")
                --end
                r.ImGui_EndMenu(ctx)
            end
            --[[if r.ImGui_BeginMenu(ctx, "Edit") then
                if r.ImGui_MenuItem(ctx, "Select All") then             -- MENU ITEMS
                    r.ShowConsoleMsg("Selecting...\n")
                end
                if r.ImGui_MenuItem(ctx, "Cut") then
                    r.ShowConsoleMsg("Cutting...\n")
                end
                if r.ImGui_MenuItem(ctx, "Copy") then
                    r.ShowConsoleMsg("Copying...\n")
                end
                if r.ImGui_MenuItem(ctx, "Paste") then
                    r.ShowConsoleMsg("Pasting...\n")
                end
                r.ImGui_EndMenu(ctx)
            end
      ]]
            --[[
            if r.ImGui_BeginMenu(ctx, "Formats") then            -- MENU ITEMS
                if r.ImGui_MenuItem(ctx, "Get Formats Info") then
                    r.ShowConsoleMsg("Open Format Info...\n")
                end
                if r.ImGui_MenuItem(ctx, "Get info on BIAB") then
                    r.ShowConsoleMsg("Showing BIAB info\n")
                end
                if r.ImGui_MenuItem(ctx, "Get info on OneMotion.com Chord Player") then
                    r.ShowConsoleMsg("Chord Player Info\n")
                end
                if r.ImGui_MenuItem(ctx, 'Convert Clipboard contents from to Onemotion.com "Edit All"') then
                    import_onemotion()
                end
                if r.ImGui_MenuItem(ctx, 'Export to Onemotion.com Chord Player "Edit All" paste in') then
                    render_onemotion()
                end
                if r.ImGui_MenuItem(ctx, "Get info on ChordSheet.com") then
                    r.ShowConsoleMsg("Chordsheet.com Info\n")
                end
                if r.ImGui_MenuItem(ctx, "Go to Chordsheet.com") then
                    r.ShowConsoleMsg("Open Chordsheet.com website\n")
                end
                r.ImGui_EndMenu(ctx)                    -- MENU ITEMS
            end
            if r.ImGui_BeginMenu(ctx, "Audition and Render") then
                if r.ImGui_MenuItem(ctx, "Audition Selection") then
                    r.ShowConsoleMsg("Auditioning Selection\n")
                end
                if r.ImGui_MenuItem(ctx, "Audition Chart") then
                    r.ShowConsoleMsg("Auditioning Chart\n")
                end
                if r.ImGui_MenuItem(ctx, "Render Selection at Cursor") then
                    r.ShowConsoleMsg("Render Selection at Cursor\n")
                end
                if r.ImGui_MenuItem(ctx, "Render Chart at Cursor") then
                    r.ShowConsoleMsg("Render Chart at Cursor\n")
                end
                if r.ImGui_MenuItem(ctx, "Render New Chart Tracks") then
                    render_all()
                end                              -- MENU ITEMS
                r.ImGui_EndMenu(ctx)
            end
      ]]
            r.ImGui_EndMenuBar(ctx)
        end
        if r.ImGui_BeginTabBar(ctx, "Feedback", r.ImGui_TabBarFlags_None()) then
            if r.ImGui_BeginTabItem(ctx, "Render") then
                feedback_tab_mode = 0
                r.ImGui_EndTabItem(ctx)
            end
            if r.ImGui_BeginTabItem(ctx, "Entry") then
                feedback_tab_mode = 1
                r.ImGui_EndTabItem(ctx)
            end -- TABS                                  -- TABS

            --[[
     if r.ImGui_BeginTabItem(ctx, "Options") then
        feedback_tab_mode = 2
        r.ImGui_EndTabItem(ctx)
            end
      if r.ImGui_BeginTabItem(ctx, "Arrange") then
        feedback_tab_mode = 3
        r.ImGui_EndTabItem(ctx)
            end            
      ]]
            if r.ImGui_BeginTabItem(ctx, "Import") then
                feedback_tab_mode = 4
                r.ImGui_EndTabItem(ctx)
            end
            if r.ImGui_BeginTabItem(ctx, "Export") then
                feedback_tab_mode = 5
                r.ImGui_EndTabItem(ctx)
            end
            if r.ImGui_BeginTabItem(ctx, "Theory") then
                feedback_tab_mode = 6
                r.ImGui_EndTabItem(ctx)
            end
            if r.ImGui_BeginTabItem(ctx, "Chains") then
                feedback_tab_mode = 7
                r.ImGui_EndTabItem(ctx)
            end
            if r.ImGui_BeginTabItem(ctx, "Help") then
                feedback_tab_mode = 8
                r.ImGui_EndTabItem(ctx)
            end
            if r.ImGui_BeginTabItem(ctx, "Beta Users") then
                feedback_tab_mode = 9
                r.ImGui_EndTabItem(ctx)
            end
            if r.ImGui_BeginTabItem(ctx, "Groove") then
                feedback_tab_mode = 10
                r.ImGui_EndTabItem(ctx)
            end

            --[[      


      if onemotionimport ~= "" then
        feedback_zone = onemotionimport
        else
        feedback_zone = 'While at the OneMotion.com Chord Player go to "Edit all" and copy the contents.'
        end
        
                   -- if r.ImGui_BeginTabItem(ctx, "Chordsheet.com") then
            --    r.ImGui_EndTabItem(ctx)
      --  feedback_tab_mode = 5        
      --  feedback_zone = help.Chordsheet_output
            --end                                -- TABS
      
              feedback_zone = help.Sample_song
      
                if onemotionimport ~= "" then
        feedback_zone = onemotionimport
        else
        feedback_zone = 'While at the OneMotion.com Chord Player go to "Edit all" and copy the contents.'
        end
        
                if onemotionoutput ~= "" then
        feedback_zone = onemotionoutput
        else
        feedback_zone = help.Onemotion_output
        end
        
        ]]
            --if r.ImGui_BeginTabItem(ctx, "Help") then
            --feedback_tab_mode = 6
            --feedback_zone = help.Template
            --  r.ImGui_EndTabItem(ctx)
            --end
            -- if r.ImGui_BeginTabItem(ctx, "Code Help") then
            --    r.ImGui_EndTabItem(ctx)
            --  feedback_tab_mode = 8
            --  feedback_zone = help.Code_help
            -- end                                -- TABS
            --  if r.ImGui_BeginTabItem(ctx, "Section Help") then
            --      r.ImGui_EndTabItem(ctx)
            --  feedback_tab_mode = 9
            --  feedback_zone = help.Section_help
            --  end
            --  if r.ImGui_BeginTabItem(ctx, "Chord Help") then
            --        r.ImGui_EndTabItem(ctx)
            --    feedback_tab_mode = 10
            --    feedback_zone = help.Chord_help
            --    end
            --    if r.ImGui_BeginTabItem(ctx, "Rhythm Help") then
            --         r.ImGui_EndTabItem(ctx)
            --    feedback_tab_mode = 11
            --    feedback_zone = help.Rhythm_help
            --     end
            --if r.ImGui_BeginTabItem(ctx, "Swing Help") then
            -- r.ImGui_EndTabItem(ctx)
            --end                                -- TABS
            r.ImGui_EndTabBar(ctx)
        end
        if feedback_tab_mode == 4 then
            if r.ImGui_BeginTabBar(ctx, "Import", r.ImGui_TabBarFlags_None()) then
                if r.ImGui_BeginTabItem(ctx, "Import Letter Chords") then
                    import_tab_mode = 1
                    r.ImGui_EndTabItem(ctx)
                end
                --[[]
        if r.ImGui_BeginTabItem(ctx, 'Import BIAB Chords') then
          import_tab_mode = 2
          r.ImGui_EndTabItem(ctx)
        end
        ]]
                if r.ImGui_BeginTabItem(ctx, "Import OneMotion Chords") then
                    import_tab_mode = 3
                    r.ImGui_EndTabItem(ctx)
                end
                r.ImGui_EndTabBar(ctx)
            end
        end

        if feedback_tab_mode == 5 then
            if r.ImGui_BeginTabBar(ctx, "Export", r.ImGui_TabBarFlags_None()) then
                if r.ImGui_BeginTabItem(ctx, "Export to BIAB") then
                    export_tab_mode = 1
                    r.ImGui_EndTabItem(ctx)
                end
                if r.ImGui_BeginTabItem(ctx, "Export to OneMotion.com") then
                    export_tab_mode = 2
                    r.ImGui_EndTabItem(ctx)
                end
                if r.ImGui_BeginTabItem(ctx, "Export to Chordsheet.com") then
                    export_tab_mode = 3
                    r.ImGui_EndTabItem(ctx)
                end
                r.ImGui_EndTabBar(ctx)
            end
        end

        if feedback_tab_mode == 8 then
            if r.ImGui_BeginTabBar(ctx, "Help", r.ImGui_TabBarFlags_None()) then
                if r.ImGui_BeginTabItem(ctx, "Sample Song") then
                    help_tab_mode = 1
                    r.ImGui_EndTabItem(ctx)
                end
                if r.ImGui_BeginTabItem(ctx, "Template") then
                    help_tab_mode = 2
                    r.ImGui_EndTabItem(ctx)
                end
                if r.ImGui_BeginTabItem(ctx, "Code Help") then
                    help_tab_mode = 3
                    r.ImGui_EndTabItem(ctx)
                end -- TABS
                if r.ImGui_BeginTabItem(ctx, "Section Help") then
                    help_tab_mode = 4
                    r.ImGui_EndTabItem(ctx)
                end
                if r.ImGui_BeginTabItem(ctx, "Chord Help") then
                    help_tab_mode = 5
                    r.ImGui_EndTabItem(ctx)
                end
                if r.ImGui_BeginTabItem(ctx, "Rhythm Help") then
                    help_tab_mode = 6
                    r.ImGui_EndTabItem(ctx)
                end
                --if r.ImGui_BeginTabItem(ctx, "Swing Help") then
                --    help_tab_mode = 7
                --   r.ImGui_EndTabItem(ctx)
                --end
                r.ImGui_EndTabBar(ctx)
            end
        end
        if feedback_tab_mode == 9 then
            reaper.ImGui_Text(ctx, "REQUIRED PLUGINS FOR THE DEFAULT PROJECT - Version 1.8.1")
            reaper.ImGui_Dummy(ctx, 0, 5) -- Add a tiny bit of vertical spacing
            Link("https://rockumk.github.io/AHS_Music_Tech/Numbers2Notes.html")
        end

        if feedback_tab_mode == 0 then
            reaper.ImGui_Text(ctx, "Render Feedback:")
            r.ImGui_InputTextMultiline(
                ctx,
                "##feedback_zone",
                render_feedback,
                592,
                573,
                reaper.ImGui_InputTextFlags_AllowTabInput()
            )
        end

        wx = 77
        hx = 19
        if feedback_tab_mode == 1 then
            -- Check specifically if SHIFT is held down (returns true/false)
            local is_shift_down = reaper.ImGui_IsKeyDown(ctx, reaper.ImGui_Mod_Shift())

            --reaper.ImGui_Text(ctx, "Entry Buttons:")

            the_root_colors = {244, 244, 244}
            thecolor =
                reaper.ImGui_ColorConvertDouble4ToU32(
                the_root_colors[1] * (1.0 / 255.0),
                the_root_colors[2] * (1.0 / 255.0),
                the_root_colors[3] * (1.0 / 255.0),
                1
            )

            reaper.ImGui_BeginGroup(ctx)
            reaper.ImGui_Dummy(ctx, 3, 5)
            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), thecolor)
            if r.ImGui_Button(ctx, "Rest", wx, hx) then
                chord_charting_area = chord_charting_area .. "-  "
            end
            r.ImGui_SameLine(ctx)
            if r.ImGui_Button(ctx, "Return", wx, hx) then
                chord_charting_area = chord_charting_area .. string.char(10)
            end

            r.ImGui_PopStyleColor(ctx, 1)
            reaper.ImGui_EndGroup(ctx)
            r.ImGui_SameLine(ctx)
            reaper.ImGui_Text(
                ctx,
                "Hold Shift for Flat Roots / Ctrl to place in chart.\nGlowing = Very Popular / Bright = In Diatonic Scale"
            )

            --r.ImGui_Separator(ctx)

            for i, v in pairs(musictheory.button_table) do
                if v[1] == "L" then
                    reaper.ImGui_Text(ctx, v[2])
                    r.ImGui_SameLine(ctx)
                    r.ImGui_Separator(ctx)
                else
                    if transpar > .9 then
                        fade_up = false
                    elseif transpar < .4 then
                        fade_up = true
                    end
                    if fade_up == false then
                        transpar = transpar - .0007
                    elseif fade_up == true then
                        transpar = transpar + .0007
                    end

                    if is_shift_down then
                        play_root = "1"
                        the_root_colors = musictheory.root_colors[play_root]
                        if v[2] == "       " then
                            thecolor = Get_Pulsing_Color(the_root_colors, transpar)
                        else
                            if v[3][1] ~= nil then
                                thecolor =
                                    reaper.ImGui_ColorConvertDouble4ToU32(
                                    the_root_colors[1] * (1.0 / 255.0),
                                    the_root_colors[2] * (1.0 / 255.0),
                                    the_root_colors[3] * (1.0 / 255.0),
                                    1
                                )
                            else
                                thecolor =
                                    reaper.ImGui_ColorConvertDouble4ToU32(
                                    the_root_colors[1] * (1.0 / 255.0),
                                    the_root_colors[2] * (1.0 / 255.0),
                                    the_root_colors[3] * (1.0 / 255.0),
                                    .2
                                )
                            end
                        end
                        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), thecolor)
                        play_button_midi(v, play_root)
                        r.ImGui_PopStyleColor(ctx, 1)
                        r.ImGui_SameLine(ctx)

                        flat_level = .59

                        play_root = "b2"
                        the_root_colors = musictheory.root_colors[play_root]
                        thecolor =
                            reaper.ImGui_ColorConvertDouble4ToU32(
                            the_root_colors[1] * (1.0 / 255.0),
                            the_root_colors[2] * (1.0 / 255.0),
                            the_root_colors[3] * (1.0 / 255.0),
                            flat_level
                        )
                        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), thecolor)
                        play_button_midi(v, play_root)
                        r.ImGui_PopStyleColor(ctx, 1)
                        r.ImGui_SameLine(ctx)

                        play_root = "b3"
                        the_root_colors = musictheory.root_colors[play_root]
                        thecolor =
                            reaper.ImGui_ColorConvertDouble4ToU32(
                            the_root_colors[1] * (1.0 / 255.0),
                            the_root_colors[2] * (1.0 / 255.0),
                            the_root_colors[3] * (1.0 / 255.0),
                            flat_level
                        )
                        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), thecolor)
                        play_button_midi(v, play_root)
                        r.ImGui_PopStyleColor(ctx, 1)
                        r.ImGui_SameLine(ctx)

                        play_root = "4"
                        the_root_colors = musictheory.root_colors[play_root]
                        if v[2] == "       " then
                            thecolor = Get_Pulsing_Color(the_root_colors, transpar)
                        else
                            if v[3][4] ~= nil then
                                thecolor =
                                    reaper.ImGui_ColorConvertDouble4ToU32(
                                    the_root_colors[1] * (1.0 / 255.0),
                                    the_root_colors[2] * (1.0 / 255.0),
                                    the_root_colors[3] * (1.0 / 255.0),
                                    1
                                )
                            else
                                thecolor =
                                    reaper.ImGui_ColorConvertDouble4ToU32(
                                    the_root_colors[1] * (1.0 / 255.0),
                                    the_root_colors[2] * (1.0 / 255.0),
                                    the_root_colors[3] * (1.0 / 255.0),
                                    .2
                                )
                            end
                        end
                        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), thecolor)
                        play_button_midi(v, play_root)
                        r.ImGui_PopStyleColor(ctx, 1)
                        r.ImGui_SameLine(ctx)

                        play_root = "b5"
                        the_root_colors = musictheory.root_colors[play_root]
                        thecolor =
                            reaper.ImGui_ColorConvertDouble4ToU32(
                            the_root_colors[1] * (1.0 / 255.0),
                            the_root_colors[2] * (1.0 / 255.0),
                            the_root_colors[3] * (1.0 / 255.0),
                            flat_level
                        )
                        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), thecolor)
                        play_button_midi(v, play_root)
                        r.ImGui_PopStyleColor(ctx, 1)
                        r.ImGui_SameLine(ctx)

                        play_root = "b6"
                        the_root_colors = musictheory.root_colors[play_root]
                        thecolor =
                            reaper.ImGui_ColorConvertDouble4ToU32(
                            the_root_colors[1] * (1.0 / 255.0),
                            the_root_colors[2] * (1.0 / 255.0),
                            the_root_colors[3] * (1.0 / 255.0),
                            flat_level
                        )
                        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), thecolor)
                        play_button_midi(v, play_root)
                        r.ImGui_PopStyleColor(ctx, 1)
                        r.ImGui_SameLine(ctx)

                        play_root = "b7"
                        the_root_colors = musictheory.root_colors[play_root]
                        thecolor =
                            reaper.ImGui_ColorConvertDouble4ToU32(
                            the_root_colors[1] * (1.0 / 255.0),
                            the_root_colors[2] * (1.0 / 255.0),
                            the_root_colors[3] * (1.0 / 255.0),
                            flat_level
                        )
                        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), thecolor)
                        play_button_midi(v, play_root)
                        r.ImGui_PopStyleColor(ctx, 1)
                    else
                        play_root = "1"
                        the_root_colors = musictheory.root_colors[play_root]
                        if v[2] == "       " then
                            thecolor = Get_Pulsing_Color(the_root_colors, transpar)
                        else
                            if v[3][1] ~= nil then
                                thecolor =
                                    reaper.ImGui_ColorConvertDouble4ToU32(
                                    the_root_colors[1] * (1.0 / 255.0),
                                    the_root_colors[2] * (1.0 / 255.0),
                                    the_root_colors[3] * (1.0 / 255.0),
                                    1
                                )
                            else
                                thecolor =
                                    reaper.ImGui_ColorConvertDouble4ToU32(
                                    the_root_colors[1] * (1.0 / 255.0),
                                    the_root_colors[2] * (1.0 / 255.0),
                                    the_root_colors[3] * (1.0 / 255.0),
                                    .2
                                )
                            end
                        end
                        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), thecolor)
                        play_button_midi(v, play_root)
                        r.ImGui_PopStyleColor(ctx, 1)
                        r.ImGui_SameLine(ctx)

                        play_root = "2"
                        the_root_colors = musictheory.root_colors[play_root]
                        if v[2] == "m      " then
                            thecolor = Get_Pulsing_Color(the_root_colors, transpar)
                        else
                            if v[3][2] ~= nil then
                                thecolor =
                                    reaper.ImGui_ColorConvertDouble4ToU32(
                                    the_root_colors[1] * (1.0 / 255.0),
                                    the_root_colors[2] * (1.0 / 255.0),
                                    the_root_colors[3] * (1.0 / 255.0),
                                    1
                                )
                            else
                                thecolor =
                                    reaper.ImGui_ColorConvertDouble4ToU32(
                                    the_root_colors[1] * (1.0 / 255.0),
                                    the_root_colors[2] * (1.0 / 255.0),
                                    the_root_colors[3] * (1.0 / 255.0),
                                    .2
                                )
                            end
                        end
                        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), thecolor)
                        play_button_midi(v, play_root)
                        r.ImGui_PopStyleColor(ctx, 1)
                        r.ImGui_SameLine(ctx)

                        play_root = "3"
                        the_root_colors = musictheory.root_colors[play_root]
                        if v[2] == "m      " then
                            thecolor = Get_Pulsing_Color(the_root_colors, transpar)
                        else
                            if v[3][3] ~= nil then
                                thecolor =
                                    reaper.ImGui_ColorConvertDouble4ToU32(
                                    the_root_colors[1] * (1.0 / 255.0),
                                    the_root_colors[2] * (1.0 / 255.0),
                                    the_root_colors[3] * (1.0 / 255.0),
                                    1
                                )
                            else
                                thecolor =
                                    reaper.ImGui_ColorConvertDouble4ToU32(
                                    the_root_colors[1] * (1.0 / 255.0),
                                    the_root_colors[2] * (1.0 / 255.0),
                                    the_root_colors[3] * (1.0 / 255.0),
                                    .2
                                )
                            end
                        end

                        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), thecolor)
                        play_button_midi(v, play_root)
                        r.ImGui_PopStyleColor(ctx, 1)
                        r.ImGui_SameLine(ctx)

                        play_root = "4"
                        the_root_colors = musictheory.root_colors[play_root]
                        if v[2] == "       " then
                            thecolor = Get_Pulsing_Color(the_root_colors, transpar)
                        else
                            if v[3][4] ~= nil then
                                thecolor =
                                    reaper.ImGui_ColorConvertDouble4ToU32(
                                    the_root_colors[1] * (1.0 / 255.0),
                                    the_root_colors[2] * (1.0 / 255.0),
                                    the_root_colors[3] * (1.0 / 255.0),
                                    1
                                )
                            else
                                thecolor =
                                    reaper.ImGui_ColorConvertDouble4ToU32(
                                    the_root_colors[1] * (1.0 / 255.0),
                                    the_root_colors[2] * (1.0 / 255.0),
                                    the_root_colors[3] * (1.0 / 255.0),
                                    .2
                                )
                            end
                        end
                        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), thecolor)
                        play_button_midi(v, play_root)
                        r.ImGui_PopStyleColor(ctx, 1)
                        r.ImGui_SameLine(ctx)

                        play_root = "5"
                        the_root_colors = musictheory.root_colors[play_root]
                        if v[2] == "       " then
                            thecolor = Get_Pulsing_Color(the_root_colors, transpar)
                        else
                            if v[3][5] ~= nil then
                                thecolor =
                                    reaper.ImGui_ColorConvertDouble4ToU32(
                                    the_root_colors[1] * (1.0 / 255.0),
                                    the_root_colors[2] * (1.0 / 255.0),
                                    the_root_colors[3] * (1.0 / 255.0),
                                    1
                                )
                            else
                                thecolor =
                                    reaper.ImGui_ColorConvertDouble4ToU32(
                                    the_root_colors[1] * (1.0 / 255.0),
                                    the_root_colors[2] * (1.0 / 255.0),
                                    the_root_colors[3] * (1.0 / 255.0),
                                    .2
                                )
                            end
                        end
                        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), thecolor)
                        play_button_midi(v, play_root)
                        r.ImGui_PopStyleColor(ctx, 1)
                        r.ImGui_SameLine(ctx)

                        play_root = "6"
                        the_root_colors = musictheory.root_colors[play_root]
                        if v[2] == "m      " then
                            thecolor = Get_Pulsing_Color(the_root_colors, transpar)
                        else
                            if v[3][6] ~= nil then
                                thecolor =
                                    reaper.ImGui_ColorConvertDouble4ToU32(
                                    the_root_colors[1] * (1.0 / 255.0),
                                    the_root_colors[2] * (1.0 / 255.0),
                                    the_root_colors[3] * (1.0 / 255.0),
                                    1
                                )
                            else
                                thecolor =
                                    reaper.ImGui_ColorConvertDouble4ToU32(
                                    the_root_colors[1] * (1.0 / 255.0),
                                    the_root_colors[2] * (1.0 / 255.0),
                                    the_root_colors[3] * (1.0 / 255.0),
                                    .2
                                )
                            end
                        end
                        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), thecolor)
                        play_button_midi(v, play_root)
                        r.ImGui_PopStyleColor(ctx, 1)
                        r.ImGui_SameLine(ctx)

                        play_root = "7"
                        the_root_colors = musictheory.root_colors[play_root]
                        if v[2] == "dim    " then
                            thecolor =
                                reaper.ImGui_ColorConvertDouble4ToU32(
                                the_root_colors[1] * (1.0 / 255.0),
                                the_root_colors[2] * (1.0 / 255.0),
                                the_root_colors[3] * (1.0 / 255.0),
                                1
                            )
                        else
                            if v[3][7] ~= nil then
                                thecolor =
                                    reaper.ImGui_ColorConvertDouble4ToU32(
                                    the_root_colors[1] * (1.0 / 255.0),
                                    the_root_colors[2] * (1.0 / 255.0),
                                    the_root_colors[3] * (1.0 / 255.0),
                                    1
                                )
                            else
                                thecolor =
                                    reaper.ImGui_ColorConvertDouble4ToU32(
                                    the_root_colors[1] * (1.0 / 255.0),
                                    the_root_colors[2] * (1.0 / 255.0),
                                    the_root_colors[3] * (1.0 / 255.0),
                                    .2
                                )
                            end
                        end

                        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), thecolor)
                        play_button_midi(v, play_root)
                        r.ImGui_PopStyleColor(ctx, 1)
                    end
                end
            end

            reaper.ImGui_InputTextFlags_AllowTabInput()
        end

        if feedback_tab_mode == 2 then
            reaper.ImGui_Text(ctx, "Not yet implemented.")

        --[[
    --r.ImGui_InputTextMultiline(ctx,"##feedback_zone", render_feedback, 577, 520,reaper.ImGui_InputTextFlags_AllowTabInput())
        reaper.ImGui_BeginGroup(ctx)
    reaper.ImGui_Dummy(ctx, 3, 5)
        if not type(bol) then bol = true end                -- BUTTONS
        rc, GridTrueFalse = r.ImGui_Checkbox(ctx, "Render Full-Range Chord Grid", GridTrueFalse)
        if not type(bol) then bol = true end
    rc, ChordsTrueFalse = r.ImGui_Checkbox(ctx, "Render Chords", ChordsTrueFalse)
        if not type(bol) then bol = true end
        rc, ChBassTrueFalse = r.ImGui_Checkbox(ctx, "Render Chord + Bass Combo", ChBassTrueFalse)    
        if not type(bol) then bol = true end
    reaper.ImGui_EndGroup(ctx)
    r.ImGui_SameLine(ctx)
    reaper.ImGui_BeginGroup(ctx)
    reaper.ImGui_Dummy(ctx, 3, 5)  
    reaper.ImGui_EndGroup(ctx)
    r.ImGui_SameLine(ctx)
    reaper.ImGui_BeginGroup(ctx)
        reaper.ImGui_Dummy(ctx, 3, 5)
    if not type(bol) then bol = true end
        rc, Lead1TrueFalse = r.ImGui_Checkbox(ctx, "Render Lead 1", Lead1TrueFalse)
    if not type(bol) then bol = true end
        rc, Lead2TrueFalse = r.ImGui_Checkbox(ctx, "Render Lead 2", Lead2TrueFalse)
        if not type(bol) then bol = true end
        rc, BassTrueFalse = r.ImGui_Checkbox(ctx, "Render Bass", BassTrueFalse)

    reaper.ImGui_EndGroup(ctx)
    ]]
        end
        if feedback_tab_mode == 3 then
            reaper.ImGui_Text(ctx, "Not yet implemented.")
        end

        if feedback_tab_mode == 4 and import_tab_mode == 1 then
            reaper.ImGui_Text(
                ctx,
                'Paste or type in lettered chord names. See "Help:Rhythm Help" for\nrhythmic formatting.  Then convert to Numbers2Notes System.\n'
            )
            Link("https://en.wikipedia.org/wiki/Nashville_Number_System")
            rv, letter_import =
                r.ImGui_InputTextMultiline(
                ctx,
                "##letter_import",
                letter_import,
                592,
                239,
                reaper.ImGui_InputTextFlags_AllowTabInput()
            )
            rv, letter_to_num_key = r.ImGui_InputTextMultiline(ctx, "Key", letter_to_num_key, 35, 22, nil)
            r.ImGui_SameLine(ctx)
            if r.ImGui_Button(ctx, "Convert Letters >> Numbers2Notes format", nil, nil) then
                numbers_from_Letters = letters_to_numbers(letter_to_num_key, letter_import)
            end
            rv, numbers_from_Letters =
                r.ImGui_InputTextMultiline(
                ctx,
                "##numbers_from_Letters",
                numbers_from_Letters,
                592,
                242,
                reaper.ImGui_InputTextFlags_AllowTabInput()
            )
        end
        if feedback_tab_mode == 4 and import_tab_mode == 2 then
            reaper.ImGui_Text(ctx, "Not yet implemented.")
        end

        if feedback_tab_mode == 4 and import_tab_mode == 3 then
            reaper.ImGui_Text(
                ctx,
                "\nNumbers2Notes provides some support for importing from OneMotion.Com's \nChord Player.\n\n"
            )
            Link("https://www.onemotion.com/chord-player/")
            reaper.ImGui_Text(
                ctx,
                '\nIt does not support importing chords with inversions and can only\nimport songs with a 4/4 time signature.\n\nMake sure to copy the data from OneMotion\'s "Edit All" dialog with units \nset to "Beat."\n\n '
            )
            rv, import_key =
                r.ImGui_InputTextMultiline(
                ctx,
                "Import Key",
                import_key,
                35,
                22,
                reaper.ImGui_InputTextFlags_AllowTabInput()
            )
            r.ImGui_SameLine(ctx)
            if r.ImGui_Button(ctx, "Convert clipboard: OneMotion >> Numbers2Notes format format", nil, nil) then
                import_onemotion()
            end
            r.ImGui_InputTextMultiline(
                ctx,
                "##onemotionimport",
                onemotionimport,
                592,
                321,
                reaper.ImGui_InputTextFlags_AllowTabInput()
            )
        end

        if feedback_tab_mode == 5 and export_tab_mode == 1 then
            reaper.ImGui_Text(
                ctx,
                '\n1) Fill in all info including the BIAB style.\n2) In Band in a Box, go to the Edit menu.\n3) Select "Paste Special - from Clipboard text to Song(s) "Ctrl Shift V"\n4) Select "Paste as New Song"\n5) Click OK.\n6) Return to the Edit menu\n7) Again select "Paste Special - from Clipboard text to Song(s)...\n8) Select "Paste into Current Song"\n9) Click OK.\n'
            )

            reaper.ImGui_Separator(ctx)

            rv, biab_style =
                r.ImGui_InputTextMultiline(
                ctx,
                "BIAB sytle",
                biab_style,
                200,
                23,
                reaper.ImGui_InputTextFlags_AllowTabInput()
            )
            reaper.ImGui_SameLine(ctx)
            if r.ImGui_Button(ctx, "Convert song to BIAB paste-in format", nil, nil) then
                export_biab()
            end

            rv, biab_export_area =
                r.ImGui_InputTextMultiline(
                ctx,
                "##biab_export_area",
                biab_export_area,
                592,
                186,
                reaper.ImGui_InputTextFlags_AllowTabInput()
            )
            student = false
            beta = true
            if student then
                reaper.ImGui_Text(ctx, "Students...\n")
                reaper.ImGui_Text(ctx, "1) Audition and select your style here:\n")
                Link("https://tinyurl.com/StylePick09844879") -- hidden database
                reaper.ImGui_Text(
                    ctx,
                    '2) Copy your selected style\'s "Copy Code" in 1st column.\n3) Paste the code into the BIAB Style blank above.\n4) Press the blue "Convert song to BIAB..." button\n5) Copy the output data and paste it in the form at this site...\n'
                )
                Link("https://forms.office.com/r/Tt2D8u0M6c") -- hidden Form
                reaper.ImGui_Text(ctx, "6) Download your files here...\n")
                Link(
                    "https://k12mnps-my.sharepoint.com/:f:/g/personal/rkennedy_mnps_org/EuickG4Y9Z1Ig1i9gU2CYqcBzAI28jkiDF3hUZHgO3IEDw?e=vq4nCH"
                ) -- hidden files
            elseif beta then
                reaper.ImGui_Text(
                    ctx,
                    "Beta Testers you can send me your output and I will try to post your \nfiles online for you. Please be patient it is not an automated process.\n"
                )
                reaper.ImGui_Text(ctx, "1) Audition and select your style here:\n")
                Link("https://tinyurl.com/StylePick") -- hidden database
                reaper.ImGui_Text(
                    ctx,
                    '2) Copy your selected style\'s "Copy Code" in 1st column.\n3) Paste the code into the BIAB Style blank above.\n4) Press the blue "Convert song to BIAB..." button\n5) Copy the output data and paste it in the form at this site...\n'
                )
                Link("https://forms.office.com/r/Tt2D8u0M6c") -- hidden Form
                reaper.ImGui_Text(ctx, "6) Download your files here...\n")
                Link(
                    "https://k12mnps-my.sharepoint.com/:f:/g/personal/rkennedy_mnps_org/EuickG4Y9Z1Ig1i9gU2CYqcBzAI28jkiDF3hUZHgO3IEDw?e=vq4nCH"
                ) -- hidden files
            else
            end
        end
        if feedback_tab_mode == 5 and export_tab_mode == 2 then
            reaper.ImGui_Text(
                ctx,
                "\nNumbers2Notes provides some support for exporting to OneMotion.Com's \nChord Player.\n"
            )

            Link("https://www.onemotion.com/chord-player/")

            reaper.ImGui_Text(
                ctx,
                '\nIt does not support exporting chords with inversions. Make sure to copy\nthe data from OneMotion\'s "Edit All" dialog with units set to "Beat."\n\n'
            )

            --if r.ImGui_Button(ctx, "Convert Chords: Numbers2Notes >> OneMotion Chord Player format", nil, nil) then
            --    render_onemotion()
            --end
            if r.ImGui_Button(ctx, "Convert Numbers2Notes >> OneMotion Chord Player format", nil, nil) then
                Export_OM()
            end
            r.ImGui_InputTextMultiline(
                ctx,
                "##onemotionoutput",
                onemotionoutput,
                592,
                401,
                reaper.ImGui_InputTextFlags_AllowTabInput()
            )
        end

        if feedback_tab_mode == 5 and export_tab_mode == 3 then
            reaper.ImGui_Text(
                ctx,
                "\nNumbers2Notes provides some support for exporting to Chordsheet.Com's \nfree chord chart PDF creation service.\n\nA few things to keep in mind.\n\n  - Only quarter note changes are supported.\n  - Up to 8 chords per bar can be shown but no rhythms will be\n       indicated. Of course you can manually add them by writing\n       them on your print-outs.\n  - Custom links have a 2000 character limit, so very long chord\n       charts may not transfer in their entirety. You may wish to\n       render them in smaller chunks\n  - When you open the link you will need to save to see your PDF.\n  - Download to print.\n  - If you want to save your chord chart at Chordsheet.com, you\n       will need to sign up for their free membership.\n  - The owner of the site has been super cooperative. Please\n       support his efforts.\n\n"
            )

            if ccc_renderd == true then
                if r.ImGui_Button(ctx, "Update my custom link.", nil, nil) then
                    export_ccc()
                end

                reaper.ImGui_Text(ctx, "\n\nYour custom link...\n\n")
                Link(ccclink)
            else
                if r.ImGui_Button(ctx, "Create my custom link.", nil, nil) then
                    export_ccc()
                end
            end
        end

        if feedback_tab_mode == 6 then
            reaper.ImGui_Text(ctx, "Chord and Progression Popularity")
            reaper.ImGui_Separator(ctx)
            reaper.ImGui_Text(ctx, "For more detailed, up-to-date information see:\n")
            Link("https://www.hooktheory.com/trends")
            reaper.ImGui_Separator(ctx)
            reaper.ImGui_Dummy(ctx, 4, 10)
            for itt = 1, 12, 1 do
                if string.len(musictheory.major_trend_table[itt][1]) == 1 then
                    chordlabler = musictheory.major_trend_table[itt][1] .. " "
                else
                    chordlabler = musictheory.major_trend_table[itt][1]
                end
                if chosentheorychord == itt then
                    if reaper.ImGui_RadioButton(ctx, chordlabler, true) then
                        chosentheorychord = itt
                    end
                else
                    if reaper.ImGui_RadioButton(ctx, chordlabler, false) then
                        chosentheorychord = itt
                    end
                end

                reaper.ImGui_SameLine(ctx)
                the_root_colors = musictheory.root_colors[musictheory.major_trend_table[itt][4]]
                thecolor =
                    reaper.ImGui_ColorConvertDouble4ToU32(
                    the_root_colors[1] * (1.0 / 255.0),
                    the_root_colors[2] * (1.0 / 255.0),
                    the_root_colors[3] * (1.0 / 255.0),
                    1
                )

                reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_PlotHistogram(), thecolor)
                reaper.ImGui_ProgressBar(
                    ctx,
                    musictheory.major_trend_table[itt][2] / 50,
                    500,
                    20,
                    musictheory.major_trend_table[itt][2] .. "% of chords"
                )
                reaper.ImGui_PopStyleColor(ctx, 1)
            end
            reaper.ImGui_Dummy(ctx, 4, 10)
            reaper.ImGui_Separator(ctx)
            reaper.ImGui_Dummy(ctx, 4, 10)
            reaper.ImGui_Text(ctx, musictheory.major_trend_table[chosentheorychord][1] .. " Moves to...")
            next_chords = musictheory.major_trend_table[chosentheorychord][3]
            for i1, v1 in pairs(next_chords) do
                if string.len(v1[1]) == 1 then
                    followchordlable = v1[1] .. "  "
                elseif string.len(v1[1]) == 2 then
                    followchordlable = v1[1] .. " "
                else
                    followchordlable = v1[1] .. ""
                end
                if i1 > 6 then
                    reaper.ImGui_SameLine(ctx)

                    reaper.ImGui_Text(ctx, "   ")
                    reaper.ImGui_SameLine(ctx)
                    reaper.ImGui_Text(ctx, v1[1])
                    reaper.ImGui_SameLine(ctx)
                    --reaper.ImGui_ProgressBar(ctx, musictheory.major_trend_table[itt][2] / 50, 500, 20, musictheory
                    rooty = string.gsub(v1[1], "m", "")

                    the_root_colors = musictheory.root_colors[rooty]
                    thecolor =
                        reaper.ImGui_ColorConvertDouble4ToU32(
                        the_root_colors[1] * (1.0 / 255.0),
                        the_root_colors[2] * (1.0 / 255.0),
                        the_root_colors[3] * (1.0 / 255.0),
                        1
                    )
                    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), thecolor)
                    r.ImGui_Button(ctx, v1[2] .. "% of the time", v1[2] * 10, nil)
                    reaper.ImGui_PopStyleColor(ctx, 1)
                else
                    reaper.ImGui_Text(ctx, followchordlable)
                    reaper.ImGui_SameLine(ctx)
                    --reaper.ImGui_ProgressBar(ctx, musictheory.major_trend_table[itt][2] / 50, 500, 20, musictheory
                    rooty = string.gsub(v1[1], "m", "")

                    the_root_colors = musictheory.root_colors[rooty]
                    thecolor =
                        reaper.ImGui_ColorConvertDouble4ToU32(
                        the_root_colors[1] * (1.0 / 255.0),
                        the_root_colors[2] * (1.0 / 255.0),
                        the_root_colors[3] * (1.0 / 255.0),
                        1
                    )
                    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), thecolor)
                    r.ImGui_Button(ctx, v1[2] .. "% of the time", v1[2] * 10, nil)
                    reaper.ImGui_PopStyleColor(ctx, 1)
                end
            end
        end

        if feedback_tab_mode == 7 then
            reaper.ImGui_Text(ctx, "Classic Chord Progressions")
            reaper.ImGui_SameLine(ctx)
            Link("https://www.hooktheory.com/theorytab/common-chord-progressions")

            reaper.ImGui_Separator(ctx)

            for i, v in pairs(musictheory.chains_table) do
                reaper.ImGui_Separator(ctx)
                reaper.ImGui_Text(ctx, "       #" .. i .. ") " .. v[1])

                thecolor = reaper.ImGui_ColorConvertDouble4ToU32(.95, .95, .95, 1)
                r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), thecolor)
                if i < 10 then
                    if r.ImGui_Button(ctx, "Add #" .. i .. "  -->", nil) then
                        chord_charting_area = chord_charting_area .. "\n" .. v[2] .. "\n"
                    end
                else
                    if r.ImGui_Button(ctx, "Add #" .. i .. " -->", nil) then
                        chord_charting_area = chord_charting_area .. "\n" .. v[2] .. "\n"
                    end
                end

                reaper.ImGui_PopStyleColor(ctx, 1)

                for ji, kv in pairs(v[3]) do
                    reaper.ImGui_SameLine(ctx)

                    the_root_colors = musictheory.root_colors[kv[3]]
                    thecolor =
                        reaper.ImGui_ColorConvertDouble4ToU32(
                        the_root_colors[1] * (1.0 / 255.0),
                        the_root_colors[2] * (1.0 / 255.0),
                        the_root_colors[3] * (1.0 / 255.0),
                        1
                    )
                    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), thecolor)
                    r.ImGui_Button(ctx, kv[2], 44)
                    reaper.ImGui_PopStyleColor(ctx, 1)
                end
            end
        end

        if feedback_tab_mode == 8 and help_tab_mode == 1 then
            r.ImGui_InputTextMultiline(
                ctx,
                "##helpsample",
                help.Sample_song,
                592,
                562,
                reaper.ImGui_InputTextFlags_AllowTabInput()
            )
        end
        if feedback_tab_mode == 8 and help_tab_mode == 2 then
            r.ImGui_InputTextMultiline(
                ctx,
                "##helptemplate",
                help.Template,
                592,
                562,
                reaper.ImGui_InputTextFlags_AllowTabInput()
            )
        end
        if feedback_tab_mode == 8 and help_tab_mode == 3 then
            r.ImGui_InputTextMultiline(
                ctx,
                "##helpcode",
                help.Code_help,
                592,
                562,
                reaper.ImGui_InputTextFlags_AllowTabInput()
            )
        end
        if feedback_tab_mode == 8 and help_tab_mode == 4 then
            r.ImGui_InputTextMultiline(
                ctx,
                "##helpsection",
                help.Section_help,
                592,
                562,
                reaper.ImGui_InputTextFlags_AllowTabInput()
            )
        end
        if feedback_tab_mode == 8 and help_tab_mode == 5 then
            r.ImGui_InputTextMultiline(
                ctx,
                "##helpchord",
                help.Chord_help,
                592,
                562,
                reaper.ImGui_InputTextFlags_AllowTabInput()
            )
        end
        if feedback_tab_mode == 8 and help_tab_mode == 6 then
            r.ImGui_InputTextMultiline(
                ctx,
                "##helpsrhythm",
                help.Rhythm_help,
                592,
                562,
                reaper.ImGui_InputTextFlags_AllowTabInput()
            )
        end

        if feedback_tab_mode == 10 then
            reaper.ImGui_Text(ctx, "N2N Groove Editor (32nd Note Offsets)")
            reaper.ImGui_Separator(ctx)

            -- TOOLBAR
            if r.ImGui_Button(ctx, "Interpolate Anchors") then
                Groove_Interpolate()
            end
            r.ImGui_SameLine(ctx)
            if r.ImGui_Button(ctx, "Reset") then
                for i = 1, 32 do
                    groove_data[i] = 0.0
                end
                Export_Groove_To_GMEM()
            end
            r.ImGui_SameLine(ctx)
            if r.ImGui_Button(ctx, "Load Preset") then
                Load_Groove()
                Export_Groove_To_GMEM()
            end
            r.ImGui_SameLine(ctx)
            if r.ImGui_Button(ctx, "Save Preset") then
                Save_Groove()
            end

            r.ImGui_Separator(ctx)

            -- =========================================================
            -- LAYOUT CONFIGURATION
            -- =========================================================
            local col_w_1 = 163 -- Width for Beat 1 (Has Labels)
            local col_w_rest = 135 -- Width for Beats 2,3,4 (No Labels)
            local gap_tight = 5 -- Gap between Checkbox and Slider for Beats 2-4
            -- =========================================================

            for beat = 0, 3 do
                if beat > 0 then
                    r.ImGui_SameLine(ctx)
                end

                -- 1. Determine Background Color (Alternating Grays)
                local bg_col
                if beat % 2 == 0 then
                    bg_col = 0xDEDEDEFF -- Light Gray (Even)
                else
                    bg_col = 0xC4C4C4FF -- Mid Gray (Odd)
                end

                r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ChildBg(), bg_col)

                -- 2. Determine Column Width
                local current_width = (beat == 0) and col_w_1 or col_w_rest

                -- 3. Create Column (Child)
                if r.ImGui_BeginChild(ctx, "beat_col_" .. beat, current_width, 220, false) then
                    -- HEADER: Black Text
                    r.ImGui_TextColored(ctx, 0x000000FF, "BEAT " .. (beat + 1))
                    r.ImGui_Separator(ctx)

                    for step = 1, 8 do
                        local i = (beat * 8) + step
                        r.ImGui_PushID(ctx, i)

                        -- A. Anchor Checkbox
                        local rv, check = r.ImGui_Checkbox(ctx, "##anc", groove_anchors[i])
                        if rv then
                            groove_anchors[i] = check
                        end

                        -- B. Label Logic
                        if beat == 0 then
                            -- BEAT 1: Show Label
                            r.ImGui_SameLine(ctx)
                            r.ImGui_TextColored(ctx, 0x000000FF, string.format("%02d", i))
                            r.ImGui_SameLine(ctx) -- Standard Spacing
                        else
                            -- BEATS 2,3,4: No Label, Tight Spacing
                            r.ImGui_SameLine(ctx, nil, gap_tight)
                        end

                        -- C. Slider Colors
                        -- Early (< 0) = GREEN | Late (> 0) = RED
                        if groove_data[i] > 0.01 then
                            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_SliderGrab(), 0xFF4444FF) -- Red (Late)
                            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBg(), 0x55222255)
                        elseif groove_data[i] < -0.01 then
                            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_SliderGrab(), 0x44FF44FF) -- Green (Early)
                            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBg(), 0x22552255)
                        else
                            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_SliderGrab(), 0xAAAAAAFF) -- Grey
                            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBg(), 0x55555555)
                        end

                        r.ImGui_SetNextItemWidth(ctx, 92)

                        -- D. Lock Index 1 (Bar Start)
                        if i == 1 then
                            groove_data[i] = 0.0 -- Force to 0
                            r.ImGui_BeginDisabled(ctx) -- Disable Input
                        end

                        local changed, val = r.ImGui_SliderDouble(ctx, "##v", groove_data[i], -1.0, 1.0, "%.3f")
                        if changed then
                            groove_data[i] = val
                            Export_Groove_To_GMEM()
                        end

                        if i == 1 then
                            r.ImGui_EndDisabled(ctx) -- Re-enable
                        end

                        r.ImGui_PopStyleColor(ctx, 2)
                        r.ImGui_PopID(ctx)
                    end
                    r.ImGui_EndChild(ctx)
                end

                r.ImGui_PopStyleColor(ctx) -- Pop ChildBg
            end

            r.ImGui_Separator(ctx)
            r.ImGui_Text(ctx, "Left (Green) = Early | Right (Red) = Late | CTRL+Click to type value.")
        end

        reaper.ImGui_EndGroup(ctx)

        r.ImGui_End(ctx)

    -- BUTTONS
    end

    reaper.ImGui_PopStyleColor(ctx, 23)
    r.ImGui_PopFont(ctx)
    if open then
        r.defer(IM_GUI_Loop)
    else
        ctx = nil -- Set ctx to nil after destroying the context
        Autosave()
        SaveLastNumbers2NotesChart()
    end
end
--  ________________________________________________________      ADDITIONAL VARIABLES
G_split = 0
G_error_log = "START ERROR LOG - " .. string.char(10)
G_time_signature_top = 4
G_ticks_per_measure = 960
G_track_list = nil
G_track_table = nil
G_region_table = {}
G_modal_on = false
onemotionoutput = ""
inparenthetical = false

chord_table = {}
pushy_chord_table = {}
temp_chord_table = {}
updated_chord_table = {}

chord_splitsection_count = 0
temp_chord_splitsection_count = 0
updated_chord_splitsection_count = 0

--  VARIABLES AND LOOKUP TABLES
j = 0
k = 0
moment = ""
measure = ""
keyshift = 0
foundnum = 0
last_v = 0
rootshift = 0
splitbar = false
chord_type = ""
measurelist = {}

unstarted = true

current_key = ""

inprogress = false

current_chorded_root = "C"
running_ppqpos_total = 0
measuremultiplelist = {}

last_char_is_o_bracket = false

-- ________________________________________________________ ADDITIONAL FUNCTIONS________________________________

-- ____________________________________________  SET THE SIMULATED USER INPUT DATA  ____________________

function Set_The_Current_Simulated_Userinput_Data(datachunk)
    datachunk = datachunk .. " "
    return datachunk
end

-- ==============================================================================
-- TRACK COMPILER & GENERATOR
-- ==============================================================================

-- Removed "local" so the UI Loop can see these globally!
FOUND_TRACKS = {}
G_RENDER_TARGETS = {}
G_BUILD_REGIONS = false
G_DRUM_CUE_MODE = false
G_ARP_CUE_MODE = false
G_MISSING_PLUGINS = {}
G_SOURCE_INDICES = {}
final_ppqpos_total = 0 -- Add this so place_special doesn't crash!

function Set_Back2Key_Transpositions()
    for _, tr_data in ipairs(G_DYNAMIC_TABLE) do
        local track = tr_data.track_ptr

        -- Apply only to receiver/playback tracks for Chords, Chords+Bass, and Bass
        if track and tr_data.mode_id > 0 and (tr_data.type_id == 16 or tr_data.type_id == 17 or tr_data.type_id == 20) then
            -- BULLETPROOF FX FINDER
            local fx_idx = -1
            for j = 0, reaper.TrackFX_GetCount(track) - 1 do
                local retval, fx_name = reaper.TrackFX_GetFXName(track, j, "")
                if retval and fx_name:find("Back2Key_N2N", 1, true) then
                    fx_idx = j
                    break
                end
            end

            if fx_idx >= 0 then
                local key_for_back2key = (G_render_mode == 0) and real_song_key or "C"
                local key_val = musictheory.key_table[key_for_back2key] or 0

                -- JSFX dropdowns ignore the <-5,6> range and expect the list Index (0 to 11).
                -- C(0)+5=5 (C to C). G(7)+5=12->0 (C to G). F#(6)+5=11 (C to F#).
                local slider_index = (key_val + 5) % 12

                -- Param 0 is slider1 (Transpose)
                reaper.TrackFX_SetParam(track, fx_idx, 0, slider_index)

                -- Enable only in Relative mode; disable in Absolute mode
                reaper.TrackFX_SetEnabled(track, fx_idx, G_render_mode == 0)
            end
        end
    end
end

local function DeepCopy(orig)
    local orig_type = type(orig)
    local copy
    if orig_type == "table" then
        copy = {}
        for orig_key, orig_value in next, orig, nil do
            copy[DeepCopy(orig_key)] = DeepCopy(orig_value)
        end
        setmetatable(copy, DeepCopy(getmetatable(orig)))
    else
        copy = orig
    end
    return copy
end

function Compile_Dynamic_Track_Table(recipe)
    local dynamic_table = {}
    G_SOURCE_INDICES = {}
    local name_counts = {}
    local current_idx = 1

    local function AddTrack(template, tr_data, type_id, mode_id)
        local t = DeepCopy(template)

        -- Lock the IDs into the track data so the Builder knows what it is!
        t.type_id = type_id
        t.mode_id = mode_id

        -- SPACER LOGIC (Source vs Receiver)
        if tr_data and tr_data.Tr_divider_before then
            -- Does this track type have a Source Track (Mode 0)?
            if config.track_table[type_id] and config.track_table[type_id][0] then
                -- Yes: Only put the spacer on the Source (0), not the receivers (1, 2, 3...)
                if mode_id == 0 then
                    t.Tr_divider_before = true
                end
            else
                -- No Source track (e.g. Drums, FX): Just put the spacer on it directly
                t.Tr_divider_before = true
            end
        end

        -- APPLY COMMON FX (ONLY TO RECEIVERS, NEVER TO MODE 0 SOURCE TRACKS)
        if tr_data and tr_data.addchain and advanced_user_setup.commonchain then
            if mode_id > 0 then
                for _, common_fx in ipairs(advanced_user_setup.commonchain) do
                    table.insert(t[5], DeepCopy(common_fx))
                end
            end
        end

        local base_name = t[1]
        local choice = tr_data and (tr_data.vsti_choice or tr_data.vst_choice)
        if base_name:find("REPLACEFX") and choice then
            base_name = base_name:gsub("REPLACEFX", choice.selection_label or "")
        end

        name_counts[base_name] = (name_counts[base_name] or 0) + 1
        local instance_num = name_counts[base_name]

        if base_name:find("##") then
            t[1] = base_name:gsub("##", tostring(instance_num))
        else
            if instance_num > 1 then
                t[1] = base_name .. " " .. instance_num
            else
                t[1] = base_name
            end
        end

        dynamic_table[current_idx] = t
        current_idx = current_idx + 1
        return current_idx - 1
    end

    for _, tr in ipairs(recipe) do
        if tr.active and config.track_table[tr.type] then
            
            -- =========================================================
            -- ROUTING CONSOLIDATION: Force Types 16 & 20 to use 17's Source
            -- =========================================================
            local source_type = tr.type
            if source_type == 16 or source_type == 20 then
                source_type = 17
            end

            -- A. Build Source Track (Mode 0)
            if config.track_table[source_type] and config.track_table[source_type][0] then
                if not G_SOURCE_INDICES[source_type] then
                    -- Pass 'tr' so the Source track inherits the divider!
                    G_SOURCE_INDICES[source_type] = AddTrack(config.track_table[source_type][0], tr, source_type, 0)
                end
            end

-- Convert mode string to numeric index
            local mode_key = 1
            if tr.mode then
                for idx, m_name in ipairs(config.mode_options) do
                    if m_name == tr.mode then
                        mode_key = idx
                        break
                    end
                end
            elseif tr.audio_choice and config.audiochoice then
                -- Map the Audio dropdown selection to indices 1-8
                for idx, a_choice in ipairs(config.audiochoice) do
                    if a_choice.selection_label == tr.audio_choice.selection_label then
                        mode_key = idx
                        break
                    end
                end
            end

            -- B. Build Target Track
            if config.track_table[tr.type][mode_key] then
                local target_idx = AddTrack(config.track_table[tr.type][mode_key], tr, tr.type, mode_key)
                local t_data = dynamic_table[target_idx]
                local active_choice = tr.vsti_choice or tr.vst_choice or tr.audio_choice






                local chosen_drum_preset = tr.preset_choice and tr.preset_choice.preset or nil

                for _, fx_info in ipairs(t_data[5]) do
                    if fx_info[1] == "REPLACEFX" and active_choice then
                        fx_info[1] = active_choice.search or ""
                        fx_info[4] = active_choice.pluginsources or 0
                    end

                    if fx_info[3] == "REPLACEPRESET" and active_choice then
                        fx_info[3] = active_choice.preset or nil
                    end
                end

                if tr.type == 31 and chosen_drum_preset and chosen_drum_preset ~= "" then
                    for _, fx_info in ipairs(t_data[5]) do
                        if fx_info[1] and (
                            fx_info[1]:find("N2N Drum Arranger") or
                            (active_choice and fx_info[1] == (active_choice.search or ""))
                        ) then
                            fx_info[3] = chosen_drum_preset
                        end
                    end
                end








                local clean_fx = {}
                for _, fx_info in ipairs(t_data[5]) do
                    if fx_info[1] ~= "" and fx_info[1] ~= "Select Other..." then
                        table.insert(clean_fx, fx_info)
                    end
                end
                t_data[5] = clean_fx

                -- Link the receiver track to the consolidated Master MIDI Source
                if G_SOURCE_INDICES[source_type] then
                    local src_idx = G_SOURCE_INDICES[source_type]
                    table.insert(dynamic_table[src_idx][6], target_idx)
                end
            end
        end
    end
    return dynamic_table
end

function Track_Needs_Cue_Child(tr)
    if not tr or not tr[5] then
        return false
    end

    for _, fx_info in ipairs(tr[5]) do
        local fx_name = fx_info[1]
        if fx_name and (
            fx_name:find("N2N Drum Arranger") or
            fx_name:find("N2N Arp")
        ) then
            return true
        end
    end

    return false
end

function Brighten_RGB_10(rgb)
    local function clamp(v)
        if v < 0 then return 0 end
        if v > 255 then return 255 end
        return math.floor(v + 0.5)
    end

    return {
        clamp(rgb[1] * 1.10),
        clamp(rgb[2] * 1.10),
        clamp(rgb[3] * 1.10)
    }
end

function Find_Cue_Child_By_Unique_ID(unique_id)
    local track_count = reaper.CountTracks(0)
    for i = 0, track_count - 1 do
        local tr = reaper.GetTrack(0, i)
        local retval, ext_val = reaper.GetSetMediaTrackInfo_String(tr, "P_EXT:N2N:CUECHILD_FOR", "", false)
        if retval and ext_val == unique_id then
            return tr
        end
    end
    return nil
end

function Ensure_Cue_Child_Track(parent_track, tr, unique_id)
    local cue_track = Find_Cue_Child_By_Unique_ID(unique_id)

    if not cue_track then
        local parent_idx = reaper.CSurf_TrackToID(parent_track, false) - 1
        reaper.InsertTrackAtIndex(parent_idx + 1, true)
        cue_track = reaper.GetTrack(0, parent_idx + 1)

        reaper.GetSetMediaTrackInfo_String(cue_track, "P_NAME", "Your Cues", true)
        reaper.GetSetMediaTrackInfo_String(cue_track, "P_EXT:N2N:CUECHILD_FOR", unique_id, true)
        reaper.GetSetMediaTrackInfo_String(cue_track, "P_EXT:N2N:IS_CUECHILD", "1", true)
    end

    local bright = Brighten_RGB_10(tr[8])
    local cue_color = reaper.ColorToNative(bright[1], bright[2], bright[3]) | 0x10000000
    reaper.SetTrackColor(cue_track, cue_color)

    -- minimal TCP height
    reaper.SetMediaTrackInfo_Value(cue_track, "B_HEIGHTLOCK", 1)
    reaper.SetMediaTrackInfo_Value(cue_track, "I_HEIGHTOVERRIDE", 24)

    -- keep visible in TCP, hide in mixer
    reaper.SetMediaTrackInfo_Value(cue_track, "B_SHOWINTCP", 1)
    reaper.SetMediaTrackInfo_Value(cue_track, "B_SHOWINMIXER", 0)

    return cue_track
end


function Scan_Existing_Tracks()
    FOUND_TRACKS = {}
    local track_count = reaper.CountTracks(0)
    for i = 0, track_count - 1 do
        local track = reaper.GetTrack(0, i)
        -- Reaper reads the invisible metadata string (e.g. "16_6")
        local retval, ext_val = reaper.GetSetMediaTrackInfo_String(track, "P_EXT:N2N:ID", "", false)
        if retval and ext_val ~= "" then
            if not FOUND_TRACKS[ext_val] then
                FOUND_TRACKS[ext_val] = {}
            end
            table.insert(FOUND_TRACKS[ext_val], track)
        end
    end
end


function Make_Monster_Drums_32_Chan()
      local track_count = reaper.CountTracks(0)
      for i = 0, track_count - 1 do
          local track = reaper.GetTrack(0, i)
          local fx_count = reaper.TrackFX_GetCount(track)
      
          for fx = 0, fx_count - 1 do
              local retval, fx_name = reaper.TrackFX_GetFXName(track, fx, "")
              if retval and fx_name:lower():find("monster drums") then
                  local current_nchan = reaper.GetMediaTrackInfo_Value(track, "I_NCHAN")
                  if current_nchan < 32 then
                      reaper.SetMediaTrackInfo_Value(track, "I_NCHAN", 32)
                  end
                  break
              end
          end
      end
end



local function Safe_Add_FX(track, fx_search_name, preset_name, source_id)
    if not fx_search_name or fx_search_name == "" then
        return
    end
    local fx_idx = reaper.TrackFX_AddByName(track, fx_search_name, false, -1)
    if fx_idx >= 0 then
        if preset_name and preset_name ~= "" then
            reaper.TrackFX_SetPreset(track, fx_idx, preset_name)
        end
    else
        table.insert(G_MISSING_PLUGINS, {name = fx_search_name, source = source_id or 0})
    end
end

-- FIXED SIGNATURE: It only receives "tr", and pulls the types out safely!
function Build_Single_Track(tr)
    local tr_type = tr.type_id
    local tr_mode = tr.mode_id

    -- Meta-Tracks
    if tr_type == 0 then
        G_BUILD_REGIONS = true
        return false
    end
    if tr_type == 32 then
        G_DRUM_CUE_MODE = true
        return false
    end
    if tr_type == 33 then
        G_ARP_CUE_MODE = true
        return false
    end

    -- The Unique ID the scanner looks for
    local unique_id = tostring(tr_type) .. "_" .. tostring(tr_mode)

    local existing_tracks = FOUND_TRACKS[unique_id]
    local track_to_use = nil
    local is_new = false

    if existing_tracks and #existing_tracks > 0 then
        track_to_use = table.remove(existing_tracks, 1)

        -- CLEAN MIDI ONLY IF CONFIG ALLOWS IT (tr[4] == 1)
        if tr[4] == 1 then
            local item_count = reaper.CountTrackMediaItems(track_to_use)
            for j = item_count - 1, 0, -1 do
                local item = reaper.GetTrackMediaItem(track_to_use, j)
                reaper.DeleteTrackMediaItem(track_to_use, item)
            end
        end
    else
        is_new = true
        reaper.InsertTrackAtIndex(reaper.CountTracks(0), true)
        track_to_use = reaper.GetTrack(0, reaper.CountTracks(0) - 1)
        reaper.GetSetMediaTrackInfo_String(track_to_use, "P_NAME", tr[1], true)

        -- INVISIBLE TAG: Locks the track permanently!
        reaper.GetSetMediaTrackInfo_String(track_to_use, "P_EXT:N2N:ID", unique_id, true)

        local plug_order = 1000
        for _, fx_info in ipairs(tr[5]) do
            local fx_name = fx_info[1]
            local fx_enabled = fx_info[2]
            local fx_preset = fx_info[3]
            local fx_source = fx_info[4] or 0

            if fx_name and fx_name ~= "" then
                Safe_Add_FX(track_to_use, fx_name, fx_preset, fx_source)
                local added_idx = reaper.TrackFX_GetByName(track_to_use, fx_name, false)
                if added_idx >= 0 then
                    reaper.TrackFX_SetEnabled(track_to_use, added_idx, fx_enabled)
                end
            end
            plug_order = plug_order - 1
        end
    end




    -- === DYNAMIC TRACK RENAMING ===
    local display_name = tr[1]
    if display_name:find("<TYPE SELECT>") then
        display_name = display_name:gsub("<TYPE SELECT>", G_render_mode == 0 and "Relative" or "Absolute")
        reaper.GetSetMediaTrackInfo_String(track_to_use, "P_NAME", display_name, true)
    end
    -- =======================================

    -- APPLIED TO BOTH NEW AND EXISTING TRACKS:
    local track_color = reaper.ColorToNative(tr[8][1], tr[8][2], tr[8][3]) | 0x10000000

    -- APPLIED TO BOTH NEW AND EXISTING TRACKS:
    local track_color = reaper.ColorToNative(tr[8][1], tr[8][2], tr[8][3]) | 0x10000000
    reaper.SetTrackColor(track_to_use, track_color)

    -- ONLY reset volume if the track is brand new!
    if is_new then
        reaper.SetTrackUIVolume(track_to_use, tr[9], false, true, 0)
    end

    -- TCP / MCP Visibility Control
    local show_tcp = (tr[2] ~= false) and 1 or 0
    local show_mcp = (tr[3] ~= false) and 1 or 0

    reaper.SetMediaTrackInfo_Value(track_to_use, "B_SHOWINTCP", show_tcp)
    reaper.SetMediaTrackInfo_Value(track_to_use, "B_SHOWINMIXER", show_mcp)



    if not G_RENDER_TARGETS[tr_type] then
        G_RENDER_TARGETS[tr_type] = {}
    end
    table.insert(G_RENDER_TARGETS[tr_type], track_to_use)

  tr.track_ptr = track_to_use

  if Track_Needs_Cue_Child(tr) then
    tr.cue_track_ptr = Ensure_Cue_Child_Track(track_to_use, tr, unique_id)
  end

  return is_new
end

function Organize_Tracks_And_Routing(dynamic_table)
    local fx_indices = {}

    for i, tr in ipairs(dynamic_table) do
        if tr.type_id == 30 then
            table.insert(fx_indices, i)
        end
        if tr.track_ptr then
            reaper.SetMediaTrackInfo_Value(tr.track_ptr, "I_FOLDERDEPTH", 0)
        end
        if tr.cue_track_ptr and reaper.ValidatePtr(tr.cue_track_ptr, "MediaTrack*") then
            reaper.SetMediaTrackInfo_Value(tr.cue_track_ptr, "I_FOLDERDEPTH", 0)
        end
    end

    -- Find the highest-positioned N2N parent track to use as our top anchor
    local start_idx = reaper.CountTracks(0)
    local has_any_tracks = false
    for _, tr in ipairs(dynamic_table) do
        if tr.track_ptr then
            local idx = reaper.CSurf_TrackToID(tr.track_ptr, false) - 1
            if idx < start_idx then
                start_idx = idx
                has_any_tracks = true
            end
        end
    end
    if not has_any_tracks then
        start_idx = 0
    end

    local insert_pos = start_idx

    local function SendExists(src_track, dest_track)
        local num_sends = reaper.GetTrackNumSends(src_track, 0)
        for s = 0, num_sends - 1 do
            local dest = reaper.GetTrackSendInfo_Value(src_track, 0, s, "P_DESTTRACK")
            if dest == dest_track then
                return true
            end
        end
        return false
    end

    for i, tr in ipairs(dynamic_table) do
        local track = tr.track_ptr
        if not track then
            goto continue
        end

        local cue_track = tr.cue_track_ptr

        -- Move parent track first
        reaper.SetOnlyTrackSelected(track)
        reaper.ReorderSelectedTracks(insert_pos, 0)

        if cue_track and reaper.ValidatePtr(cue_track, "MediaTrack*") then
            -- Parent becomes folder start
            reaper.SetMediaTrackInfo_Value(track, "I_FOLDERDEPTH", 1)
            reaper.SetMediaTrackInfo_Value(track, "I_FOLDERCOMPACT", 0)

            -- Move cue track directly under parent
            reaper.SetOnlyTrackSelected(cue_track)
            reaper.ReorderSelectedTracks(insert_pos + 1, 0)

            -- Cue track closes folder, so it is the last item in the folder
            reaper.SetMediaTrackInfo_Value(cue_track, "I_FOLDERDEPTH", -1)
            reaper.SetMediaTrackInfo_Value(cue_track, "I_FOLDERCOMPACT", 0)

            insert_pos = insert_pos + 2
        else
            reaper.SetMediaTrackInfo_Value(track, "I_FOLDERDEPTH", 0)
            reaper.SetMediaTrackInfo_Value(track, "I_FOLDERCOMPACT", 0)
            insert_pos = insert_pos + 1
        end

        local is_instrument =
            (tr.type_id == 16 and tr.mode_id > 0) or
            (tr.type_id == 17 and tr.mode_id > 0) or
            (tr.type_id == 20 and tr.mode_id > 0) or
            (tr.type_id == 31)

        if is_instrument then
            for _, fx_idx in ipairs(fx_indices) do
                local fx_track = dynamic_table[fx_idx].track_ptr
                if fx_track and not SendExists(track, fx_track) then
                    local new_send = reaper.CreateTrackSend(track, fx_track)
                    reaper.SetTrackSendInfo_Value(track, 0, new_send, "D_VOL", 10 ^ (-12.0 / 20))
                end
            end
        end

        for _, target_idx in ipairs(tr[6] or {}) do
            local target_track = dynamic_table[target_idx] and dynamic_table[target_idx].track_ptr
            if target_track and not SendExists(track, target_track) then
                reaper.CreateTrackSend(track, target_track)
            end
        end

        ::continue::
    end

    reaper.TrackList_AdjustWindows(false)
    reaper.UpdateArrange()

    -- Apply spacers only to parent tracks after ordering
    for i, tr in ipairs(dynamic_table) do
        local track = tr.track_ptr
        if track then
            if tr.Tr_divider_before then
                reaper.SetMediaTrackInfo_Value(track, "I_SPACER", 1)
            else
                reaper.SetMediaTrackInfo_Value(track, "I_SPACER", 0)
            end
        end
    end

    reaper.TrackList_AdjustWindows(false)
    reaper.UpdateArrange()
end

-------------------------------------------------------------------- OLD SETUP TRACKS ENDS HERE

function Sync_Chart_Colors()
    -- Colors are now synced instantly via track pointers in place_MIDI_data.
    -- This function is safely retired!
end




function Normalize_Form_Line(header_text)
    local lines = {}
    
    -- Split the header line by line safely
    for line in header_text:gmatch("[^\r\n]+") do
        if line:match("^Form:") then
            local prefix, form_string = line:match("^(Form:%s*)(.*)$")
            if form_string then
                -- 1. First, convert any {Custom Words} into "Custom Words"
                form_string = form_string:gsub("%{(.-)%}", '"%1"')

                -- 2. Read the line left-to-right, respecting quotes
                local tokens = {}
                local in_quotes = false
                local current_token = ""

                for i = 1, #form_string do
                    local char = form_string:sub(i, i)
                    if char == '"' then
                        in_quotes = not in_quotes
                        current_token = current_token .. char
                    elseif char:match("%s") and not in_quotes then
                        if current_token ~= "" then
                            table.insert(tokens, current_token)
                            current_token = ""
                        end
                    else
                        current_token = current_token .. char
                    end
                end
                if current_token ~= "" then table.insert(tokens, current_token) end

                -- 3. Check each word. If it's not a standard single letter, quote it.
                local standard = { I=true, V=true, C=true, B=true, O=true, P=true, M=true, S=true, R=true, F=true, D=true, ["#"]=true }
                
                for j, token in ipairs(tokens) do
                    -- If it doesn't start and end with a quote, and isn't a standard letter
                    if not token:match('^".*"$') and not standard[token] then
                        tokens[j] = '"' .. token .. '"'
                    end
                end

                line = prefix .. table.concat(tokens, " ")
                
                -- UNCOMMENT THIS LINE if you want to see the invisible translation in the console!
                -- reaper.ShowConsoleMsg("DEBUG FORM TRANSLATOR:\nOriginal User Input: " .. form_string .. "\nSent to form.lua: " .. table.concat(tokens, " ") .. "\n\n")
            end
        end
        table.insert(lines, line)
    end
    
    return table.concat(lines, "\n")
end



function inital_swaps(chunky1)
    databoy = string.gsub(chunky1, "%^%^", "~")
    --[[
  databoy = string.gsub(databoy, " r ", " - ")
  databoy = string.gsub(databoy, " R ", " - ")
  databoy = string.gsub(databoy, " r" .. string.char(10), " -" .. string.char(10))
  databoy = string.gsub(databoy, " R" .. string.char(10), " -" .. string.char(10))
  databoy = string.gsub(databoy, string.char(10) .. "r ", string.char(10) .. "- ")
  databoy = string.gsub(databoy, string.char(10) .. "R ", string.char(10) .. "r ")
  databoy = string.gsub(databoy, string.char(10) .. "r" .. string.char(10), string.char(10) .. "-" .. string.char(10))
  databoy = string.gsub(databoy, string.char(10) .. "R" .. string.char(10), string.char(10) .. "-" .. string.char(10))
  databoy = string.gsub(databoy, "(r ", "(- ")
  databoy = string.gsub(databoy, "(R ", "(- ")
  databoy = string.gsub(databoy, "(r)", "(-)")
  databoy = string.gsub(databoy, "(R)", "(-)")
  databoy = string.gsub(databoy, " r)", " -)")
  databoy = string.gsub(databoy, " R)", " -)")
  --Show_To_Dev(databoy)
]]
    return databoy
end

-- ____________________________________________  SET THE KEY  ____________________

function Autosave()
    _, quit_title_startso = string.find(header_area, "Title: ") -- GET THE PROJECT SETTINGS AND PLACE IN THE SHELL
    quit_title_endso, _ = string.find(header_area, "Writer:")

    quittitlefound = string.sub(header_area, quit_title_startso + 1, quit_title_endso - 2)
    thetime = os.date("%Y-%m-%d %H-%M-%S")
    if string.len(quittitlefound) < 30 and quittitlefound ~= nil then
        filenamewillbe = quittitlefound .. " " .. thetime .. ".txt"
    else
        filenamewillbe = "N2Nautobackup " .. thetime .. ".txt"
    end

    local info = debug.getinfo(1, "S")
    local path = info.source:match [[^@?(.*[\/])[^\/]-$]]
    local chordchart_path = path .. "ChordCharts/"
    --retval, fileName =
    --  reaper.JS_Dialog_BrowseForSaveFile(
    --  "Save Chord Chart as...",
    --  chordchart_path,
    --  filenamewillbe,
    --  ".txt"
    --)

    write_path = io.open(chordchart_path .. filenamewillbe, "w")
    write_path:write(
        "<Numbers2NotesProject>\n<header_area>\n" ..
            header_area ..
                "\n</header_area>\n<chord_charting_area>\n" ..
                    chord_charting_area ..
                        "\n</chord_charting_area>\n<lyrics_charting_area>\n" ..
                            lyrics_charting_area ..
                                "\n</lyrics_charting_area>\n<notes_charting_area>\n" ..
                                    notes_charting_area .. "\n</notes_charting_area>\n</Numbers2NotesProject>"
    )
    write_path:close()
end

function SaveLastNumbers2NotesChart()
    local info = debug.getinfo(1, "S")
    local path = info.source:match [[^@?(.*[\/])[^\/]-$]]
    local chordchart_path = path .. "ChordCharts/"

    -- Define the fixed filename for the last Numbers2Notes chart
    local filenamewillbe = "Last_Numbers2Notes_Chart.txt"

    -- SERIALIZE GROOVE DATA
    local groove_str = ""
    for i = 1, 32 do
        groove_str = groove_str .. tostring(groove_data[i]) .. ","
    end

    -- Open the file in write mode, which will overwrite if the file already exists
    write_path = io.open(chordchart_path .. filenamewillbe, "w")

    -- Write the current project state to the file
    write_path:write(
        "<Numbers2NotesProject>\n<header_area>\n" ..
            header_area ..
                "\n</header_area>\n<chord_charting_area>\n" ..
                    chord_charting_area ..
                        "\n</chord_charting_area>\n<lyrics_charting_area>\n" ..
                            lyrics_charting_area ..
                                "\n</lyrics_charting_area>\n<notes_charting_area>\n" ..
                                    notes_charting_area ..
                                        "\n</notes_charting_area>\n<groove_data>\n" ..
                                            groove_str .. "\n</groove_data>\n</Numbers2NotesProject>"
    )

    -- Close the file
    write_path:close()
end

function set_the_key(stk_progression)
    starting_key = ""
    _, key_endchar = string.find(stk_progression, "Key:")
    if key_endchar == nil then
        --Show_To_Dev("Key not set. Rendered in the Key of C" .. string.char(10))
        starting_key = "C"
    else
        return_char_location, _ =
            string.find((string.sub(stk_progression, key_endchar + 1, string.len(stk_progression))), string.char(10))
        --Show_To_Dev("return location: " .. return_char_location .. string.char(10))
        if return_char_location == nil then
            --Show_To_Dev("Odd situation where Key was not on it's own line. Rendered in C." .. string.char(10))
            starting_key = "C"
        else
            key_line = string.sub(stk_progression, key_endchar + 1, key_endchar + return_char_location - 1)
            --Show_To_Dev("keyline = '" .. key_line .. "'" .. string.char(10))
            for i = 1, string.len(key_line), 1 do
                if string.sub(key_line, i, i) == " " then
                    --Show_To_Dev("keyline character = space" .. string.char(10))
                else
                    --Show_To_Dev("keyline character = '" .. string.sub(key_line, i, i) ..  "'" .. string.char(10))
                    starting_key = starting_key .. string.sub(key_line, i, i)
                end
            end
            if musictheory.key_table[starting_key] == nil then
                --Show_To_Dev("Key '" .. starting_key .. "' not found - Rendered in the Key of C" .. string.char(10))
                starting_key = "C"
            else
                --Show_To_Dev("Key set to " .. starting_key .. string.char(10))
            end
        end
    end
    return starting_key
end

-- ____________________________________________  SET THE BPM  ____________________

function set_the_bpm(stk_progression)
    project_bpm, project_bpi = reaper.GetProjectTimeSignature2(0)
    stk_progression = stk_progression .. string.char(10)

    starting_bpm = ""
    _, key_endchar = string.find(stk_progression, "BPM:")
    if key_endchar == nil then
        --Show_To_Dev("BMP not set." .. string.char(10))
        starting_bpm = project_bpm
    else
        return_char_location, _ =
            string.find((string.sub(stk_progression, key_endchar + 1, string.len(stk_progression))), string.char(10))
        --Show_To_Dev("return location: " .. return_char_location .. string.char(10))
        if return_char_location == nil then
            --Show_To_Dev("Odd situation where BPM was not on it's own line. Rendered in C." .. string.char(10))
            starting_bpm = project_bpm
        else
            BPM_line = string.sub(stk_progression, key_endchar + 1, key_endchar + return_char_location - 1)
            --Show_To_Dev("BPM_line = '" .. BPM_line .. "'" .. string.char(10))
            for i = 1, string.len(BPM_line), 1 do
                if string.sub(BPM_line, i, i) == " " then
                    --Show_To_Dev("BPM_line character = space" .. string.char(10))
                else
                    --Show_To_Dev("BPM_line character = '" .. string.sub(BPM_line, i, i) ..  "'" .. string.char(10))
                    starting_bpm = starting_bpm .. string.sub(BPM_line, i, i)
                end
            end
            number_from_string = tonumber(string.match(starting_bpm, "%d+"))
            if number_from_string == nil then
                --Show_To_Dev("BPM '" .. starting_bpm .. "' not found - Project tempo left unchanged" .. string.char(10))
                starting_bpm = project_bpm
            else
                if number_from_string < 2 or number_from_string > 960 then
                    render_feedback =
                        render_feedback ..
                        "BPM '" ..
                            number_from_string ..
                                "' out of range (Minimum = 2 and Maximum = 960) \nProject tempo left unchanged.\n_____________" ..
                                    string.char(10)
                    starting_bpm = project_bpm
                else
                    starting_bpm = number_from_string
                    reaper.SetCurrentBPM(0, number_from_string, true)
                    --Show_To_Dev("Tempo set to " .. starting_bpm .. string.char(10))
                    render_feedback = render_feedback .. "BPM set to " .. number_from_string .. string.char(10)
                end
            end
        end
    end
    --reaper.ShowConsoleMsg("=======BPM=======" .. starting_bpm .. "=======BPM=======")
    return starting_bpm
end

-- ____________________________________________  SET THE SWING  ____________________

function set_the_swing(stk_progression)
    project_swing = 0
    stk_progression = stk_progression .. string.char(10)

    starting_swing = ""
    _, key_endchar = string.find(stk_progression, "Swing")
    if key_endchar == nil then
        --Show_To_Dev("Swing not set." .. string.char(10))
        starting_swing = project_swing
    else
        return_char_location, _ =
            string.find((string.sub(stk_progression, key_endchar + 1, string.len(stk_progression))), string.char(10))
        --Show_To_Dev("return location: " .. return_char_location .. string.char(10))
        if return_char_location == nil then
            --Show_To_Dev("Odd situation where Swing was not on it's own line. Rendered in C." .. string.char(10))
            the_swing = 0
        else
            swing_line = string.sub(stk_progression, key_endchar + 1, key_endchar + return_char_location - 1)
            --Show_To_Dev("swing_line = '" .. swing_line .. "'" .. string.char(10))
            for i = 1, string.len(swing_line), 1 do
                if string.sub(swing_line, i, i) == " " then
                    --Show_To_Dev("swing_line character = space" .. string.char(10))
                else
                    --Show_To_Dev("swing_line character = '" .. string.sub(swing_line, i, i) ..  "'" .. string.char(10))
                    starting_swing = starting_swing .. string.sub(swing_line, i, i)
                end
            end
            number_from_string = tonumber(string.match(starting_swing, "%d+"))
            if number_from_string == nil then
                --Show_To_Dev("Swing '" .. starting_swing .. "' not found - Project tempo left unchanged" .. string.char(10))
                starting_swing = project_swing
            else
                if number_from_string < 0 or number_from_string > 100 then
                    render_feedback =
                        render_feedback ..
                        "Swing '" ..
                            number_from_string ..
                                "' out of range (Minimum = 0 and Maximum = 100) \nSwing set to 0.\n_____________" ..
                                    string.char(10)
                    starting_swing = project_swing
                else
                    starting_swing = number_from_string
                    reaper.gmem_write(2, starting_swing)

                    render_feedback = render_feedback .. "Swing set to " .. number_from_string .. string.char(10)
                end
            end
        end
    end
    --reaper.ShowConsoleMsg("=======BPM=======" .. starting_bpm .. "=======BPM=======")
    return starting_swing
end

-- ______________________________________________ORGANIZE INPUTS INTO BARS

function orgainize_input_into_bars(oiib_error_log) -- PLACE ALL THE USER INPUT INTO AN ORGANIZED TABLE
    local oiib_split = 0
    local oiib_measurecount = 0
    local oiib_inmeasure = false
    local oiib_last_char_is_space = true
    local oiib_measuremultiple = 1
    j = 1
    ::testchar::
    for i = j, string.len(progression), 1 do -- PROCESS EACH CHARACTER OF USER INPUT
    

         
         if string.sub(progression, i, i) == "{" then
             -- Support both {$ $} from the form expander, and normal { }
             local is_dollar = (string.sub(progression, i + 1, i + 1) == "$")
             local end_char = is_dollar and "$}" or "}"
             
             -- 'true' disables Lua's regex, making the search completely safe
             section_close_start, section_close_end = string.find(progression, end_char, i + 1, true)
             
             if section_close_end then
                 section_name = string.sub(progression, i, section_close_end)
                 oiib_measurecount = oiib_measurecount + 1
                 oiib_measure_ticks = 0
                 measuremultiplelist[oiib_measurecount] = oiib_measure_ticks
                 table.insert(chord_table, oiib_measurecount, {0, 1, 0, section_name})
                 table.insert(chord_table, oiib_measurecount, {0, 1, 0, section_name})
                 j = section_close_end + 1
                 goto testchar
             end
         elseif
             string.byte(progression, i) == 32 or string.byte(progression, i) == 10 or string.byte(progression, i) == 13 or
                 string.byte(progression, i) == 9
          then --  WHEN CHARACTER IS A SPACER (SPACE, TAB, RETURN)
          
          
          
          
          
          
            if oiib_inmeasure == false then -- WHEN NOT WORKING WITH A SPLIT MEASURE
                if oiib_last_char_is_space == false then -- WHEN NOT AFTER A SPACE
                    oiib_last_char_is_space = true
                    oiib_measurecount = oiib_measurecount + 1
                    oiib_measure_ticks = oiib_measuremultiple * G_time_signature_top * G_ticks_per_measure
                    measuremultiplelist[oiib_measurecount] = oiib_measure_ticks
                    if splitbar == false then
                        table.insert(
                            chord_table,
                            oiib_measurecount,
                            {0, oiib_measuremultiple, oiib_measure_ticks, measure}
                        )
                    else
                        table.insert(
                            chord_table,
                            oiib_measurecount,
                            {1, oiib_measuremultiple, oiib_measure_ticks, measure}
                        )
                    end
                    splitbar = false
                    measure = ""
                    oiib_measuremultiple = 1
                else
                    oiib_last_char_is_space = true -- WHEN AFTER A SPACE
                end
            else -- WHEN WORKING WITH A SPLIT MEASSURE
                if oiib_last_char_is_space == false then -- NOT AFTER A SPACE
                    oiib_last_char_is_space = true
                    measure = measure .. " "
                else -- AFTER A SPACE
                end
            end
        elseif string.byte(progression, i) == 91 then -- CHARACTER IS OPEN BRACKET
            splitbar = true
            if oiib_inmeasure == true then
                oiib_error_log = oiib_error_log .. '\n\nMissing "]" - Not all "split" bars were closed.'
            end
            if oiib_last_char_is_space == true then -- AND LAST CHARACTER WAS A SPACE (NOT A MULTIBAR)
                oiib_inmeasure = true
            else
                oiib_inmeasure = true -- AND LAST CHARACTER WAS A NOT A SPACE (IS A MULTIBAR)
                oiib_measuremultiple = measure
                measure = ""
                oiib_last_char_is_space = true
            end
        elseif string.byte(progression, i) == 93 then -- CHARACTER IS CLOSED BRACKET
            oiib_inmeasure = false -- NOT IN A SPLIT MEASURE
            oiib_last_char_is_space = false
        else -- IN A SPLIT MEASURE
            oiib_last_char_is_space = false
            measure = measure .. string.sub(progression, i, i)
        end
    end
    if oiib_inmeasure == true then
        oiib_error_log = oiib_error_log .. '\n\nMissing "]" - The final bar was not closed.'
    end

    finalcount = 0
    for i, value in pairs(chord_table) do
        finalcount = finalcount + 1
    end

    for i = 1, finalcount, 1 do
        if chord_table[i][4] == "%" then --  PROCESS BAR REPEATS
            ----Show_To_Dev(chord_table[i][4]  .. " yes | " .. string.char(10))
            chord_table[i] = chord_table[i - 1]
        else
            ----Show_To_Dev(chord_table[i][4]  .. " no | " .. string.char(10))
        end
    end

    chord_splitsection_count = oiib_measurecount
    for i, v in pairs(chord_table) do
        --Show_To_Dev("YO!... " .. tostring(v[1])  .. " | " .. tostring(v[2])  .. " | " .. tostring(v[3]) .. " | " .. tostring(v[4]) .. " | " .. string.char(10))
    end
    return oiib_split, oiib_error_log
end

-- _______________________________________________________________________  PROCESS EACH CHARACTER OF USER INPUT  ____________________
function process_data_chunks(
    pdc_chord_table,
    pdc_chord_splitsection_count,
    pdc_current_chunk_data,
    pdc_split,
    pdc_error_log)
    local pdc_section_in_progress = false
    local pdc_chord_in_progress = false
    local pdc_parenthetical_depth = 0
    local pdc_multiple = 1
    for i = 1, string.len(pdc_current_chunk_data), 1 do -- PROCESS EACH CHARACTER OF USER INPUT
        if
            string.byte(pdc_current_chunk_data, i) == 32 or string.byte(pdc_current_chunk_data, i) == 9 or
                string.byte(pdc_current_chunk_data, i) == 10 or
                string.byte(pdc_current_chunk_data, i) == 13
         then
            --  IS THE CHARACTER IS A SPACER (SPACE, TAB, RETURN)               SPACE
            if pdc_section_in_progress == true then --  AND IN THE MIDST OF PROCESSING A SPLIT SECTION
                pdc_current_chord = pdc_current_chord .. " " --  CONVERT TO SPACE
            elseif pdc_chord_in_progress == true then --  IF IT ISN'T A SPLIT SECTION, BUT OCCURS AFTER THE PROGRESS OF WORKING WITH A SINGLE CHORD
                pdc_chord_splitsection_count = pdc_chord_splitsection_count + 1 --  THEN THERE A NEW CHORD HAS BEEN PROCESSED ADD IT TO THE COUNT
                pdc_split = pdc_split + pdc_multiple --  CALCULATE HOW MANY PORTIONS THE TIME HAS BEEN SPLIT INTO BY ADDING THE NEW CHORD'S PORTION
                table.insert(pdc_chord_table, pdc_chord_splitsection_count, {0, pdc_multiple, 1, pdc_current_chord})
                --  INSERT THE NEW CHORD INTO THE TABLE OF CHORDS
                --  {0 = NOT A SPLIT, MULTIPLE = 1 BECAUSE IT IS NOT SPLIT, 1 IS A PLACE HOLDER, THE CHORD)
                pdc_current_chord = "" --  CLEAR THE CURRENT CHORD VARIABLE SO IT'S READY FOR THE NEXT CHORD
                pdc_chord_in_progress = false --  STARTING FRESH IN THE SEARCH FOR THE NEXT CHORD = THERE IS NO CURRENT CHORD STARTED
                pdc_multiple = 1 --  THE MULTIPLE IS RESET TO 1 WHICH IS THE DEFAULT
            elseif pdc_chord_in_progress == false then --  IF THERE IS NO CHORD OR SECTION IN PROGRESS THEN THE SPACER IS NOT NEEDED
            else
                pdc_error_log = pdc_error_log .. "error 1 - Something wrong with input or program." .. string.char(10) --  IF NONE OF THESE IS THE CASE THERE MUST BE AN ERROR IN THE CODE OR THE USER ENTRY
            end
        elseif string.byte(pdc_current_chunk_data, i) == 40 then --  WHEN CHARACTER IS AN OPEN PARENTHESIS                           (
            pdc_parenthetical_depth = pdc_parenthetical_depth + 1 --  EACH "(" THAT SHOWS UP TAKES US A LEVEL DEEPER IN THE SPLITTING OF THE BAR AND BEATS
            --  THIS COUNT IS NEEDED TO MAKE SURE THAT THE USER CLOSES ALL OPEN PARANTHESIS WITH CLOSES
            if pdc_section_in_progress == true then --  IF A SECTION IS ALREADY IN PROGRESS IT IS SIMPLY STORED TO DEAL WITH LATER
                pdc_current_chord = pdc_current_chord .. "("
            elseif pdc_chord_in_progress == false then --  IF THERE IS NO SPLIT SECTION OR CHORD IN PROGRESS THE "(" WOULD SIGNIFY THE START OF A NEW SPLIT SECTION
                pdc_chord_in_progress = false
                pdc_section_in_progress = true
                pdc_current_chord = ""
            else --  THIS WOULD ONLY OCCUR WHEN THERE IS A MULTIPLE BEFORE THE START OF A SECTION
                pdc_section_in_progress = true
                pdc_chord_in_progress = false
                pdc_multiple = pdc_current_chord --  SO STORE THE MULTIPLE AND CLEAR THE CURRENT CHORD VARIABLE TO GET READY TO START STORING A NEW SECTION
                pdc_current_chord = ""
            end
        elseif string.byte(pdc_current_chunk_data, i) == 41 then --  WHEN CHARACTER IS AN OPEN PARENTHESIS                           )
            pdc_parenthetical_depth = pdc_parenthetical_depth - 1 --  pdc_parenthetical_depth IS REDUCED TO SHOW ONE SPLIT HAS BEEN CLOSED
            if pdc_parenthetical_depth < 0 then --  SINCE THERE SHOULD NEVER BE A CLOSE WITHOUT A CORRESPONDING OPENING HAVING HAPPENED FIRST,
                --  A NEGATIVE INDICATES AN ERROR IN THE USER INPUT
                pdc_error_log = pdc_error_log .. string.char(10) .. "Missing close parenthesis" .. string.char(10)
            elseif pdc_parenthetical_depth == 0 and pdc_section_in_progress == true then
                --  A pdc_parenthetical_depth OF 0 INDICATES THAT THE INTERNAL AND OVERALL SPLIT SECTIONS HAVE BEEN CLOSED
                pdc_chord_splitsection_count = pdc_chord_splitsection_count + 1 --  SPLIT COMPLETED AND ADDED TO THE COUNT
                pdc_split = pdc_split + pdc_multiple --  TRACKING OF HOW MANY SPLITS HAVE OCCURED IS INCREMENTED BY THE NEW SPLIT'S MULTIPLE
                table.insert(pdc_chord_table, pdc_chord_splitsection_count, {1, pdc_multiple, 1, pdc_current_chord})
                --  ADD THE SPLIT TO THE CHORD TABLE
                pdc_current_chord = "" --  CLEAR THE CURRENT CHORD VARIABLE TO PREP FOR THE NEXT CHORD SEARCH
                pdc_chord_in_progress = false --  STARTING FRESH SO NEITHER A CHORD OR SPLIT IS IN PROGRESS
                pdc_section_in_progress = false
                pdc_multiple = 1 --  MULTIPLE IS RESET TO DEFAULT VALUE OF 1
            elseif pdc_parenthetical_depth > 0 and pdc_section_in_progress == true then --  IF THE SECTION WAS ALREADY IN PROGRESS A POSITIVE VALUE WOULD INDICATED BEING IN THE MIDST OF A
                --  AN ONGOING SPLIT AND THAT THE CLOSE IS INTERNAL AND SIMPLY NEEDS TO BE ADDED TO THE SPLIT IN PROGRESS
                pdc_current_chord = pdc_current_chord .. ")"
            else
                pdc_error_log = pdc_error_log .. "error 2 - Something wrong with input or program." .. string.char(10) --  ANY OTHER OUTCOME INDICATES SOMETHING IS WRONG WITH EITHER THE PROGRAMMING OR THE USER INPUT
            end
        else --  WHEN THE CHARACTER IS ANYTHING ELSE                      FOR EXAMPLE  m, 4, 7, j
            if pdc_section_in_progress == true then --  WHEN IN THE MIDST OF A SPLIT SECTION JUST CONTINUE BY ADDING THE CURRENT CHAR TO THE SPLIT SECTION
                pdc_current_chord = pdc_current_chord .. string.sub(pdc_current_chunk_data, i, i)
            elseif pdc_chord_in_progress == true then --  WHEN IN THE MIDST OF A CHORD JUST CONTINUE BY ADDING THE CURRENT CHAR THE CHORD
                pdc_current_chord = pdc_current_chord .. string.sub(pdc_current_chunk_data, i, i)
            else
                pdc_chord_in_progress = true --  OTHERISE A NEW CHORD OR SPLIT STARTING WITH A MULTIPLE HAS BEGUN - IF IT IS A MULTIPL IT WILL BE DETERMINED LATER
                pdc_current_chord = string.sub(pdc_current_chunk_data, i, i)
                --  CURRENT CHORD = THE CURRENT CHARACTER
                pdc_multiple = 1 --  MULTIPLE SET TO DEFAULT OF 1 WHICH WILL BE CHANGED LATER IN THE CASE OF A MULTIPLE AND SPLIT
            end
        end
    end
    return pdc_chord_table, pdc_chord_splitsection_count, pdc_split, pdc_error_log
end

-- _______________________________________________________________________  DISPLAY THE CHORD TABLE IN THE CONSOLE  ____________________

function presentdata(p_split, p_error_log)
    datapeek = ""
    for i, value in pairs(chord_table) do
        datapeek = datapeek .. string.char(10) .. "i = " .. i .. " | " .. string.char(10)
        k = 0
        for k, v in pairs(value) do
            datapeek = datapeek .. " k = " .. k .. " / value = " .. v .. string.char(10)
        end
    end
    --Show_To_Dev(datapeek .. string.char(10))

    --THIS SPLIT IS WRONG !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
    --Show_To_Dev("Split = " .. p_split .. string.char(10))
    --Show_To_Dev("Error Record:" .. string.char(10) .. p_error_log .. string.char(10))
end

-- _______________________________________________________________________  ASSIGN EACH CHORD AND SPLIT SECTION IT'S PORTION OF TIME  ____________________

function asign_ticks_per_split_portion(at_chord_table, at_chord_splitsection_count, at_ticks_per, at_split)
    for i = 1, at_chord_splitsection_count, 1 do
        at_chord_table[i][3] = (at_chord_table[i][2]) * at_ticks_per / at_split --  BASE # OF TICKS * THE CHORD/SPLIT SECTION's MULTIPL
    end
    return at_chord_table
end

-- _______________________________________________________________________ PROCESS NESTED SPLITS  ____________________

function process_nested_split_sections(pnss_split, pnss_error_log)
    temp_chord_table = chord_table -- MAKE A COPY OF THE CHORD TABLE AND IT'S COUNT
    temp_chord_splitsection_count = chord_splitsection_count
    pnss_updated_chord_split_section_count = 0 -- CREATE NEW TABLES AND COUNTS FOR HOLDING DATA AS IT CHANGES
    pnss_updated_chord_table = {}
    pnss_still_more_nested = false

    for i = 1, temp_chord_splitsection_count, 1 do -- PROCESS THE DATA
        if temp_chord_table[i][1] == 0 then -- IF IT HAS NO SPLIT (0) THEN JUST COPY OVER
            pnss_updated_chord_split_section_count = pnss_updated_chord_split_section_count + 1
            table.insert(pnss_updated_chord_table, pnss_updated_chord_split_section_count, temp_chord_table[i])
        elseif temp_chord_table[i][1] == 1 then -- IF IT HAS A SPLIT (1) THEN
            pnss_still_more_nested = true
            chord_table = {}
            chord_splitsection_count = 0
            pnss_current_chunk_data = temp_chord_table[i][4] .. " "
            pnss_current_chunk_data = pnss_current_chunk_data .. " "
            pnss_split = 0
            --   ______________________________________________________________________     PROCESS DATA CHUNKS FUNCTION TRIGGERED HERE!!!
            chord_table, chord_splitsection_count, pnss_split, pnss_error_log =
                process_data_chunks(
                chord_table,
                chord_splitsection_count,
                pnss_current_chunk_data,
                pnss_split,
                pnss_error_log
            )

            pnss_ticks_per_section = temp_chord_table[i][3]
            --   ______________________________________________________________________        ASSIGN TICKS FUNCTION TRIGGERED HERE!!!
            chord_table =
                asign_ticks_per_split_portion(chord_table, chord_splitsection_count, pnss_ticks_per_section, pnss_split)
            for i = 1, chord_splitsection_count, 1 do
                pnss_updated_chord_split_section_count = pnss_updated_chord_split_section_count + 1
                table.insert(pnss_updated_chord_table, pnss_updated_chord_split_section_count, chord_table[i])
            end
        end
    end

    chord_table = pnss_updated_chord_table
    chord_splitsection_count = pnss_updated_chord_split_section_count
    pnss_updated_chord_table = {}
    pnss_updated_chord_split_section_count = 0
    if pnss_still_more_nested == true then
        pnss_still_more_nested = false
        process_nested_split_sections()
    end
    return pnss_split, pnss_error_log
end

-- _______________________________________________________________________ PLACE TEXT ITEMS  /

function place_TEXT_data(dynamic_table)
    local ptd_updating_start_ppqpos = 0
    local ptd_note_end_ppqpos = 0
    local ptd_measure_start_point = 0
    local ptd_measure_end_point = 0
    local ptd_first_run_start_point = 0
    local ptd_last_end_point = 0
    local ptd_text_item_count = 0

    local tr_nns = G_RENDER_TARGETS[1] and G_RENDER_TARGETS[1][1]

    -- Setup text targets and their transposition shifts
    local text_targets = {}

    if G_RENDER_TARGETS[6] then
        table.insert(
            text_targets,
            {
                tr = G_RENDER_TARGETS[6][1],
                shift = musictheory.key_table[current_key] or 0,
                use_flats = musictheory.is_it_flat_table[current_key]
            }
        )
    end

    if G_RENDER_TARGETS[5] then
        table.insert(text_targets, {tr = G_RENDER_TARGETS[5][1], shift = 0, use_flats = false})
    end

    if G_RENDER_TARGETS[4] then
        -- Find out which key the user picked from the recipe!
        local u_shift, u_flats = 0, false
        for _, tr in ipairs(config.track_recipe) do
            if tr.type == 4 then
                local choice = tr.vst_choice or tr.vsti_choice
                if choice then
                    u_shift = choice.transpose or 0
                    u_flats = choice.flat or false
                end
                break
            end
        end
        table.insert(text_targets, {tr = G_RENDER_TARGETS[4][1], shift = u_shift, use_flats = u_flats})
    end

    for i, value in pairs(chord_table) do
        ptd_note_end_ppqpos = ptd_updating_start_ppqpos + value[3]

        if ptd_updating_start_ppqpos == 0 then
            ptd_measure_start_point = 0
        else
            ptd_measure_start_point = ptd_updating_start_ppqpos / G_ticks_per_measure
        end

        if i == 1 then
            ptd_first_run_start_point = ptd_measure_start_point
        end

        if ptd_note_end_ppqpos == 0 then
            ptd_measure_end_point = 0
        else
            ptd_measure_end_point = ptd_note_end_ppqpos / G_ticks_per_measure
        end

        local ptd_chord_entry_to_text = value[4]
        if ptd_chord_entry_to_text == "-" then
            ptd_chord_entry_to_text = "Rest"
        end

        -- 1. NNS Number Chart
        if tr_nns then
            local m_item = reaper.CreateNewMIDIItemInProj(tr_nns, ptd_measure_start_point, ptd_measure_end_point, true)
            local t_pos = reaper.GetMediaItemInfo_Value(m_item, "D_POSITION")
            local t_len = reaper.GetMediaItemInfo_Value(m_item, "D_LENGTH")
            local text_item = reaper.AddMediaItemToTrack(tr_nns)
            reaper.SetMediaItemInfo_Value(text_item, "D_POSITION", t_pos)
            reaper.SetMediaItemInfo_Value(text_item, "D_LENGTH", t_len)
            reaper.DeleteTrackMediaItem(tr_nns, m_item)
            reaper.ULT_SetMediaItemNote(text_item, ptd_chord_entry_to_text)
        end

        -- 2. Letter Charts (Loops through Active Types 4, 5, and 6)
        for _, tgt in ipairs(text_targets) do
            local m_item = reaper.CreateNewMIDIItemInProj(tgt.tr, ptd_measure_start_point, ptd_measure_end_point, true)
            local t_pos = reaper.GetMediaItemInfo_Value(m_item, "D_POSITION")
            local t_len = reaper.GetMediaItemInfo_Value(m_item, "D_LENGTH")
            local text_item = reaper.AddMediaItemToTrack(tgt.tr)
            reaper.SetMediaItemInfo_Value(text_item, "D_POSITION", t_pos)
            reaper.SetMediaItemInfo_Value(text_item, "D_LENGTH", t_len)
            reaper.DeleteTrackMediaItem(tgt.tr, m_item)

            local final_text = ptd_chord_entry_to_text
            if ptd_chord_entry_to_text ~= "Rest" and string.sub(ptd_chord_entry_to_text, 1, 1) ~= "{" then
                local numberRoot, chordtypy, notSharped, isFlatted
                if string.sub(ptd_chord_entry_to_text, 1, 1) == "#" then
                    numberRoot = string.sub(ptd_chord_entry_to_text, 1, 2)
                    chordtypy = string.sub(ptd_chord_entry_to_text, 3)
                    notSharped = false
                    isFlatted = false
                elseif string.sub(ptd_chord_entry_to_text, 1, 1) == "b" then
                    numberRoot = string.sub(ptd_chord_entry_to_text, 1, 2)
                    chordtypy = string.sub(ptd_chord_entry_to_text, 3)
                    notSharped = true
                    isFlatted = true
                else
                    numberRoot = string.sub(ptd_chord_entry_to_text, 1, 1)
                    chordtypy = string.sub(ptd_chord_entry_to_text, 2)
                    notSharped = true
                    isFlatted = false
                end

                if chordtypy == nil then
                    chordtypy = ""
                end

                local flatOrNot = tgt.use_flats
                local rootShiftedAmount = musictheory.root_table[numberRoot]
                local keyShiftedAmount = tgt.shift

                if rootShiftedAmount and keyShiftedAmount then
                    local finalshifty = rootShiftedAmount + keyShiftedAmount
                    if finalshifty > 11 then
                        finalshifty = finalshifty - 12
                    end
                    if finalshifty < 0 then
                        finalshifty = finalshifty + 12
                    end

                    if flatOrNot and notSharped then
                        final_text = musictheory.flats_table[finalshifty] .. chordtypy
                    elseif isFlatted then
                        final_text = musictheory.flats_table[finalshifty] .. chordtypy
                    else
                        final_text = musictheory.sharps_table[finalshifty] .. chordtypy
                    end
                end
            end
            reaper.ULT_SetMediaItemNote(text_item, final_text)
        end

        ptd_text_item_count = ptd_text_item_count + 1
        ptd_updating_start_ppqpos = ptd_note_end_ppqpos
        ptd_last_end_point = ptd_measure_end_point
    end
--[[
    if ptd_last_end_point <= ptd_first_run_start_point then
        ptd_last_end_point = ptd_first_run_start_point + 1
    end

    local tr_abs_grid = G_RENDER_TARGETS[7] and G_RENDER_TARGETS[7][1]
    local tr_rel_grid = G_RENDER_TARGETS[15] and G_RENDER_TARGETS[15][1]  ]]
--    local tr_chords = G_SOURCE_INDICES[16] and dynamic_table[G_SOURCE_INDICES[16]].track_ptr
--   local tr_chbass = G_SOURCE_INDICES[17] and dynamic_table[G_SOURCE_INDICES[17]].track_ptr
--  local tr_bass = G_SOURCE_INDICES[20] and dynamic_table[G_SOURCE_INDICES[20]].track_ptr
--[[
    local grid_midi =
        tr_abs_grid and reaper.CreateNewMIDIItemInProj(tr_abs_grid, ptd_first_run_start_point, ptd_last_end_point, true)
    local lead_midi =
        tr_rel_grid and reaper.CreateNewMIDIItemInProj(tr_rel_grid, ptd_first_run_start_point, ptd_last_end_point, true)
    local chords_midi =
        tr_chords and reaper.CreateNewMIDIItemInProj(tr_chords, ptd_first_run_start_point, ptd_last_end_point, true)
    local chbass_midi =
        tr_chbass and reaper.CreateNewMIDIItemInProj(tr_chbass, ptd_first_run_start_point, ptd_last_end_point, true)
    local bass_midi =
        tr_bass and reaper.CreateNewMIDIItemInProj(tr_bass, ptd_first_run_start_point, ptd_last_end_point, true)



    return ptd_text_item_count, lead_midi, chords_midi, bass_midi, chbass_midi, grid_midi
end
]]


if ptd_last_end_point <= ptd_first_run_start_point then
        ptd_last_end_point = ptd_first_run_start_point + 1
    end

    local tr_abs_grid = G_RENDER_TARGETS[7] and G_RENDER_TARGETS[7][1]
    local tr_rel_grid = G_RENDER_TARGETS[15] and G_RENDER_TARGETS[15][1]
    
    -- ONLY pull the track pointer for Type 17 (N2N Master MIDI Source)
    local tr_chbass = G_SOURCE_INDICES[17] and dynamic_table[G_SOURCE_INDICES[17]].track_ptr

    local grid_midi = tr_abs_grid and reaper.CreateNewMIDIItemInProj(tr_abs_grid, ptd_first_run_start_point, ptd_last_end_point, true)
    local lead_midi = tr_rel_grid and reaper.CreateNewMIDIItemInProj(tr_rel_grid, ptd_first_run_start_point, ptd_last_end_point, true)
    
    -- LEGACY PATHS MADE DORMANT
    local chords_midi = nil
    local bass_midi   = nil
    
    -- Create the single unified MIDI item
    local chbass_midi = tr_chbass and reaper.CreateNewMIDIItemInProj(tr_chbass, ptd_first_run_start_point, ptd_last_end_point, true)

    return ptd_text_item_count, lead_midi, chords_midi, bass_midi, chbass_midi, grid_midi
end


-- _______________________________________________________________________ PLACE MIDI

-- _______________________________________________________________________ PLACE MIDI

-- _______________________________________________________________________ PLACE MIDI

function place_MIDI_data(
    pmd_text_item_count,
    pmd_lead_id,
    pmd_chords_id,
    pmd_bass_id,
    pmd_chbass_id,
    pmd_grid_id,
    dynamic_table)
    local pmd_running_ppqpos_total = 0
    local pmd_note_end_ppqpos = 0
    local pmd_error_log = ""

    local lead_item_first_take = pmd_lead_id and reaper.GetMediaItemTake(pmd_lead_id, 0)
    local chord_item_first_take = pmd_chords_id and reaper.GetMediaItemTake(pmd_chords_id, 0)
    local bass_item_first_take = pmd_bass_id and reaper.GetMediaItemTake(pmd_bass_id, 0)
    local chbass_item_first_take = pmd_chbass_id and reaper.GetMediaItemTake(pmd_chbass_id, 0)
    local grid_item_first_take = pmd_grid_id and reaper.GetMediaItemTake(pmd_grid_id, 0)

    -- Safely grab the track if it exists
    local tr_nns = G_RENDER_TARGETS[1] and G_RENDER_TARGETS[1][1]

    for i, value in pairs(chord_table) do
        local pmd_root, rel_root, bass_note, rel_bass = "", 0, 0, 0
        local chord_type = ""

        -- Safely get the item to color ONLY if the track exists
        local pmd_item_to_color = nil
        if tr_nns then
            pmd_item_to_color = reaper.GetTrackMediaItem(tr_nns, i - 1)
        end

        -- ============================================================
        -- COMMAND PARSER
        -- ============================================================
        if string.sub(value[4], 1, 1) == "{" then
            local tag_content = value[4]
            local _, _, new_key_str = string.find(tag_content, "[Kk]ey:%s*([%a#b]+)")
            if new_key_str and musictheory.key_table[new_key_str] then
                current_key = new_key_str
                keyshift = musictheory.key_table[current_key]
                if grid_item_first_take then
                    reaper.AddProjectMarker(
                        0,
                        false,
                        reaper.MIDI_GetProjTimeFromPPQPos(grid_item_first_take, pmd_running_ppqpos_total),
                        0,
                        "Key: " .. current_key,
                        -1
                    )
                end
            end
            local _, _, new_bpm_str = string.find(tag_content, "BPM:%s*(%d+)")
            if new_bpm_str then
                local new_bpm = tonumber(new_bpm_str)
                if new_bpm and new_bpm > 0 and grid_item_first_take then
                    local t_pos = reaper.MIDI_GetProjTimeFromPPQPos(grid_item_first_take, pmd_running_ppqpos_total)
                    reaper.SetTempoTimeSigMarker(0, -1, t_pos, -1, -1, new_bpm, 0, 0, false)
                end
            end
            local _, _, new_sw_str = string.find(tag_content, "Swing:%s*(%d+)")
            if new_sw_str and grid_item_first_take then
                local sw_val = tonumber(new_sw_str)
                if sw_val then
                    if sw_val < 0 then
                        sw_val = 0
                    end
                    if sw_val > 100 then
                        sw_val = 100
                    end
                    local ins_pos = pmd_running_ppqpos_total
                    if ins_pos > 0 then
                        ins_pos = ins_pos - 1
                    end
                    reaper.MIDI_InsertCC(grid_item_first_take, false, false, ins_pos, 176, 0, 119, sw_val)
                end
            end
        end

        -- ============================================================
        -- PARSING & ERROR LOGIC
        -- ============================================================
        if string.sub(value[4], 1, 1) == "-" then
            pmd_note_end_ppqpos = pmd_running_ppqpos_total + value[3]
            pmd_running_ppqpos_total = pmd_note_end_ppqpos
            if pmd_item_to_color then
                reaper.SetMediaItemInfo_Value(
                    pmd_item_to_color,
                    "I_CUSTOMCOLOR",
                    reaper.ColorToNative(133, 133, 133) | 0x1000000
                )
            end
        elseif (string.sub(value[4], 1, 1) == "b" and musictheory.root_table[string.sub(value[4], 1, 2)] == nil) then
            pmd_note_end_ppqpos = pmd_running_ppqpos_total + value[3]
            pmd_running_ppqpos_total = pmd_note_end_ppqpos
            if pmd_item_to_color then
                reaper.SetMediaItemInfo_Value(
                    pmd_item_to_color,
                    "I_CUSTOMCOLOR",
                    reaper.ColorToNative(0, 0, 0) | 0x1000000
                )
                reaper.ULT_SetMediaItemNote(pmd_item_to_color, "!!! ENTRY ERROR !!!")
            end
            pmd_root = "-"
        elseif (string.sub(value[4], 1, 1) == "#" and musictheory.root_table[string.sub(value[4], 1, 2)] == nil) then
            pmd_note_end_ppqpos = pmd_running_ppqpos_total + value[3]
            pmd_running_ppqpos_total = pmd_note_end_ppqpos
            if pmd_item_to_color then
                reaper.SetMediaItemInfo_Value(
                    pmd_item_to_color,
                    "I_CUSTOMCOLOR",
                    reaper.ColorToNative(0, 0, 0) | 0x1000000
                )
                reaper.ULT_SetMediaItemNote(pmd_item_to_color, "!!! ENTRY ERROR !!!")
            end
            pmd_root = "-"
        elseif
            (musictheory.root_table[string.sub(value[4], 1, 1)] == nil and string.sub(value[4], 1, 1) ~= "{" and
                string.sub(value[4], 1, 1) ~= "b" and
                string.sub(value[4], 1, 1) ~= "#")
         then
            pmd_note_end_ppqpos = pmd_running_ppqpos_total + value[3]
            pmd_running_ppqpos_total = pmd_note_end_ppqpos
            if pmd_item_to_color then
                reaper.SetMediaItemInfo_Value(
                    pmd_item_to_color,
                    "I_CUSTOMCOLOR",
                    reaper.ColorToNative(0, 0, 0) | 0x1000000
                )
                reaper.ULT_SetMediaItemNote(pmd_item_to_color, "!!! ENTRY ERROR !!!")
            end
            pmd_root = "-"
        elseif
            (musictheory.root_table[string.sub(value[4], 1, 1)] == nil and string.sub(value[4], 1, 1) ~= "b" and
                string.sub(value[4], 1, 1) ~= "#")
         then
            -- MARKERS
            pmd_note_end_ppqpos = pmd_running_ppqpos_total + 0
            pmd_running_ppqpos_total = pmd_note_end_ppqpos
            local raw = tostring(value[4] or "")
            local marker_name = raw:match("{%$(.-)%$}") or raw:match("{(.-)}") or raw
            marker_name = marker_name:gsub("^%s*", ""):gsub("%s*$", ""):gsub("%$$", "")
            table.insert(G_region_table, {pmd_running_ppqpos_total, marker_name})

            -- Smart Forward-Crawl for Colors

            local color_root = nil
            for search_idx = i + 1, #chord_table do
                local future_val = chord_table[search_idx] and chord_table[search_idx][4]
                -- Stop searching as soon as we hit a non-marker item
                if future_val and not future_val:match("^{") then
                    if future_val == "-" then
                        color_root = "REST"
                    else
                        local first_char = string.sub(future_val, 1, 1)
                        if first_char == "b" or first_char == "#" then
                            color_root = string.sub(future_val, 1, 2)
                        else
                            color_root = first_char
                        end
                    end
                    break
                end
            end

            if pmd_item_to_color and color_root then
                if color_root == "REST" then
                    reaper.SetMediaItemInfo_Value(
                        pmd_item_to_color,
                        "I_CUSTOMCOLOR",
                        reaper.ColorToNative(133, 133, 133) | 0x1000000
                    )
                else
                    local color_table = musictheory.root_colors[color_root]
                    if color_table then
                        reaper.SetMediaItemInfo_Value(
                            pmd_item_to_color,
                            "I_CUSTOMCOLOR",
                            reaper.ColorToNative(color_table[1], color_table[2], color_table[3]) | 0x1000000
                        )
                    end
                end
            end
        else
            -- NORMAL CHORD PROCESSING
            if string.sub(value[4], 1, 1) == "b" or string.sub(value[4], 1, 1) == "#" then
                pmd_root = musictheory.root_table[string.sub(value[4], 1, 2)]
                chord_type = string.sub(value[4], 3, string.len(value[4]))
                if pmd_item_to_color then
                    local color_table = musictheory.root_colors[string.sub(value[4], 1, 2)]
                    reaper.SetMediaItemInfo_Value(
                        pmd_item_to_color,
                        "I_CUSTOMCOLOR",
                        reaper.ColorToNative(color_table[1], color_table[2], color_table[3]) | 0x1000000
                    )
                end
            else
                pmd_root = musictheory.root_table[string.sub(value[4], 1, 1)]
                chord_type = string.sub(value[4], 2, string.len(value[4]))
                if pmd_item_to_color then
                    local color_table = musictheory.root_colors[string.sub(value[4], 1, 1)]
                    reaper.SetMediaItemInfo_Value(
                        pmd_item_to_color,
                        "I_CUSTOMCOLOR",
                        reaper.ColorToNative(color_table[1], color_table[2], color_table[3]) | 0x1000000
                    )
                end
            end

            -----------------------------------------------------------------

            if string.find(chord_type, "/") then
                local _, slash_end = string.find(chord_type, "/")
                local bass_str = string.sub(chord_type, slash_end + 1)
                chord_type = string.sub(chord_type, 1, slash_end - 1)
                bass_note = musictheory.root_table[bass_str]
            else
                bass_note = pmd_root
            end

            if chord_type == "" then
                chord_type = "z"
            end

            -- PREPARE FOR PERFECT INVERSION MATH
            local processing_keyshift = musictheory.key_table[processing_key] or 0
            local real_keyshift = musictheory.key_table[real_song_key] or 0




            -- Calculate absolute roots for perfect voicing boundaries
            local abs_root = (pmd_root + processing_keyshift) % 12
            local abs_bass = (bass_note + processing_keyshift) % 12

            -- Calculate the exact shift the JSFX will apply (-5 to +6)
            local jsfx_shift = 0
            if G_render_mode ~= 0 then
                jsfx_shift = real_keyshift
                if jsfx_shift > 6 then
                    jsfx_shift = jsfx_shift - 12
                end
            end

            pmd_note_end_ppqpos = pmd_running_ppqpos_total + value[3]
            tiny_table_of_chord_tones = musictheory.type_table[chord_type]

            if tiny_table_of_chord_tones == nil then
                if pmd_item_to_color then
                    reaper.SetMediaItemInfo_Value(
                        pmd_item_to_color,
                        "I_CUSTOMCOLOR",
                        reaper.ColorToNative(0, 0, 0) | 0x1000000
                    )
                    reaper.ULT_SetMediaItemNote(pmd_item_to_color, "!!! ENTRY ERROR !!!")
                end
                pmd_running_ppqpos_total = pmd_note_end_ppqpos
            else
                -- GROOVE + VELOCITY LOGIC
                local start_qn_project = 0
                if grid_item_first_take then
                    start_qn_project = reaper.MIDI_GetProjQNFromPPQPos(grid_item_first_take, pmd_running_ppqpos_total)
                end

                local start_bar_pos_qn = start_qn_project % 4
                local start_step_idx = math.floor(start_bar_pos_qn * 8) + 1
                if start_step_idx < 1 then
                    start_step_idx = 1
                end
                if start_step_idx > 32 then
                    start_step_idx = 1
                end

                local start_ticks_shift = math.floor((groove_data[start_step_idx] or 0.0) * 60)

                local end_qn_project = 0
                if grid_item_first_take then
                    end_qn_project = reaper.MIDI_GetProjQNFromPPQPos(grid_item_first_take, pmd_note_end_ppqpos)
                end

                local end_bar_pos_qn = end_qn_project % 4
                local end_step_idx = math.floor(end_bar_pos_qn * 8) + 1
                if end_step_idx < 1 then
                    end_step_idx = 1
                end
                if end_step_idx > 32 then
                    end_step_idx = 1
                end

                local end_ticks_shift = math.floor((groove_data[end_step_idx] or 0.0) * 60)

                local final_start = pmd_running_ppqpos_total + start_ticks_shift
                local raw_end = pmd_note_end_ppqpos + end_ticks_shift

                local grooved_duration = raw_end - final_start
                local trim_amount = math.floor(G_ticks_per_measure / 32)

                if grooved_duration <= (trim_amount * 2) then
                    trim_amount = math.floor(grooved_duration * 0.3)
                end

                local final_end = raw_end - trim_amount
                if final_start < 0 then
                    final_start = 0
                end
                if final_end <= final_start then
                    final_end = final_start + 1
                end

                for _, v in pairs(tiny_table_of_chord_tones) do
                    local chan = 1
                    local vel, vel_bass = 80, 90
                    local is_dim = string.find(chord_type, "dim")

                    if v == 0 then
                        vel = 89
                    elseif v == 1 or v == 2 then
                        vel = 88
                    elseif v == 3 or v == 4 then
                        vel = 87
                    elseif v == 5 then
                        vel = 86
                    elseif v == 6 then
                        vel = is_dim and 85 or 86
                    elseif v == 7 or v == 8 then
                        vel = 85
                    elseif v == 9 then
                        vel = is_dim and 83 or 84
                    elseif v >= 10 then
                        vel = 83
                    end

                    -- Generate perfectly tuned Absolute pitch first

                    local pitch = (v + abs_root > 10) and (60 + abs_root + v - 12) or (60 + abs_root + v)

                    -- Visually reverse the JSFX shift for Relative modes so it sits cleanly on C in the editor!
                    local visual_pitch = (G_render_mode == 0) and (pitch - jsfx_shift) or pitch
                    local rel_grid_pitch = pitch - jsfx_shift -- Type 15 is ALWAYS in C

                    if chord_item_first_take then
                        reaper.MIDI_InsertNote(
                            chord_item_first_take,
                            0,
                            0,
                            final_start,
                            final_end,
                            chan,
                            pitch,
                            vel
                        )
                    end
                    if chbass_item_first_take then
                        reaper.MIDI_InsertNote(
                            chbass_item_first_take,
                            0,
                            0,
                            final_start,
                            final_end,
                            chan,
                            pitch,
                            vel
                        )
                    end

                    -- Explicitly populate BOTH grids!
                    if grid_item_first_take then
                        reaper.MIDI_InsertNote(grid_item_first_take, 0, 0, final_start, final_end, chan, pitch, vel)
                    end
                    if lead_item_first_take then
                        reaper.MIDI_InsertNote(
                            lead_item_first_take,
                            0,
                            0,
                            final_start,
                            final_end,
                            chan,
                            rel_grid_pitch,
                            vel
                        )
                    end

                    if v == 0 then
                        local bp = (v + abs_root > 10) and (60 + abs_bass + v - 36) or (60 + abs_bass + v - 24)
                        local visual_bp = (G_render_mode == 0) and (bp - jsfx_shift) or bp
                        local rel_grid_bp = bp - jsfx_shift

                        if bass_item_first_take then
                            reaper.MIDI_InsertNote(
                                bass_item_first_take,
                                0,
                                0,
                                final_start,
                                final_end,
                                chan,
                                bp,
                                vel_bass
                            )
                        end
                        if chbass_item_first_take then
                            reaper.MIDI_InsertNote(
                                chbass_item_first_take,
                                0,
                                0,
                                final_start,
                                final_end,
                                chan,
                                bp,
                                vel_bass
                            )
                        end

                        -- Explicitly populate BOTH grids with bass!
                        if grid_item_first_take then
                            reaper.MIDI_InsertNote(
                                grid_item_first_take,
                                0,
                                0,
                                final_start,
                                final_end,
                                chan,
                                bp,
                                vel_bass
                            )
                        end
                        if lead_item_first_take then
                            reaper.MIDI_InsertNote(
                                lead_item_first_take,
                                0,
                                0,
                                final_start,
                                final_end,
                                chan,
                                rel_grid_bp,
                                vel_bass
                            )
                        end
                    end
                end
            end
            pmd_running_ppqpos_total = pmd_note_end_ppqpos
        end
    end

    -- SAFE COLOR COPYING FOR ALL TEXT TRACKS
    local tr_source = G_RENDER_TARGETS[1] and G_RENDER_TARGETS[1][1]
    local dest_types = {4, 5, 6} -- Target the 3 Letter Chart types

    if tr_source then
        local item_count = reaper.CountTrackMediaItems(tr_source)
        for _, d_type in ipairs(dest_types) do
            local tr_dest = G_RENDER_TARGETS[d_type] and G_RENDER_TARGETS[d_type][1]
            if tr_dest then
                for i = 0, item_count - 1 do
                    local item_src = reaper.GetTrackMediaItem(tr_source, i)
                    if item_src then
                        local color = reaper.GetMediaItemInfo_Value(item_src, "I_CUSTOMCOLOR")
                        local item_dst = reaper.GetTrackMediaItem(tr_dest, i)
                        if item_dst then
                            reaper.SetMediaItemInfo_Value(item_dst, "I_CUSTOMCOLOR", color)
                        end
                    end
                end
            end
        end
    end

    return pmd_error_log, pmd_running_ppqpos_total, grid_item_first_take, lead_item_first_take
end



function Get_Stretched_ABCD_Index(phrase_idx, total_phrases)
    if total_phrases <= 1 then
        return 0 -- A
    elseif total_phrases == 2 then
        return phrase_idx -- A B
    elseif total_phrases == 3 then
        return phrase_idx -- A B C
    elseif total_phrases == 4 then
        return phrase_idx -- A B C D
    elseif total_phrases == 5 then
        local map = {0, 0, 1, 2, 3} -- A A B C D
        return map[phrase_idx + 1]
    elseif total_phrases == 6 then
        local map = {0, 0, 1, 2, 2, 3} -- A A B C C D
        return map[phrase_idx + 1]
    elseif total_phrases == 7 then
        local map = {0, 0, 1, 1, 2, 2, 3} -- A A B B C C D
        return map[phrase_idx + 1]
    elseif total_phrases == 8 then
        local map = {0, 0, 0, 1, 2, 2, 2, 3} -- A A A B C C C D
        return map[phrase_idx + 1]
    else
        local t = phrase_idx / (total_phrases - 1)

        if t < 0.30 then
            return 0 -- A
        elseif t < 0.50 then
            return 1 -- B
        elseif t < 0.80 then
            return 2 -- C
        else
            return 3 -- D
        end
    end
end












-- =========================================================
-- DRUM CONDUCTOR HELPERS v4 (Final Corrections)
-- =========================================================

-- 1. VISUAL LOOKUP (Colors & Names for Text Items)
function Get_Drum_Visuals(pc)
    local name = "Section"
    local r, g, b = 0.7, 0.7, 0.7

    if pc == 24 then
        name = "Count-In"
        r, g, b = 0.3, 0.3, 0.3
    elseif pc >= 32 and pc <= 35 then
        local letter = string.char(64 + (pc - 31))
        name = "Intro-" .. letter
        r, g, b = 0.2, 1.0, 1.0
    elseif pc >= 36 and pc <= 39 then
        local letter = string.char(64 + (pc - 35))
        name = "Verse 1-" .. letter
        r, g, b = 0.4, 0.6, 1.0
    elseif pc >= 40 and pc <= 43 then
        local letter = string.char(64 + (pc - 39))
        name = "Verse 2-" .. letter
        r, g, b = 0.4, 0.6, 1.0
    elseif pc >= 44 and pc <= 47 then
        local letter = string.char(64 + (pc - 43))
        name = "Verse 3-" .. letter
        r, g, b = 0.4, 0.6, 1.0
    elseif pc >= 48 and pc <= 51 then
        local letter = string.char(64 + (pc - 47))
        name = "Pre 1-" .. letter
        r, g, b = 0.7, 0.4, 1.0
    elseif pc >= 52 and pc <= 55 then
        local letter = string.char(64 + (pc - 51))
        name = "Pre 2-" .. letter
        r, g, b = 0.7, 0.4, 1.0
    elseif pc >= 56 and pc <= 59 then
        local letter = string.char(64 + (pc - 55))
        name = "Pre 3-" .. letter
        r, g, b = 0.7, 0.4, 1.0
    elseif pc >= 60 and pc <= 63 then
        local letter = string.char(64 + (pc - 59))
        name = "Chorus 1-" .. letter
        r, g, b = 1.0, 0.4, 0.4
    elseif pc >= 64 and pc <= 67 then
        local letter = string.char(64 + (pc - 63))
        name = "Chorus 2-" .. letter
        r, g, b = 1.0, 0.4, 0.4
    elseif pc >= 68 and pc <= 71 then
        local letter = string.char(64 + (pc - 67))
        name = "Chorus 3-" .. letter
        r, g, b = 1.0, 0.4, 0.4
    elseif pc >= 72 and pc <= 75 then
        local letter = string.char(64 + (pc - 71))
        name = "Bridge-" .. letter
        r, g, b = 1.0, 0.9, 0.2
    elseif pc >= 76 and pc <= 79 then
        local letter = string.char(64 + (pc - 75))
        name = "Solo-" .. letter
        r, g, b = 0.8, 0.5, 0.9
    elseif pc >= 80 and pc <= 83 then
        local letter = string.char(64 + (pc - 79))
        name = "Outro-" .. letter
        r, g, b = 0.5, 0.8, 0.7
    end

    return name, r, g, b
end

-- 2. SELECTIVE CLEANUP - Only remove our PC stamps (24-83)
-- 2. SELECTIVE CLEANUP - Optimized
function Clean_Drum_Track(track)
    if not track then
        return
    end

    local r = reaper
    local item_count = r.CountTrackMediaItems(track)
    if item_count == 0 then
        return
    end

    -- Valid PC range that we manage (24-83)
    local valid_pcs = {}
    for i = 24, 83 do
        valid_pcs[i] = true
    end

    for i = item_count - 1, 0, -1 do
        local item = r.GetTrackMediaItem(track, i)
        local should_delete = false

        -- Check for text labels first (faster than MIDI parsing)
        local _, notes = r.GetSetMediaItemInfo_String(item, "P_NOTES", "", false)

        if notes ~= "" and notes:match("^Drums ") then
            should_delete = true
        else
            -- Only check MIDI if no text match
            local take = r.GetActiveTake(item)
            if take and r.TakeIsMIDI(take) then
                -- Check first CC only - assume PC is first event
                local _, _, cccnt, _ = r.MIDI_CountEvts(take)
                if cccnt > 0 then
                    local _, _, _, _, msgtype, _, msg2, _ = r.MIDI_GetCC(take, 0)
                    if msgtype >= 0xC0 and msgtype <= 0xCF and valid_pcs[msg2] then
                        should_delete = true
                    end
                end
            end
        end

        if should_delete then
            r.DeleteTrackMediaItem(track, item)
        end
    end
end

-- 3. MAP REGION TO PC
function Parse_Region_To_PC(name)
    if not name or name == "" then
        return nil
    end
    local map = {
        ["Intro"] = 11,
        ["Verse"] = 21,
        ["Pre"] = 31,
        ["Chorus"] = 41,
        ["Bridge"] = 51,
        ["Outro"] = 61,
        ["Minimal"] = 71,
        ["Hit"] = 71,
        ["Fill"] = 81
    }

    arpmap = {
        ["Intro"] = 8,
        ["Verse"] = 16,
        ["Pre"] = 24,
        ["Chorus"] = 32,
        ["Bridge"] = 40,
        ["Outro"] = 48
    }
    local base_pc = nil
    for key, pc in pairs(map) do
        if name:find(key) then
            base_pc = pc
            break
        end
    end
    if not base_pc then
        return nil
    end
    local var = tonumber(name:match("%d+")) or 1
    if var < 1 then
        var = 1
    end
    if var > 7 then
        var = 7
    end
    return base_pc + (var - 1)
end

-- 3. MAP REGION NAME TO BASE PC
function Parse_Region_To_Base_PC(name)
    if not name or name == "" then
        return nil
    end

    local upper = string.upper(name)

    -- Support the explicit '#' symbol or the word 'count'
    if upper == "#" or upper == "{#}" or upper:find("COUNT") or upper:find("OFF") then
        return 24
    elseif upper:find("INTRO") or upper:find("INTERLUDE") or upper:match("^I%d*$") or upper:match("^IN%d*$") then
        return 32
    elseif upper:find("VERSE") or upper:match("^V%d*$") then
        local instance = tonumber(name:match("%d+")) or 1
        return 36 + (instance == 1 and 0 or (instance == 2 and 4 or 8))
    elseif upper:find("PRE") or upper:match("^P%d*$") or upper:match("^PC%d*$") then
        local instance = tonumber(name:match("%d+")) or 1
        return 48 + (instance == 1 and 0 or (instance == 2 and 4 or 8))
    elseif upper:find("CHORUS") or upper:match("^C%d*$") then
        local instance = tonumber(name:match("%d+")) or 1
        return 60 + (instance == 1 and 0 or (instance == 2 and 4 or 8))
    elseif upper:find("BRIDGE") or upper:match("^B%d*$") then
        return 72
    elseif upper:find("SOLO") or upper:match("^S%d*$") then
        return 76
    elseif upper:find("OUTRO") or upper:find("CODA") or upper:match("^O%d*$") then
        return 80
    else
        return nil -- Unrecognized words carry the previous groove gracefully
    end
end

-- 4. INSERT TRIGGER & TEXT (Text = 1 bar, Pattern = 4 bars)
function Insert_Drum_Trigger(track, time_pos, pc_val)
    local r = reaper

    -- MIDI EARLY (8th note early = 0.5 QN)
    local midi_qn = r.TimeMap2_timeToQN(0, time_pos) - 0.5
    if midi_qn < 0 then
        midi_qn = 0
    end

    local midi_time = r.TimeMap2_QNToTime(0, midi_qn)
    local end_time = r.TimeMap2_QNToTime(0, midi_qn + 1.0)

    local m_item = r.CreateNewMIDIItemInProj(track, midi_time, end_time, false)
    local m_take = r.GetActiveTake(m_item)
    if m_take then
        local ppq = r.MIDI_GetPPQPosFromProjTime(m_take, midi_time)
        r.MIDI_InsertCC(m_take, false, false, ppq, 0xC0, 15, pc_val, 0)
        r.MIDI_Sort(m_take)
    end

    -- TEXT LABEL - Only 1 bar long
    local section_name, rr, gg, bb = Get_Drum_Visuals(pc_val)
    local label = "Drums " .. section_name

    -- Text item spans 1 bar (changed from 4)
    local start_qn = r.TimeMap2_timeToQN(0, time_pos)
    local end_qn = start_qn + 4 -- 1 bar instead of 4
    local end_time_text = r.TimeMap2_QNToTime(0, end_qn)

    local t_item = r.AddMediaItemToTrack(track)
    if t_item then
        r.SetMediaItemInfo_Value(t_item, "D_POSITION", time_pos)
        r.SetMediaItemInfo_Value(t_item, "D_LENGTH", end_time_text - time_pos)
        r.GetSetMediaItemInfo_String(t_item, "P_NAME", label, true)
        r.GetSetMediaItemInfo_String(t_item, "P_NOTES", label, true)

        local native_color =
            r.ColorToNative(math.floor(rr * 255), math.floor(gg * 255), math.floor(bb * 255)) | 0x1000000
        r.SetMediaItemInfo_Value(t_item, "I_CUSTOMCOLOR", native_color)
    end
end



function Generate_Drum_Conductor_For_Track(drum_track)
    local r = reaper
    if not drum_track then
        return
    end

    Clean_Drum_Track(drum_track)

    local _, num_markers, num_regions = r.CountProjectMarkers(0)
    local total = num_markers + num_regions

    local first_region_pos = nil
    local last_region_end = 0
    local has_region_at_zero = false

    for i = 0, total - 1 do
        local _, isrgn, pos, rgnend = r.EnumProjectMarkers(i)
        if isrgn then
            if first_region_pos == nil or pos < first_region_pos then
                first_region_pos = pos
            end
            if rgnend > last_region_end then
                last_region_end = rgnend
            end
            if pos <= 0.01 then
                has_region_at_zero = true
            end
        end
    end

    if G_DRUM_CUE_PLACEMENT == "On/Off" then
        if not has_region_at_zero then
            Insert_Drum_Trigger(drum_track, 0.0, 0)
        end

        if first_region_pos ~= nil then
            Insert_Drum_Trigger(drum_track, first_region_pos, 26)
        end

        if last_region_end > 0 then
            Insert_Drum_Trigger(drum_track, last_region_end, 0)
        end

        r.UpdateArrange()
        return
    end

    if not has_region_at_zero then
        Insert_Drum_Trigger(drum_track, 0.0, 24)
    end

    for i = 0, total - 1 do
        local _, isrgn, pos, rgnend, name = r.EnumProjectMarkers(i)
        if isrgn then
            local base_pc = Parse_Region_To_Base_PC(name)

            if base_pc then
                if G_DRUM_CUE_PLACEMENT == "Every Section" then
                    Insert_Drum_Trigger(drum_track, pos, base_pc)

                elseif G_DRUM_CUE_PLACEMENT == "Every 4 Bars" then
                    local start_qn = r.TimeMap2_timeToQN(0, pos)
                    local end_qn = r.TimeMap2_timeToQN(0, rgnend)
                    local length_qn = end_qn - start_qn
                    local num_phrases = math.ceil(length_qn / 16)

                    for phrase = 0, num_phrases - 1 do
                        local phrase_start_qn = start_qn + (phrase * 16)
                        if phrase_start_qn >= end_qn then
                            break
                        end
                        local pattern_index = Get_Stretched_ABCD_Index(phrase, num_phrases)
                        local pc_val = base_pc + pattern_index
                        local phrase_time = r.TimeMap2_QNToTime(0, phrase_start_qn)
                        Insert_Drum_Trigger(drum_track, phrase_time, pc_val)
                    end
                end
            end
        end
    end

    if last_region_end > 0 then
        Insert_Drum_Trigger(drum_track, last_region_end, 24)
    end

    r.UpdateArrange()
end

-- HELPER: Find ALL tracks with N2N Drum Arranger FX
function Find_All_Tracks_With_Drum_FX()
    local r = reaper
    local target_fx = "N2N Drum Arranger"
    local matching_tracks = {}

    local track_count = r.CountTracks(0)
    for i = 0, track_count - 1 do
        local tr = r.GetTrack(0, i)
        local fx_count = r.TrackFX_GetCount(tr)

        for fx = 0, fx_count - 1 do
            local retval, buf = r.TrackFX_GetFXName(tr, fx, "")
            if retval and buf then
                local normalized = buf:lower()
                if normalized:find("n2n drum arranger") then
                    table.insert(matching_tracks, tr)
                    break -- Found it on this track, move to next track
                end
            end
        end
    end
    return matching_tracks
end

-- 6. PROCESS ALL N2N DRUM ARRANGER TRACKS
function Generate_Drum_Conductor_All()
    local r = reaper
    local tracks = Find_All_Tracks_With_Drum_FX()

    for _, track in ipairs(tracks) do
        Generate_Drum_Conductor_For_Track(track)
    end

    r.UpdateArrange()
end

-- 1. PARSE REGION TO ARP PC (using arpmap)
function Parse_Region_To_Arp_PC(name)
    return Parse_Region_To_Base_PC(name)
end

-- 2. GET ARP VISUALS (colors/names for the Arp track)
function Get_Arp_Visuals(pc)
    return Get_Drum_Visuals(pc)
end

-- 3. INSERT ARP TRIGGER (similar to drum trigger but with arp-specific visuals)
function Insert_Arp_Trigger(track, time_pos, pc_val)
    local r = reaper

    -- MIDI timing (8th note early = 0.5 QN)
    local midi_qn = r.TimeMap2_timeToQN(0, time_pos) - 0.5
    if midi_qn < 0 then
        midi_qn = 0
    end

    local midi_time = r.TimeMap2_QNToTime(0, midi_qn)
    local end_time = r.TimeMap2_QNToTime(0, midi_qn + 1.0)

    -- Create MIDI item with Program Change
    local m_item = r.CreateNewMIDIItemInProj(track, midi_time, end_time, false)
    local m_take = r.GetActiveTake(m_item)
    if m_take then
        local ppq = r.MIDI_GetPPQPosFromProjTime(m_take, midi_time)
        -- Program Change on channel 1 (0xC0), value pc_val
        r.MIDI_InsertCC(m_take, false, false, ppq, 0xC0, 15, pc_val, 0)
        r.MIDI_Sort(m_take)
    end

    -- INSERT VISUAL TEXT LABEL
    local section_name, rr, gg, bb = Get_Arp_Visuals(pc_val)
    local label = "Arp " .. section_name

    local start_qn = r.TimeMap2_timeToQN(0, time_pos)
    local end_qn = start_qn + 4
    local end_time_label = r.TimeMap2_QNToTime(0, end_qn)

    local t_item = r.AddMediaItemToTrack(track)
    if t_item then
        r.SetMediaItemInfo_Value(t_item, "D_POSITION", time_pos)
        r.SetMediaItemInfo_Value(t_item, "D_LENGTH", end_time_label - time_pos)

        r.GetSetMediaItemInfo_String(t_item, "P_NAME", label, true)
        r.GetSetMediaItemInfo_String(t_item, "P_NOTES", label, true)

        local native_color =
            r.ColorToNative(math.floor(rr * 255), math.floor(gg * 255), math.floor(bb * 255)) | 0x1000000
        r.SetMediaItemInfo_Value(t_item, "I_CUSTOMCOLOR", native_color)
    end
end

-- 4. CLEAN ARP TRACK (similar to Clean_Drum_Track)
function Clean_Arp_Track(track)
    if not track then
        return
    end
    local r = reaper
    local item_count = r.CountTrackMediaItems(track)

    for i = item_count - 1, 0, -1 do
        local item = r.GetTrackMediaItem(track, i)
        local should_delete = false

        -- Check for Arp text labels
        local _, name = r.GetSetMediaItemInfo_String(item, "P_NAME", "", false)
        local _, notes = r.GetSetMediaItemInfo_String(item, "P_NOTES", "", false)

        if notes ~= "" and notes:match("^Arp ") then
            should_delete = true
        elseif
            name and
                (name:match("^Arp") or name:match("^Intro") or name:match("^Verse") or name:match("^Pre") or
                    name:match("^Chorus") or
                    name:match("^Bridge") or
                    name:match("^Outro") or
                    name:match("^Off"))
         then
            should_delete = true
        else
            -- Check for MIDI PC messages
            local take = r.GetActiveTake(item)
            if take and r.TakeIsMIDI(take) then
                local _, _, cccnt, _ = r.MIDI_CountEvts(take)
                for j = 0, cccnt - 1 do
                    local _, _, _, _, msgtype, _, msg2, _ = r.MIDI_GetCC(take, j)
                    if (msgtype >= 0xC0 and msgtype <= 0xCF) then
                        should_delete = true
                        break
                    end
                end
            end
        end

        if should_delete then
            r.DeleteTrackMediaItem(track, item)
        end
    end
end

function Generate_Arp_Conductor(arp_track)
    local r = reaper
    Clean_Arp_Track(arp_track)

    local _, num_markers, num_regions = r.CountProjectMarkers(0)
    local total = num_markers + num_regions

    local first_region_pos = nil
    local last_region_end = 0
    local has_region_at_zero = false

    for i = 0, total - 1 do
        local _, isrgn, pos, rgnend = r.EnumProjectMarkers(i)
        if isrgn then
            if first_region_pos == nil or pos < first_region_pos then
                first_region_pos = pos
            end
            if rgnend > last_region_end then
                last_region_end = rgnend
            end
            if pos <= 0.01 then
                has_region_at_zero = true
            end
        end
    end

    if G_ARP_CUE_PLACEMENT == "On/Off" then
        if not has_region_at_zero then
            Insert_Arp_Trigger(arp_track, 0.0, 0)
        end

        if first_region_pos ~= nil then
            Insert_Arp_Trigger(arp_track, first_region_pos, 1) -- default ARP cue
        end

        if last_region_end > 0 then
            Insert_Arp_Trigger(arp_track, last_region_end, 0)
        end

        r.UpdateArrange()
        return
    end

    if not has_region_at_zero then
        Insert_Arp_Trigger(arp_track, 0.0, 0)
    end

    for i = 0, total - 1 do
        local _, isrgn, pos, rgnend, name = r.EnumProjectMarkers(i)
        if isrgn then
            if G_ARP_CUE_PLACEMENT == "Every Section" then
                local pc = Parse_Region_To_Arp_PC(name)
                if pc then
                    Insert_Arp_Trigger(arp_track, pos, pc)
                end

            elseif G_ARP_CUE_PLACEMENT == "Every 4 Bars" then
                local base_pc = Parse_Region_To_Arp_PC(name)
                if base_pc then
                    local start_qn = r.TimeMap2_timeToQN(0, pos)
                    local end_qn = r.TimeMap2_timeToQN(0, rgnend)
                    local length_qn = end_qn - start_qn
                    local num_phrases = math.ceil(length_qn / 16)

                    for phrase = 0, num_phrases - 1 do
                        local phrase_start_qn = start_qn + (phrase * 16)
                        if phrase_start_qn >= end_qn then
                            break
                        end

                        local pattern_index = Get_Stretched_ABCD_Index(phrase, num_phrases)
                        local pc_val = base_pc + pattern_index
                        local phrase_time = r.TimeMap2_QNToTime(0, phrase_start_qn)
                        Insert_Arp_Trigger(arp_track, phrase_time, pc_val)
                    end
                end
            end
        end
    end

    r.UpdateArrange()
end

-- Find ALL tracks containing N2N Arp FX
function Find_All_Tracks_With_Arp_FX()
    local r = reaper
    local target_fx = "N2N Arp"
    local arp_tracks = {} -- Table to hold all matching tracks

    local track_count = r.CountTracks(0)
    for i = 0, track_count - 1 do
        local tr = r.GetTrack(0, i)
        local fx_count = r.TrackFX_GetCount(tr)

        for fx = 0, fx_count - 1 do
            local retval, buf = r.TrackFX_GetFXName(tr, fx, "")
            if retval and buf then
                local normalized = buf:lower()
                local target_lower = target_fx:lower()

                if
                    normalized:find(target_fx, 1, true) or normalized:find(target_lower, 1, true) or
                        normalized:find("js: " .. target_lower, 1, true)
                 then
                    -- Add to table instead of returning immediately
                    table.insert(arp_tracks, tr)
                    break -- Found FX on this track, move to next track
                end
            end
        end
    end

    return arp_tracks -- Return table of all matching tracks
end

function place_special()
    -- 1. Bulletproof Region Clearing
    local retval, num_markers, num_regions = reaper.CountProjectMarkers(0)
    local total_markers = num_markers + num_regions
    for i = total_markers - 1, 0, -1 do
        reaper.DeleteProjectMarkerByIndex(0, i)
    end

    -- Track instance counts for each region type
    local region_counts = {}

    -- 2. Use ipairs() to strictly guarantee timeline chronological order
    for i, v in ipairs(G_region_table) do
        local region_end = 0
        if G_region_table[i + 1] == nil then
            region_end = reaper.TimeMap2_beatsToTime(0, final_ppqpos_total / 960)
        else
            region_end = reaper.TimeMap2_beatsToTime(0, G_region_table[i + 1][1] / 960)
        end

        local the_regions_name = v[2]

        -- Check if this region type should be numbered
        
        
        
        
        
        
        local should_number = false
local region_type_upper = string.upper(the_regions_name)
        local display_name = the_regions_name
        local base_color_name = the_regions_name

        -- Tiny helper function to keep the counter perfectly synced with explicit numbers
        local function update_section(base_name, num)
            base_color_name = base_name
            if num then
                local n = tonumber(num)
                -- If they typed C2, force the internal counter to catch up!
                if n and n > (region_counts[base_name] or 0) then
                    region_counts[base_name] = n
                end
                display_name = base_name .. " " .. num
            else
                region_counts[base_name] = (region_counts[base_name] or 0) + 1
                if region_counts[base_name] == 1 then
                    display_name = base_name -- Just "Chorus" for the first one
                else
                    display_name = base_name .. " " .. region_counts[base_name] -- "Chorus 2" for the next
                end
            end
        end

        -- 1. Expand reserved shorthands dynamically! 
        if region_type_upper:match("^V%d*$") or region_type_upper == "VERSE" then
            update_section("Verse", region_type_upper:match("%d+"))
        elseif region_type_upper:match("^C%d*$") or region_type_upper == "CHORUS" then
            update_section("Chorus", region_type_upper:match("%d+"))
        elseif region_type_upper:match("^P%d*$") or region_type_upper:match("^PC%d*$") or region_type_upper:match("^PRE[- ]?") then
            update_section("Pre-Chorus", region_type_upper:match("%d+"))
        elseif region_type_upper:match("^B%d*$") or region_type_upper == "BRIDGE" then
            update_section("Bridge", region_type_upper:match("%d+"))
        elseif region_type_upper:match("^O%d*$") or region_type_upper == "OUTRO" then
            update_section("Outro", region_type_upper:match("%d+"))
        elseif region_type_upper:match("^I%d*$") or region_type_upper:match("^IN%d*$") or region_type_upper == "INTRO" then
            update_section("Intro", region_type_upper:match("%d+"))
        elseif region_type_upper:match("^M%d*$") or region_type_upper == "MIDDLE 8" then
            update_section("Middle 8", region_type_upper:match("%d+"))
        elseif region_type_upper:match("^R%d*$") or region_type_upper == "RAMP" then
            update_section("Ramp", region_type_upper:match("%d+"))
        elseif region_type_upper:match("^D%d*$") or region_type_upper == "DROP" then
            update_section("Drop", region_type_upper:match("%d+"))
        elseif region_type_upper:match("^S%d*$") or region_type_upper == "SOLO" then
            update_section("Solo", region_type_upper:match("%d+"))
        elseif region_type_upper:match("^F%d*$") or region_type_upper == "FADEOUT" then
            update_section("Fadeout", region_type_upper:match("%d+"))
        end

        -- 2. Apply Colors using the expanded base_color_name!
        local region_item_color = reaper.ColorToNative(80, 80, 100) | 0x1000000
        
        -- Pull the color dictionary from form.lua
        if form.sections_colors and form.sections_colors[base_color_name] then
            local the_color_values = form.sections_colors[base_color_name]
            region_item_color = reaper.ColorToNative(the_color_values[1], the_color_values[2], the_color_values[3]) | 0x1000000
        elseif form.sections_colors and form.sections_colors[the_regions_name] then
            local the_color_values = form.sections_colors[the_regions_name]
            region_item_color = reaper.ColorToNative(the_color_values[1], the_color_values[2], the_color_values[3]) | 0x1000000
        end





        local starts_position = reaper.TimeMap2_beatsToTime(0, v[1] / 960)

        if G_region_table[i + 1] == nil then
            region_end = reaper.TimeMap2_beatsToTime(0, final_ppqpos_total / 960)
        else
            region_end = reaper.TimeMap2_beatsToTime(0, G_region_table[i + 1][1] / 960)
        end
        
        if region_end <= starts_position then
            region_end = starts_position + 0.001
        end


        -- Pass 0 as the ID so Reaper auto-assigns the safest ID number
        reaper.AddProjectMarker2(0, true, starts_position, region_end, display_name, 0, region_item_color)
    end

    -- 3. Cleanup
    G_region_table = {}
end

goopy = 0

function process_pushes()
    pushy_chord_table = chord_table
    for i, v in pairs(chord_table) do
        last_element = i
    end
    push_grab = 0
    
    
for i = last_element, 1, -1 do
        -- SAFETY NET: Skip if the chord entry is blank or corrupted
        if not chord_table[i] or type(chord_table[i][4]) ~= "string" then 
            goto skip_push 
        end

        chord_table[i][3] = chord_table[i][3] - push_grab
        if string.sub(chord_table[i][4], 1, 2) == "<." then
            --reaper.ShowConsoleMsg("Dottend 8th Push - " .. chord_table[i][4] .. "\n")
            chord_table[i][4] = string.sub(chord_table[i][4], 3, string.len(chord_table[i][4]))
            push_grab = 3 * (G_ticks_per_measure / 4)
        elseif string.sub(chord_table[i][4], 1, 3) == "2t<" or string.sub(chord_table[i][4], 1, 3) == "2T<" then
            --reaper.ShowConsoleMsg("Two Triplet Push - " .. chord_table[i][4] .. "\n")
            chord_table[i][4] = string.sub(chord_table[i][4], 4, string.len(chord_table[i][4]))
            push_grab = 2 * (G_ticks_per_measure / 3)
        elseif string.sub(chord_table[i][4], 1, 2) == "t<" or string.sub(chord_table[i][4], 1, 2) == "T<" then
            chord_table[i][4] = string.sub(chord_table[i][4], 3, string.len(chord_table[i][4]))
            --reaper.ShowConsoleMsg("Triplet Push - " .. chord_table[i][4] .. "\n")
            push_grab = G_ticks_per_measure / 3
        elseif string.sub(chord_table[i][4], 1, 2) == "<<" then
            chord_table[i][4] = string.sub(chord_table[i][4], 3, string.len(chord_table[i][4]))
            --reaper.ShowConsoleMsg("Sixteenth Push - " .. chord_table[i][4] .. "\n")
            push_grab = G_ticks_per_measure / 4
        elseif string.sub(chord_table[i][4], 1, 1) == "<" then
            chord_table[i][4] = string.sub(chord_table[i][4], 2, string.len(chord_table[i][4]))
            --reaper.ShowConsoleMsg("Eighth Push - " .. chord_table[i][4] .. "\n")
            push_grab = G_ticks_per_measure / 2
        else
            push_grab = 0
        end
        chord_table[i][3] = chord_table[i][3] + push_grab
        
        ::skip_push::
    end
    
    
    
    
    
    
     
end

function chords_to_onemotion()
    local is_synco_found = false
    local the_absolute_chord = ""
    local om_root = ""
    local om_type_start = 0
    onemotionoutput = ""
    local om_notice = ""
    local ombeats = 0
    for i, value in pairs(chord_table) do
        --reaper.ShowConsoleMsg(value[4].."\n")
        if string.sub(value[4], 1, 2) == "{$" then
            om_marker = string.sub(value[4], 3, string.len(value[4]) - 2)

            onemotionoutput = onemotionoutput .. "<" .. om_marker .. "> "
        elseif string.sub(value[4], 1, 1) == "-" then
            reaper.ShowConsoleMsg(
                "ei 1 = " ..
                    value[1] .. " 2 = " .. value[2] .. " 3 = " .. (value[3]) / 960 .. " 4 = " .. value[4] .. "\n"
            )
            ombeats = math.floor(value[3] / G_ticks_per_measure)
            if ombeats ~= (value[3] / G_ticks_per_measure) then
                if is_synco_found == false then
                    om_notice =
                        "Notice! - Onemotion.com does not handle off-beat chord changes." ..
                        string.char(10) ..
                            "Chord changes rounded to nearest beat!" ..
                                string.char(10) ..
                                    "_________________________________________________________________" ..
                                        string.char(10) .. string.char(10)
                    is_synco_found = true
                else
                end
            end

            onemotionoutput = onemotionoutput .. ombeats .. "rest default "
        else
            --k = 0
            --for k, v in pairs(value) do
            --    datapeek = datapeek .. " k = " .. k .. " / value = " .. v .. string.char(10)
            --end
            ombeats = math.floor(value[3] / G_ticks_per_measure)
            reaper.ShowConsoleMsg(
                "e 1 = " ..
                    value[1] .. " 2 = " .. value[2] .. " 3 = " .. (value[3]) / 960 .. " 4 = " .. value[4] .. "\n"
            )
            if ombeats ~= (value[3] / G_ticks_per_measure) then
                if is_synco_found == false then
                    om_notice =
                        "Notice! - Onemotion.com does not handle off-beat chord changes." ..
                        string.char(10) ..
                            "Chord changes rounded to nearest beat!" ..
                                string.char(10) ..
                                    "_________________________________________________________________" ..
                                        string.char(10) .. string.char(10)
                    is_synco_found = true
                end
            end

            if ombeats == 0 then
                ombeats = 1
            end
            if string.sub(value[4], 1, 1) == "b" or string.sub(value[4], 1, 1) == "#" then
                om_root = string.sub(value[4], 1, 2)
                om_type_start = 3
            else
                om_root = string.sub(value[4], 1, 1)
                om_type_start = 2
            end
            current_key = set_the_key(header_area)
            current_key_shift = musictheory.key_table[current_key]

            local the_om_key_index = musictheory.root_table[om_root]
            if the_om_key_index == nil then
                --Show_To_Dev("!!!!!!!!!!!!!!!!!!!!! " .. om_root .. string.char(10))
            elseif the_om_key_index + current_key_shift < 0 then
                the_om_key_index = the_om_key_index + current_key_shift + 12
            elseif the_om_key_index + current_key_shift > 24 then
                the_om_key_index = the_om_key_index + current_key_shift - 24
            elseif the_om_key_index + current_key_shift >= 12 then
                the_om_key_index = the_om_key_index + current_key_shift - 12
            else
                the_om_key_index = the_om_key_index + current_key_shift
            end

            --reaper.ShowConsoleMsg(the_om_key_index.."\n")
            if musictheory.is_it_flat_table[current_key] == true then
                the_absolute_chord = musictheory.flats_table[the_om_key_index]
            else
                the_absolute_chord = musictheory.sharps_table[the_om_key_index]
            end
            if string.sub(value[4], om_type_start, string.len(value[4])) == "" then
                onemotionoutput = onemotionoutput .. ombeats .. the_absolute_chord .. " "
            else
                om_slash_start_pos, _ = string.find(value[4], "/")
                if om_slash_start_pos ~= nil then
                    reaper.ShowConsoleMsg("found one\n")
                    type_end_pos = om_slash_start_pos - 1
                else
                    type_end_pos = string.len(value[4])
                end

                onemotion_chord_type =
                    musictheory.to_onemotion_translation[string.sub(value[4], om_type_start, type_end_pos)]

                if onemotion_chord_type == nil then
                    --reaper.ShowConsoleMsg("value was ".. value[4] .. "\n")
                    onemotionoutput = onemotionoutput .. ombeats .. the_absolute_chord .. " "
                else
                    --reaper.ShowConsoleMsg(onemotion_chord_type.."\n")
                    onemotionoutput = onemotionoutput .. ombeats .. the_absolute_chord .. onemotion_chord_type .. " "
                end
            end
        end
    end
    reaper.ImGui_SetClipboardText(ctx, onemotionoutput)
    onemotionoutput = om_notice .. onemotionoutput
end

function PreRender_Setup()
    reaper.ClearConsole()
    Autosave()
    SaveLastNumbers2NotesChart()

    local thetime = os.date("%Y-%m-%d %H-%M-%S")
    render_feedback = render_feedback .. "Rendered at " .. thetime .. "\n"

    -- CHECK GROOVE STATUS
    local is_groove_active = false
    for i = 1, 32 do
        if math.abs(groove_data[i]) > 0.001 then
            is_groove_active = true
            break
        end
    end

    if is_groove_active then
        render_feedback = render_feedback .. "NOTE: Rendering with Custom Groove active.\n"
    end

    -- FORCE CLEAN STATE TO PREVENT ACCUMULATION BUGS FROM PREVIOUS RENDERS
    G_split = 0
    G_error_log = "START ERROR LOG - " .. string.char(10)
    G_time_signature_top = 4
    G_ticks_per_measure = 960
    inparenthetical = false
    chord_table = {}
    temp_chord_table = {}
    updated_chord_table = {}
    chord_splitsection_count = 0
    temp_chord_splitsection_count = 0
    updated_chord_splitsection_count = 0
    G_region_table = {}
    final_ppqpos_total = 0

    chord_charting_area = inital_swaps(chord_charting_area)
    local safe_header = Normalize_Form_Line(header_area)
    unfolded_user_data, error_zone = form.process_the_form(header_area, chord_charting_area)
    progression = Set_The_Current_Simulated_Userinput_Data(unfolded_user_data)
end

function Apply_Project_Settings()

    real_song_key = set_the_key(header_area)

    if G_render_mode == 0 then
        processing_key = "C"
    else
        processing_key = real_song_key
    end
    
    current_key = processing_key
    
    current_bpm = set_the_bpm(header_area)

    -- Time Sig is handled inside the parser now, but we init here
    local ts_num, ts_denom = set_the_time_sig(header_area)
    G_time_signature_top = ts_num

    -- CORRECTED: Use SetTempoTimeSigMarker at time 0.0 to set project default
    reaper.SetTempoTimeSigMarker(0, -1, 0.0, -1, -1, current_bpm, ts_num, ts_denom, false)
    set_the_swing(header_area)
end

function Parse_Chord_Data()
    G_split, G_error_log = orgainize_input_into_bars(G_error_log)
    G_split, G_error_log = process_nested_split_sections(G_split, G_error_log)
    process_pushes()
    presentdata(G_split, G_error_log)
end

function Export_To_GMEM(chbass_item_id)
    if gmem_export and chbass_item_id then
        local light_take = reaper.GetActiveTake(chbass_item_id)
        if light_take then
            -- CRITICAL: Must attach before any gmem_write!
            reaper.gmem_attach("N2N_Ecosystem_RSKennedy")

            local r_tonic, m_center = gmem_export.Analyze(light_take, processing_key)
            gmem_export.SendToGMEM(light_take, r_tonic, m_center)
            gmem_export.SendScaleToGMEM(light_take, r_tonic)

            return r_tonic, m_center -- RETURN THE VALUES!
        end
    end

    -- Fallback if GMEM isn't set up yet
    local fallback_key = musictheory.key_table[processing_key] or 0
    return fallback_key, fallback_key
end

function Resolve_Cue_Placement_Modes()
    G_DRUM_CUE_PLACEMENT = "Every 4 Bars"
    G_ARP_CUE_PLACEMENT  = "Every Section"

    for _, tr in ipairs(config.track_recipe) do
        if tr.active and tr.drum_arp_mode then
            if tr.type == 32 then
                G_DRUM_CUE_PLACEMENT = tr.drum_arp_mode
            elseif tr.type == 33 then
                G_ARP_CUE_PLACEMENT = tr.drum_arp_mode
            end
        end
    end
end

function Generate_Arranger_Conductors()
    Resolve_Cue_Placement_Modes()

    place_special()

    local drum_tracks = Find_All_Tracks_With_Drum_FX()
    for _, drum_track in ipairs(drum_tracks) do
        Generate_Drum_Conductor_For_Track(drum_track)
    end

    local arp_tracks = Find_All_Tracks_With_Arp_FX()
    for _, arp_track in ipairs(arp_tracks) do
        if arp_track then
            Generate_Arp_Conductor(arp_track)
        end
    end
end

function Generate_Spectrums(grid_take, lead_take)
    -- A. Absolute Grid (Key of Song)
    if grid_take and reaper.ValidatePtr(grid_take, "MediaItem_Take*") then
        local notneeded = spectrum.make_full_spectrum(grid_take)
    end

    -- B. Relative Grid (Key of C - For Lead/Delay Track)
    if lead_take and reaper.ValidatePtr(lead_take, "MediaItem_Take*") then
        local notneeded = spectrum.make_full_spectrum(lead_take)
    end
end

function PostRender_Cleanup()
    Sync_Chart_Colors()

    local close_all_fx_windows = reaper.NamedCommandLookup("_S&M_WNCLS3")
    reaper.Main_OnCommand(close_all_fx_windows, 0)

    -- RESET VARIABLES
    G_split = 0
    G_error_log = "START ERROR LOG - " .. string.char(10)
    G_time_signature_top = 4
    G_ticks_per_measure = 960

    inparenthetical = false
    chord_table = {}
    temp_chord_table = {}
    updated_chord_table = {}

    chord_splitsection_count = 0
    temp_chord_splitsection_count = 0
    updated_chord_splitsection_count = 0
end

-- Global variables to hold our background rendering state
render_co = nil
render_status_msg = ""
G_DYNAMIC_TABLE = {}

function Start_Render_Coroutine()
    modal_on = true
    render_status_msg = "Preparing Project..."
    render_co = coroutine.create(Render_Process_Routine)
end

function Render_Process_Routine()
    reaper.PreventUIRefresh(1)
    PreRender_Setup()

    -- Reset Render Targets so old track pointers don't linger!
    G_RENDER_TARGETS = {}

    G_DYNAMIC_TABLE = Compile_Dynamic_Track_Table(config.track_recipe)

    Scan_Existing_Tracks()
    
    reaper.PreventUIRefresh(-1)

    coroutine.yield("Scanning existing tracks...")

    for i, tr in ipairs(G_DYNAMIC_TABLE) do
        reaper.PreventUIRefresh(1)
        local is_new = Build_Single_Track(tr)
        reaper.PreventUIRefresh(-1)

        if is_new then
            coroutine.yield("Building Track: " .. tostring(tr[1]))
        end
    end

    reaper.PreventUIRefresh(1)
    Organize_Tracks_And_Routing(G_DYNAMIC_TABLE)
    Make_Monster_Drums_32_Chan() 
    reaper.PreventUIRefresh(-1)

    coroutine.yield("Generating MIDI Data...")

    reaper.PreventUIRefresh(1)
    Apply_Project_Settings()
    Parse_Chord_Data()

    local pmd_tc, lead_id, chord_id, bass_id, chbass_id, grid_id = place_TEXT_data(G_DYNAMIC_TABLE)

    -- Ensuring final_ppqpos_total maps globally to place_special

  local dummy_err, fppt, grid_take, lead_take =
    place_MIDI_data(pmd_tc, lead_id, chord_id, bass_id, chbass_id, grid_id, G_DYNAMIC_TABLE)

  final_ppqpos_total = fppt


    Set_Back2Key_Transpositions()

local r_tonic, m_center = Export_To_GMEM(chbass_id)

local abs_tonic = musictheory.key_table[real_song_key] or 0
local modal_offset = (m_center - r_tonic) % 12
local abs_m_center = (abs_tonic + modal_offset) % 12

Set_Mood2Mode_Parameters(abs_tonic, abs_m_center)




    Generate_Arranger_Conductors()

    -- Pass them explicitly into the spectrum generator!
    Generate_Spectrums(grid_take, lead_take)

    PostRender_Cleanup()
    reaper.PreventUIRefresh(-1)
end

function import_onemotion()
    reaper.PreventUIRefresh(1)
    local omi_key = "G"
    local omi_conversion_table = {}
    local omi_beats = 0
    local omi_root = ""
    local omi_type = ""
    local omi_inmarker = false
    local omi_import_text = ""
    local omi_inchord = false
    local omi_chord = ""
    local omi_chord_table = {}
    local omi_parsed_table = {}
    local chord_count = 0
    onemotionimport = ""
    omi_import_text = reaper.CF_GetClipboard()

    if
        string.len(omi_import_text) == 0 or string.len(omi_import_text) == nil or
            musictheory.key_table[import_key] == nil
     then
        onemotionimport =
            'Make sure you have copied the "Edit All" data from Onemotion.com Chord \nPlayer and set the Import Key before attempting conversion.'
    else
        --omi_import_text = "<Intro> 2G5 2Gadd9 4Bsus4 4C 4Dadd9 <Verse 1> 4G5 4Gadd9 4Bsus4 4C 4Dadd9 1Ebm 1Rest 1Em 1C 2D 6Em 4Em 4C#m 4D 4Em 4Em 4C 4C 4C 4D"
        local swaptext = string.gsub(omi_import_text, "4onlyBass", "")
        omi_import_text = string.gsub(swaptext, "onlyBass", "")
        swaptext = string.gsub(omi_import_text, "4onlyChord", "")
        omi_import_text = string.gsub(swaptext, "onlyChord", "")
        swaptext = string.gsub(omi_import_text, "default", "")
        omi_import_text = swaptext

        --Show_To_Dev("start inport" .. string.char(10) .. omi_import_text .. string.char(10) )

        for i = 1, string.len(omi_import_text), 1 do
            -- USELESS SPACE
            if string.sub(omi_import_text, i, i) == " " and omi_inchord == false and omi_inmarker == false then
                -- SPACE THAT CAPS OFF A CHORD OR MARKER
            elseif string.sub(omi_import_text, i, i) == " " and omi_inchord == true and omi_inmarker == false then
                -- SPACE IN THE MIDDLE OF A MARKER
                chord_count = chord_count + 1
                table.insert(omi_chord_table, chord_count, omi_chord)
                --Show_To_Dev("omichord = " .. omi_chord .. string.char(10) )
                omi_inmarker = false
                omi_inchord = false
                omi_chord = ""
            elseif string.sub(omi_import_text, i, i) == " " and omi_inmarker == true and omi_inchord == false then
                -- "<" TRIGGERING START OF A MARKER
                omi_inchord = false
                omi_chord = omi_chord .. string.sub(omi_import_text, i, i)
            elseif string.sub(omi_import_text, i, i) == "<" then
                -- ">" TRIGGERING END OF A MARKER
                omi_inchord = false
                omi_inmarker = true
                omi_chord = omi_chord .. string.sub(omi_import_text, i, i)
            elseif string.sub(omi_import_text, i, i) == ">" then
                -- OTHER CHARACTERS IN THE MIDDLE OF A CHORD
                omi_inmarker = false
                omi_inchord = true
            else
                if omi_inmarker == false then
                    omi_inchord = true
                end
                omi_chord = omi_chord .. string.sub(omi_import_text, i, i)
            end
        end
        if omi_inchord == true then
            chord_count = chord_count + 1
            table.insert(omi_chord_table, chord_count, omi_chord)
            --Show_To_Dev("omichord = " .. omi_chord .. string.char(10) )
            omi_inchord = false
            omi_chord = ""
        end
        for i, v in pairs(omi_chord_table) do
            --Show_To_Dev(v .. string.char(10))
            onemotionimport = onemotionimport .. v .. string.char(10)
            local beatcountlen = 0
            alldone = false
            for j = 1, string.len(v), 1 do
                if tonumber(string.sub(v, j, j)) ~= nil and alldone == false then
                    beatcountlen = beatcountlen + 1
                else
                    alldone = true
                end
            end
            if beatcountlen > 0 then
                --Show_To_Dev("number of beats = " .. string.sub(v, 1, beatcountlen) .. " ")
                omi_beats = string.sub(v, 1, beatcountlen)
                if string.sub(v, beatcountlen + 1, string.len(v)) == "Rest" then
                    --Show_To_Dev("type = Rest" .. string.char(10) )
                    omi_root = "-"
                    final_omi_numeric_root = omi_root
                    omi_real_root = false
                    omi_type = ""
                elseif
                    string.sub(v, beatcountlen + 2, beatcountlen + 2) == "#" or
                        string.sub(v, beatcountlen + 2, beatcountlen + 2) == "b"
                 then
                    omi_root = string.sub(v, beatcountlen + 1, beatcountlen + 2)
                    omi_real_root = true
                    --Show_To_Dev("root = " .. string.sub(v, beatcountlen + 1, beatcountlen + 2) .. " " )

                    if beatcountlen + 3 > string.len(v) then
                        --Show_To_Dev("type = " .. string.char(10) )
                        omi_type = ""
                    else
                        --Show_To_Dev("type = " .. musictheory.from_onemotion_translation[string.sub(v, beatcountlen + 3, string.len(v))] .. string.char(10) )
                        omi_type =
                            musictheory.from_onemotion_translation[string.sub(v, beatcountlen + 3, string.len(v))]
                    end
                else
                    omi_root = string.sub(v, beatcountlen + 1, beatcountlen + 1)
                    omi_real_root = true
                    --Show_To_Dev("root = " .. string.sub(v, beatcountlen + 1, beatcountlen + 1) .. " " )
                    if beatcountlen + 2 > string.len(v) then
                        --Show_To_Dev("type = " .. string.char(10) )
                        omi_type = ""
                    else
                        --Show_To_Dev("type = " .. musictheory.from_onemotion_translation[string.sub(v, beatcountlen + 2, string.len(v))] .. string.char(10) )
                        omi_type =
                            musictheory.from_onemotion_translation[string.sub(v, beatcountlen + 2, string.len(v))]
                    end
                end
            elseif beatcountlen == 0 and string.sub(v, 1, 1) == "<" then
                --Show_To_Dev("something else = " .. '>"' .. string.sub(v, 2, -1) .. '"}' .. string.char(10) )
                omi_beats = 0
                omi_root = '{"' .. string.sub(v, 2, -1) .. '"}'
                final_omi_numeric_root = omi_root
                omi_type = "marker"
                omi_real_root = false
            end
            if omi_real_root == true then
                omi_key_is_flat = musictheory.is_it_flat_table[omi_root]
                omi_root_value = musictheory.key_table[omi_root]
                omi_root_shift = musictheory.key_table[import_key]
                omi_combo_shift = omi_root_value - omi_root_shift
                if omi_combo_shift > 24 then
                    omi_combo_shift = omi_combo_shift - 24
                elseif omi_combo_shift > 12 then
                    omi_combo_shift = omi_combo_shift - 12
                elseif omi_combo_shift < 0 then
                    omi_combo_shift = omi_combo_shift + 12
                end
                --Show_To_Dev("root = " .. omi_root_value .. " shift value = " .. omi_root_shift .. " combo = " .. omi_combo_shift .. string.char(10))

                final_omi_numeric_root = musictheory.reverse_root_table[omi_combo_shift]
            end

            table.insert(omi_parsed_table, i, {omi_beats, final_omi_numeric_root, omi_type})

            onemotionimport =
                swaptext ..
                string.char(10) ..
                    "________________________________________________________________" ..
                        string.char(10) ..
                            "Imported Onemotion.com Chord Player progression from clipboard..." ..
                                string.char(10) ..
                                    "________________________________________________________________" ..
                                        string.char(10)
            oim_in_measure = false
            oim_beats_thus_far = 0
            oim_measures_in_clump = 0
            oim_measures_per_line = 0
            for i, v in pairs(omi_parsed_table) do
                oim_current_beats = tonumber(v[1])
                if oim_current_beats == 0 then
                    onemotionimport = onemotionimport .. string.char(10) .. string.char(10) .. v[2] .. string.char(10)
                else
                    ::doagain::
                    if oim_beats_thus_far == 0 and oim_current_beats > 0 then
                        if oim_current_beats > 4 then
                            oim_measures_per_line = oim_measures_per_line + 1
                            if oim_measures_per_line < 4 then
                                onemotionimport = onemotionimport .. v[2] .. v[3] .. "\t\t\t\t"
                            else
                                onemotionimport = onemotionimport .. v[2] .. v[3] .. "\t\t\t\t" .. string.char(10)
                                oim_measures_per_line = 0
                            end
                            oim_current_beats = oim_current_beats - 4
                            goto doagain
                        elseif oim_current_beats == 4 then
                            oim_measures_per_line = oim_measures_per_line + 1
                            if oim_measures_per_line < 4 then
                                onemotionimport = onemotionimport .. v[2] .. v[3] .. "\t\t\t\t"
                            else
                                onemotionimport = onemotionimport .. v[2] .. v[3] .. "\t\t\t\t" .. string.char(10)
                                oim_measures_per_line = 0
                            end
                            oim_current_beats = 0
                        elseif oim_current_beats < 4 then
                            onemotionimport = onemotionimport .. "[" .. oim_current_beats .. "(" .. v[2] .. v[3] .. ") "
                            oim_beats_thus_far = oim_current_beats
                        end
                    elseif oim_beats_thus_far + oim_current_beats < 4 then
                        oim_beats_thus_far = oim_current_beats + oim_beats_thus_far
                        onemotionimport = onemotionimport .. oim_current_beats .. "(" .. v[2] .. v[3] .. ") "
                    elseif oim_beats_thus_far + oim_current_beats == 4 then
                        oim_beats_thus_far = 0
                        onemotionimport = onemotionimport .. oim_current_beats .. "(" .. v[2] .. v[3] .. ") "
                        oim_measures_per_line = oim_measures_per_line + 1
                        if oim_measures_per_line < 4 then
                            onemotionimport = onemotionimport .. "]\t\t\t"
                        else
                            onemotionimport = onemotionimport .. "]\t\t\t" .. string.char(10)
                            oim_measures_per_line = 0
                        end
                        oim_current_beats = 0
                    else
                        if oim_beats_thus_far + oim_current_beats > 4 then
                            needed_beats = 4 - oim_beats_thus_far
                            oim_measures_per_line = oim_measures_per_line + 1
                            if oim_measures_per_line < 4 then
                                onemotionimport = onemotionimport .. needed_beats .. "(" .. v[2] .. v[3] .. ")]\t\t"
                            else
                                onemotionimport =
                                    onemotionimport .. needed_beats .. "(" .. v[2] .. v[3] .. ")]" .. string.char(10)
                            end

                            oim_current_beats = oim_current_beats - needed_beats
                            oim_beats_thus_far = 0
                            goto doagain
                        end
                    end
                end
            end
        end
    end

    --reaper.ImGui_SetClipboardText(ctx, onemotionimport)
    reaper.PreventUIRefresh(-1)
end

function letters_to_numbers(keysig, letters)
    reaper.PreventUIRefresh(1) -- turn off screen updates so script can go faster
    if musictheory.is_it_flat_table[keysig] ~= nil then -- double check a valid major key has been entered
        numbers_result = letters
        for k, v in pairs(musictheory.conflict_table) do -- temporarily replace chords name parts with musical alphabet letters like add2 so no confusion with A or D chords
            numbers_result = string.gsub(numbers_result, k, v)
        end
        key_number = musictheory.key_table[keysig] -- for example in Ab key_number = 8
        for i, v in pairs(musictheory.full_letter_list_set) do
            currentletter = v[1] -- go through every possible musical alphabet letter name ie, A, A#, Ab etc.
            --reaper.ShowConsoleMsg(currentletter.."\n")
            shifted_key_number = v[2] - key_number -- letter shift from C
            --reaper.ShowConsoleMsg("v[2] = " .. v[2].. " - key number " .. key_number .. " = " .. shifted_key_number .. "\n")
            if v[2] - key_number < 0 then
                shifted_key_number = (v[2] - key_number) + 12
            end -- shift up an octave if needed
            replacing_number = musictheory.reverse_root_table[shifted_key_number] -- look up the numeric root now that the key shift and individual note shift are known
            numbers_result = string.gsub(numbers_result, currentletter, replacing_number) -- swap out the name (like C) for the number (like 1)
        end
        for k, v in pairs(musictheory.reverse_conflict_table) do
            numbers_result = string.gsub(numbers_result, k, v) -- put back the chords name parts with musical alphabet letters like add2
        end
        ::tidy::
        slenght = string.len(numbers_result)
        numbers_result = string.gsub(numbers_result, "  ", " ")
        numbers_result = string.gsub(numbers_result, string.char(10) .. " ", string.char(10))
        if string.len(numbers_result) ~= slenght then
            goto tidy
        end
        slenght = string.len(numbers_result)
        numbers_result = string.gsub(numbers_result, " ", "    ")
    else
        numbers_result =
            "You must first enter a valid key signature.\nUse a major key!\n\nWhen the key is minor, Nashville Numbers generally indicate the \nrelative minor and focus on 6m as the key center."
    end
    reaper.PreventUIRefresh(-1)
    return numbers_result
end

function Get_Pulsing_Color(rgb_table, pulse_val)
    -- We ignore pulse_val here so the background stays solid and beautiful!
    return reaper.ImGui_ColorConvertDouble4ToU32(
        rgb_table[1] / 255.0,
        rgb_table[2] / 255.0,
        rgb_table[3] / 255.0,
        1.0
    )
end


function play_button_midi(v_in, play_root_in)
    local btn_label = play_root_in .. v_in[2]
    local clean_name = v_in[2]:gsub("%s+", "")
    
    -- Detect if it's a popular diatonic chord (to draw the glowing border)
    local is_popular = false
    if not reaper.ImGui_IsKeyDown(ctx, reaper.ImGui_Mod_Shift()) then
        if (play_root_in == "1" and clean_name == "") or
           (play_root_in == "4" and clean_name == "") or
           (play_root_in == "5" and clean_name == "") or
           (play_root_in == "2" and clean_name == "m") or
           (play_root_in == "3" and clean_name == "m") or
           (play_root_in == "6" and clean_name == "m") then
            is_popular = true
        end
    end
    
    -- Push the pulsing white border (Thickness increased to 3.0)
    if is_popular then
        reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_FrameBorderSize(), 3.0)
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Border(), reaper.ImGui_ColorConvertDouble4ToU32(1, 1, 1, transpar or 0.8))
    end
    
    -- Draw the Button
    r.ImGui_Button(ctx, btn_label, wx, hx)
    
    -- Pop border styles
    if is_popular then
        reaper.ImGui_PopStyleColor(ctx, 1)
        reaper.ImGui_PopStyleVar(ctx, 1)
    end
    
    -- MOUSE DOWN (Start playing & add to chart)
    if r.ImGui_IsItemActivated(ctx) then
        local is_ctrl_down = reaper.ImGui_IsKeyDown(ctx, reaper.ImGui_Mod_Ctrl())
        if is_ctrl_down then
            chord_charting_area = chord_charting_area .. play_root_in .. clean_name .. "  "
        end

        play_root = play_root_in
        last_play_root = play_root_in
        local this_type = (v_in[1] == "") and "z" or v_in[1]
        current_playing_tone_array = musictheory.type_table[this_type] or v_in[3]
        
        local root_val = musictheory.root_table[play_root] or 0
        local total_shift = (root_val + audition_key_shift) % 12
        
        if audition_track and reaper.ValidatePtr(audition_track, "MediaTrack*") then
            reaper.SetMediaTrackInfo_Value(audition_track, "B_MUTE", 0)
        end
        
        for _, v in pairs(current_playing_tone_array) do
            -- Invert upper voices tightly
            local pitch = (v + total_shift > 10) and (60 + total_shift + v - 12) or (60 + total_shift + v)
            reaper.StuffMIDIMessage(0, 144, pitch, 111)
            
            -- Doubled heavy bass notes (-12 and -24)
            if v == 0 then 
                reaper.StuffMIDIMessage(0, 144, pitch - 12, 115) 
                reaper.StuffMIDIMessage(0, 144, pitch - 24, 120) 
            end
        end
    end
    
    -- MOUSE UP (Stop playing notes)
    if r.ImGui_IsItemDeactivated(ctx) then
        local root_val = musictheory.root_table[play_root_in] or 0
        local total_shift = (root_val + audition_key_shift) % 12
        
        for _, v in pairs(current_playing_tone_array) do
            local pitch = (v + total_shift > 10) and (60 + total_shift + v - 12) or (60 + total_shift + v)
            reaper.StuffMIDIMessage(0, 128, pitch, 0)
            
            -- Turn off both bass notes
            if v == 0 then 
                reaper.StuffMIDIMessage(0, 128, pitch - 12, 0)
                reaper.StuffMIDIMessage(0, 128, pitch - 24, 0) 
            end
        end
        
        if audition_track and reaper.ValidatePtr(audition_track, "MediaTrack*") then
            reaper.SetMediaTrackInfo_Value(audition_track, "B_MUTE", 1)
        end
    end
end

function Export_OM()
    OM_ex_warning = ""
    reaper.PreventUIRefresh(1)
    the_last_ccc_bar_content = "" -- CLEAR OUT THE OLD AND SET UP THE SHELL FOR THE NEW DATA
    _, ckey_startso = string.find(header_area, "Key: ")
    ckey_endso, _ = string.find(header_area, "Swing:")
    _, cbpm_startso = string.find(header_area, "BPM: ")
    cbpm_endso, _ = string.find(header_area, "Key:")
    cbpmfound = string.sub(header_area, cbpm_startso + 1, cbpm_endso - 2)
    ckeyfound = string.sub(header_area, ckey_startso + 1, ckey_endso - 2)
    theresultofprocessOMbars = Process_OM_bars()
    --if cancel_OM_opperation == true then
    --  onemotionoutput = the_OM_fail
    --  else
    onemotionoutput = theresultofprocessOMbars
    --end
    reaper.PreventUIRefresh(-1)
end

-- ==============================================================================

---------------------------------------------------------Chordsheet Com Create SUB FOR PROCESSESSING ALL THE BARS
-- \\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\

function Process_OM_bars()
    local processmore_OM_table = {}
    local insubdepth = 0
    local inmeasurenow = false -- !!!!!!!!!!!!!!!!   GET THE DATA READY TO BE PUT INTO TABLES ONE CHAR AT A TIME  !!!!!!
    cancel_OM_opperation = false
    the_OM_fail = ""
    OM_ex_warning = ""
    measurechord_count = 0
    OM_rebuild = ""
    local safe_header = Normalize_Form_Line(header_area)
    unfolded_OM_data, error_zone = form.process_the_form(header_area, chord_charting_area)
    unfolded_OM_data = inital_swaps(unfolded_OM_data)

    --make chord list protected by swaping chord for &chord&
    OM_swaplist = {
        {"<<", "~"},
        {",", "  "},
        {";", "  "},
        {"%^%^", "~"},
        {"%^", " <"},
        {"%$", ""},
        {"\n", "  "},
        {"\t", "  "},
        {"  ", " "},
        {"%]%[", "] ["},
        {"%[ ", "["},
        {" %]", "]"},
        {" %- ", " $r$ "},
        {" R ", " $r$ "},
        {" r ", " $r$ "},
        {"%( ", "("},
        {"%)  ", ") "},
        {" %)", ")"},
        {"J", "majorJ"},
        {"majorJ", "j"},
        {"Maj", "major"},
        {"MAJ", "major"},
        {"major", "maj"},
        {"Sus", "sustained"},
        {"SUS", "sustained"},
        {"sustained", "sus"},
        {"Add", "Addition"},
        {"ADD", "Addition"},
        {"Addition", "add"},
        {"Aug", "Augmented"},
        {"AUG", "Augmented"},
        {"Augmented", "aug"},
        {"Dim", "diminished"},
        {"DIM", "diminished"},
        {"diminished", "dim"},
        {"Hdim", "hdim"},
        {"HDIM", "hdim"},
        {"M", "minor"},
        {"minor", "m"}
    }

    stuff_to_purge_from_chords = {
        ["A"] = 1,
        ["B"] = 1,
        ["C"] = 1,
        ["D"] = 1,
        ["E"] = 1,
        ["F"] = 1,
        ["G"] = 1,
        ["I"] = 1,
        ["K"] = 1,
        ["L"] = 1,
        ["M"] = 1,
        ["N"] = 1,
        ["O"] = 1,
        ["P"] = 1,
        ["Q"] = 1,
        ["R"] = 1,
        ["S"] = 1,
        ["T"] = 1,
        ["V"] = 1,
        ["W"] = 1,
        ["Y"] = 1,
        ["Z"] = 1,
        ["c"] = 1,
        ["e"] = 1,
        ["f"] = 1,
        ["k"] = 1,
        ["l"] = 1,
        ["p"] = 1,
        ["q"] = 1,
        ["t"] = 1,
        ["v"] = 1,
        ["w"] = 1,
        ["y"] = 1,
        ["z"] = 1,
        ["@"] = 1,
        ["&"] = 1,
        ["*"] = 1,
        ['"'] = 1,
        ["'"] = 1,
        ["`"] = 1
    }

    unfolded_OM_data = string.gsub(unfolded_OM_data, "%)", ") ")
    unfolded_OM_data = Swapout(unfolded_OM_data, OM_swaplist)

    for i = 1, string.len(unfolded_OM_data) do
        if cancel_OM_opperation == true then
            the_OM_fail = 'Subdivision close ")" found without first being opened with "(".\n'
            cancel_OM_opperation = true
            break
        elseif string.sub(unfolded_OM_data, i, i) == "{" and inmarker == true then -- WARN WHEN THERE IS A {{ USER ERROR
            the_OM_fail = 'Don\'t use a "{" until you first close off the marker you are in.\n'
            cancel_OM_opperation = true
            break
        elseif string.sub(unfolded_OM_data, i, i) == "}" and inmarker == false then -- WARN WHEN THERE IS A LONE } USER ERROR
            the_OM_fail = 'Marker closer "}" found without a previous marker starter "{".\n'
            cancel_OM_opperation = true
            break
        elseif string.sub(unfolded_OM_data, i, i) == "{" and inmeasurenow == true then -- WARN WHEN THERE IS A { in measure USER ERROR
            the_OM_fail = 'You should not use "{" in the middle of a measure.\n'
            cancel_OM_opperation = true
            break
        elseif string.sub(unfolded_OM_data, i, i) == "}" and inmeasurenow == true then -- WARN WHEN THERE IS A } in measure USER ERROR
            the_OM_fail = 'You should not use "}" in the middle of a measure.\n'
            cancel_OM_opperation = true
            break
        elseif string.sub(unfolded_OM_data, i, i) == "[" and inmeasurenow == true then -- WARN WHEN THERE IS A ]] USER ERROR
            the_OM_fail = 'Incident of mismatched braces.  Make sure to use "[" and "]" in pairs.\n'
            cancel_OM_opperation = true
            break
        elseif string.sub(unfolded_OM_data, i, i) == "]" and inmeasurenow == false then -- WARN WHEN THERE IS A [[ USER ERROR
            the_OM_fail = 'Incident of mismatched braces.  Make sure to use "[" and "]" in pairs.\n'
            cancel_OM_opperation = true
            break
        elseif string.sub(unfolded_OM_data, i, i) == "(" and inmeasurenow == false then -- WARN WHEN THERE IS A ( in a measure USER ERROR
            the_OM_fail = 'Subdivisions marked with "(" should only occur in measure markers "[  ]".\n'
            cancel_OM_opperation = true
            break
        elseif string.sub(unfolded_OM_data, i, i) == ")" and inmeasurenow == false then -- WARN WHEN THERE IS A ) in a measure USER ERROR
            the_OM_fail = 'Subdivisions closings marked with ")" should only occur in within measure markers "[  ]".\n'
            cancel_OM_opperation = true
            break
        elseif string.sub(unfolded_OM_data, i, i) == ")" and inmeasurenow == true and inmarker == false then
            OM_rebuild = OM_rebuild .. ")" -- CHANGE IN MEASURE SEPS TO COLON
            if insubdepth == 0 then
                the_OM_fail = 'Subdivision close ")" found without first being opened with "(".\n'
                cancel_OM_opperation = true
            else
                insubdepth = insubdepth - 1
            end
        elseif string.sub(unfolded_OM_data, i, i) == "(" and inmeasurenow == true and inmarker == false then
            OM_rebuild = OM_rebuild .. "(" -- CHANGE IN MEASURE SEPS TO COLON
            insubdepth = insubdepth + 1
        elseif insubdepth < 0 then -- WARN WHEN THERE IS A ]] USER ERROR
            the_OM_fail = the_OM_fail .. 'Incident of mismatched parentensis.  Make sure to use "(" and ")" in pairs.\n'
            cancel_OM_opperation = true
            break
        elseif string.sub(unfolded_OM_data, i, i) == "{" then
            inmarker = true
            OM_rebuild = OM_rebuild .. string.sub(unfolded_OM_data, i, i) -- OM_rebuild WITH IN BRACE AS IS (UNLESS...)
        elseif string.sub(unfolded_OM_data, i, i) == "}" then
            inmarker = false
            OM_rebuild = OM_rebuild .. string.sub(unfolded_OM_data, i, i) -- OM_rebuild WITH IN BRACE AS IS (UNLESS...)
        elseif string.sub(unfolded_OM_data, i, i) == "[" and inmeasurenow == false then
            inmeasurenow = true
            OM_rebuild = OM_rebuild .. string.sub(unfolded_OM_data, i, i) -- OM_rebuild WITH IN BRACE AS IS (UNLESS...)
        elseif string.sub(unfolded_OM_data, i, i) == "]" and inmeasurenow == true then
            inmeasurenow = false
            OM_rebuild = OM_rebuild .. string.sub(unfolded_OM_data, i, i) -- OM_rebuild WITH OUT BRACE AS IS (UNLESS...)
        elseif
            string.sub(unfolded_OM_data, i, i) == " " and inmeasurenow == false and inmarker == false and
                insubdepth == 0
         then
            OM_rebuild = OM_rebuild .. "," -- CHANGE MEASURE SEPARATORS TO COMMA
        elseif
            string.sub(unfolded_OM_data, i, i) == " " and inmeasurenow == true and inmarker == false and insubdepth > 0
         then
            OM_rebuild = OM_rebuild .. ";"
        elseif
            string.sub(unfolded_OM_data, i, i) == " " and inmeasurenow == true and inmarker == false and insubdepth == 0
         then
            OM_rebuild = OM_rebuild .. ":" -- CHANGE IN MEASURE SEPS TO COLON
        else
            OM_rebuild = OM_rebuild .. string.sub(unfolded_OM_data, i, i) -- PASS EVERYTHING ELSE AS IS
        end
    end

    inmarkernow = false
    OM_rebuild2 = ""
    for i = 1, string.len(OM_rebuild) do
        current_singleOMchar = string.sub(OM_rebuild, i, i)
        if current_singleOMchar == "{" then
            inmarkernow = true
            OM_rebuild2 = OM_rebuild2 .. current_singleOMchar
        elseif current_singleOMchar == "}" then
            inmarkernow = false
            OM_rebuild2 = OM_rebuild2 .. current_singleOMchar
        elseif stuff_to_purge_from_chords[current_singleOMchar] == nil then
            OM_rebuild2 = OM_rebuild2 .. current_singleOMchar -- PASS EVERYTHING ELSE AS IS
        elseif inmarkernow == true then
            OM_rebuild2 = OM_rebuild2 .. current_singleOMchar -- PASS EVERYTHING ELSE AS IS
        else
        end
    end

    --reaper.ShowConsoleMsg(unfolded_OM_data.. "\n")
    --reaper.ShowConsoleMsg(OM_rebuild.. "\n")
    --reaper.ShowConsoleMsg("THE FAIL: " .. the_OM_fail.. "\n")

    OM_main_bars_table = Split(OM_rebuild2, ",") -- PUT THE DATA INTO TABLE
    OM_rebuild = "" -- clear memory
    OM_rebuild2 = "" -- clear memory
    unfolded_OM_data = "" -- clear memory

    -----
    for iOM, vOM in pairs(OM_main_bars_table) do --  !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!    DETERMINE IF MULTIBAR !!!!!!!!!!
        if vOM ~= nil and vOM ~= "" then
            if string.find(vOM, "%[") then
                processmore_OM_table[iOM] = {true, 1} -- TAG AS MULTIBAR IN this TABLE
            elseif string.find(vOM, "{") then
                processmore_OM_table[iOM] = {false, 0} -- A) SECTION HEADER - NOT A MEASURE
            else
                processmore_OM_table[iOM] = {false, 1}
                OM_main_bars_table[iOM] = OM_main_bars_table[iOM] -- TAG AS A SINGLE BAR
            end
        end
    end
    -----

    -----------------
    for iOMpm, vOMpm in pairs(processmore_OM_table) do
        OM_start_brace_pos, _ = string.find(OM_main_bars_table[iOMpm], "%[")
        if OM_start_brace_pos ~= nil and OM_start_brace_pos > 1 then
            should_be_multiple = string.sub(OM_main_bars_table[iOMpm], 1, OM_start_brace_pos - 1)
            if "number" == type(tonumber(should_be_multiple)) then
                --reaper.ShowConsoleMsg(tostring(should_be_multiple) .. "\n")
                processmore_OM_table[iOMpm][2] = tonumber(should_be_multiple)
            else
                processmore_OM_table[iOMpm][2] = 1
                the_OM_fail = the_OM_fail .. 'Only numbers should preceed the "[" symbol.'
            end
            OM_main_bars_table[iOMpm] =
                string.sub(OM_main_bars_table[iOMpm], OM_start_brace_pos + 1, string.len(OM_main_bars_table[iOMpm]) - 1)
        elseif OM_start_brace_pos ~= nil and OM_start_brace_pos == 1 then
            OM_main_bars_table[iOMpm] =
                string.sub(OM_main_bars_table[iOMpm], OM_start_brace_pos + 1, string.len(OM_main_bars_table[iOMpm]) - 1)
        end
        _, OM_bar_chord_count = string.gsub(OM_main_bars_table[iOMpm], ":", "")
        processmore_OM_table[iOMpm][3] = OM_bar_chord_count + 1
        processmore_OM_table[iOMpm][4] = Split(OM_main_bars_table[iOMpm], ":")
    end

    -----------------
    cyclecount = 0
    ::run_an_unfolding_cycle::

    nextlayer_table = {}
    nextlayer_table_elem_count = 0
    timesignature = 4
    OMfalsesofar = 0
    tablerecords = ""
    chordchunk = {}
    for i1, tablerecords in pairs(processmore_OM_table) do
        right_now_table = {}
        if tablerecords[1] == false and tablerecords[2] == 0 then -- NO MEASURE MARKER ONLY
            -- COULD DO THE SECTION SWAPOUTS RIGHT HERE
            nextlayer_table_elem_count = nextlayer_table_elem_count + 1
            nextlayer_table[nextlayer_table_elem_count] = {
                processmore_OM_table[i1][1],
                processmore_OM_table[i1][2],
                nextlayer_table_elem_count,
                processmore_OM_table[i1][4]
            }
        elseif tablerecords[1] == false and tablerecords[2] > 0 then -- SINGLE CHORD
            nextlayer_table_elem_count = nextlayer_table_elem_count + 1
            nextlayer_table[nextlayer_table_elem_count] = {
                processmore_OM_table[i1][1],
                processmore_OM_table[i1][2],
                nextlayer_table_elem_count,
                processmore_OM_table[i1][4]
            }
        elseif tablerecords[1] == true then
            divtotal = 0
            for i2, chordchunk in pairs(tablerecords[4]) do --  PROCESS EACH CHORD CHUNK
                --reaper.ShowConsoleMsg("chunk: " .. chordchunk .." -- \n")
                start_pos_OM_par, _ = string.find(chordchunk, "%(") -- LOOK IN THAT CHUNK FOR (
                if
                    start_pos_OM_par ~= nil and
                        type(tonumber(string.sub(chordchunk, 1, start_pos_OM_par - 1))) == "number"
                 then
                    --reaper.ShowConsoleMsg("start_pos_OM_par " .. start_pos_OM_par .." -- \n")   -- SHOW WHERE
                    divmult = tonumber(string.sub(chordchunk, 1, start_pos_OM_par - 1)) --  FOUND ANOTHER DIGIT
                elseif start_pos_OM_par ~= nil then -- FOUND DIVISION MULTI THAT ISN'T A NUMBER
                    --reaper.ShowConsoleMsg("USER ERROR DON'T PUT ANYTHING BUT NUMBERS " .. 'BY "("\n')
                    divmult = 1
                    local subdivOM = string.sub(chordchunk, 1, subdiv_numlength)
                else
                    --reaper.ShowConsoleMsg("THERE WAS NO MULTI\n")
                    divmult = 1
                end
                --reaper.ShowConsoleMsg("divmult = " .. divmult .. "\n")
                divtotal = divtotal + divmult
            end
            --reaper.ShowConsoleMsg("divtotal = " .. divtotal .. "\n")
            for i2, chordchunk in pairs(tablerecords[4]) do --  PROCESS EACH CHORD CHUNK
                start_pos_OM_par, _ = string.find(chordchunk, "%(") -- LOOK IN THAT CHUNK FOR (
                if
                    start_pos_OM_par ~= nil and
                        type(tonumber(string.sub(chordchunk, 1, start_pos_OM_par - 1))) == "number"
                 then
                    divmult = tonumber(string.sub(chordchunk, 1, start_pos_OM_par - 1)) --  FOUND ANOTHER DIGIT
                    nextlayer_table_elem_count = nextlayer_table_elem_count + 1
                    new_multi = (processmore_OM_table[i1][2] * divmult) / divtotal
                    revised_chunk = string.sub(chordchunk, start_pos_OM_par + 1, string.len(chordchunk) - 1)
                    start_pos_OM_inwardpar, _ = string.find(revised_chunk, "%(")
                    start_pos_OM_inwardsep, _ = string.find(revised_chunk, ";")
                    if start_pos_OM_inwardpar == nil and start_pos_OM_inwardsep == nil then
                        nextlayer_table[nextlayer_table_elem_count] = {
                            false,
                            new_multi,
                            nextlayer_table_elem_count,
                            {revised_chunk}
                        }
                    else
                        OMfalsesofar = OMfalsesofar + 1
                        revisedandcleaned = ""
                        local par_count_depth = 0
                        for iggie = 1, string.len(revised_chunk), 1 do
                            if par_count_depth < 0 then
                                --user error SEND MESSAGE !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
                            elseif string.sub(revised_chunk, iggie, iggie) == "(" then
                                newcharreplace = "("
                                par_count_depth = par_count_depth + 1
                            elseif string.sub(revised_chunk, iggie, iggie) == ")" then
                                newcharreplace = ")"
                                par_count_depth = par_count_depth - 1
                            elseif string.sub(revised_chunk, iggie, iggie) == ";" and par_count_depth == 0 then
                                newcharreplace = ","
                            else
                                newcharreplace = string.sub(revised_chunk, iggie, iggie)
                            end
                            revisedandcleaned = revisedandcleaned .. newcharreplace
                        end
                        table_of_div_chunks = Split(revisedandcleaned, ",")
                        nextlayer_table[nextlayer_table_elem_count] = {true, new_multi, nextlayer_table_elem_count, {}}
                        for idc, vdc in pairs(table_of_div_chunks) do
                            nextlayer_table[nextlayer_table_elem_count][4][idc] = vdc
                        end
                    end
                elseif start_pos_OM_par ~= nil then -- FOUND DIVISION MULTI THAT ISN'T A NUMBER
                    nextlayer_table_elem_count = nextlayer_table_elem_count + 1
                    new_multi = processmore_OM_table[i1][2] / divtotal
                    revised_chunk = string.sub(chordchunk, start_pos_OM_par + 1, string.len(chordchunk) - 1)
                    start_pos_OM_inwardpar, _ = string.find(revised_chunk, "%(")
                    start_pos_OM_inwardsep, _ = string.find(revised_chunk, ";")
                    if start_pos_OM_inwardpar == nil and start_pos_OM_inwardsep == nil then
                        nextlayer_table[nextlayer_table_elem_count] = {
                            false,
                            new_multi,
                            nextlayer_table_elem_count,
                            {revised_chunk}
                        }
                    else
                        -- ALERT USER THAT INPUT IS MESSED UP
                        OMfalsesofar = OMfalsesofar + 1
                        revisedandcleaned = ""
                        local par_count_depth = 0
                        for iggie = 1, string.len(revised_chunk), 1 do
                            if par_count_depth < 0 then
                                --user error SEND MESSAGE !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
                            elseif string.sub(revised_chunk, iggie, iggie) == "(" then
                                newcharreplace = "("
                                par_count_depth = par_count_depth + 1
                            elseif string.sub(revised_chunk, iggie, iggie) == ")" then
                                newcharreplace = ")"
                                par_count_depth = par_count_depth - 1
                            elseif string.sub(revised_chunk, iggie, iggie) == ";" and par_count_depth == 0 then
                                newcharreplace = ","
                            else
                                newcharreplace = string.sub(revised_chunk, iggie, iggie)
                            end
                            revisedandcleaned = revisedandcleaned .. newcharreplace
                        end
                        table_of_div_chunks = Split(revisedandcleaned, ",")
                        nextlayer_table[nextlayer_table_elem_count] = {true, new_multi, nextlayer_table_elem_count, {}}
                        for idc, vdc in pairs(table_of_div_chunks) do
                            nextlayer_table[nextlayer_table_elem_count][4][idc] = vdc
                        end
                    end
                else
                    nextlayer_table_elem_count = nextlayer_table_elem_count + 1
                    new_multi = processmore_OM_table[i1][2] / divtotal
                    nextlayer_table[nextlayer_table_elem_count] = {
                        false,
                        new_multi,
                        nextlayer_table_elem_count,
                        {processmore_OM_table[i1][4][i2]}
                    }
                end
            end
        end
        --reaper.ShowConsoleMsg(nextlayer_table_elem_count .. ' - ' .. tostring(nextlayer_table[nextlayer_table_elem_count][4]) .. "\n")
    end

    if OMfalsesofar > 0 then
        cyclecount = cyclecount + 1

        --reaper.ShowConsoleMsg("-------CYCLE COUNT = ------" .. cyclecount ..  "-------PM------\n")
        --table_printed_strings = Table_Print(processmore_OM_table)
        --reaper.ShowConsoleMsg(table_printed_strings)
        --reaper.ShowConsoleMsg("---------------------------NL----------\n")
        --table_printed_strings = Table_Print(nextlayer_table)
        --reaper.ShowConsoleMsg(table_printed_strings)

        processmore_OM_table = {}
        processmore_OM_table = nextlayer_table
        nextlayer_table = {}

        goto run_an_unfolding_cycle
    else
        borrow_time = 0

        for ice = nextlayer_table_elem_count, 1, -1 do
            if (nextlayer_table[ice][2] * 4) - borrow_time > 0 then
                nextlayer_table[ice][2] = (nextlayer_table[ice][2] * 4) - borrow_time
            else
                -- message to user about problem
            end
            if string.sub(nextlayer_table[ice][4][1], 1, 1) == "~" and nextlayer_table_elem_count > 1 then
                borrow_time = .5
                nextlayer_table[ice][2] = nextlayer_table[ice][2] + borrow_time
                nextlayer_table[ice][4][1] =
                    string.sub(nextlayer_table[ice][4][1], 2, string.len(nextlayer_table[ice][4][1]))
            elseif string.sub(nextlayer_table[ice][4][1], 1, 1) == "<" and nextlayer_table_elem_count > 1 then
                borrow_time = .25
                nextlayer_table[ice][2] = nextlayer_table[ice][2] + borrow_time
                nextlayer_table[ice][4][1] =
                    string.sub(nextlayer_table[ice][4][1], 2, string.len(nextlayer_table[ice][4][1]))
            elseif string.sub(nextlayer_table[ice][4][1], 1, 1) == "~" and nextlayer_table_elem_count == 1 then
                -- message to user about problem
            elseif string.sub(nextlayer_table[ice][4][1], 1, 1) == "<" and nextlayer_table_elem_count == 1 then
                -- message to user about problem
            else
                borrow_time = 0
            end
        end

        cyclecount = cyclecount + 1
        --reaper.ShowConsoleMsg("-----LAST CYCLE COUNT = ---" .. cyclecount ..  "------PM-------\n")
        --table_printed_strings = Table_Print(processmore_OM_table)
        --reaper.ShowConsoleMsg(table_printed_strings)
        --reaper.ShowConsoleMsg("-----------------------------NL--------\n")
        --table_printed_strings = Table_Print(nextlayer_table)
        --reaper.ShowConsoleMsg(table_printed_strings)

        theresultofprocessOMbars = ""
        OM_swaplist2 = {
            {"%$r%$", "rest"},
            {"{", " <"},
            {"}", "> "},
            {"> ", ">"},
            {" <", "<"}
        }

        if musictheory.key_table[ckeyfound] ~= nil then
            --reaper.ShowConsoleMsg("Keyshift = " .. keyshifter_OM .. " Is flat is " .. tostring(isitflat) .. "\n")
            keyshifter_OM = musictheory.key_table[ckeyfound]
            isitflat = musictheory.is_it_flat_table[ckeyfound]
        else
            -- message and cancel
            --reaper.ShowConsoleMsg("was nil\n")
        end
        for iome = 1, nextlayer_table_elem_count, 1 do
            the_itemOM = nextlayer_table[iome][4][1]
            the_itemOM = Swapout(the_itemOM, OM_swaplist2)
            if string.sub(the_itemOM, 1, 1) == "b" or string.sub(the_itemOM, 1, 1) == "#" then
                da_root = string.sub(the_itemOM, 1, 2)
                da_rest = string.sub(the_itemOM, 3, string.len(the_itemOM))
            else
                da_root = string.sub(the_itemOM, 1, 1)
                da_rest = string.sub(the_itemOM, 2, string.len(the_itemOM))
            end

            if musictheory.root_table[da_root] ~= nil then
                combo_shift = musictheory.root_table[da_root] + keyshifter_OM
                if combo_shift > 23 then
                    combo_shift = combo_shift - 24
                elseif combo_shift > 11 then
                    combo_shift = combo_shift - 12
                elseif combo_shift < 0 then
                    combo_shift = combo_shift + 12
                else
                end
                if isitflat then
                    letter_r_root = musictheory.flats_table[combo_shift]
                else
                    letter_r_root = musictheory.sharps_table[combo_shift]
                end

                cob_start, cob_end = string.find(da_rest, "/")
                if cob_start ~= nil then
                    da_bass = string.sub(da_rest, cob_start + 1, string.len(da_rest))

                    if string.sub(da_bass, 1, 1) == "b" then
                        --reaper.ShowConsoleMsg("flat = " .. da_real_bass .. "\n")
                        da_real_bass = string.sub(da_bass, 1, 2)
                        da_pre_bass = string.sub(da_rest, 1, cob_start)
                    elseif string.sub(da_bass, 1, 1) == "#" then
                        --reaper.ShowConsoleMsg("sharp = " .. da_real_bass .. "\n")
                        da_real_bass = string.sub(da_bass, 1, 2)
                        da_pre_bass = string.sub(da_rest, 1, cob_start)
                    else
                        da_real_bass = string.sub(da_bass, 1, 1)
                        da_pre_bass = string.sub(da_rest, 1, cob_start)
                    end

                    if musictheory.root_table[da_real_bass] ~= nil then
                        combo_shift = musictheory.root_table[da_real_bass] + keyshifter_OM
                        if combo_shift > 23 then
                            combo_shift = combo_shift - 24
                        elseif combo_shift > 11 then
                            combo_shift = combo_shift - 12
                        elseif combo_shift < 0 then
                            combo_shift = combo_shift + 12
                        else
                        end
                        if isitflat then
                            letter_bass = musictheory.flats_table[combo_shift]
                        else
                            letter_bass = musictheory.sharps_table[combo_shift]
                        end

                        the_itemOM = letter_r_root .. da_pre_bass .. letter_bass
                    end
                else
                    the_itemOM = letter_r_root .. da_rest
                end
            else
                -- warn missing root
            end

            if nextlayer_table[iome][2] > 0 then
                fraction = Provide_Fraction(nextlayer_table[iome][2], 1)
                added_element = " " .. tostring(fraction) .. the_itemOM
            else
                added_element = " " .. the_itemOM
            end

            --reaper.ShowConsoleMsg(added_element .. "\n")
            theresultofprocessOMbars = theresultofprocessOMbars .. added_element
        end
    end
    theresultofprocessOMbars = cbpmfound .. "BPM " .. theresultofprocessOMbars

    return theresultofprocessOMbars
end

function export_ccc()
    ccc_ex_warning = ""
    ccc_export_area = ""
    reaper.PreventUIRefresh(1)
    the_last_ccc_bar_content = "" -- CLEAR OUT THE OLD AND SET UP THE SHELL FOR THE NEW DATA
    _, ctitle_startso = string.find(header_area, "Title: ") -- GET THE PROJECT SETTINGS AND PLACE IN THE SHELL
    ctitle_endso, _ = string.find(header_area, "Writer:")
    _, cwriter_startso = string.find(header_area, "Writer: ")
    cwriter_endso, _ = string.find(header_area, "BPM:")
    _, ckey_startso = string.find(header_area, "Key: ")
    ckey_endso, _ = string.find(header_area, "Swing:")
    _, cbpm_startso = string.find(header_area, "BPM: ")
    cbpm_endso, _ = string.find(header_area, "Key:")
    ctitlefound = string.sub(header_area, ctitle_startso + 1, ctitle_endso - 2)
    cwriterfound = string.sub(header_area, cwriter_startso + 1, cwriter_endso - 2)
    cbpmfound = string.sub(header_area, cbpm_startso + 1, cbpm_endso - 2)
    ckeyfound = string.sub(header_area, ckey_startso + 1, ckey_endso - 2)

    -- https://www.chordsheet.com/song/populate-new?title=Your%20Title&artist=Your%20Artist&chords=A%20B%20C%20D%20%0AA%20B%20C%20D&key=Bbm&bpm=96

    ctitlefound = urlencode(ctitlefound)
    cwriterfound = urlencode(cwriterfound)
    unencoded_keyfound = ckeyfound
    ckeyfound = urlencode(ckeyfound)
    cbpmfound = urlencode(cbpmfound)

    cccchords = process_ccc_bars()
    cccchords = urlencode(cccchords)

    if cccchords ~= "Error..." then
        ulink =
            "https://www.chordsheet.com/song/populate-new?title=" ..
            ctitlefound ..
                "&artist=" ..
                    cwriterfound .. "&chords=" .. cccchords .. "&key=" .. ckeyfound .. "&bpm=" .. cbpmfound .. "&nns=1"

        ccclink = ulink

        --Your%20Title&artist=Your%20Artist&chords=A%20B%20C%20D%20%0AA%20B%20C%20D&key=Bbm&bpm=96"'

        --reaper.ShowConsoleMsg(ccclink..'\n\n')
        ccc_renderd = true
    end
end

char_to_hex = function(c)
    return string.format("%%%02X", string.byte(c))
end

function urlencode(theurl)
    if theurl == nil then
        return
    end
    theurl = theurl:gsub("\n", "\r\n")
    theurl = theurl:gsub("([^%w _%%%-%.~])", char_to_hex)
    theurl = theurl:gsub(" ", "+")
    return theurl

    -- https://gist.github.com/liukun/f9ce7d6d14fa45fe9b924a3eed5c3d99
    -- ref: https://gist.github.com/ignisdesign/4323051
    -- ref: http://stackoverflow.com/questions/20282054/how-to-urldecode-a-request-uri-string-in-lua
    -- to encode table as parameters, see https://github.com/stuartpb/tvtropes-lua/blob/master/urlencode.lua
end

ccc_ex_warning = ""
---------------------------------------------------------Chordsheet Com Create SUB FOR PROCESSESSING ALL THE BARS
function process_ccc_bars()
    thefail = ""
    chord_charting_area = inital_swaps(chord_charting_area)
    local safe_header = Normalize_Form_Line(header_area)
    unfolded_ccc_data, error_zone = form.process_the_form(header_area, chord_charting_area)
    -- FORM     DEAL WITH UNFOLDING THE FORM
    unfolded_ccc_data = string.gsub(unfolded_ccc_data, "{", "=")

    unfolded_ccc_data = string.gsub(unfolded_ccc_data, "$}", "|")
    unfolded_ccc_data = string.gsub(unfolded_ccc_data, "%$", "")
    --unfolded_ccc_data = string.gsub(unfolded_ccc_data, "%%", "!Repeat!")
    -- CODE THE SIMPLEST AS A OR B SECTIONS DELETE THE REST

    --reaper.ShowConsoleMsg(unfolded_ccc_data.. "\n")

    ::striplabels:: -- REMOVE THE SECTION LABELS
    local in_num = string.len(unfolded_ccc_data)
    section_start, _ = string.find(unfolded_ccc_data, "=")
    _, section_end = string.find(unfolded_ccc_data, "|")
    if section_start ~= nil and section_end ~= nil and section_end > section_start then
    --reaper.ShowConsoleMsg("did find\n")
    --unfolded_ccc_data = string.gsub(unfolded_ccc_data, string.sub(unfolded_ccc_data,section_start,section_end) , "")
    --else
    --reaper.ShowConsoleMsg("didn't find\n")
    end
    if in_num ~= string.len(unfolded_ccc_data) then
        goto striplabels
    end

    -- CONVERT RETURNS TO SPACES

    ::flaten:: -- CONVERT RETURNS TO SPACES
    in_num = string.len(unfolded_ccc_data)
    unfolded_ccc_data = string.gsub(unfolded_ccc_data, "\n", " ")
    if in_num ~= string.len(unfolded_ccc_data) then
        goto flaten
    end

    ::detab:: -- CONVERT TABS TO SPACES
    in_num = string.len(unfolded_ccc_data)
    unfolded_ccc_data = string.gsub(unfolded_ccc_data, "\t", " ")
    if in_num ~= string.len(unfolded_ccc_data) then
        goto detab
    end
    -- TRIM DOWN TO SINGLE SPACES
    ::trimwhitespace::
    in_num = string.len(unfolded_ccc_data)
    unfolded_ccc_data = string.gsub(unfolded_ccc_data, "  ", " ")
    if in_num ~= string.len(unfolded_ccc_data) then
        goto trimwhitespace
    end

    ::reducecr:: -- ?? TRIM BACK RETURNS (didn't I do this)
    in_num = string.len(unfolded_ccc_data)
    unfolded_ccc_data = string.gsub(unfolded_ccc_data, "\n\n", "\n")
    if in_num ~= string.len(unfolded_ccc_data) then
        goto reducecr
    end

    ::fluffen:: -- SEPARATE BRACED MEASURES BY A SPACE
    in_num = string.len(unfolded_ccc_data)
    unfolded_ccc_data = string.gsub(unfolded_ccc_data, "%]%[", "] [")
    if in_num ~= string.len(unfolded_ccc_data) then
        goto fluffen
    end

    ::squish1:: -- TRIM OUT SPACES FROM INSIDE IN BRACES
    in_num = string.len(unfolded_ccc_data)
    unfolded_ccc_data = string.gsub(unfolded_ccc_data, "%[ ", "[")
    if in_num ~= string.len(unfolded_ccc_data) then
        goto squish1
    end

    ::squish2:: -- TRIM OUT SPACES FROM INSIDE OUT BRACES
    in_num = string.len(unfolded_ccc_data)
    unfolded_ccc_data = string.gsub(unfolded_ccc_data, " %]", "]")
    if in_num ~= string.len(unfolded_ccc_data) then
        goto squish2
    end

    ::derestrest:: -- CONVERT ALL REST TO Chordsheet REST 1.
    in_num = string.len(unfolded_ccc_data)
    unfolded_ccc_data = string.gsub(unfolded_ccc_data, " %- ", " rr ")
    unfolded_ccc_data = string.gsub(unfolded_ccc_data, " R ", " rr ")
    if in_num ~= string.len(unfolded_ccc_data) then
        goto derestrest
    end

    ::derest:: -- CONVERT ALL REST TO Chordsheet REST 1.
    in_num = string.len(unfolded_ccc_data)
    unfolded_ccc_data = string.gsub(unfolded_ccc_data, " rr ", " r ")
    if in_num ~= string.len(unfolded_ccc_data) then
        goto derest
    end

    local inmeasurenow = false -- !!!!!!!!!!!!!!!!   GET THE DATA READY TO BE PUT INTO TABLES ONE CHAR AT A TIME  !!!!!!
    measurechord_count = 0
    rebuild = ""
    for i = 1, string.len(unfolded_ccc_data) do
        if string.sub(unfolded_ccc_data, i, i) == "=" then
            rebuild = rebuild .. string.sub(unfolded_ccc_data, i, i) -- REBUILD WITH SECTION SWAP AS IS
            inmeasurenow = false
        elseif string.sub(unfolded_ccc_data, i, i) == "[" and inmeasurenow == false then
            inmeasurenow = true
            rebuild = rebuild .. string.sub(unfolded_ccc_data, i, i) -- REBUILD WITH IN BRACE AS IS (UNLESS...)
        elseif string.sub(unfolded_ccc_data, i, i) == "]" and inmeasurenow == true then
            inmeasurenow = false
            rebuild = rebuild .. string.sub(unfolded_ccc_data, i, i) -- REBUILD WITH OUT BRACE AS IS (UNLESS...)
        elseif string.sub(unfolded_ccc_data, i, i) == "]" and inmeasurenow == false then -- WARN WHEN THERE IS A [[ USER ERROR
            thefail = thefail .. 'Incident of mismatched braces.  Make sure to use "[" and "]" in pairs.\n'
        elseif string.sub(unfolded_ccc_data, i, i) == "[" and inmeasurenow == true then -- WARN WHEN THERE IS A ]] USER ERROR
            thefail = thefail .. 'Incident of mismatched braces.  Make sure to use "[" and "]" in pairs.\n'
        elseif string.sub(unfolded_ccc_data, i, i) == " " and inmeasurenow == false then
            rebuild = rebuild .. "," -- CHANGE MEASURE SEPARATORS TO COMMA
        elseif string.sub(unfolded_ccc_data, i, i) == " " and inmeasurenow == true then
            rebuild = rebuild .. ":" -- CHANGE IN MEASURE SEPS TO COLON
        else
            rebuild = rebuild .. string.sub(unfolded_ccc_data, i, i) -- PASS EVERYTHING ELSE AS IS
        end
    end
    ccc_main_bars_table = Split(rebuild, ",") -- PUT THE DATA INTO TABLE

    local warned = false -- PREPING VARIABLES
    local rewarned = false
    local newtablevalue = ""
    local processmore_table = {}
    local ccc_post_table_chord_data = ""

    for ib, vb in pairs(ccc_main_bars_table) do --  !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!    DETERMINE IF MULTIBAR !!!!!!!!!!
        if string.find(vb, "%[") then
            processmore_table[ib] = {true, 1} -- TAG AS MULTIBAR IN this TABLE
        elseif string.find(vb, "=") then
            processmore_table[ib] = {false, 0} -- A) SECTION HEADER - NOT A MEASURE
        else
            processmore_table[ib] = {false, 1} -- TAG AS A SINGLE BAR
        end
        --reaper.ShowConsoleMsg(tostring(processmore_table[ib][1]).."\n")
    end

    for ipm, vpm in pairs(processmore_table) do -- !!!!!!!!!!!!!!!!!!!!!!!!!!!!!    DEAL WITH ALL THE MULTIBARS     !!!!!!!
        barmultiplier = 0
        if processmore_table[ipm][1] then
            if string.sub(ccc_main_bars_table[ipm], 1, 1) ~= "[" then --   CHECK TO SEE IF MULTIBAR
                if string.find(ccc_main_bars_table[ipm], ":") then
                    startsbrace, endbrace = string.find(ccc_main_bars_table[ipm], "%[", 1)
                    --reaper.ShowConsoleMsg(startsbrace.."\n")
                    barmultiplier = tonumber(string.sub(ccc_main_bars_table[ipm], 1, startsbrace - 1))
                    if barmultiplier ~= nil and barmultiplier ~= 1 then -- MULTIBAR WITH MULTI CHORDS = BAD
                        if warned == false then
                            ccc_ex_warning =
                                ccc_ex_warning ..
                                '- Multibars with more than one chord are not supported in Chordsheet.com export\nbecause they easily result in rhythms Chordsheet.com can not accept as input.\nThese measures have been rendered as "NC" which will help you find \nand adjust them.\n\n'
                            warned = true
                        end
                        newtablevalue = "NC "
                        for count = 1, barmultiplier - 1, 1 do
                            newtablevalue = newtablevalue .. "NC "
                        end
                        processmore_table[ipm][1] = false
                        processmore_table[ipm][2] = barmultiplier
                    elseif barmultiplier ~= nil and barmultiplier == 1 then
                        newtablevalue =
                            string.sub(ccc_main_bars_table[ipm], startsbrace, string.len(ccc_main_bars_table[ipm]))

                        processmore_table[ipm][1] = true
                        processmore_table[ipm][2] = 0
                    else -- LIKELY USER SCREW UP NON NUMBER MULTIBAR ie G[2m 5]
                        ccc_ex_warning =
                            ccc_ex_warning ..
                            '- Looks like your chord entry has formatting error.\nIt has been rendered as "NC" so you can find and manually adjust the error.'
                        newtablevalue = "NC "
                        processmore_table[ipm][1] = false
                        processmore_table[ipm][2] = 1
                    end
                else -- ONLY ONE INTERNAL CHORD ALL GOOD
                    startsbrace, endbrace = string.find(ccc_main_bars_table[ipm], "%[", 1)
                    --reaper.ShowConsoleMsg(startsbrace.."\n")
                    barmultiplier = tonumber(string.sub(ccc_main_bars_table[ipm], 1, startsbrace - 1))
                    if barmultiplier ~= nil then ---!!!!!!!!!!!!!!!!!!! THIS WORKS BUT SHOULDN'T !!! WHY ???????????
                        newtablevalue_part =
                            string.sub(
                            ccc_main_bars_table[ipm],
                            startsbrace + 1,
                            string.len(ccc_main_bars_table[ipm]) - 1
                        )
                        for count = 1, barmultiplier, 1 do
                            newtablevalue = newtablevalue .. " " .. newtablevalue_part .. " "
                        end
                        processmore_table[ipm][2] = barmultiplier
                    else -- LIKELY USER ERROR - ONLY 1 INTERNAL CHORD, BUT BAD MULTI ie G[4]
                        ccc_ex_warning =
                            ccc_ex_warning ..
                            "- Looks like your chord entry has formatting error.\nIt has been rendered as " ..
                                string.sub(
                                    ccc_main_bars_table[ipm],
                                    startsbrace + 1,
                                    string.len(ccc_main_bars_table[ipm]) - 1
                                ) ..
                                    " so you can find and manually adjust the error.\n"
                        newtablevalue =
                            string.sub(
                            ccc_main_bars_table[ipm],
                            startsbrace + 1,
                            string.len(ccc_main_bars_table[ipm]) - 1
                        )
                        processmore_table[ipm][1] = false
                        processmore_table[ipm][2] = 1
                    end
                end
                ccc_main_bars_table[ipm] = newtablevalue
            end
        --reaper.ShowConsoleMsg(tostring(processmore_table[ib][1]).."\n")
        end
    end
    ccc_measurecount_total = 0 -- LABEL ALL THE MEASURES ACCORDING TO THEIR MEASURE NUMBER
    for i, v in pairs(processmore_table) do
        ccc_measurecount_total = ccc_measurecount_total + processmore_table[i][2]
        processmore_table[i][3] = ccc_measurecount_total
    end

    in_item_table = {} --  !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!! DEAL WITH BRACED MEASURE INTERNALS
    for i, v in pairs(processmore_table) do
        if processmore_table[i][1] then
            inmeasure_table = Split(string.sub(ccc_main_bars_table[i], 2, string.len(ccc_main_bars_table[i]) - 1), ":")
            --reaper.ShowConsoleMsg(string.sub(ccc_main_bars_table[i],2,string.len(ccc_main_bars_table[i])-1) .. "\n")
            buileroo = ""
            split_mult_total = 0
            chord_count_total = 0
            in_item_table = {}
            for ibt, vbt in pairs(inmeasure_table) do
                chord_count_total = chord_count_total + 1

                item_split_starter, item_split_ender = string.find(vbt, "%(", 1)
                if item_split_starter ~= nil then
                    --reaper.ShowConsoleMsg("splitmult = ".. split_mult .. " SplitMult Total = " .. split_mult_total .. " Cell: " .. in_item_table[ibt][2] .. "\n")
                    --reaper.ShowConsoleMsg("found it\n")
                    split_mult = tonumber(string.sub(vbt, 1, item_split_starter - 1))
                    split_mult_total = split_mult_total + split_mult
                    in_item_table[ibt] = {split_mult, string.sub(vbt, item_split_starter + 1, string.len(vbt) - 1)}
                else
                    --reaper.ShowConsoleMsg("splitmult = ".. split_mult .. " SplitMult Total = " .. split_mult_total .. " Cell: " .. in_item_table[ibt][2] .. "\n")
                    --reaper.ShowConsoleMsg("nope\n")
                    split_mult = 1
                    split_mult_total = split_mult_total + split_mult
                    --reaper.ShowConsoleMsg("splitmult = ".. split_mult .. " SplitMult Total = " .. split_mult_total .. ' string = ' .. string.sub(vbt,1,string.len(vbt)) .. "\n")
                    in_item_table[ibt] = {1, vbt}
                end
            end
            ----------------------------------------------------------------------------------------

            for ig, vg in pairs(in_item_table) do
                addstart = 1
                if string.sub(vg[2], 1, 1) == " " then
                    addstart = 2
                else
                end
                if string.sub(vg[2], addstart, addstart) == "^" then
                    if string.sub(vg[2], addstart + 1, addstart + 1) == "^" then
                        addstart = addstart + 2
                    else
                        addstart = addstart + 1
                    end
                else
                end
                if string.sub(vg[2], addstart, addstart) == "b" or string.sub(vg[2], addstart, addstart) == "#" then
                    addstart = addstart + 2
                else
                    addstart = addstart + 1
                end
                endtype, _ = string.find(vg[2], "/")
                if endtype ~= nil then
                    endtype = endtype - 1
                end
                if endtype == nil then
                    endtype, _ = string.find(string.sub(vg[2], 2, string.len(vg[2])), " ")
                end
                if endtype == nil then
                    endtype = string.len(vg[2])
                end
                replacetype = string.sub(vg[2], addstart, endtype)
                --reaper.ShowConsoleMsg(replacetype .. "\n")
                if musictheory.to_ccc_translation[replacetype] ~= nil then
                    in_item_table[ig][2] =
                        string.sub(vg[2], 1, addstart - 1) ..
                        musictheory.to_ccc_translation[replacetype] .. string.sub(vg[2], endtype + 1, string.len(vg[2]))
                end
            end

            ----------------------------------------------------------------------------------------
            if chord_count_total == 1 then
                buileroo = in_item_table[1][2] .. " "
            elseif chord_count_total == 2 and in_item_table[1][1] == in_item_table[2][1] then
                buileroo = in_item_table[1][2] .. "_" .. in_item_table[2][2] .. " "
            elseif chord_count_total == 2 and tonumber(in_item_table[1][1]) == 3 and tonumber(in_item_table[2][1]) == 1 then
                buileroo = in_item_table[1][2] .. "_/_/_" .. in_item_table[2][2] .. " "
            elseif chord_count_total == 2 and tonumber(in_item_table[1][1]) == 1 and tonumber(in_item_table[2][1]) == 3 then
                buileroo = in_item_table[1][2] .. "_" .. in_item_table[2][2] .. "_/_/ "
            elseif chord_count_total == 2 and in_item_table[1][1] > in_item_table[2][1] then
                ccc_ex_warning =
                    ccc_ex_warning ..
                    "- Around measure " ..
                        processmore_table[i][3] .. "\n" .. ccc_main_bars_table[i] .. " may have been simplified.\n"
                buileroo = in_item_table[1][2] .. "_" .. in_item_table[2][2] .. " "
            elseif chord_count_total == 2 and in_item_table[1][1] < in_item_table[2][1] then
                ccc_ex_warning =
                    ccc_ex_warning ..
                    "- Around measure " ..
                        processmore_table[i][3] .. "\n" .. ccc_main_bars_table[i] .. " may have been simplified.\n"
                buileroo = in_item_table[1][2] .. "_" .. in_item_table[2][2] .. " "
            elseif
                chord_count_total == 3 and tonumber(in_item_table[1][1]) == 2 and tonumber(in_item_table[2][1]) == 1 and
                    tonumber(in_item_table[3][1]) == 1
             then
                buileroo = in_item_table[1][2] .. "_/_" .. in_item_table[2][2] .. "_" .. in_item_table[3][2] .. " "
            elseif
                chord_count_total == 3 and tonumber(in_item_table[1][1]) == 1 and tonumber(in_item_table[2][1]) == 1 and
                    tonumber(in_item_table[3][1]) == 2
             then
                buileroo = in_item_table[1][2] .. "_" .. in_item_table[2][2] .. "_" .. in_item_table[3][2] .. "_/ "
            elseif
                chord_count_total == 3 and tonumber(in_item_table[1][1]) == 1 and tonumber(in_item_table[2][1]) == 2 and
                    tonumber(in_item_table[3][1]) == 1
             then
                buileroo = in_item_table[1][2] .. "_" .. in_item_table[2][2] .. "_/_" .. in_item_table[3][2] .. " "
            elseif
                chord_count_total == 3 and tonumber(in_item_table[1][1]) > tonumber(in_item_table[2][1]) and
                    tonumber(in_item_table[1][1]) > tonumber(in_item_table[3][1])
             then
                buileroo = in_item_table[1][2] .. "_" .. in_item_table[2][2] .. "_" .. in_item_table[3][2] .. " "
                ccc_ex_warning =
                    ccc_ex_warning ..
                    "- Around measure " ..
                        processmore_table[i][3] .. "\n" .. ccc_main_bars_table[i] .. " may have been simplified.\n"
            elseif
                chord_count_total == 3 and tonumber(in_item_table[3][1]) > tonumber(in_item_table[1][1]) and
                    tonumber(in_item_table[3][1]) > tonumber(in_item_table[2][1])
             then
                buileroo = in_item_table[1][2] .. "_" .. in_item_table[2][2] .. "_" .. in_item_table[3][2] .. " "
                ccc_ex_warning =
                    ccc_ex_warning ..
                    "- Around measure " ..
                        processmore_table[i][3] .. "\n" .. ccc_main_bars_table[i] .. " may have been simplified.\n"
            elseif
                chord_count_total == 3 and tonumber(in_item_table[2][1]) > tonumber(in_item_table[1][1]) and
                    tonumber(in_item_table[2][1]) > tonumber(in_item_table[3][1])
             then
                ccc_ex_warning =
                    ccc_ex_warning ..
                    "- Around measure " ..
                        processmore_table[i][3] .. "\n" .. ccc_main_bars_table[i] .. " may have been simplified.\n"
                buileroo = in_item_table[1][2] .. "_" .. in_item_table[2][2] .. "_" .. in_item_table[3][2] .. " "
            elseif
                chord_count_total == 4 and tonumber(in_item_table[1][1]) == tonumber(in_item_table[2][1]) and
                    tonumber(in_item_table[1][1]) == tonumber(in_item_table[3][1]) and
                    tonumber(in_item_table[1][1]) == tonumber(in_item_table[4][1])
             then
                buileroo =
                    in_item_table[1][2] ..
                    "_" .. in_item_table[2][2] .. "_" .. in_item_table[3][2] .. "_" .. in_item_table[4][2] .. " "
            elseif chord_count_total == 4 and split_mult_total > 4 then
                ccc_ex_warning =
                    ccc_ex_warning ..
                    "- Around measure " ..
                        processmore_table[i][3] ..
                            " " ..
                                "\nthe rhythm of chords " ..
                                    ccc_main_bars_table[i] .. "\n was simplified due to Chord Sheet limititations.\n"
                buileroo =
                    in_item_table[1][2] ..
                    "_" .. in_item_table[2][2] .. "_" .. in_item_table[3][2] .. "_" .. in_item_table[4][2] .. " "
            elseif chord_count_total == 5 then
                ccc_ex_warning =
                    ccc_ex_warning ..
                    "- Around measure " ..
                        processmore_table[i][3] .. " rhythm could not be rendered due to Chord Sheet limitations.\n"
                buileroo =
                    in_item_table[1][2] ..
                    "_" ..
                        in_item_table[2][2] ..
                            "_" ..
                                in_item_table[3][2] .. "_" .. in_item_table[4][2] .. "_" .. in_item_table[5][2] .. " "
            elseif chord_count_total == 6 then
                ccc_ex_warning =
                    ccc_ex_warning ..
                    "- Around measure " ..
                        processmore_table[i][3] .. " rhythm could not be rendered due to Chord Sheet limitations.\n"
                buileroo =
                    in_item_table[1][2] ..
                    "_" ..
                        in_item_table[2][2] ..
                            "_" ..
                                in_item_table[3][2] ..
                                    "_" ..
                                        in_item_table[4][2] ..
                                            "_" .. in_item_table[5][2] .. "_" .. in_item_table[6][2] .. " "
            elseif chord_count_total == 7 then
                ccc_ex_warning =
                    ccc_ex_warning ..
                    "- Around measure " ..
                        processmore_table[i][3] .. " rhythm could not be rendered due to Chord Sheet limitations.\n"
                buileroo =
                    in_item_table[1][2] ..
                    "_" ..
                        in_item_table[2][2] ..
                            "_" ..
                                in_item_table[3][2] ..
                                    "_" ..
                                        in_item_table[4][2] ..
                                            "_" ..
                                                in_item_table[5][2] ..
                                                    "_" .. in_item_table[6][2] .. "_" .. in_item_table[7][2] .. " "
            elseif chord_count_total == 8 then
                ccc_ex_warning =
                    ccc_ex_warning ..
                    "- Around measure " ..
                        processmore_table[i][3] .. " rhythm could not be rendered due to Chord Sheet limitations.\n"
                buileroo =
                    in_item_table[1][2] ..
                    "_" ..
                        in_item_table[2][2] ..
                            "_" ..
                                in_item_table[3][2] ..
                                    "_" ..
                                        in_item_table[4][2] ..
                                            "_" ..
                                                in_item_table[5][2] ..
                                                    "_" ..
                                                        in_item_table[6][2] ..
                                                            "_" ..
                                                                in_item_table[7][2] .. "_" .. in_item_table[8][2] .. " "
            elseif chord_count_total > 8 then
                ccc_ex_warning =
                    ccc_ex_warning ..
                    "- Around measure " ..
                        processmore_table[i][3] ..
                            " " ..
                                ccc_main_bars_table[i] ..
                                    "\nonly the chords " ..
                                        in_item_table[1][2] ..
                                            " " ..
                                                in_item_table[2][2] ..
                                                    " " ..
                                                        in_item_table[3][2] ..
                                                            " " ..
                                                                in_item_table[4][2] ..
                                                                    " " ..
                                                                        in_item_table[5][2] ..
                                                                            " " ..
                                                                                in_item_table[6][2] ..
                                                                                    " " ..
                                                                                        in_item_table[7][2] ..
                                                                                            " " ..
                                                                                                in_item_table[8][2] ..
                                                                                                    "\n could be rendered due to Chord Sheet limit of 8 chords per bar.\n"
                buileroo =
                    in_item_table[1][2] ..
                    "_" ..
                        in_item_table[2][2] ..
                            "_" ..
                                in_item_table[3][2] ..
                                    "_" ..
                                        in_item_table[4][2] ..
                                            "_" ..
                                                in_item_table[5][2] ..
                                                    "_" ..
                                                        in_item_table[6][2] ..
                                                            "_" ..
                                                                in_item_table[7][2] .. "_" .. in_item_table[8][2] .. " "
            else
                buileroo = ccc_main_bars_table[i]
            end

            ccc_main_bars_table[i] = buileroo
        else
            this_single_chord = ccc_main_bars_table[i]
            addstart = 1
            if string.sub(this_single_chord, 1, 1) == " " then
                addstart = 2
            else
            end
            if string.sub(this_single_chord, addstart, addstart) == "<" then
                if string.sub(this_single_chord, addstart + 1, addstart + 1) == "<" then
                    addstart = addstart + 2
                else
                    addstart = addstart + 1
                end
            else
            end
            if
                string.sub(this_single_chord, addstart, addstart) == "b" or
                    string.sub(this_single_chord, addstart, addstart) == "#"
             then
                addstart = addstart + 2
            else
                addstart = addstart + 1
            end
            endtype, _ = string.find(this_single_chord, "/")
            if endtype ~= nil then
                endtype = endtype - 1
            end
            if endtype == nil then
                endtype, _ = string.find(string.sub(this_single_chord, 2, string.len(this_single_chord)), " ")
            end
            if endtype == nil then
                endtype = string.len(this_single_chord)
            end
            replacetype = string.sub(this_single_chord, addstart, endtype)
            --reaper.ShowConsoleMsg(replacetype .. "\n")
            if musictheory.to_ccc_translation[replacetype] ~= nil then
                ccc_main_bars_table[i] =
                    string.sub(this_single_chord, 1, addstart - 1) ..
                    musictheory.to_ccc_translation[replacetype] ..
                        string.sub(this_single_chord, endtype + 1, string.len(this_single_chord))
            end
        end
    end

    for i, v in pairs(ccc_main_bars_table) do --  DEAL WITH REPEATS ON THE WAY TO TEXT
        if v == "!Repeat!" then
            ccc_post_table_chord_data = ccc_post_table_chord_data .. "  " .. the_last_ccc_bar_content
        else
            ccc_post_table_chord_data = ccc_post_table_chord_data .. "  " .. v
            the_last_ccc_bar_content = v
        end
    end

    --ccc_post_table_chord_data = string.gsub(ccc_post_table_chord_data, "| Â |", "|A) ")    -- SWAP OUT FOR A)
    --ccc_post_table_chord_data = string.gsub(ccc_post_table_chord_data, "| Å |", "|B) ")      -- AND B) SECTION MARKS
    --ccc_post_table_chord_data = string.gsub(ccc_post_table_chord_data, "<<", "")      -- SWAP OUT FOR 16th
    --ccc_post_table_chord_data = string.gsub(ccc_post_table_chord_data, "<", "")          -- AND 8th PUSHES IN ccc FORMAT

    --reaper.ShowConsoleMsg("cf = "..unencoded_keyfound.. "\n")
    ccc_key_shift = musictheory.key_table[unencoded_keyfound]

    if ccc_key_shift ~= nil then
        --reaper.ShowConsoleMsg("cccf = "..tostring(ccc_flat).. "\n")
        --reaper.ShowConsoleMsg("cccks = "..ccc_key_shift.. "\n")

        ccc_flat = musictheory.is_it_flat_table[ckeyfound]
    else
        --reaper.ShowConsoleMsg("Check your key.\nNumbers2Notes, like many Nashville Number System users, does not use minor keys.\n Instead, use the relative major and write your charts with the focus on 6m rather than 1.\n")

        return "Error...", 0, "Check your key.\nNumbers2Notes, like many Nashville Number System users, does not use minor keys.\n Instead, use the relative major and write your charts with the focus on 6m rather than 1.\n"
    end

    for i, v in pairs(musictheory.cccroot_table) do
        if v + ccc_key_shift >= 12 then
            totalshift = v + ccc_key_shift - 12
        elseif v + ccc_key_shift < 0 then
            totalshift = v + ccc_key_shift + 12
        else
            totalshift = v + ccc_key_shift
        end
        --reaper.ShowConsoleMsg("ccctf = "..tostring(totalshift).. "\n")
        if ccc_flat then
            ccc_post_table_chord_data =
                string.gsub(ccc_post_table_chord_data, " " .. i, musictheory.flats_table[totalshift])
        else
            ccc_post_table_chord_data =
                string.gsub(ccc_post_table_chord_data, " " .. i, musictheory.sharps_table[totalshift])
        end
    end

    for i, v in pairs(musictheory.cccroot_table) do
        if v + ccc_key_shift >= 12 then
            totalshift = v + ccc_key_shift - 12
        elseif v + ccc_key_shift < 0 then
            totalshift = v + ccc_key_shift + 12
        else
            totalshift = v + ccc_key_shift
        end
        --reaper.ShowConsoleMsg("ccctf = "..tostring(totalshift).. "\n")
        if ccc_flat then
            ccc_post_table_chord_data =
                string.gsub(ccc_post_table_chord_data, "/" .. i, "/" .. musictheory.flats_table[totalshift])
        else
            ccc_post_table_chord_data =
                string.gsub(ccc_post_table_chord_data, "/" .. i, "/" .. musictheory.sharps_table[totalshift])
        end
    end

    for i, v in pairs(musictheory.cccroot_table) do
        if v + ccc_key_shift >= 12 then
            totalshift = v + ccc_key_shift - 12
        elseif v + ccc_key_shift < 0 then
            totalshift = v + ccc_key_shift + 12
        else
            totalshift = v + ccc_key_shift
        end
        --reaper.ShowConsoleMsg("ccctf = "..tostring(totalshift).. "\n")
        if ccc_flat then
            ccc_post_table_chord_data =
                string.gsub(ccc_post_table_chord_data, "_" .. i, "_" .. musictheory.flats_table[totalshift])
        else
            ccc_post_table_chord_data =
                string.gsub(ccc_post_table_chord_data, "_" .. i, "_" .. musictheory.sharps_table[totalshift])
        end
    end

    ::doubleclean:: -- CONVERT RETURNS TO SPACES
    in_num = string.len(ccc_post_table_chord_data)
    ccc_post_table_chord_data = string.gsub(ccc_post_table_chord_data, "  ", " ")
    if in_num ~= string.len(ccc_post_table_chord_data) then
        goto doubleclean
    end

    last_ccc_rebuild_for_4bar_lines = ""
    spacecounter = 1
    for i = 1, string.len(ccc_post_table_chord_data), 1 do
        if string.sub(ccc_post_table_chord_data, i, i) == " " then
            if spacecounter == 4 then
                spacecounter = 1
                last_ccc_rebuild_for_4bar_lines = last_ccc_rebuild_for_4bar_lines .. "\n"
            else
                spacecounter = spacecounter + 1
                last_ccc_rebuild_for_4bar_lines =
                    last_ccc_rebuild_for_4bar_lines .. string.sub(ccc_post_table_chord_data, i, i)
            end
        elseif string.sub(ccc_post_table_chord_data, i, i) == "|" then
            last_ccc_rebuild_for_4bar_lines = last_ccc_rebuild_for_4bar_lines .. "\n"
            spacecounter = 0
        else
            last_ccc_rebuild_for_4bar_lines =
                last_ccc_rebuild_for_4bar_lines .. string.sub(ccc_post_table_chord_data, i, i)
        end
    end
    ccc_post_table_chord_data = last_ccc_rebuild_for_4bar_lines

    the_ccc_bar_count = 0
    --reaper.ShowConsoleMsg("\n-----------------------------------------\n")
    for i, v in pairs(processmore_table) do
        the_ccc_bar_count = the_ccc_bar_count + tonumber(processmore_table[i][2])
        --reaper.ShowConsoleMsg("COUNT = " .. tonumber(processmore_table[i][2]) .. "TOTAL = " .. the_ccc_bar_count .. "\n")
    end
    return ccc_post_table_chord_data, the_ccc_bar_count, thefail
end

the_last_BIAB_bar_content = ""
function export_biab()
    biab_ex_warning = ""
    biab_export_area = ""
    reaper.PreventUIRefresh(1)
    the_last_BIAB_bar_content = "" -- CLEAR OUT THE OLD AND SET UP THE SHELL FOR THE NEW DATA
    local headshell =
        [[
"[Song]
[Title !W! - !T!]
[Key !K!] 
[Tempo !B!]
[Form 1-!F!*1]
[.sty _!S!.sty]
[Chords]
[Fix]
!C!
[ChordsEnd]
[SongEnd]"]]
    to_biab_export_area = headshell
    _, title_startso = string.find(header_area, "Title: ") -- GET THE PROJECT SETTINGS AND PLACE IN THE SHELL
    title_endso, _ = string.find(header_area, "Writer:")
    _, writer_startso = string.find(header_area, "Writer: ")
    writer_endso, _ = string.find(header_area, "BPM:")
    _, key_startso = string.find(header_area, "Key: ")
    key_endso, _ = string.find(header_area, "Swing:")
    _, bpm_startso = string.find(header_area, "BPM: ")
    bpm_endso, _ = string.find(header_area, "Key:")
    titlefound = string.sub(header_area, title_startso + 1, title_endso - 2)
    writerfound = string.sub(header_area, writer_startso + 1, writer_endso - 2)
    bpmfound = string.sub(header_area, bpm_startso + 1, bpm_endso - 2)
    keyfound = string.sub(header_area, key_startso + 1, key_endso - 2)
    to_biab_export_area = string.gsub(to_biab_export_area, "!W!", writerfound)
    to_biab_export_area = string.gsub(to_biab_export_area, "!T!", titlefound)
    to_biab_export_area = string.gsub(to_biab_export_area, "!K!", keyfound)
    to_biab_export_area = string.gsub(to_biab_export_area, "!B!", bpmfound)
    to_biab_export_area = string.gsub(to_biab_export_area, "!S!", biab_style)
    biab_bars, biab_bar_count = process_biab_bars() -- MOST WORK IS HERE IN THIS SUB
    to_biab_export_area = string.gsub(to_biab_export_area, "!F!", biab_bar_count)
    to_biab_export_area = string.gsub(to_biab_export_area, "!C!", biab_bars)
    if string.len(biab_ex_warning) > 0 then
        biab_export_area = biab_ex_warning .. "_____________________________________\n\n" .. to_biab_export_area
    else
        biab_export_area = to_biab_export_area
    end
    reaper.PreventUIRefresh(-1)
end

biab_ex_warning = ""
---------------------------------------------------------BIAB SUB FOR PROCESSESSING ALL THE BARS
function process_biab_bars()
    thefail = ""
    chord_charting_area = inital_swaps(chord_charting_area)
    local safe_header = Normalize_Form_Line(header_area)
    unfolded_biab_data, error_zone = form.process_the_form(header_area, chord_charting_area)
    -- FORM     DEAL WITH UNFOLDING THE FORM
    unfolded_biab_data = string.gsub(unfolded_biab_data, "{$Intro$}", "Â")
    unfolded_biab_data = string.gsub(unfolded_biab_data, "{$Verse$}", "Â")
    unfolded_biab_data = string.gsub(unfolded_biab_data, "{$Chorus$}", "Å")
    unfolded_biab_data = string.gsub(unfolded_biab_data, "{$Outro$}", "Å")
    unfolded_biab_data = string.gsub(unfolded_biab_data, "%%", "!Repeat!")
    -- CODE THE SIMPLEST AS A OR B SECTIONS DELETE THE REST

    ::striplabels:: -- REMOVE THE SECTION LABELS
    local in_num = string.len(unfolded_biab_data)
    section_start, _ = string.find(unfolded_biab_data, "{%$")
    _, section_end = string.find(unfolded_biab_data, "%$}")
    if section_start ~= nil and section_end ~= nil and section_end > section_start then
        --reaper.ShowConsoleMsg("did find\n")
        unfolded_biab_data =
            string.gsub(unfolded_biab_data, string.sub(unfolded_biab_data, section_start, section_end), "")
    --else
    --reaper.ShowConsoleMsg("didn't find\n")
    end
    if in_num ~= string.len(unfolded_biab_data) then
        goto striplabels
    end

    -- CONVERT RETURNS TO SPACES

    ::flaten:: -- CONVERT RETURNS TO SPACES
    in_num = string.len(unfolded_biab_data)
    unfolded_biab_data = string.gsub(unfolded_biab_data, "\n", " ")
    if in_num ~= string.len(unfolded_biab_data) then
        goto flaten
    end

    ::detab:: -- CONVERT TABS TO SPACES
    in_num = string.len(unfolded_biab_data)
    unfolded_biab_data = string.gsub(unfolded_biab_data, "\t", " ")
    if in_num ~= string.len(unfolded_biab_data) then
        goto detab
    end
    -- TRIM DOWN TO SINGLE SPACES
    ::trimwhitespace::
    in_num = string.len(unfolded_biab_data)
    unfolded_biab_data = string.gsub(unfolded_biab_data, "  ", " ")
    if in_num ~= string.len(unfolded_biab_data) then
        goto trimwhitespace
    end

    ::reducecr:: -- ?? TRIM BACK RETURNS (didn't I do this)
    in_num = string.len(unfolded_biab_data)
    unfolded_biab_data = string.gsub(unfolded_biab_data, "\n\n", "\n")
    if in_num ~= string.len(unfolded_biab_data) then
        goto reducecr
    end

    ::fluffen:: -- SEPARATE BRACED MEASURES BY A SPACE
    in_num = string.len(unfolded_biab_data)
    unfolded_biab_data = string.gsub(unfolded_biab_data, "%]%[", "] [")
    if in_num ~= string.len(unfolded_biab_data) then
        goto fluffen
    end

    ::squish1:: -- TRIM OUT SPACES FROM INSIDE IN BRACES
    in_num = string.len(unfolded_biab_data)
    unfolded_biab_data = string.gsub(unfolded_biab_data, "%[ ", "[")
    if in_num ~= string.len(unfolded_biab_data) then
        goto squish1
    end

    ::squish2:: -- TRIM OUT SPACES FROM INSIDE OUT BRACES
    in_num = string.len(unfolded_biab_data)
    unfolded_biab_data = string.gsub(unfolded_biab_data, " %]", "]")
    if in_num ~= string.len(unfolded_biab_data) then
        goto squish2
    end

    ::derest:: -- CONVERT ALL REST TO BIAB REST 1.
    in_num = string.len(unfolded_biab_data)
    unfolded_biab_data = string.gsub(unfolded_biab_data, " %- ", " 1. ")
    unfolded_biab_data = string.gsub(unfolded_biab_data, " R ", " 1. ")
    unfolded_biab_data = string.gsub(unfolded_biab_data, " r ", " 1. ")
    if in_num ~= string.len(unfolded_biab_data) then
        goto derest
    end

    local inmeasurenow = false -- !!!!!!!!!!!!!!!!   GET THE DATA READY TO BE PUT INTO TABLES ONE CHAR AT A TIME  !!!!!!
    measurechord_count = 0
    rebuild = ""
    for i = 1, string.len(unfolded_biab_data) do
        if string.sub(unfolded_biab_data, i, i) == "Â" or string.sub(unfolded_biab_data, i, i) == "Å" then
            rebuild = rebuild .. string.sub(unfolded_biab_data, i, i) -- REBUILD WITH SECTION SWAP AS IS
            inmeasurenow = false
        elseif string.sub(unfolded_biab_data, i, i) == "[" and inmeasurenow == false then
            inmeasurenow = true
            rebuild = rebuild .. string.sub(unfolded_biab_data, i, i) -- REBUILD WITH IN BRACE AS IS (UNLESS...)
        elseif string.sub(unfolded_biab_data, i, i) == "]" and inmeasurenow == true then
            inmeasurenow = false
            rebuild = rebuild .. string.sub(unfolded_biab_data, i, i) -- REBUILD WITH OUT BRACE AS IS (UNLESS...)
        elseif string.sub(unfolded_biab_data, i, i) == "]" and inmeasurenow == false then -- WARN WHEN THERE IS A [[ USER ERROR
            thefail = thefail .. 'Incident of mismatched braces.  Make sure to use "[" and "]" in pairs.\n'
        elseif string.sub(unfolded_biab_data, i, i) == "[" and inmeasurenow == true then -- WARN WHEN THERE IS A ]] USER ERROR
            thefail = thefail .. 'Incident of mismatched braces.  Make sure to use "[" and "]" in pairs.\n'
        elseif string.sub(unfolded_biab_data, i, i) == " " and inmeasurenow == false then
            rebuild = rebuild .. "," -- CHANGE MEASURE SEPARATORS TO COMMA
        elseif string.sub(unfolded_biab_data, i, i) == " " and inmeasurenow == true then
            rebuild = rebuild .. ":" -- CHANGE IN MEASURE SEPS TO COLON
        else
            rebuild = rebuild .. string.sub(unfolded_biab_data, i, i) -- PASS EVERYTHING ELSE AS IS
        end
    end
    BIAB_main_bars_table = Split(rebuild, ",") -- PUT THE DATA INTO TABLE

    local warned = false -- PREPING VARIABLES
    local rewarned = false
    local newtablevalue = ""
    local processmore_table = {}
    local BIAB_post_table_chord_data = ""

    for ib, vb in pairs(BIAB_main_bars_table) do --  !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!    DETERMINE IF MULTIBAR !!!!!!!!!!
        if string.find(vb, "%[") then
            processmore_table[ib] = {true, 1} -- TAG AS MULTIBAR IN this TABLE
        elseif string.find(vb, "Â") then
            processmore_table[ib] = {false, 0} -- A) SECTION HEADER - NOT A MEASURE
        elseif string.find(vb, "Å") then
            processmore_table[ib] = {false, 0} -- B) SECTION HEADER - NOT A MEASURE
        else
            processmore_table[ib] = {false, 1} -- TAG AS A SINGLE BAR
        end
        --reaper.ShowConsoleMsg(tostring(processmore_table[ib][1]).."\n")
    end

    for ipm, vpm in pairs(processmore_table) do -- !!!!!!!!!!!!!!!!!!!!!!!!!!!!!    DEAL WITH ALL THE MULTIBARS     !!!!!!!
        barmultiplier = 0
        if processmore_table[ipm][1] then
            if string.sub(BIAB_main_bars_table[ipm], 1, 1) ~= "[" then --   CHECK TO SEE IF MULTIBAR
                if string.find(BIAB_main_bars_table[ipm], ":") then
                    startsbrace, endbrace = string.find(BIAB_main_bars_table[ipm], "%[", 1)
                    --reaper.ShowConsoleMsg(startsbrace.."\n")
                    barmultiplier = tonumber(string.sub(BIAB_main_bars_table[ipm], 1, startsbrace - 1))
                    if barmultiplier ~= nil and barmultiplier ~= 1 then -- MULTIBAR WITH MULTI CHORDS = BAD
                        if warned == false then
                            biab_ex_warning =
                                biab_ex_warning ..
                                '- Multibars with more than one chord are not supported in BIAB export\nbecause they easily result in rhythms BIAB can not accept as input.\nThese measures have been rendered as "1.d" which will sound drums only\nallowing you to find and adjust them.\n\n'
                            warned = true
                        end
                        newtablevalue = "1.d"
                        for count = 1, barmultiplier - 1, 1 do
                            newtablevalue = newtablevalue .. " | "
                        end
                        processmore_table[ipm][1] = false
                        processmore_table[ipm][2] = barmultiplier
                    elseif barmultiplier ~= nil and barmultiplier == 1 then -- THERE IS A 1 MULTIBAR - JUST REMOVE MULTI
                        newtablevalue =
                            string.sub(
                            BIAB_main_bars_table[ipm],
                            startsbrace + 1,
                            string.len(BIAB_main_bars_table[ipm]) - 1
                        )
                        processmore_table[ipm][1] = false
                        processmore_table[ipm][2] = 1
                    else -- LIKELY USER SCREW UP NON NUMBER MULTIBAR ie G[2m 5]
                        biab_ex_warning =
                            biab_ex_warning ..
                            '- Looks like your chord entry has formatting error.\nIt has been rendered as "1b.d" so you can find and manually adjust the error.'
                        newtablevalue = "1b.d"
                        processmore_table[ipm][1] = false
                        processmore_table[ipm][2] = 1
                    end
                else -- ONLY ONE INTERNAL CHORD ALL GOOD
                    startsbrace, endbrace = string.find(BIAB_main_bars_table[ipm], "%[", 1)
                    --reaper.ShowConsoleMsg(startsbrace.."\n")
                    barmultiplier = tonumber(string.sub(BIAB_main_bars_table[ipm], 1, startsbrace - 1))
                    if barmultiplier ~= nil and barmultiplier == 1 then -- THERE IS A 1 MULTIBAR - JUST REMOVE MULTI
                        newtablevalue =
                            string.sub(
                            BIAB_main_bars_table[ipm],
                            startsbrace + 1,
                            string.len(BIAB_main_bars_table[ipm]) - 1
                        )
                        processmore_table[ipm][1] = false
                        processmore_table[ipm][2] = 1
                    elseif barmultiplier ~= nil then ---!!!!!!!!!!!!!!!!!!! THIS WORKS BUT SHOULDN'T !!! WHY ???????????
                        newtablevalue =
                            string.sub(
                            BIAB_main_bars_table[ipm],
                            startsbrace,
                            string.len(BIAB_main_bars_table[ipm]) - 1
                        )
                        for count = 1, barmultiplier - 1, 1 do
                            newtablevalue = newtablevalue .. " | "
                        end
                        processmore_table[ipm][2] = barmultiplier
                    else -- LIKELY USER ERROR - ONLY 1 INTERNAL CHORD, BUT BAD MULTI ie G[4]
                        biab_ex_warning =
                            biab_ex_warning ..
                            "- Looks like your chord entry has formatting error.\nIt has been rendered as " ..
                                string.sub(
                                    BIAB_main_bars_table[ipm],
                                    startsbrace + 1,
                                    string.len(BIAB_main_bars_table[ipm]) - 1
                                ) ..
                                    " so you can find and manually adjust the error.\n"
                        newtablevalue =
                            string.sub(
                            BIAB_main_bars_table[ipm],
                            startsbrace + 1,
                            string.len(BIAB_main_bars_table[ipm]) - 1
                        )
                        processmore_table[ipm][1] = false
                        processmore_table[ipm][2] = 1
                    end
                end
                BIAB_main_bars_table[ipm] = newtablevalue
            end
        --reaper.ShowConsoleMsg(tostring(processmore_table[ib][1]).."\n")
        end
    end
    biab_measurecount_total = 0 -- LABEL ALL THE MEASURES ACCORDING TO THEIR MEASURE NUMBER
    for i, v in pairs(processmore_table) do
        biab_measurecount_total = biab_measurecount_total + processmore_table[i][2]
        processmore_table[i][3] = biab_measurecount_total
    end

    in_item_table = {} --  !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!! DEAL WITH BRACED MEASURE INTERNALS
    for i, v in pairs(processmore_table) do
        if processmore_table[i][1] then
            inmeasure_table =
                Split(string.sub(BIAB_main_bars_table[i], 2, string.len(BIAB_main_bars_table[i]) - 1), ":")
            --reaper.ShowConsoleMsg(string.sub(BIAB_main_bars_table[i],2,string.len(BIAB_main_bars_table[i])-1) .. "\n")
            buileroo = ""
            split_mult_total = 0
            chord_count_total = 0
            in_item_table = {}
            for ibt, vbt in pairs(inmeasure_table) do
                chord_count_total = chord_count_total + 1

                item_split_starter, item_split_ender = string.find(vbt, "%(", 1)
                if item_split_starter ~= nil then
                    --reaper.ShowConsoleMsg("splitmult = ".. split_mult .. " SplitMult Total = " .. split_mult_total .. " Cell: " .. in_item_table[ibt][2] .. "\n")
                    --reaper.ShowConsoleMsg("found it\n")
                    split_mult = tonumber(string.sub(vbt, 1, item_split_starter - 1))
                    split_mult_total = split_mult_total + split_mult
                    in_item_table[ibt] = {split_mult, string.sub(vbt, item_split_starter + 1, string.len(vbt) - 1)}
                else
                    --reaper.ShowConsoleMsg("splitmult = ".. split_mult .. " SplitMult Total = " .. split_mult_total .. " Cell: " .. in_item_table[ibt][2] .. "\n")
                    --reaper.ShowConsoleMsg("nope\n")
                    split_mult = 1
                    split_mult_total = split_mult_total + split_mult
                    --reaper.ShowConsoleMsg("splitmult = ".. split_mult .. " SplitMult Total = " .. split_mult_total .. ' string = ' .. string.sub(vbt,1,string.len(vbt)) .. "\n")
                    in_item_table[ibt] = {1, vbt}
                end
            end
            ----------------------------------------------------------------------------------------

            for ig, vg in pairs(in_item_table) do
                addstart = 1
                if string.sub(vg[2], 1, 1) == " " then
                    addstart = 2
                else
                end
                if string.sub(vg[2], addstart, addstart) == "^" then
                    if string.sub(vg[2], addstart + 1, addstart + 1) == "^" then
                        addstart = addstart + 2
                    else
                        addstart = addstart + 1
                    end
                else
                end
                if string.sub(vg[2], addstart, addstart) == "b" or string.sub(vg[2], addstart, addstart) == "#" then
                    addstart = addstart + 2
                else
                    addstart = addstart + 1
                end
                endtype, _ = string.find(vg[2], "/")
                if endtype ~= nil then
                    endtype = endtype - 1
                end
                if endtype == nil then
                    endtype, _ = string.find(string.sub(vg[2], 2, string.len(vg[2])), " ")
                end
                if endtype == nil then
                    endtype = string.len(vg[2])
                end
                replacetype = string.sub(vg[2], addstart, endtype)
                --reaper.ShowConsoleMsg(replacetype .. "\n")
                if musictheory.to_biab_translation[replacetype] ~= nil then
                    in_item_table[ig][2] =
                        string.sub(vg[2], 1, addstart - 1) ..
                        musictheory.to_biab_translation[replacetype] ..
                            string.sub(vg[2], endtype + 1, string.len(vg[2]))
                end
            end

            ----------------------------------------------------------------------------------------
            if chord_count_total == 1 then
                buileroo = in_item_table[1][2] .. " "
            elseif chord_count_total == 2 and in_item_table[1][1] == in_item_table[2][1] then
                buileroo = in_item_table[1][2] .. " " .. in_item_table[2][2] .. " "
            elseif chord_count_total == 2 and tonumber(in_item_table[1][1]) == 3 and tonumber(in_item_table[2][1]) == 1 then
                buileroo = in_item_table[1][2] .. " / / " .. in_item_table[2][2] .. " "
            elseif chord_count_total == 2 and tonumber(in_item_table[1][1]) == 1 and tonumber(in_item_table[2][1]) == 3 then
                buileroo = in_item_table[1][2] .. " " .. in_item_table[2][2] .. " / / "
            elseif chord_count_total == 2 and in_item_table[1][1] > in_item_table[2][1] then
                biab_ex_warning =
                    biab_ex_warning ..
                    "- Around measure " ..
                        processmore_table[i][3] .. "\n" .. BIAB_main_bars_table[i] .. " may have been simplified.\n"
                buileroo = in_item_table[1][2] .. " / / " .. in_item_table[2][2] .. " "
            elseif chord_count_total == 2 and in_item_table[1][1] < in_item_table[2][1] then
                biab_ex_warning =
                    biab_ex_warning ..
                    "- Around measure " ..
                        processmore_table[i][3] .. "\n" .. BIAB_main_bars_table[i] .. " may have been simplified.\n"
                buileroo = in_item_table[1][2] .. " " .. in_item_table[2][2] .. " / / "
            elseif
                chord_count_total == 3 and tonumber(in_item_table[1][1]) == 2 and tonumber(in_item_table[2][1]) == 1 and
                    tonumber(in_item_table[3][1]) == 1
             then
                buileroo = in_item_table[1][2] .. " / " .. in_item_table[2][2] .. " " .. in_item_table[3][2] .. " "
            elseif
                chord_count_total == 3 and tonumber(in_item_table[1][1]) == 1 and tonumber(in_item_table[2][1]) == 1 and
                    tonumber(in_item_table[3][1]) == 2
             then
                buileroo = in_item_table[1][2] .. " " .. in_item_table[2][2] .. " " .. in_item_table[3][2] .. " / "
            elseif
                chord_count_total == 3 and tonumber(in_item_table[1][1]) == 1 and tonumber(in_item_table[2][1]) == 2 and
                    tonumber(in_item_table[3][1]) == 1
             then
                buileroo = in_item_table[1][2] .. " " .. in_item_table[2][2] .. " / " .. in_item_table[3][2] .. " "
            elseif
                chord_count_total == 3 and tonumber(in_item_table[1][1]) > tonumber(in_item_table[2][1]) and
                    tonumber(in_item_table[1][1]) > tonumber(in_item_table[3][1])
             then
                buileroo = in_item_table[1][2] .. " / " .. in_item_table[2][2] .. " " .. in_item_table[3][2] .. " "
                biab_ex_warning =
                    biab_ex_warning ..
                    "- Around measure " ..
                        processmore_table[i][3] .. "\n" .. BIAB_main_bars_table[i] .. " may have been simplified.\n"
            elseif
                chord_count_total == 3 and tonumber(in_item_table[3][1]) > tonumber(in_item_table[1][1]) and
                    tonumber(in_item_table[3][1]) > tonumber(in_item_table[2][1])
             then
                buileroo = in_item_table[1][2] .. " " .. in_item_table[2][2] .. " " .. in_item_table[3][2] .. " / "
                biab_ex_warning =
                    biab_ex_warning ..
                    "- Around measure " ..
                        processmore_table[i][3] .. "\n" .. BIAB_main_bars_table[i] .. " may have been simplified.\n"
            elseif
                chord_count_total == 3 and tonumber(in_item_table[2][1]) > tonumber(in_item_table[1][1]) and
                    tonumber(in_item_table[2][1]) > tonumber(in_item_table[3][1])
             then
                biab_ex_warning =
                    biab_ex_warning ..
                    "- Around measure " ..
                        processmore_table[i][3] .. "\n" .. BIAB_main_bars_table[i] .. " may have been simplified.\n"
                buileroo = in_item_table[1][2] .. " " .. in_item_table[2][2] .. " / " .. in_item_table[3][2] .. " "
            elseif
                chord_count_total == 4 and tonumber(in_item_table[1][1]) == tonumber(in_item_table[2][1]) and
                    tonumber(in_item_table[1][1]) == tonumber(in_item_table[3][1]) and
                    tonumber(in_item_table[1][1]) == tonumber(in_item_table[4][1])
             then
                buileroo =
                    in_item_table[1][2] ..
                    " " .. in_item_table[2][2] .. " " .. in_item_table[3][2] .. " " .. in_item_table[4][2] .. " "
            elseif chord_count_total == 4 and split_mult_total > 4 then
                biab_ex_warning =
                    biab_ex_warning ..
                    "- Around measure " ..
                        processmore_table[i][3] ..
                            " " ..
                                "\nthe rhythm of chords " ..
                                    BIAB_main_bars_table[i] .. "\n was simplified due to BIAB limititations.\n"
                buileroo =
                    in_item_table[1][2] ..
                    " " .. in_item_table[2][2] .. " " .. in_item_table[3][2] .. " " .. in_item_table[4][2] .. " "
            elseif chord_count_total > 4 then
                biab_ex_warning =
                    biab_ex_warning ..
                    "- Around measure " ..
                        processmore_table[i][3] ..
                            " " ..
                                BIAB_main_bars_table[i] ..
                                    "\nonly the chords " ..
                                        in_item_table[1][2] ..
                                            " " ..
                                                in_item_table[2][2] ..
                                                    " " ..
                                                        in_item_table[3][2] ..
                                                            " " ..
                                                                in_item_table[4][2] ..
                                                                    "\n could be rendered due to BIAB limit of 4 chords per bar.\n"
                buileroo =
                    in_item_table[1][2] ..
                    " " .. in_item_table[2][2] .. " " .. in_item_table[3][2] .. " " .. in_item_table[4][2] .. " "
            else
                buileroo = BIAB_main_bars_table[i]
            end

            BIAB_main_bars_table[i] = buileroo
        else
            this_single_chord = BIAB_main_bars_table[i]
            addstart = 1
            if string.sub(this_single_chord, 1, 1) == " " then
                addstart = 2
            else
            end
            if string.sub(this_single_chord, addstart, addstart) == "^" then
                if string.sub(this_single_chord, addstart + 1, addstart + 1) == "^" then
                    addstart = addstart + 2
                else
                    addstart = addstart + 1
                end
            else
            end
            if
                string.sub(this_single_chord, addstart, addstart) == "b" or
                    string.sub(this_single_chord, addstart, addstart) == "#"
             then
                addstart = addstart + 2
            else
                addstart = addstart + 1
            end
            endtype, _ = string.find(this_single_chord, "/")
            if endtype ~= nil then
                endtype = endtype - 1
            end
            if endtype == nil then
                endtype, _ = string.find(string.sub(this_single_chord, 2, string.len(this_single_chord)), " ")
            end
            if endtype == nil then
                endtype = string.len(this_single_chord)
            end
            replacetype = string.sub(this_single_chord, addstart, endtype)
            --reaper.ShowConsoleMsg(replacetype .. "\n")
            if musictheory.to_biab_translation[replacetype] ~= nil then
                BIAB_main_bars_table[i] =
                    string.sub(this_single_chord, 1, addstart - 1) ..
                    musictheory.to_biab_translation[replacetype] ..
                        string.sub(this_single_chord, endtype + 1, string.len(this_single_chord))
            end
        end
    end

    for i, v in pairs(BIAB_main_bars_table) do --  DEAL WITH REPEATS ON THE WAY TO TEXT
        if v == "!Repeat!" then
            BIAB_post_table_chord_data = BIAB_post_table_chord_data .. " | " .. the_last_BIAB_bar_content
        else
            BIAB_post_table_chord_data = BIAB_post_table_chord_data .. " | " .. v
            the_last_BIAB_bar_content = v
        end
    end

    BIAB_post_table_chord_data = string.gsub(BIAB_post_table_chord_data, "| Â |", "|A) ") -- SWAP OUT FOR A)
    BIAB_post_table_chord_data = string.gsub(BIAB_post_table_chord_data, "| Å |", "|B) ") -- AND B) SECTION MARKS
    BIAB_post_table_chord_data = string.gsub(BIAB_post_table_chord_data, "<<", "^^") -- SWAP OUT FOR 16th
    BIAB_post_table_chord_data = string.gsub(BIAB_post_table_chord_data, "<", "^") -- AND 8th PUSHES IN BIAB FORMAT

    BIAB_post_table_chord_data = string.gsub(BIAB_post_table_chord_data, " b1", " 1b") -- SWAP OUT ROOTS TO BIAB STYLE
    BIAB_post_table_chord_data = string.gsub(BIAB_post_table_chord_data, " b2", " 2b")
    BIAB_post_table_chord_data = string.gsub(BIAB_post_table_chord_data, " b3", " 3b")
    BIAB_post_table_chord_data = string.gsub(BIAB_post_table_chord_data, " b4", " 4b")
    BIAB_post_table_chord_data = string.gsub(BIAB_post_table_chord_data, " b5", " 5b")
    BIAB_post_table_chord_data = string.gsub(BIAB_post_table_chord_data, " b6", " 6b")
    BIAB_post_table_chord_data = string.gsub(BIAB_post_table_chord_data, " b7", " 7b")

    BIAB_post_table_chord_data = string.gsub(BIAB_post_table_chord_data, "/b1", "/1b") -- SWAP OUT BASS TO BIAB STYLE
    BIAB_post_table_chord_data = string.gsub(BIAB_post_table_chord_data, "/b2", "/2b")
    BIAB_post_table_chord_data = string.gsub(BIAB_post_table_chord_data, "/b3", "/3b")
    BIAB_post_table_chord_data = string.gsub(BIAB_post_table_chord_data, "/b4", "/4b")
    BIAB_post_table_chord_data = string.gsub(BIAB_post_table_chord_data, "/b5", "/5b")
    BIAB_post_table_chord_data = string.gsub(BIAB_post_table_chord_data, "/b6", "/6b")
    BIAB_post_table_chord_data = string.gsub(BIAB_post_table_chord_data, "/b7", "/7b")

    the_BIAB_bar_count = 0
    --reaper.ShowConsoleMsg("\n-----------------------------------------\n")
    for i, v in pairs(processmore_table) do
        the_BIAB_bar_count = the_BIAB_bar_count + tonumber(processmore_table[i][2])
        --reaper.ShowConsoleMsg("COUNT = " .. tonumber(processmore_table[i][2]) .. "TOTAL = " .. the_BIAB_bar_count .. "\n")
    end
    return BIAB_post_table_chord_data, the_BIAB_bar_count, thefail
end

function Split(s, delimiter)
    result = {}
    for match in (s .. delimiter):gmatch("(.-)" .. delimiter) do
        table.insert(result, match)
    end
    return result
end

---------------------------------------------------------Swap out sets of unequal lenght items
-- \\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\
function Swapout(haystack, needletable)
    for swap_i, swap_v in pairs(needletable) do
        ::keepswapping:: -- CONVERT TABS TO SPACES
        local current_text_length = string.len(haystack)
        haystack = string.gsub(haystack, swap_v[1], swap_v[2])
        if current_text_length ~= string.len(haystack) then
            goto keepswapping
        end
    end
    return haystack
end

--  Write to Console - Commented out for general user runtime - Turn on to Debug
function Show_To_User(to_user_message)
    --reaper.ShowConsoleMsg(to_user_message)
end

--  Write to Console - Commented out unless debugging
function Show_To_Dev(to_dev_message)
    reaper.ShowConsoleMsg(to_dev_message)
end

--  A function that returns every value of a table as text - NOT ORIGINAL WORK
function Table_Print(tbl, indent)
    if not indent then
        indent = 0
    end
    local toprint = string.rep(" ", indent) .. "{\r\n"
    indent = indent + 2
    for k, v in pairs(tbl) do
        toprint = toprint .. string.rep(" ", indent)
        if (type(k) == "number") then
            toprint = toprint .. "[" .. k .. "] = "
        elseif (type(k) == "string") then
            toprint = toprint .. k .. "= "
        end
        if (type(v) == "number") then
            toprint = toprint .. v .. ",\r\n"
        elseif (type(v) == "string") then
            toprint = toprint .. '"' .. v .. '",\r\n'
        elseif (type(v) == "table") then
            toprint = toprint .. Table_Print(v, indent + 2) .. ",\r\n"
        else
            toprint = toprint .. '"' .. tostring(v) .. '",\r\n'
        end
    end
    toprint = toprint .. string.rep(" ", indent - 2) .. "}"
    return toprint
end

--  A pair of functions that return convert decimals to fractions - NOT ORIGINAL WORK

function Provide_Fraction(numer, denom)
    fracttop, fractbottom = Convert_Decimal_To_Fraction(numer)
    if fractbottom == 1 then
        fractiontoreturn = fracttop
    else
        fractiontoreturn = string.format("%d/%d", fracttop, fractbottom)
    end
    return fractiontoreturn
end

function Convert_Decimal_To_Fraction(num)
    local W = math.floor(num)
    local F = num - W
    local pn, n, N = 0, 1
    local pd, d, D = 1, 0
    local x, err, q, Q
    repeat
        x = x and 1 / (x - q) or F
        q, Q = math.floor(x), math.floor(x + 0.5)
        pn, n, N = n, q * n + pn, Q * n + pn
        pd, d, D = d, q * d + pd, Q * d + pd
        err = F - N / D
    until math.abs(err) < 1e-15
    return N + D * W, D, err
end

-- Example functions for each case
function case1(s1v, s2v, track)
    reaper.ShowConsoleMsg("Case 1 executed\n" .. s1v .. " \n" .. s2v .. "\n" .. track .. "\n")
end
function case2(s1v, s2v, track)
    reaper.ShowConsoleMsg("Case 2 executed\n" .. s1v .. " \n" .. s2v .. "\n" .. track .. "\n")
end
function case3(s1v, s2v, track)
    reaper.ShowConsoleMsg("Case 3 executed\n" .. s1v .. " \n" .. s2v .. "\n" .. track .. "\n")
end
function case4(s1v, s2v, track)
    reaper.ShowConsoleMsg("Case 4 executed\n" .. s1v .. " \n" .. s2v .. "\n" .. track .. "\n")
end
function case5(s1v, s2v, track)
    reaper.ShowConsoleMsg("Case 5 executed\n" .. s1v .. " \n" .. s2v .. "\n" .. track .. "\n")
end
function case6(s1v, s2v, track)
    reaper.ShowConsoleMsg("Case 6 executed\n" .. s1v .. " \n" .. s2v .. "\n" .. track .. "\n")
end
function case7(s1v, s2v, track)
    reaper.ShowConsoleMsg("Case 7 executed\n" .. s1v .. " \n" .. s2v .. "\n" .. track .. "\n")
end
function case8(s1v, s2v, track)
    reaper.ShowConsoleMsg("Case 8 executed\n" .. s1v .. " \n" .. s2v .. "\n" .. track .. "\n")
end
function case9(s1v, s2v, track)
    reaper.ShowConsoleMsg("Case 9 executed\n" .. s1v .. " \n" .. s2v .. "\n" .. track .. "\n")
end
function case10(s1v, s2v, track)
    reaper.ShowConsoleMsg("Case 10 executed\n" .. s1v .. " \n" .. s2v .. "\n" .. track .. "\n")
end
function case11(s1v, s2v, track)
    reaper.ShowConsoleMsg("Case 11 executed\n" .. s1v .. " \n" .. s2v .. "\n" .. track .. "\n")
end
function case12(s1v, s2v, track)
    reaper.ShowConsoleMsg("Case 12 executed\n" .. s1v .. " \n" .. s2v .. "\n" .. track .. "\n")
end
function case13(s1v, s2v, track)
    reaper.ShowConsoleMsg("Case 13 executed\n" .. s1v .. " \n" .. s2v .. "\n" .. track .. "\n")
end
function case14(s1v, s2v, track)
    reaper.ShowConsoleMsg("Case 14 executed\n" .. s1v .. " \n" .. s2v .. "\n" .. track .. "\n")
end
function case15(s1v, s2v, track)
    reaper.ShowConsoleMsg("Case 15 executed\n" .. s1v .. " \n" .. s2v .. "\n" .. track .. "\n")
end
function case16(s1v, s2v, track)
    reaper.ShowConsoleMsg("Case 16 executed\n" .. s1v .. " \n" .. s2v .. "\n" .. track .. "\n")
end
function case17(s1v, s2v, track)
    reaper.ShowConsoleMsg("Case 17 executed\n" .. s1v .. " \n" .. s2v .. "\n" .. track .. "\n")
end
function case18(s1v, s2v, track)
    reaper.ShowConsoleMsg("Case 18 executed\n" .. s1v .. " \n" .. s2v .. "\n" .. track .. "\n")
end
function case19(s1v, s2v, track)
    reaper.ShowConsoleMsg("Case 19 executed\n" .. s1v .. " \n" .. s2v .. "\n" .. track .. "\n")
end
function case20(s1v, s2v, track)
    reaper.ShowConsoleMsg("Case 20 executed\n" .. s1v .. " \n" .. s2v .. "\n" .. track .. "\n")
end
function case21(s1v, s2v, track)
    reaper.ShowConsoleMsg("Case 21 executed\n" .. s1v .. " \n" .. s2v .. "\n" .. track .. "\n")
end
function case22(s1v, s2v, track)
    reaper.ShowConsoleMsg("Case 22 executed\n" .. s1v .. " \n" .. s2v .. "\n" .. track .. "\n")
end
function case23(s1v, s2v, track)
    reaper.ShowConsoleMsg("Case 23 executed\n" .. s1v .. " \n" .. s2v .. "\n" .. track .. "\n")
end

-- Dispatch table
local caseFunctions = {
    [1] = case1,
    [2] = case2,
    [3] = case3,
    [4] = case4,
    [5] = case5,
    [6] = case6,
    [7] = case7,
    [8] = case8,
    [9] = case9,
    [10] = case10,
    [11] = case11,
    [12] = case12,
    [13] = case13,
    [14] = case14,
    [15] = case15,
    [16] = case16,
    [17] = case17,
    [18] = case18,
    [19] = case19,
    [20] = case20,
    [21] = case21,
    [22] = case22,
    [23] = case23
}

-- Function to find the closest integer
function closestInteger(num)
    return math.floor(num + 0.5)
end

function render_gather_go()
    local num_tracks = reaper.GetNumTracks() -- Count the number of tracks
    --reaper.ShowConsoleMsg("I found " .. num_tracks .. " tracks\n")
    for i = 1, num_tracks - 1 do -- Iterate over all tracks
        local track = reaper.GetTrack(0, i) -- Get the track
        local fx_index = reaper.TrackFX_GetByName(track, "#2notes", false)
        --reaper.ShowConsoleMsg("Found on track " .. i .. " = " .. fx_index .. " \n")
        if fx_index >= 0 then
            local slider1value = reaper.TrackFX_GetParamNormalized(track, fx_index, 0) * 23
            local slider2value = reaper.TrackFX_GetParamNormalized(track, fx_index, 1) * 17
            reaper.ShowConsoleMsg(
                "So slider number 1 of track " ..
                    i ..
                        " is set to " ..
                            slider1value ..
                                " which corresponds with " ..
                                    JSFX_data_request1[slider1value] ..
                                        " and slider number 2 is set to " ..
                                            slider2value ..
                                                " with the corresponding meaning of " ..
                                                    JSFX_data_request2[slider2value + 1] .. "\n"
            )

            local closestCase = closestInteger(slider1value, slider2value)

            -- Execute the corresponding function, if it exists
            if caseFunctions[closestCase] then
                caseFunctions[closestCase](slider1value, slider2value, i)
            else
                reaper.ShowConsoleMsg("No corresponding case for value " .. closestCase)
            end
        end
    end
    modal_on = false
end

-- _______________________________________________________________________ MAIN FUNCTION  ____________________
--Initialize_Track_Setup()
LoadLastNumbers2NotesChart()

-- RUN THE STARTUP AUDIT
local errors_found = Check_Plugins_On_Startup()
if errors_found then
    modal_on = true -- Force the GUI to open the error popup immediately
end




IM_GUI_Loop()
