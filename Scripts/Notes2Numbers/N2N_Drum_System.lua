-- @description N2N Drum System
-- @version 1.5

local script_path = debug.getinfo(1, "S").source:match("@(.*[\\/])")
package.path = package.path .. ";" .. script_path .. "?.lua"

local drum_map = require("MapDrumsToLaunchpad")

--------------------------------------------------
-- USER SETTINGS
--------------------------------------------------
local CHECK_INTERVAL = 2.0
local RESCAN_INTERVAL = 10.0

local CUSTOM_SLOT = 1



local sep = package.config:sub(1,1)

local MIDI_NOTE_NAMES_FOLDER = reaper.GetResourcePath() .. sep .. "MIDINoteNames" .. sep
local DRUM_MAP_FOLDER = reaper.GetResourcePath() .. sep .. "Data" .. sep .. "AHS_Music_Tech" .. sep .. "DrumArranger" .. sep



local TXT_MATCH_THRESHOLD = 60

local EXTSTATE_SECTION = "N2N_Drum_System"
local EXTSTATE_OUTPUT_NAME = "MidiOutputName"

local WINDOW_W = 300
local WINDOW_H = 240
--------------------------------------------------

local watched_tracks = {}
local last_check_time = 0
local last_scan_time = 0
local current_flashed_preset = ""
local is_initial_scan = true

local MIDI_OUTPUT_INDEX = nil
local MIDI_OUTPUT_NAME = nil

--------------------------------------------------
-- IMGUI SETUP
--------------------------------------------------
local has_imgui = reaper.APIExists and reaper.APIExists("ImGui_CreateContext")
local ctx = nil
local font = nil

if has_imgui then
    ctx = reaper.ImGui_CreateContext("N2N Drum System Output")
    font = reaper.ImGui_CreateFont("sans-serif", 14)
    if font then
        reaper.ImGui_Attach(ctx, font)
    end
end

--------------------------------------------------
-- HELPERS
--------------------------------------------------
local function lower(s)
    return (s or ""):lower()
end

local function trim(s)
    return (s or ""):match("^%s*(.-)%s*$") or ""
end

local function normalize_name(s)
    s = lower(s)
    s = s:gsub("%.jsfx$", "")
    s = s:gsub("%.txt$", "")
    s = s:gsub("[_%-%./\\%(%)%[%]]", " ")
    s = s:gsub("%s+", " ")
    s = trim(s)
    return s
end

local function bytes_to_string(t)
    local chars = {}
    for i = 1, #t do
        chars[i] = string.char(t[i])
    end
    return table.concat(chars)
end

local function send_bytes_to_output(output_index, bytes)
    if output_index == nil then return end
    reaper.SendMIDIMessageToHardware(output_index, bytes_to_string(bytes))
end

local function console(msg)
    reaper.ShowConsoleMsg(tostring(msg) .. "\n")
end



local sep = package.config:sub(1,1)

local MIDI_NOTE_NAMES_FOLDER = reaper.GetResourcePath() .. sep .. "MIDINoteNames" .. sep
local DRUM_MAP_FOLDER = reaper.GetResourcePath() .. sep .. "Data" .. sep .. "AHS_Music_Tech" .. sep .. "DrumArranger" .. sep

local function ensure_folder(path)
    reaper.RecursiveCreateDirectory(path, 0)
end





local function strip_reapack_header_lines(data)
    local lines = {}
    local started_real_content = false

    data = data:gsub("\r\n", "\n"):gsub("\r", "\n")

    for line in data:gmatch("([^\n]*)\n?") do
        if line == "" and not started_real_content then
            -- skip leading blank lines
        elseif line:match("^%s*//%s*@") and not started_real_content then
            -- skip leading ReaPack-style header lines like // @version, // @author
        else
            started_real_content = true
            lines[#lines + 1] = line
        end
    end

    return table.concat(lines, "\n")
end

local function copy_file_binary(src, dst)
    local infile = io.open(src, "rb")
    if not infile then return false end

    local data = infile:read("*a")
    infile:close()

    data = strip_reapack_header_lines(data)

    local outfile = io.open(dst, "wb")
    if not outfile then return false end

    outfile:write(data)
    outfile:close()

    return true
end
















local function sync_midi_note_names_to_drum_map_folder()
    ensure_folder(DRUM_MAP_FOLDER)

    local copied = 0
    local failed = 0
    local i = 0

    while true do
        local name = reaper.EnumerateFiles(MIDI_NOTE_NAMES_FOLDER, i)
        if not name then break end

        if lower(name):match("%.txt$") then
            local src = MIDI_NOTE_NAMES_FOLDER .. name
            local dst = DRUM_MAP_FOLDER .. name

            if copy_file_binary(src, dst) then
                copied = copied + 1
            else
                failed = failed + 1
            end
        end

        i = i + 1
    end

  --  reaper.ShowConsoleMsg("Drum map sync: copied " .. copied .. " file(s), failed " .. failed .. "\n")
end













--------------------------------------------------
-- MIDI OUTPUT LIST
--------------------------------------------------
local midi_outputs = {}
local selected_output_ui_index = 1

local function refresh_midi_outputs()
    midi_outputs = {}
    local i = 0
    while true do
        local ok, name = reaper.GetMIDIOutputName(i, "")
        if not ok then break end
        midi_outputs[#midi_outputs + 1] = {
            index = i,
            name = name or ("Output " .. tostring(i))
        }
        i = i + 1
    end
end

local function save_selected_output(name)
    reaper.SetExtState(EXTSTATE_SECTION, EXTSTATE_OUTPUT_NAME, name or "", true)
end

local function load_saved_output()
    local saved_name = reaper.GetExtState(EXTSTATE_SECTION, EXTSTATE_OUTPUT_NAME)
    if saved_name == "" then return end

    for i = 1, #midi_outputs do
        if midi_outputs[i].name == saved_name then
            MIDI_OUTPUT_INDEX = midi_outputs[i].index
            MIDI_OUTPUT_NAME = midi_outputs[i].name
            selected_output_ui_index = i
            return
        end
    end
end

local function ensure_default_output()
    if MIDI_OUTPUT_INDEX ~= nil then return end
    if #midi_outputs > 0 then
        MIDI_OUTPUT_INDEX = midi_outputs[1].index
        MIDI_OUTPUT_NAME = midi_outputs[1].name
        selected_output_ui_index = 1
    end
end

local function set_active_output_from_ui(i)
    local item = midi_outputs[i]
    if not item then return end
    selected_output_ui_index = i
    MIDI_OUTPUT_INDEX = item.index
    MIDI_OUTPUT_NAME = item.name
    save_selected_output(item.name)
end

--------------------------------------------------
-- FX MATCHING
--------------------------------------------------
local function score_candidate_name(candidate, preferred_exact, fallback_list)
    local raw = candidate or ""
    local norm = normalize_name(raw)
    local pref = normalize_name(preferred_exact)

    if raw == preferred_exact then return 1000 end
    if norm == pref then return 950 end

    for i = 1, #(fallback_list or {}) do
        local fb = fallback_list[i]
        local nfb = normalize_name(fb)
        if nfb ~= "" and norm:find(nfb, 1, true) then
            return 900 - i
        end
    end

    return 0
end

local function get_best_matching_fx(track, preferred_exact, fallback_list)
    local fx_count = reaper.TrackFX_GetCount(track)
    local best_fx = nil
    local best_score = 0

    for fx = 0, fx_count - 1 do
        local ok, fx_name = reaper.TrackFX_GetFXName(track, fx, "")
        if ok then
            local score = score_candidate_name(fx_name, preferred_exact, fallback_list)
            if score > best_score then
                best_score = score
                best_fx = fx
            end
        end
    end

    return best_fx, best_score
end

local function get_preset_name(track, fx_index)
    local ok, preset_name = reaper.TrackFX_GetPreset(track, fx_index, "")
    return ok and (preset_name or "") or ""
end

--------------------------------------------------
-- TXT FILE MATCHING
--------------------------------------------------
local function split_words(s)
    local t = {}
    for word in normalize_name(s):gmatch("%S+") do
        t[#t+1] = word
    end
    return t
end

local function token_overlap_score(a, b)
    local wa = split_words(a)
    local wb = split_words(b)

    local set_a, set_b = {}, {}
    for i = 1, #wa do set_a[wa[i]] = true end
    for i = 1, #wb do set_b[wb[i]] = true end

    local common = 0
    local total = 0

    for k in pairs(set_a) do
        total = total + 1
        if set_b[k] then common = common + 1 end
    end
    for k in pairs(set_b) do
        if not set_a[k] then total = total + 1 end
    end

    if total == 0 then return 0 end
    return common / total
end

local function score_filename_match(target_name, candidate_name)
    local t = normalize_name(target_name)
    local c = normalize_name(candidate_name)

    if t == "" or c == "" then return 0 end
    if t == c then return 1000 end
    if c:find(t, 1, true) or t:find(c, 1, true) then return 800 end

    return math.floor(token_overlap_score(t, c) * 100)
end

local function get_best_matching_txt_file(folder, wanted_name)
    local wanted_norm = normalize_name(wanted_name)
    if wanted_norm == "" then return nil, nil, 0 end

    local best_file = nil
    local best_score = 0

    local i = 0
    while true do
        local filename = reaper.EnumerateFiles(folder, i)
        if not filename then break end

        if lower(filename):sub(-4) == ".txt" then
            local score = score_filename_match(wanted_name, filename)
            if score > best_score then
                best_score = score
                best_file = filename
            end
        end

        i = i + 1
    end

    if best_file and best_score >= TXT_MATCH_THRESHOLD then
        return folder .. best_file, best_file, best_score
    end

    return nil, nil, best_score
end

--------------------------------------------------
-- LAUNCHPAD UPDATE
--------------------------------------------------
local function trigger_launchpad_update(preset_name)
    if preset_name == ""
    or preset_name == current_flashed_preset
    or normalize_name(preset_name) == "start page" then
        return
    end

    if MIDI_OUTPUT_INDEX == nil then
        return
    end

    local exact_filename = DRUM_MAP_FOLDER .. preset_name .. ".txt"
    local chosen_path = nil
    local chosen_label = nil

    if reaper.file_exists(exact_filename) then
        chosen_path = exact_filename
        chosen_label = preset_name .. ".txt"
    else
        local best_path, best_file, best_score = get_best_matching_txt_file(DRUM_MAP_FOLDER, preset_name)
        if best_path then
            chosen_path = best_path
            chosen_label = best_file
            console("Preset '" .. preset_name .. "' using closest txt match '" .. best_file .. "' (score " .. tostring(best_score) .. ")")
        end
    end

    if not chosen_path then
        return
    end

    local pad_sysex = drum_map.GenerateSysexFromFile(chosen_path, CUSTOM_SLOT)

    if pad_sysex then
        reaper.SendMIDIMessageToHardware(MIDI_OUTPUT_INDEX, pad_sysex)

        local start = reaper.time_precise()
        while (reaper.time_precise() - start) * 1000 < 100 do end

        local switch_to_custom_sysex = {
            0xF0, 0x00, 0x20, 0x29, 0x02, 0x0D, 0x00, (0x03 + CUSTOM_SLOT), 0xF7
        }
        send_bytes_to_output(MIDI_OUTPUT_INDEX, switch_to_custom_sysex)

        current_flashed_preset = preset_name
    else
        console("Could not generate Launchpad SysEx from file: " .. tostring(chosen_path))
    end
end

--------------------------------------------------
-- TRACK SCAN / SYNC
--------------------------------------------------



local function scan_tracks()
    local new_watched = {}
    local track_count = reaper.CountTracks(0)

    for i = 0, track_count - 1 do
        local track = reaper.GetTrack(0, i)
        if track then
            local track_key = tostring(track)

            local fx_a = get_best_matching_fx(
                track,
                "JS: N2N Drum Arranger.jsfx",
                {
                    "JS: N2N Drum Arranger",
                    "N2N Drum Arranger"
                }
            )

local fx_b = get_best_matching_fx(
    track,
    "VST3i: MONSTER Drums v3",
    {
        "MONSTER Drum v3",
        "MONSTER Drums v3",
        "Monster Drum v3",
        "Monster Drums v3",
        "MONSTER Drum",
        "MONSTER Drums",
        "Monster Drum",
        "Monster Drums"
    }
)

            if fx_a ~= nil and fx_b ~= nil then
                if watched_tracks[track_key] then
                    new_watched[track_key] = watched_tracks[track_key]
                    new_watched[track_key].fx_a = fx_a
                    new_watched[track_key].fx_b = fx_b
                else
                    local preset_a = fx_a and get_preset_name(track, fx_a) or ""
                    local preset_b = fx_b and get_preset_name(track, fx_b) or ""

                    new_watched[track_key] = {
                        track = track,
                        fx_a = fx_a,
                        fx_b = fx_b,
                        last_a = preset_a,
                        last_b = preset_b
                    }

                    if is_initial_scan then
                        local active_preset = (preset_a ~= "") and preset_a or preset_b
                        trigger_launchpad_update(active_preset)
                    end
                end
            end
        end
    end

    watched_tracks = new_watched
    is_initial_scan = false
end

local function sync_pair(data)
    local track = data.track
    if not reaper.ValidatePtr(track, "MediaTrack*") then
        return
    end

    local current_a = data.fx_a and get_preset_name(track, data.fx_a) or ""
    local current_b = data.fx_b and get_preset_name(track, data.fx_b) or ""

    local a_changed = (data.fx_a ~= nil and current_a ~= data.last_a)
    local b_changed = (data.fx_b ~= nil and current_b ~= data.last_b)

    if a_changed then
        if data.fx_b ~= nil then
            reaper.TrackFX_SetPreset(track, data.fx_b, current_a)
            current_b = get_preset_name(track, data.fx_b)
        end

        data.last_a = current_a
        data.last_b = current_b
        trigger_launchpad_update(current_b ~= "" and current_b or current_a)

    elseif b_changed then
        data.last_b = current_b
        trigger_launchpad_update(current_b)
    end
end

--------------------------------------------------
-- IMGUI WINDOW
--------------------------------------------------
local function draw_output_window()
    if not has_imgui or not ctx then return end

    reaper.ImGui_SetNextWindowSize(ctx, WINDOW_W, WINDOW_H, reaper.ImGui_Cond_Always())

    local vp = reaper.ImGui_GetMainViewport(ctx)
    local vx, vy = reaper.ImGui_Viewport_GetPos(vp)
    local vw, vh = reaper.ImGui_Viewport_GetSize(vp)
    local x = vx + (vw - WINDOW_W) * 0.5
    local y = vy + (vh - WINDOW_H) * 0.5
    reaper.ImGui_SetNextWindowPos(ctx, x, y, reaper.ImGui_Cond_FirstUseEver())

local flags = reaper.ImGui_WindowFlags_NoCollapse() | reaper.ImGui_WindowFlags_NoResize()
local visible, open = reaper.ImGui_Begin(ctx, "N2N Drum System - MIDI Output", true, flags)
    if visible then
        reaper.ImGui_Text(ctx, "Click a MIDI hardware output to make it active.")
        reaper.ImGui_Separator(ctx)

        if reaper.ImGui_Button(ctx, "Refresh Outputs") then
            local old_name = MIDI_OUTPUT_NAME
            refresh_midi_outputs()
            if old_name then
                for i = 1, #midi_outputs do
                    if midi_outputs[i].name == old_name then
                        selected_output_ui_index = i
                        MIDI_OUTPUT_INDEX = midi_outputs[i].index
                        MIDI_OUTPUT_NAME = midi_outputs[i].name
                        break
                    end
                end
            end
            if MIDI_OUTPUT_INDEX == nil then
                ensure_default_output()
            end
        end

        reaper.ImGui_SameLine(ctx)
        reaper.ImGui_Text(ctx, "Active: " .. tostring(MIDI_OUTPUT_NAME or "None"))

        if reaper.ImGui_BeginListBox(ctx, "##midioutputs", -1, 150) then
            for i = 1, #midi_outputs do
                local item = midi_outputs[i]
                local selected = (selected_output_ui_index == i)
                local label = string.format("[%d] %s", item.index, item.name)

                if reaper.ImGui_Selectable(ctx, label, selected) then
                    set_active_output_from_ui(i)
                end
                if selected then
                    reaper.ImGui_SetItemDefaultFocus(ctx)
                end
            end
            reaper.ImGui_EndListBox(ctx)
        end
    end
    reaper.ImGui_End(ctx)
end

--------------------------------------------------
-- MAIN
--------------------------------------------------
local function main()
    local now = reaper.time_precise()

    if (now - last_scan_time) >= RESCAN_INTERVAL then
        scan_tracks()
        last_scan_time = now
    end

    if (now - last_check_time) >= CHECK_INTERVAL then
        for _, data in pairs(watched_tracks) do
            sync_pair(data)
        end
        last_check_time = now
    end

    draw_output_window()
    reaper.defer(main)
end

--------------------------------------------------
-- STARTUP
--------------------------------------------------
sync_midi_note_names_to_drum_map_folder()


refresh_midi_outputs()
load_saved_output()
ensure_default_output()




scan_tracks()
last_scan_time = reaper.time_precise()
last_check_time = reaper.time_precise()
main()
