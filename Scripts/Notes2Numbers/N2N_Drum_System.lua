-- @description N2N Drum System
-- @version 2.0

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
local EXTSTATE_MANUAL_MODE = "ManualMode"
local EXTSTATE_MODEL = "Model"

local WINDOW_W = 700
local WINDOW_H = 410
--------------------------------------------------

local watched_tracks = {}
local last_check_time = 0
local last_scan_time = 0
local current_flashed_preset = ""
local is_initial_scan = true

-- FORWARD DECLARATION: This tells the UI above that the function exists below!
local trigger_device_init_sequence

local MIDI_OUTPUT_INDEX = nil
local MIDI_OUTPUT_NAME = nil
local manual_midi_mode = false
local selected_model = "M" -- Default to Mini

local ui_state = "MAIN" -- "MAIN", "PROMPT", "CLOSED"
local sysex_queue = {}

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
local function lower(s) return (s or ""):lower() end
local function trim(s) return (s or ""):match("^%s*(.-)%s*$") or "" end

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
    for i = 1, #t do chars[i] = string.char(t[i]) end
    return table.concat(chars)
end

local function send_bytes_to_output(output_index, bytes)
    if output_index == nil then return end
    reaper.SendMIDIMessageToHardware(output_index, bytes_to_string(bytes))
end

local function console(msg)
    reaper.ShowConsoleMsg(tostring(msg) .. "\n")
end

local function ensure_folder(path)
    reaper.RecursiveCreateDirectory(path, 0)
end

local function strip_reapack_header_lines(data)
    local lines = {}
    local started_real_content = false
    data = data:gsub("\r\n", "\n"):gsub("\r", "\n")
    for line in data:gmatch("([^\n]*)\n?") do
        if line == "" and not started_real_content then
        elseif line:match("^%s*//%s*@") and not started_real_content then
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
    local copied, failed, i = 0, 0, 0
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
end

--------------------------------------------------
-- MIDI OUTPUT LIST
--------------------------------------------------
local midi_outputs = {}
local selected_output_ui_index = 1

local function refresh_midi_outputs()
    midi_outputs = {}
    -- Fix for Bug #1: Ensure looping 0-63 to skip unassigned IDs (common OS gap issue)
    for i = 0, 63 do
        local ok, name = reaper.GetMIDIOutputName(i, "")
        if ok then
            midi_outputs[#midi_outputs + 1] = {
                index = i,
                name = (name ~= "") and name or ("Output " .. tostring(i))
            }
        end
    end
end

local function save_selected_output(name)
    reaper.SetExtState(EXTSTATE_SECTION, EXTSTATE_OUTPUT_NAME, name or "", true)
end



local function load_saved_output()
    local saved_mode = reaper.GetExtState(EXTSTATE_SECTION, EXTSTATE_MANUAL_MODE)
    manual_midi_mode = (saved_mode == "1")

    local saved_model = reaper.GetExtState(EXTSTATE_SECTION, EXTSTATE_MODEL)
    if saved_model == "M" or saved_model == "X" or saved_model == "P" or saved_model == "K" then
        selected_model = saved_model
    end

    local saved_name = reaper.GetExtState(EXTSTATE_SECTION, EXTSTATE_OUTPUT_NAME)
    
    
    
    
    
    if manual_midi_mode then
        if saved_name ~= "" then
            MIDI_OUTPUT_INDEX = tonumber(saved_name) or 0
            MIDI_OUTPUT_NAME = "Manual ID " .. tostring(MIDI_OUTPUT_INDEX)
        end
        return
    end

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
    if MIDI_OUTPUT_INDEX ~= nil or manual_midi_mode then return end
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
    
    -- Send Init Sequence when device is changed via list
    if current_flashed_preset ~= "" then
        trigger_device_init_sequence(current_flashed_preset)
    end
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
        if nfb ~= "" and norm:find(nfb, 1, true) then return 900 - i end
    end
    return 0
end

local function get_best_matching_fx(track, preferred_exact, fallback_list)
    local fx_count = reaper.TrackFX_GetCount(track)
    local best_fx, best_score = nil, 0
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

-- Replaces get_preset_name for the N2N Arranger
local function get_n2n_slider10(track, fx_index)
    local ok, value_str = reaper.TrackFX_GetFormattedParamValue(track, fx_index, 9, "")
    return ok and (value_str or "") or ""
end

--------------------------------------------------
-- TXT FILE MATCHING
--------------------------------------------------
local function split_words(s)
    local t = {}
    for word in normalize_name(s):gmatch("%S+") do t[#t+1] = word end
    return t
end

local function token_overlap_score(a, b)
    local wa, wb = split_words(a), split_words(b)
    local set_a, set_b = {}, {}
    for i = 1, #wa do set_a[wa[i]] = true end
    for i = 1, #wb do set_b[wb[i]] = true end
    local common, total = 0, 0
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
    local t, c = normalize_name(target_name), normalize_name(candidate_name)
    if t == "" or c == "" then return 0 end
    if t == c then return 1000 end
    if c:find(t, 1, true) or t:find(c, 1, true) then return 800 end
    return math.floor(token_overlap_score(t, c) * 100)
end

local function get_best_matching_txt_file(folder, wanted_name)
    local wanted_norm = normalize_name(wanted_name)
    if wanted_norm == "" then return nil, nil, 0 end
    local best_file, best_score, i = nil, 0, 0
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
-- SYSEX QUEUE / LAUNCHPAD UPDATE
--------------------------------------------------
local function process_sysex_queue()
    if #sysex_queue == 0 then return end
    local now = reaper.time_precise()
    
    local task = sysex_queue[1]
    if now >= task.time then
        if task.type == "color" then
            local tmp_path = DRUM_MAP_FOLDER .. "tmp_color_seq.txt"
            local f = io.open(tmp_path, "w")
            if f then
                f:write(task.text)
                f:close()
                local pad_sysex = drum_map.GenerateSysexFromFile(tmp_path, CUSTOM_SLOT, selected_model)
                if pad_sysex and MIDI_OUTPUT_INDEX then
                    reaper.SendMIDIMessageToHardware(MIDI_OUTPUT_INDEX, pad_sysex)
                end
            end
        elseif task.type == "final" then
            local pad_sysex = drum_map.GenerateSysexFromFile(task.path, CUSTOM_SLOT, selected_model)
            if pad_sysex and MIDI_OUTPUT_INDEX then
                reaper.SendMIDIMessageToHardware(MIDI_OUTPUT_INDEX, pad_sysex)
                table.insert(sysex_queue, 2, { time = now + 0.1, type = "switch" })
            else
                console("Could not generate Launchpad SysEx from file: " .. tostring(task.path))
            end
            
            
            
            
        elseif task.type == "switch" then
            if MIDI_OUTPUT_INDEX then
                -- Dynamically select the correct Novation Device ID
                local model_id = 0x0D -- Mini Mk3
                if selected_model == "X" then model_id = 0x0C
                elseif selected_model == "P" then model_id = 0x0E
                elseif selected_model == "K" then model_id = 0x14 -- Launchkey Mk4
                end
                
                local switch_to_custom_sysex = { 0xF0, 0x00, 0x20, 0x29, 0x02, model_id, 0x00, (0x03 + CUSTOM_SLOT), 0xF7 }
                send_bytes_to_output(MIDI_OUTPUT_INDEX, switch_to_custom_sysex)
            end
        end
        
        
        
        
        table.remove(sysex_queue, 1)
    end
end

-- FUNCTION 1: Full Init Color Sequence (Assigned to global namespace because of forward declaration)
function trigger_device_init_sequence(preset_name)
    -- We removed the preset == current check here so it forces a flash when you select a NEW device!
    if preset_name == "" or normalize_name(preset_name) == "start page" then
        return
    end

    if MIDI_OUTPUT_INDEX == nil then return end

    local exact_filename = DRUM_MAP_FOLDER .. preset_name .. ".txt"
    local chosen_path = nil

    if reaper.file_exists(exact_filename) then
        chosen_path = exact_filename
    else
        local best_path, best_file, best_score = get_best_matching_txt_file(DRUM_MAP_FOLDER, preset_name)
        if best_path then chosen_path = best_path end
    end

    if not chosen_path then return end

    current_flashed_preset = preset_name
    local now = reaper.time_precise()
    
    -- Assign sequence to queue
    sysex_queue = {
        { time = now,       type = "color", text = "35   //   Red" },
        { time = now + 0.7, type = "color", text = "35   //   Amber" },
        { time = now + 1.4, type = "color", text = "35   //   Green" },
        { time = now + 2.1, type = "final", path = chosen_path }
    }
end

-- FUNCTION 2: Fast Kit Switching
local function update_launchpad_kit_only(preset_name)
    -- This keeps the duplicate check so we don't resend the same kit repeatedly during playback
    if preset_name == "" or preset_name == current_flashed_preset or normalize_name(preset_name) == "start page" then
        return
    end

    if MIDI_OUTPUT_INDEX == nil then return end

    local exact_filename = DRUM_MAP_FOLDER .. preset_name .. ".txt"
    local chosen_path = nil

    if reaper.file_exists(exact_filename) then
        chosen_path = exact_filename
    else
        local best_path, best_file, best_score = get_best_matching_txt_file(DRUM_MAP_FOLDER, preset_name)
        if best_path then chosen_path = best_path end
    end

    if not chosen_path then return end

    current_flashed_preset = preset_name
    
    -- Skip the color flashes, send final immediately
    sysex_queue = {
        { time = reaper.time_precise(), type = "final", path = chosen_path }
    }
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
            local fx_a = get_best_matching_fx(track, "JS: N2N Drum Arranger.jsfx", {"JS: N2N Drum Arranger", "N2N Drum Arranger"})
            local fx_b = get_best_matching_fx(track, "VST3i: MONSTER Drums v3", {
                "MONSTER Drum v3", "MONSTER Drums v3", "Monster Drum v3", "Monster Drums v3",
                "MONSTER Drum", "MONSTER Drums", "Monster Drum", "Monster Drums"
            })

            if fx_a ~= nil and fx_b ~= nil then
                if watched_tracks[track_key] then
                    new_watched[track_key] = watched_tracks[track_key]
                    new_watched[track_key].fx_a = fx_a
                    new_watched[track_key].fx_b = fx_b
                else
                    local current_a = fx_a and get_n2n_slider10(track, fx_a) or ""
                    local preset_b = fx_b and get_preset_name(track, fx_b) or ""

                    new_watched[track_key] = {
                        track = track,
                        fx_a = fx_a,
                        fx_b = fx_b,
                        last_a = current_a,
                        last_b = preset_b
                    }

                    if is_initial_scan then
                        local active_preset = (current_a ~= "") and current_a or preset_b
                        -- Fire Init sequence on script boot!
                        trigger_device_init_sequence(active_preset)
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
    if not reaper.ValidatePtr(track, "MediaTrack*") then return end

    local current_a = data.fx_a and get_n2n_slider10(track, data.fx_a) or ""
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
        -- Fire fast switch when actively changing kits
        update_launchpad_kit_only(current_b ~= "" and current_b or current_a)

    elseif b_changed then
        data.last_b = current_b
        update_launchpad_kit_only(current_b)
    end
end

--------------------------------------------------
-- IMGUI WINDOWS
--------------------------------------------------
local function draw_quit_prompt()
    if not has_imgui or not ctx then return end

    reaper.ImGui_SetNextWindowSize(ctx, 185, 70, reaper.ImGui_Cond_Always())
    local flags = reaper.ImGui_WindowFlags_NoCollapse() | reaper.ImGui_WindowFlags_NoResize()
    local visible, open = reaper.ImGui_Begin(ctx, "N2N Drum System", true, flags)
    
    if visible then
        reaper.ImGui_Spacing(ctx)
        
        if reaper.ImGui_Button(ctx, "SETTINGS", 80, 25) then
            ui_state = "MAIN"
        end
        reaper.ImGui_SameLine(ctx)
        if reaper.ImGui_Button(ctx, "QUIT", 80, 25) then
            ui_state = "CLOSED"
        end
    end
    reaper.ImGui_End(ctx)
    
    if not open then
        ui_state = "CLOSED"
    end
end

local function draw_output_window()
    if not has_imgui or not ctx then return end

    reaper.ImGui_SetNextWindowSize(ctx, WINDOW_W, WINDOW_H)

    local vp = reaper.ImGui_GetMainViewport(ctx)
    local vx, vy = reaper.ImGui_Viewport_GetPos(vp)
    local vw, vh = reaper.ImGui_Viewport_GetSize(vp)
    local x = vx + (vw - WINDOW_W) * 0.5
    local y = vy + (vh - WINDOW_H) * 0.5
    reaper.ImGui_SetNextWindowPos(ctx, x, y, reaper.ImGui_Cond_FirstUseEver())

    local flags = reaper.ImGui_WindowFlags_NoCollapse() | reaper.ImGui_WindowFlags_NoResize()
    local visible, open = reaper.ImGui_Begin(ctx, "N2N Drum System - MIDI Output", true, flags)
    
    if visible then
        reaper.ImGui_Text(ctx, "Select or define a MIDI hardware output for your Launchpad.")
        reaper.ImGui_SameLine(ctx)
        reaper.ImGui_Dummy(ctx,245,10)
        
        reaper.ImGui_SameLine(ctx)
        if reaper.ImGui_Button(ctx, "QUIT", 70, 25) then
            ui_state = "CLOSED"
        end
        
        reaper.ImGui_Separator(ctx)    
        

        
        -- "Launchpad Mini Mk3" - M, "Launchpad X Mk3" - X, "Launchpad Pro Mk3" - P, "Launchkey Mk4" - K
        
        reaper.ImGui_Text(ctx, "Select Device Model:")
                
                local function SetModel(m)
                    selected_model = m
                    reaper.SetExtState(EXTSTATE_SECTION, EXTSTATE_MODEL, selected_model, true)
                    if current_flashed_preset ~= "" then
                        trigger_device_init_sequence(current_flashed_preset)
                    end
                end
        
                if reaper.ImGui_RadioButton(ctx, "Launchpad Mini Mk3", selected_model == "M") then SetModel("M") end
                reaper.ImGui_SameLine(ctx)
                
                if reaper.ImGui_RadioButton(ctx, "Launchpad X Mk3", selected_model == "X") then SetModel("X") end
                reaper.ImGui_SameLine(ctx)
                
                if reaper.ImGui_RadioButton(ctx, "Launchpad Pro Mk3", selected_model == "P") then SetModel("P") end
                reaper.ImGui_SameLine(ctx)
                
                if reaper.ImGui_RadioButton(ctx, "Launchkey Mk4", selected_model == "K") then SetModel("K") end
        
        
        reaper.ImGui_Separator(ctx)

        local rv
        rv, manual_midi_mode = reaper.ImGui_Checkbox(ctx, "Use Manual Device ID", manual_midi_mode)
        if rv then
            reaper.SetExtState(EXTSTATE_SECTION, EXTSTATE_MANUAL_MODE, manual_midi_mode and "1" or "0", true)
            if manual_midi_mode then
                MIDI_OUTPUT_INDEX = tonumber(reaper.GetExtState(EXTSTATE_SECTION, EXTSTATE_OUTPUT_NAME)) or 0
                MIDI_OUTPUT_NAME = "Manual ID " .. tostring(MIDI_OUTPUT_INDEX)
            else
                refresh_midi_outputs()
                load_saved_output()
                ensure_default_output()
            end
        end


        if manual_midi_mode then
            reaper.ImGui_Text(ctx, "Set MIDI Hardware Output ID (+ / -):")
            local current_id = MIDI_OUTPUT_INDEX or 0
            
            reaper.ImGui_PushItemWidth(ctx, 150)
            local id_rv, new_val = reaper.ImGui_InputInt(ctx, "##manualid", current_id)
            reaper.ImGui_PopItemWidth(ctx)
            
            if id_rv then
                if new_val < 0 then new_val = 0 end
                MIDI_OUTPUT_INDEX = new_val
                MIDI_OUTPUT_NAME = "Manual ID " .. tostring(new_val)
                save_selected_output(tostring(new_val))
                
                -- Send Init Sequence when device is changed manually
                if current_flashed_preset ~= "" then
                    trigger_device_init_sequence(current_flashed_preset)
                end
            end
            
            reaper.ImGui_Spacing(ctx)
            reaper.ImGui_TextColored(ctx, 0xFFD700FF, "Active Out: " .. tostring(MIDI_OUTPUT_NAME or "None"))
        else
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
            reaper.ImGui_TextColored(ctx, 0xFFD700FF, "Active Out: " .. tostring(MIDI_OUTPUT_NAME or "None"))

            if #midi_outputs == 0 then
                reaper.ImGui_TextColored(ctx, 0xFF0000FF, "No MIDI Devices Detected.")
            else
                if reaper.ImGui_BeginListBox(ctx, "##midioutputs", -1, 240) then
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
        end
    end
    reaper.ImGui_End(ctx)
    
    if not open then
        ui_state = "PROMPT"
    end
end

--------------------------------------------------
-- MAIN
--------------------------------------------------
local function main()
    if ui_state == "CLOSED" then return end

    process_sysex_queue()

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

    if ui_state == "MAIN" then
        draw_output_window()
    elseif ui_state == "PROMPT" then
        draw_quit_prompt()
    end
    
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
