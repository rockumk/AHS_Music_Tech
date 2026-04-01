-- @description FX Graffiti
-- @author Rock Kennedy (Mac/Cross-Platform Refactor v1.2.2)
-- @version 1.2.2
-- @about
--   A ReaScript to draw and overlay custom shapes/graffiti on FX windows.
--   Features include importing/exporting overlays, customizable shapes (circles, squares, outlines),
--   opacity controls, and dynamic window tracking.
-- @changelog
--   + Fixed ImGui GetCursorPos argument crash.
--   + Anchored Prompt Menu and Hover Math to ImGui space to bypass macOS inverted OS coordinates.
--   + Fixed hidden dot indicator placement on Mac.

--------------------------------------------------------------------------------
-- INITIALIZATION & DEPENDENCIES
--------------------------------------------------------------------------------
local reaper = reaper
package.path = package.path .. ";" .. reaper.ImGui_GetBuiltinPath() .. "/?.lua"
local ImGui = require("imgui")

local ctx = reaper.ImGui_CreateContext("FX-Graffiti")

--------------------------------------------------------------------------------
-- FILE PATHS & DIRECTORIES
--------------------------------------------------------------------------------
local resource_path = reaper.GetResourcePath():gsub("\\", "/")
local base_folder = resource_path .. "/Data/FXGraffiti"
local data_folder = base_folder .. "/FXGraffiti_Data"
local overlays_folder = base_folder .. "/FXGraffiti_Overlays"
local marker_filename = data_folder .. "/FXGraffiti_Overlay_Data.txt"

--------------------------------------------------------------------------------
-- GLOBALS & STATE VARIABLES
--------------------------------------------------------------------------------
local colortable_row_count = 5
local colortable_column_count = 13
local UI_AREA_START_Y_REL = 40 
local ui_area_start_y_abs = nil 
local temp_hidden_fx = {}
local colors = {
    -- Row 1: Lightest shades
    0xFAD1D1FF, 0xFAE6D1FF, 0xFAFAD1FF, 0xE6FAD1FF, 0xD1FAD1FF, 0xD1FAE6FF, 0xD1FAFAFF, 0xD1E6FAFF, 0xD1D1FAFF, 0xE6D1FAFF, 0xFAD1FAFF, 0xFAD1E6FF, 0xFFFFFFFF,
    -- Row 2: Mid-light colors
    0xF07575FF, 0xF0B275FF, 0xF0F075FF, 0xB2F075FF, 0x75F075FF, 0x75F0B2FF, 0x75F0F0FF, 0x75B2F0FF, 0x7575F0FF, 0xB275F0FF, 0xF075F0FF, 0xF075B2FF, 0xC0C0C0FF,
    -- Row 3: Mid-tones
    0xE61919FF, 0xE68019FF, 0xE6E619FF, 0x80E619FF, 0x19E619FF, 0x19E680FF, 0x19E6E6FF, 0x1980E6FF, 0x1919E6FF, 0x8019E6FF, 0xE619E6FF, 0xE61980FF, 0x808080FF,
    -- Row 4: Darker versions
    0x8A0F0FFF, 0x8A4C0FFF, 0x8A8A0FFF, 0x4C8A0FFF, 0x0F8A0FFF, 0x0F8A4CFF, 0x0F8A8AFF, 0x0F4C8AFF, 0x0F0F8AFF, 0x4C0F8AFF, 0x8A0F8AFF, 0x8A0F4CFF, 0x404040FF,
    -- Row 5: Deepest tones
    0x2E0505FF, 0x2E1A05FF, 0x2E2E05FF, 0x1A2E05FF, 0x052E05FF, 0x052E1AFF, 0x052E2EFF, 0x051A2EFF, 0x05052EFF, 0x1A052EFF, 0x2E052EFF, 0x2E051AFF, 0x010101FF
}

local edit_mode = false
local backup_circles = nil
local square_size = 15
local pending_focus_change = nil
local pending_focus_counter = 0
local selected_shape = "circle"
local transparency_value = 255
local move_start_time = nil
local move_delay = 0.2
local move_repeat_rate = 0.05
local default_width = 20
local default_height = 20
local overlay_active = false
local selected_color = 0xFFFFFFFF
local fx_markers = {}
local last_track, last_index = nil, nil
local fx_persist_timer = 0
local quit_requested = false
local selected_dot = nil
local last_transparency_value = 255
local selected_dots = {}
local drag_active = false
local drag_start_x, drag_start_y = nil, nil
local select_rect_active = false
local select_rect_start_x, select_rect_start_y = nil, nil
local select_rect_end_x, select_rect_end_y = nil, nil
local show_import_confirm = false
local show_overlay_choice = false
local overlayChoiceData = nil
local show_duplicate_confirm = false
local duplicateFXName = ""
local duplicateOverlay = nil
local duplicateAllFlag = false
local currentFXName = ""
local edit_prompt_timer = 0
local edit_prompt_hold_frames = 20

--------------------------------------------------------------------------------
-- HELPER FUNCTIONS
--------------------------------------------------------------------------------
function sanitizeFilename(filename)
    return filename:gsub('[\\/:%*%?"<>|]', "_")
end

local function FX_HasOverlay(fx_data)
    return fx_data and fx_data.circles and #fx_data.circles > 0
end

local function FX_IsOverlayVisible(fx_name, fx_data)
    if not fx_name or not fx_data then return false end
    if temp_hidden_fx[fx_name] then return false end
    return fx_data.visible ~= false
end

local function FX_IsOverlayHidden(fx_name, fx_data)
    return FX_HasOverlay(fx_data) and not FX_IsOverlayVisible(fx_name, fx_data)
end

function adjustOverlayBounds(overlay)
    local fxWidth, fxHeight = 800, 600
    if overlay and overlay.circles then
        for i, dot in ipairs(overlay.circles) do
            if dot.x > fxWidth or dot.y > fxHeight then
                dot.x = 10
                dot.y = 10
            end
        end
    end
    return overlay
end

function loadOverlayFromFile(filepath)
    local f = io.open(filepath, "r")
    if not f then return nil end
    local content = f:read("*a")
    f:close()

    local chunk, err = load(content)
    if not chunk then
        reaper.ShowConsoleMsg("Failed to parse overlay file: " .. tostring(err) .. "\n")
        return nil
    end

    local ok, importedData = pcall(chunk)
    if not ok then
        reaper.ShowConsoleMsg("Failed to execute overlay file: " .. tostring(importedData) .. "\n")
        return nil
    end
    return importedData
end

function Load_FX_Settings(track, index)
    local _, fx_name = reaper.TrackFX_GetFXName(track, index, "")
    currentFXName = fx_name

    if not fx_markers[fx_name] then
        fx_markers[fx_name] = { circles = {}, visible = true }
    else
        fx_markers[fx_name].circles = fx_markers[fx_name].circles or {}
        if fx_markers[fx_name].visible == nil then
            fx_markers[fx_name].visible = true
        end
    end
    return fx_markers[fx_name]
end

function importOverlay()
    local retval, file = reaper.GetUserFileNameForRead(overlays_folder .. "/", "Select overlay file", ".txt")
    if not retval or not file or file == "" then return end

    local importedData = loadOverlayFromFile(file)
    if not importedData then return end

    local layoutCount = 0
    local firstOverlay = nil
    for _ in pairs(importedData) do
        layoutCount = layoutCount + 1
        if not firstOverlay then firstOverlay = importedData[next(importedData)] end
    end

    if layoutCount == 1 and firstOverlay and firstOverlay.circles then
        fx_markers[currentFXName or "ImportedOverlay"] = Fix_Out_Of_Bounds(firstOverlay, last_track, last_index)
        Save_FX_Graffiti()
    elseif layoutCount > 1 then
        overlayChoiceData = importedData
        show_overlay_choice = true
    else
        reaper.ShowConsoleMsg("Invalid overlay data in " .. file .. "\n")
    end
end

function Fix_Out_Of_Bounds(overlay_data, track, index)
    if not overlay_data or not overlay_data.circles or not track or not index then return overlay_data end
    local fx_window = reaper.TrackFX_GetFloatingWindow(track, index)
    if not fx_window then return overlay_data end
    local ret, left, top, right, bottom = reaper.JS_Window_GetRect(fx_window)
    if not ret then return overlay_data end
    local overlay_width = math.abs(right - left) - 16
    local draw_height = (bottom - top) - 38

    for _, dot in ipairs(overlay_data.circles) do
        local w = dot.width or default_width
        local h = dot.height or default_height
        if dot.x < 0 or dot.x + w / 2 > overlay_width or dot.y < 0 or dot.y + h / 2 > draw_height then
            dot.x = 10
            dot.y = 10
        end
    end
    return overlay_data
end

local function ContainsDot(dots, index)
    for _, dot in ipairs(dots) do
        if dot.index == index then return true end
    end
    return false
end

local function DrawThickEllipse(draw_list, cx, cy, rx, ry, color, thickness)
    for i = 0, thickness - 1 do
        reaper.ImGui_DrawList_AddEllipse(draw_list, cx, cy, rx + i, ry + i, color, 0)
    end
end

local function DrawThickRect(draw_list, x1, y1, x2, y2, color, thickness)
    for i = 0, thickness - 1 do
        reaper.ImGui_DrawList_AddRect(draw_list, x1 - i, y1 - i, x2 + i, y2 + i, color, 0)
    end
end

function Load_FX_Dots_and_Graffiti()
    local file = io.open(marker_filename, "r")
    if file then
        local content = file:read("*a")
        file:close()
        local loadedFunc = load(content)
        if loadedFunc then
            local ok, result = pcall(loadedFunc)
            if ok and type(result) == "table" then
                fx_markers = result
            else
                fx_markers = {}
            end
        end
    else
        fx_markers = {}
    end
end

local function Check_For_Quit()
    if quit_requested then
        Cleanup()
        return true
    end
    return false
end

function Cleanup() end

local function Initialize_Overlay_Window()
    reaper.ImGui_SetNextWindowSize(ctx, 300, 85)
    local visible, open_state = reaper.ImGui_Begin(ctx, "FX Graffiti Setup", true, reaper.ImGui_WindowFlags_NoDecoration())
    return visible, open_state
end

--------------------------------------------------------------------------------
-- DIALOG DEFERRAL SYSTEM
--------------------------------------------------------------------------------
local pending_dialog = nil
local dialog_wait_frames = 0

local function Handle_Pending_Dialog()
    if pending_dialog == "import" then
        importOverlay()
    elseif pending_dialog == "import_multiple" then
        local retval, file = reaper.GetUserFileNameForRead(overlays_folder, "Select overlay library file", "txt")
        if retval and file and file ~= "" then
            local importedLibrary = loadOverlayFromFile(file)
            if importedLibrary then
                for fxName, overlay in pairs(importedLibrary) do
                    if fx_markers[fxName] and not duplicateAllFlag then
                        show_duplicate_confirm = true
                        duplicateFXName = fxName
                        duplicateOverlay = overlay
                        break
                    else
                        fx_markers[fxName] = overlay
                    end
                end
                Save_FX_Graffiti()
            end
        end
    elseif pending_dialog == "export" then
        local safeFXName = sanitizeFilename(currentFXName or "CurrentFX")
        local retval, file = reaper.JS_Dialog_BrowseForSaveFile("Export current overlay", overlays_folder, safeFXName .. ".txt", "Text Files (*.txt)\0*.txt\0")
        if retval and file and file ~= "" then
            if not file:match("%.txt$") then file = file .. ".txt" end
            local exportTable = {[currentFXName] = fx_markers[currentFXName] or {} }
            local f = io.open(file, "w")
            if f then
                f:write("return " .. Serialize_Table(exportTable))
                f:close()
            end
        end
    elseif pending_dialog == "export_all" then
        local retval, file = reaper.JS_Dialog_BrowseForSaveFile("Export All Overlays", data_folder, "FXGraffiti_Overlay_Data_backup.txt", "Text Files (*.txt)\0*.txt\0")
        if retval and file and file ~= "" then
            if not file:match("%.txt$") then file = file .. ".txt" end
            local f = io.open(file, "w")
            if f then
                f:write("return " .. Serialize_Table(fx_markers))
                f:close()
            end
        end
    end
    pending_dialog = nil
end

--------------------------------------------------------------------------------
-- CORE FX TRACKING LOGIC
--------------------------------------------------------------------------------
local function GUI_Work(visible)
    local restart_required = false

    if pending_dialog then
        dialog_wait_frames = dialog_wait_frames - 1
        if dialog_wait_frames <= 0 then Handle_Pending_Dialog() end
        if visible then
            if reaper.ImGui_Button(ctx, "Quit") then quit_requested = true end
            reaper.ImGui_End(ctx)
        end
        return false
    end

    if visible then
        local fx_found, track, index = Check_For_Focused_FX()
        if fx_found then
            restart_required = FX_Found_Prep_Overlay(track, index)
        else
            FX_Not_Found_Signal_No_Overlay()
        end
        if reaper.ImGui_Button(ctx, "Quit") then quit_requested = true end
        reaper.ImGui_PushTextWrapPos(ctx, 0)
        reaper.ImGui_Text(ctx, "Hover near an FX window title bar and hold down 'Opt/Alt' (or Cmd/Ctrl) to get started.")
        reaper.ImGui_PopTextWrapPos(ctx)
    end

    reaper.ImGui_End(ctx)
    return restart_required
end

function Check_For_Focused_FX()
    local fx_found, track, index
    if edit_mode then
        fx_found = (last_track ~= nil)
        track, index = last_track, last_index
    else
        local retval, trk, _, idx = reaper.GetFocusedFX2()
        if retval & 1 == 1 and trk > 0 then
            fx_found, track, index = true, reaper.GetTrack(0, trk - 1), idx
        else
            fx_found, track, index = false, nil, nil
        end
    end
    return fx_found, track, index
end

function FX_Found_Prep_Overlay(track, index)
    fx_persist_timer = 30
    if not last_track or (not edit_mode and (track ~= last_track or index ~= last_index)) then
        if pending_focus_change and pending_focus_change.track == track and pending_focus_change.index == index then
            pending_focus_counter = pending_focus_counter - 1
            if pending_focus_counter <= 0 then
                last_track, last_index = track, index
                local fx_data = Load_FX_Settings(track, index)

                if fx_data and fx_data.fx_width and fx_data.fx_height and not edit_mode then
                    local fx_window = reaper.TrackFX_GetFloatingWindow(track, index)
                    if fx_window then
                        local ret, left, top, right, bottom = reaper.JS_Window_GetRect(fx_window)
                        if ret then
                            local cur_w, cur_h = math.abs(right - left), math.abs(bottom - top)
                            if math.abs(cur_w - fx_data.fx_width) > 2 or math.abs(cur_h - fx_data.fx_height) > 2 then
                                reaper.JS_Window_SetPosition(fx_window, left, top, fx_data.fx_width, fx_data.fx_height)
                            end
                        end
                    end
                end
                selected_dot = nil
                pending_focus_change = nil
            end
        else
            pending_focus_change = {track = track, index = index}
            pending_focus_counter = 2
        end
    else
        pending_focus_change = nil
    end

    if last_track and last_index ~= nil then
        Open_The_Overlay_Window(last_track, last_index)
    end
    return false
end

function FX_Not_Found_Signal_No_Overlay()
    if fx_persist_timer > 0 then
        fx_persist_timer = fx_persist_timer - 1
        if last_track and last_index then
            Open_The_Overlay_Window(last_track, last_index)
        end
    else
        overlay_active = false
        last_track, last_index = nil, nil
    end
end

local function Handle_Dot_Graffiti_Movement()
    if #selected_dots == 0 then return end
    local time_now = reaper.time_precise()
    local move_x, move_y = 0, 0
    
    if reaper.ImGui_IsKeyDown(ctx, reaper.ImGui_Key_LeftArrow()) then move_x = -1 end
    if reaper.ImGui_IsKeyDown(ctx, reaper.ImGui_Key_UpArrow()) then move_y = -1 end
    if reaper.ImGui_IsKeyDown(ctx, reaper.ImGui_Key_RightArrow()) then move_x = 1 end
    if reaper.ImGui_IsKeyDown(ctx, reaper.ImGui_Key_DownArrow()) then move_y = 1 end

    if move_x ~= 0 or move_y ~= 0 then
        if not move_start_time then
            move_start_time = time_now
            for _, sel_dot in ipairs(selected_dots) do
                sel_dot.dot.x = sel_dot.dot.x + move_x
                sel_dot.dot.y = sel_dot.dot.y + move_y
            end
            Save_FX_Graffiti()
        elseif (time_now - move_start_time) > move_delay then
            if (time_now - move_start_time) > (move_delay + move_repeat_rate) then
                for _, sel_dot in ipairs(selected_dots) do
                    sel_dot.dot.x = sel_dot.dot.x + move_x
                    sel_dot.dot.y = sel_dot.dot.y + move_y
                end
                Save_FX_Graffiti()
                move_start_time = time_now - move_delay
            end
        end
    else
        move_start_time = nil
    end
end

--------------------------------------------------------------------------------
-- MAIN OVERLAY UI RENDER
--------------------------------------------------------------------------------
function Open_The_Overlay_Window(track, index)
    local _, fx_name = reaper.TrackFX_GetFXName(track, index, "")
    local fx_data = Load_FX_Settings(track, index)
    
    local global_modifiers = reaper.JS_Mouse_GetState(0xFF)
    local is_modifier_down = (global_modifiers & 16 == 16) or (global_modifiers & 32 == 32)
    
    if not track then return end

    local fx_window = reaper.TrackFX_GetFloatingWindow(track, index)
    if not fx_window then return end

    local ret, left, top, right, bottom = reaper.JS_Window_GetRect(fx_window)
    if not ret then return end

    local fx_width = math.abs(right - left)
    local fx_height = math.abs(bottom - top)

    if edit_mode then
        fx_data.fx_width = fx_width
        fx_data.fx_height = fx_height
    end

    local overlay_left = left + 8
    local overlay_top = top + 30
    local overlay_width = fx_width - 16
    local extraUI = (edit_mode and 280) or 0
    local overlay_height = fx_height + extraUI - 37

    reaper.ImGui_SetNextWindowPos(ctx, overlay_left, overlay_top)
    reaper.ImGui_SetNextWindowSize(ctx, overlay_width, overlay_height + 1)

    local is_topmost = false
    local fg_hwnd = reaper.JS_Window_GetForeground()
    local overlay_hwnd = reaper.JS_Window_Find("FX Overlay Window", true)
    local reaper_main = reaper.GetMainHwnd()

    if fg_hwnd == fx_window or (overlay_hwnd and fg_hwnd == overlay_hwnd) or fg_hwnd == reaper_main then
        is_topmost = true
    else
        local parent = reaper.JS_Window_GetParent(fg_hwnd)
        while parent do
            if parent == fx_window or parent == reaper_main then
                is_topmost = true
                break
            end
            parent = reaper.JS_Window_GetParent(parent)
        end
    end

    if fg_hwnd then
        local title = reaper.JS_Window_GetTitle(fg_hwnd) or ""
        if title:match("ReaScript development environment") or title:match("ReaScript IDE") then
            is_topmost = false
        end
    end

    local window_flags
    if edit_mode then
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_WindowBg(), 0x00000001) 
        window_flags = reaper.ImGui_WindowFlags_NoTitleBar() | reaper.ImGui_WindowFlags_NoMove() |
                       reaper.ImGui_WindowFlags_NoResize() | reaper.ImGui_WindowFlags_NoSavedSettings() |
                       reaper.ImGui_WindowFlags_NoNav()
    else
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_WindowBg(), 0x00000000)
        window_flags = reaper.ImGui_WindowFlags_NoTitleBar() | reaper.ImGui_WindowFlags_NoFocusOnAppearing() |
                       reaper.ImGui_WindowFlags_NoInputs() | reaper.ImGui_WindowFlags_NoMove() |
                       reaper.ImGui_WindowFlags_NoResize() | reaper.ImGui_WindowFlags_NoSavedSettings() |
                       reaper.ImGui_WindowFlags_NoBackground()
    end

    if is_topmost then window_flags = window_flags | reaper.ImGui_WindowFlags_TopMost() end

    local visible, open_state = reaper.ImGui_Begin(ctx, "FX Overlay Window", true, window_flags)
    if not visible then
        reaper.ImGui_End(ctx)
        reaper.ImGui_PopStyleColor(ctx)
        return
    end

    local win_x, win_y = reaper.ImGui_GetWindowPos(ctx)
    local draw_list = reaper.ImGui_GetWindowDrawList(ctx)
    local im_mx, im_my = reaper.ImGui_GetMousePos(ctx)

    if FX_IsOverlayVisible(fx_name, fx_data) then
        for i, circle in ipairs(fx_data.circles) do
            local center_x, center_y = win_x + circle.x, win_y + circle.y
            local draw_width = (circle.width and circle.width > 0) and circle.width or default_width
            local draw_height = (circle.height and circle.height > 0) and circle.height or default_height

            if circle.shape == "circle" then
                reaper.ImGui_DrawList_AddEllipseFilled(draw_list, center_x, center_y, draw_width / 2, draw_height / 2, circle.color)
            elseif circle.shape == "outlined circle" then
                DrawThickEllipse(draw_list, center_x, center_y, draw_width / 2, draw_height / 2, circle.color, circle.thickness or 3)
            elseif circle.shape == "outlined rectangle" then
                reaper.ImGui_DrawList_AddRect(draw_list, center_x - draw_width / 2, center_y - draw_height / 2, center_x + draw_width / 2, center_y + draw_height / 2, circle.color, 0, 0, circle.thickness or 2)
            else
                reaper.ImGui_DrawList_AddRectFilled(draw_list, center_x - draw_width / 2, center_y - draw_height / 2, center_x + draw_width / 2, center_y + draw_height / 2, circle.color)
            end

            if ContainsDot(selected_dots, i) then
                local border_color = 0x00FF00FF
                if circle.shape == "circle" or circle.shape == "outlined circle" then
                    DrawThickEllipse(draw_list, center_x, center_y, draw_width / 2, draw_height / 2, border_color, 3)
                else
                    DrawThickRect(draw_list, center_x - draw_width / 2, center_y - draw_height / 2, center_x + draw_width / 2, center_y + draw_height / 2, border_color, 3)
                end
            end
        end
    end

    if select_rect_active and reaper.ImGui_IsMouseDown(ctx, 0) then
        select_rect_end_x, select_rect_end_y = im_mx, im_my
        reaper.ImGui_DrawList_AddRect(draw_list, select_rect_start_x, select_rect_start_y, select_rect_end_x, select_rect_end_y, 0x00FF00FF, 0, 0, 2)
    end

    if not edit_mode then
        -- Native ImGui coordinate math to totally bypass OS Y-inversions
        local mouse_in_title_bar = (im_mx >= win_x and im_mx <= (win_x + overlay_width) and im_my >= (win_y - 45) and im_my <= (win_y + 10))
        local prompt_hovered = reaper.ImGui_IsWindowHovered(ctx)

        if is_modifier_down then
            if mouse_in_title_bar or prompt_hovered or edit_prompt_timer > 0 then
                edit_prompt_timer = edit_prompt_hold_frames
            end
        else
            edit_prompt_timer = 0
        end

        if edit_prompt_timer > 0 then
            local has_overlay = FX_HasOverlay(fx_data)
            local overlay_visible = FX_IsOverlayVisible(fx_name, fx_data)

            -- Spawn the Prompt dynamically relative to the ImGui Main window's top edge
            reaper.ImGui_SetNextWindowPos(ctx, win_x + 5, win_y - 35)
            reaper.ImGui_SetNextWindowSize(ctx, has_overlay and 395 or 176, 35, reaper.ImGui_Cond_Always())
            reaper.ImGui_SetNextWindowBgAlpha(ctx, 1.0)
            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_WindowBg(), 0x000000FF)

            local prompt_flags = reaper.ImGui_WindowFlags_NoDecoration() | reaper.ImGui_WindowFlags_NoFocusOnAppearing() | reaper.ImGui_WindowFlags_NoSavedSettings()
            if is_topmost then prompt_flags = prompt_flags | reaper.ImGui_WindowFlags_TopMost() end

            local prompt_visible, prompt_open = reaper.ImGui_Begin(ctx, "Edit Prompt", true, prompt_flags)
            if prompt_visible then
                if reaper.ImGui_Button(ctx, "EDIT GRAFFITI") then
                    edit_prompt_timer = edit_prompt_hold_frames
                    backup_circles = {}
                    for i, dot in ipairs(fx_data.circles) do
                        local new_dot = {}
                        for k, v in pairs(dot) do new_dot[k] = v end
                        table.insert(backup_circles, new_dot)
                    end
                    edit_mode = true
                    edit_prompt_timer = 0
                end
            
                if has_overlay then
                    reaper.ImGui_SameLine(ctx)
                    reaper.ImGui_Dummy(ctx, 30, 2)
                    reaper.ImGui_SameLine(ctx)
            
                    if overlay_visible then
                        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), 0x228B22FF)
                        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), 0x32CD32FF)
                        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(), 0x1E7A1EFF)
                    end
                    if reaper.ImGui_Button(ctx, "SHOW") then
                        edit_prompt_timer = edit_prompt_hold_frames
                        temp_hidden_fx[fx_name] = nil
                        fx_data.visible = true
                        Save_FX_Graffiti()
                    end
                    if overlay_visible then reaper.ImGui_PopStyleColor(ctx, 3) end
            
                    reaper.ImGui_SameLine(ctx)
            
                    local off_active = temp_hidden_fx[fx_name] == true
                    if off_active then
                        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), 0x8B6B22FF)
                        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), 0xCD9B32FF)
                        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(), 0x7A5E1EFF)
                    end
                    if reaper.ImGui_Button(ctx, "HIDE") then
                        edit_prompt_timer = edit_prompt_hold_frames
                        temp_hidden_fx[fx_name] = true
                    end
                    if off_active then reaper.ImGui_PopStyleColor(ctx, 3) end
            
                    reaper.ImGui_SameLine(ctx)
            
                    local keep_hidden_active = (fx_data.visible == false and not temp_hidden_fx[fx_name])
                    if keep_hidden_active then
                        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), 0x8B2222FF)
                        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), 0xCD3232FF)
                        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(), 0x7A1E1EFF)
                    end
                    if reaper.ImGui_Button(ctx, "KEEP HIDDEN") then
                        edit_prompt_timer = edit_prompt_hold_frames
                        temp_hidden_fx[fx_name] = nil
                        fx_data.visible = false
                        Save_FX_Graffiti()
                    end
                    if keep_hidden_active then reaper.ImGui_PopStyleColor(ctx, 3) end
                end
            
                reaper.ImGui_SameLine(ctx)
                reaper.ImGui_Dummy(ctx, 30, 2)
                reaper.ImGui_SameLine(ctx)
            
                if reaper.ImGui_Button(ctx, "QUIT") then quit_requested = true end
                reaper.ImGui_End(ctx)
            end
            reaper.ImGui_PopStyleColor(ctx)
        end
    end

    if FX_IsOverlayHidden(fx_name, fx_data) then
        local dot_flags = reaper.ImGui_WindowFlags_NoDecoration() | reaper.ImGui_WindowFlags_NoFocusOnAppearing() |
                          reaper.ImGui_WindowFlags_NoInputs() | reaper.ImGui_WindowFlags_NoMove() |
                          reaper.ImGui_WindowFlags_NoResize() | reaper.ImGui_WindowFlags_NoSavedSettings() |
                          reaper.ImGui_WindowFlags_NoBackground()
        if is_topmost then dot_flags = dot_flags | reaper.ImGui_WindowFlags_TopMost() end

        reaper.ImGui_SetNextWindowPos(ctx, win_x - 1, win_y - 30)
        reaper.ImGui_SetNextWindowSize(ctx, 18, 18)

        local dot_visible = reaper.ImGui_Begin(ctx, "##HiddenOverlayDot_" .. tostring(fx_name), true, dot_flags)
        if dot_visible then
            local hw_x, hw_y = reaper.ImGui_GetWindowPos(ctx)
            reaper.ImGui_DrawList_AddCircleFilled(reaper.ImGui_GetWindowDrawList(ctx), hw_x + 6, hw_y + 6, 5, 0x3FA9F5FF)
            reaper.ImGui_End(ctx)
        end
    end

    ----------------------------------------------------------------------------
    -- EDIT MODE UI
    ----------------------------------------------------------------------------
    if edit_mode then
        reaper.ImGui_SetCursorPosY(ctx, fx_height - 33)
        local recx, recy = reaper.ImGui_GetWindowPos(ctx)
        reaper.ImGui_DrawList_AddRectFilled(draw_list, recx, recy + (fx_height - 38), recx + overlay_width, recy + fx_height + 1000, 0x111111FF)

        reaper.ImGui_SetCursorPosY(ctx, fx_height - 33)
        local x, y = reaper.ImGui_GetCursorPos(ctx)
        reaper.ImGui_SetCursorPos(ctx, x, y + 3)

        for row = 1, colortable_row_count do
            local row_x, row_y = reaper.ImGui_GetCursorPos(ctx)
            reaper.ImGui_SetCursorPos(ctx, row_x + 5, row_y - 3)

            for col = 1, colortable_column_count do
                local idx = (row - 1) * colortable_column_count + col
                local color = colors[idx]
                reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), color)

                local bx, by = reaper.ImGui_GetCursorPos(ctx)
                reaper.ImGui_SetCursorPos(ctx, bx - 7, by)

                if reaper.ImGui_Button(ctx, "##" .. idx, square_size + 12, square_size + 3) then
                    local current_alpha = (#selected_dots > 0 and (selected_dots[1].dot.color & 0xFF)) or last_transparency_value
                    local r, g, b = (color >> 24) & 0xFF, (color >> 16) & 0xFF, (color >> 8) & 0xFF
                    local new_color = (r << 24) | (g << 16) | (b << 8) | current_alpha
                    if #selected_dots > 0 then
                        for _, sel_dot in ipairs(selected_dots) do sel_dot.dot.color = new_color end
                        Save_FX_Graffiti()
                    else
                        selected_color = new_color
                    end
                end

                reaper.ImGui_PopStyleColor(ctx)
                if col < colortable_column_count then reaper.ImGui_SameLine(ctx) end
            end
        end

        reaper.ImGui_Text(ctx, "Dot Shape:")
        reaper.ImGui_SameLine(ctx)
        local px, py = reaper.ImGui_GetCursorPos(ctx)
        reaper.ImGui_SetCursorPos(ctx, px + 36, py)

        reaper.ImGui_Text(ctx, "Custom:")
        reaper.ImGui_SameLine(ctx)

        local current_edit_color = (#selected_dots > 0) and selected_dots[1].dot.color or selected_color
        reaper.ImGui_SetNextItemWidth(ctx, 120)
        local color_changed, new_color = reaper.ImGui_ColorEdit4(ctx, "##CustomColorPicker", current_edit_color, reaper.ImGui_ColorEditFlags_AlphaBar() | reaper.ImGui_ColorEditFlags_NoDragDrop())

        if color_changed then
            selected_color = new_color
            last_transparency_value = new_color & 0xFF
            if #selected_dots > 0 then
                for _, sel_dot in ipairs(selected_dots) do sel_dot.dot.color = new_color end
                Save_FX_Graffiti()
            end
        end

        reaper.ImGui_SameLine(ctx)
        px, py = reaper.ImGui_GetCursorPos(ctx)
        reaper.ImGui_SetCursorPos(ctx, px + 53, py)

        if reaper.ImGui_Button(ctx, "?", 27) then reaper.ImGui_OpenPopup(ctx, "FX Graffiti Help") end

        if reaper.ImGui_BeginPopupModal(ctx, "FX Graffiti Help", true, reaper.ImGui_WindowFlags_AlwaysAutoResize()) then
            reaper.ImGui_Text(ctx, "FX Graffiti Help\n\n- Hold Opt/Cmd over FX title bar to enter Edit Mode.\n- Middle click to draw.\n- Left click/drag to select and move.\n- Arrow keys nudge.\n- Delete key to remove.\n- Mouse wheel resizes (Shift=Height, Alt=Width).")
            if reaper.ImGui_Button(ctx, "Close", 80, 24) then reaper.ImGui_CloseCurrentPopup(ctx) end
            reaper.ImGui_EndPopup(ctx)
        end

        local shape_options = { {"Circle", "circle"}, {"Outlined Circle", "outlined circle"}, {"Rectangle", "square"}, {"Outlined Rect.", "outlined rectangle"} }
        for i, opt in ipairs(shape_options) do
            if reaper.ImGui_RadioButton(ctx, opt[1], selected_shape == opt[2]) then
                selected_shape = opt[2]
                for _, sel_dot in ipairs(selected_dots) do sel_dot.dot.shape = selected_shape end
                if #selected_dots > 0 then Save_FX_Graffiti() end
            end
            if i < 4 then reaper.ImGui_SameLine(ctx) end
        end

        reaper.ImGui_Text(ctx, "Transparency")
        reaper.ImGui_SameLine(ctx)

        local alpha = (#selected_dots > 0 and (selected_dots[1].dot.color & 0xFF)) or last_transparency_value
        reaper.ImGui_SetNextItemWidth(ctx, 232)
        local alpha_changed, new_alpha = reaper.ImGui_SliderInt(ctx, "##Transparency", alpha, 1, 255)

        if alpha_changed then
            last_transparency_value = new_alpha
            if #selected_dots > 0 then
                for _, sel_dot in ipairs(selected_dots) do
                    local r, g, b = (sel_dot.dot.color >> 24) & 0xFF, (sel_dot.dot.color >> 16) & 0xFF, (sel_dot.dot.color >> 8) & 0xFF
                    sel_dot.dot.color = (r << 24) | (g << 16) | (b << 8) | new_alpha
                end
                Save_FX_Graffiti()
            else
                local r, g, b = (selected_color >> 24) & 0xFF, (selected_color >> 16) & 0xFF, (selected_color >> 8) & 0xFF
                selected_color = (r << 24) | (g << 16) | (b << 8) | new_alpha
            end
        end

        local function QuickAdjustBtn(label, cur_val, min_v, max_v, key)
            reaper.ImGui_SameLine(ctx)
            local px_b, py_b = reaper.ImGui_GetCursorPos(ctx)
            reaper.ImGui_SetCursorPos(ctx, px_b - 3, py_b)
            if reaper.ImGui_Button(ctx, label .. "##" .. key, 20, 20) then
                local offset = (label == "-") and -1 or 1
                return math.max(min_v, math.min(max_v, cur_val + offset)), true
            end
            return cur_val, false
        end

        local fine_alpha, changed = QuickAdjustBtn("-", alpha, 1, 255, "Alpha")
        local fine_alpha2, changed2 = QuickAdjustBtn("+", fine_alpha, 1, 255, "Alpha")
        if changed or changed2 then
            last_transparency_value = changed and fine_alpha or fine_alpha2
            local c_alpha = last_transparency_value
            if #selected_dots > 0 then
                for _, sel_dot in ipairs(selected_dots) do
                    local r, g, b = (sel_dot.dot.color >> 24) & 0xFF, (sel_dot.dot.color >> 16) & 0xFF, (sel_dot.dot.color >> 8) & 0xFF
                    sel_dot.dot.color = (r << 24) | (g << 16) | (b << 8) | c_alpha
                end
                Save_FX_Graffiti()
            else
                local r, g, b = (selected_color >> 24) & 0xFF, (selected_color >> 16) & 0xFF, (selected_color >> 8) & 0xFF
                selected_color = (r << 24) | (g << 16) | (b << 8) | c_alpha
            end
        end

        reaper.ImGui_Text(ctx, "Width:")
        reaper.ImGui_SameLine(ctx)
        local width = (#selected_dots > 0 and selected_dots[1].dot.width) or default_width
        local wx, wy = reaper.ImGui_GetCursorPos(ctx)
        reaper.ImGui_SetCursorPos(ctx, wx + 4, wy)
        reaper.ImGui_SetNextItemWidth(ctx, 263)
        local width_changed, new_width = reaper.ImGui_SliderInt(ctx, "##Width", width, 5, 4000)
        
        local is_shift_down = reaper.ImGui_IsKeyDown(ctx, reaper.ImGui_Mod_Shift())
        local is_alt_down_edit = reaper.ImGui_IsKeyDown(ctx, reaper.ImGui_Mod_Alt())

        if width_changed then
            for _, sel_dot in ipairs(selected_dots) do
                sel_dot.dot.width = new_width
                if is_shift_down then sel_dot.dot.height = new_width end
            end
            if #selected_dots > 0 then Save_FX_Graffiti() else
                default_width = new_width
                if is_shift_down then default_height = new_width end
            end
        end

        local fine_w, w_changed = QuickAdjustBtn("-", width, 5, 4000, "Width")
        local fine_w2, w_changed2 = QuickAdjustBtn("+", fine_w, 5, 4000, "Width")
        if w_changed or w_changed2 then
            local nw = w_changed and fine_w or fine_w2
            for _, sel_dot in ipairs(selected_dots) do sel_dot.dot.width = nw end
            if #selected_dots > 0 then Save_FX_Graffiti() else default_width = nw end
        end

        reaper.ImGui_Text(ctx, "Height:")
        reaper.ImGui_SameLine(ctx)
        local height = (#selected_dots > 0 and selected_dots[1].dot.height) or default_height
        reaper.ImGui_SetNextItemWidth(ctx, 263)
        local height_changed, new_height = reaper.ImGui_SliderInt(ctx, "##Height", height, 5, 4000)

        if height_changed then
            for _, sel_dot in ipairs(selected_dots) do
                sel_dot.dot.height = new_height
                if is_shift_down then sel_dot.dot.width = new_height end
            end
            if #selected_dots > 0 then Save_FX_Graffiti() else
                default_height = new_height
                if is_shift_down then default_width = new_height end
            end
        end

        local fine_h, h_changed = QuickAdjustBtn("-", height, 5, 4000, "Height")
        local fine_h2, h_changed2 = QuickAdjustBtn("+", fine_h, 5, 4000, "Height")
        if h_changed or h_changed2 then
            local nh = h_changed and fine_h or fine_h2
            for _, sel_dot in ipairs(selected_dots) do sel_dot.dot.height = nh end
            if #selected_dots > 0 then Save_FX_Graffiti() else default_height = nh end
        end

        local show_thickness = (#selected_dots > 0 and (selected_dots[1].dot.shape == "outlined circle" or selected_dots[1].dot.shape == "outlined rectangle"))
        if show_thickness or (selected_shape == "outlined circle" or selected_shape == "outlined rectangle") then
            reaper.ImGui_Text(ctx, "Thickness:")
            reaper.ImGui_SameLine(ctx)
            local thickness = (#selected_dots > 0 and selected_dots[1].dot.thickness) or (selected_shape == "outlined circle" and 3) or 2
            reaper.ImGui_SetNextItemWidth(ctx, 167)
            local thickness_changed, new_thickness = reaper.ImGui_SliderInt(ctx, "##Thickness", thickness, 1, 100)
            if thickness_changed and #selected_dots > 0 then
                for _, sel_dot in ipairs(selected_dots) do
                    if sel_dot.dot.shape:match("outlined") then sel_dot.dot.thickness = new_thickness end
                end
                Save_FX_Graffiti()
            end
        end

        -- Safe Button Alignment Logic Fixes!
        if reaper.ImGui_Button(ctx, "Import Overlay") then
            if fx_data and fx_data.circles and #fx_data.circles > 0 then show_import_confirm = true else
                pending_dialog = "import"
                dialog_wait_frames = 2
            end
        end
        reaper.ImGui_SameLine(ctx)
        local c1_x, c1_y = reaper.ImGui_GetCursorPos(ctx)
        reaper.ImGui_SetCursorPos(ctx, c1_x - 3, c1_y)
        
        if reaper.ImGui_Button(ctx, "Import Multiple") then
            pending_dialog = "import_multiple"
            dialog_wait_frames = 2
        end
        reaper.ImGui_SameLine(ctx)
        local c2_x, c2_y = reaper.ImGui_GetCursorPos(ctx)
        reaper.ImGui_SetCursorPos(ctx, c2_x + 31, c2_y)

        if reaper.ImGui_Button(ctx, "Delete All Graffiti Objects") then
            fx_data.circles = {}
            Save_FX_Graffiti()
        end

        if reaper.ImGui_Button(ctx, "Export Overlay", 86) then pending_dialog = "export"; dialog_wait_frames = 2 end
        reaper.ImGui_SameLine(ctx)
        local c3_x, c3_y = reaper.ImGui_GetCursorPos(ctx)
        reaper.ImGui_SetCursorPos(ctx, c3_x - 3, c3_y)
        
        if reaper.ImGui_Button(ctx, "Export All", 90) then pending_dialog = "export_all"; dialog_wait_frames = 2 end
        
        reaper.ImGui_SameLine(ctx)
        local c4_x, c4_y = reaper.ImGui_GetCursorPos(ctx)
        reaper.ImGui_SetCursorPos(ctx, c4_x + 31, c4_y)

        if reaper.ImGui_Button(ctx, "Save and Apply") then
            Save_FX_Graffiti()
            edit_mode = false
            backup_circles = nil
            selected_dots = {}
        end
        reaper.ImGui_SameLine(ctx)
        local c5_x, c5_y = reaper.ImGui_GetCursorPos(ctx)
        reaper.ImGui_SetCursorPos(ctx, c5_x - 3, c5_y)
        
        if reaper.ImGui_Button(ctx, "Cancel", 46) then
            if backup_circles then fx_data.circles = backup_circles end
            edit_mode = false
            backup_circles = nil
            selected_dots = {}
            Save_FX_Graffiti()
        end

        -- MOUSE LOGIC
        local mouse_left_down = reaper.ImGui_IsMouseDown(ctx, 0)
        local mouse_left_clicked = reaper.ImGui_IsMouseClicked(ctx, 0)
        local mouse_left_released = reaper.ImGui_IsMouseReleased(ctx, 0)
        local mouse_middle_clicked = reaper.ImGui_IsMouseClicked(ctx, 2)

        if mouse_left_released then
            if select_rect_active then
                local min_x = math.min(select_rect_start_x - win_x, select_rect_end_x - win_x)
                local max_x = math.max(select_rect_start_x - win_x, select_rect_end_x - win_x)
                local min_y = math.min(select_rect_start_y - win_y, select_rect_end_y - win_y)
                local max_y = math.max(select_rect_start_y - win_y, select_rect_end_y - win_y)
                for i, circle in ipairs(fx_data.circles) do
                    if circle.x >= min_x and circle.x <= max_x and circle.y >= min_y and circle.y <= max_y then
                        if not ContainsDot(selected_dots, i) then
                            table.insert(selected_dots, {index = i, dot = circle, offset_x = 0, offset_y = 0})
                        end
                    end
                end
                select_rect_active = false
            end
            drag_active = false
            drag_start_x, drag_start_y = nil, nil
            for _, sel_dot in ipairs(selected_dots) do sel_dot.orig_x, sel_dot.orig_y = nil, nil end
        end

        if mouse_left_clicked then
            ui_area_start_y_abs = win_y + (fx_height - UI_AREA_START_Y_REL)
            local mouse_in_ui_area = (im_my >= ui_area_start_y_abs)
            if not reaper.ImGui_IsAnyItemHovered(ctx) and not mouse_in_ui_area then
                local rel_x, rel_y = im_mx - win_x, im_my - win_y
                local candidates = {}
                for i, circle in ipairs(fx_data.circles) do
                    local left_bound = circle.x - (circle.width or default_width) / 2
                    local right_bound = circle.x + (circle.width or default_width) / 2
                    local top_bound = circle.y - (circle.height or default_height) / 2
                    local bottom_bound = circle.y + (circle.height or default_height) / 2
                    if rel_x >= left_bound and rel_x <= right_bound and rel_y >= top_bound and rel_y <= bottom_bound then
                        table.insert(candidates, {index = i, dot = circle, distance = math.sqrt((circle.x - rel_x)^2 + (circle.y - rel_y)^2)})
                    end
                end
                if #candidates > 0 then
                    table.sort(candidates, function(a, b) return a.distance < b.distance end)
                    local closest = candidates[1]
                    closest.offset_x, closest.offset_y = rel_x - closest.dot.x, rel_y - closest.dot.y
                    if is_shift_down then
                        if not ContainsDot(selected_dots, closest.index) then table.insert(selected_dots, closest) end
                    else
                        selected_dots = {closest}
                    end
                    for _, sel_dot in ipairs(selected_dots) do sel_dot.orig_x, sel_dot.orig_y = nil, nil end
                    drag_active = false
                    drag_start_x, drag_start_y = im_mx, im_my
                else
                    drag_active, select_rect_active = false, true
                    select_rect_start_x, select_rect_start_y = im_mx, im_my
                    select_rect_end_x, select_rect_end_y = im_mx, im_my
                    if not is_shift_down then selected_dots = {} end
                end
            end
        end

        if #selected_dots > 0 and mouse_left_down and not select_rect_active then
            if (im_my - win_y) < (fx_height - 38) then
                if not drag_active and drag_start_x and drag_start_y then
                    if math.sqrt((im_mx - drag_start_x)^2 + (im_my - drag_start_y)^2) > 5 then drag_active = true end
                end
                if drag_active then
                    if is_alt_down_edit and not selected_dots[1].duplicated then
                        local new_dots = {}
                        for _, sel_dot in ipairs(selected_dots) do
                            local dup_dot = { x = sel_dot.dot.x, y = sel_dot.dot.y, color = sel_dot.dot.color, shape = sel_dot.dot.shape, width = sel_dot.dot.width, height = sel_dot.dot.height, thickness = sel_dot.dot.thickness }
                            table.insert(fx_data.circles, dup_dot)
                            table.insert(new_dots, {index = #fx_data.circles, dot = dup_dot, offset_x = sel_dot.offset_x, offset_y = sel_dot.offset_y, duplicated = true})
                        end
                        selected_dots = new_dots
                        Save_FX_Graffiti()
                    elseif drag_start_x and drag_start_y then
                        for _, sel_dot in ipairs(selected_dots) do
                            if not sel_dot.orig_x then sel_dot.orig_x, sel_dot.orig_y = sel_dot.dot.x, sel_dot.dot.y end
                            sel_dot.dot.x = sel_dot.orig_x + (im_mx - drag_start_x)
                            sel_dot.dot.y = sel_dot.orig_y + (im_my - drag_start_y)
                        end
                        Save_FX_Graffiti()
                    end
                end
            end
        end

        if mouse_middle_clicked and (im_my - win_y) < (fx_height - 38) then
            table.insert(fx_data.circles, {
                x = im_mx - win_x, y = im_my - win_y,
                color = selected_color, shape = selected_shape,
                width = default_width, height = default_height,
                thickness = (selected_shape:match("outlined")) and 2 or nil
            })
            if #selected_dots > 0 then selected_dots = {} end
            Save_FX_Graffiti()
        end

        if #selected_dots > 0 then
            Handle_Dot_Graffiti_Movement()
            
            if reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_Delete()) or reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_Backspace()) then
                local indices = {}
                for _, sel_dot in ipairs(selected_dots) do table.insert(indices, sel_dot.index) end
                table.sort(indices, function(a, b) return a > b end)
                for _, idx in ipairs(indices) do table.remove(fx_data.circles, idx) end
                selected_dots = {}
                Save_FX_Graffiti()
            end
            
            local mouse_wheel = reaper.ImGui_GetMouseWheel(ctx) or 0
            if mouse_wheel ~= 0 then
                for _, sel_dot in ipairs(selected_dots) do
                    if is_shift_down then sel_dot.dot.height = math.max(5, sel_dot.dot.height + mouse_wheel)
                    elseif is_alt_down_edit then sel_dot.dot.width = math.max(5, sel_dot.dot.width + mouse_wheel)
                    else
                        sel_dot.dot.width = math.max(5, sel_dot.dot.width + mouse_wheel)
                        sel_dot.dot.height = math.max(5, sel_dot.dot.height + mouse_wheel)
                    end
                end
                Save_FX_Graffiti()
            end
        end
    end

    reaper.ImGui_End(ctx)
    reaper.ImGui_PopStyleColor(ctx)

    if not open_state then
        overlay_active, last_track, last_index, selected_dots = false, nil, nil, {}
    end
end

--------------------------------------------------------------------------------
-- FILE I/O & SERIALIZATION
--------------------------------------------------------------------------------
function Serialize_Table(val, name, skipnewlines, depth)
    skipnewlines = skipnewlines or false
    depth = depth or 0
    local indent = string.rep(" ", depth)
    local tmp = ""
    if name then
        if type(name) == "string" and string.match(name, "^[a-zA-Z_][a-zA-Z0-9_]*$") then
            tmp = indent .. name .. " = "
        elseif type(name) == "string" then
            tmp = indent .. string.format("[%q] = ", name)
        else
            tmp = indent .. "[" .. tostring(name) .. "] = "
        end
    else
        tmp = indent
    end

    if type(val) == "table" then
        tmp = tmp .. "{" .. (not skipnewlines and "\n" or "")
        for k, v in pairs(val) do
            tmp = tmp .. Serialize_Table(v, k, skipnewlines, depth + 2) .. "," .. (not skipnewlines and "\n" or "")
        end
        tmp = tmp .. indent .. "}"
    elseif type(val) == "number" or type(val) == "boolean" then
        tmp = tmp .. tostring(val)
    elseif type(val) == "string" then
        tmp = tmp .. string.format("%q", val)
    else
        tmp = tmp .. '"[inserializeable datatype:' .. type(val) .. ']"'
    end
    return tmp
end

function Save_FX_Graffiti()
    local file = io.open(marker_filename, "w")
    if file then
        file:write("return " .. Serialize_Table(fx_markers))
        file:close()
    end
end

--------------------------------------------------------------------------------
-- STARTUP EXECUTION
--------------------------------------------------------------------------------
function The_Main_Loop()
    if Check_For_Quit() then return end
    local visible, open_state = Initialize_Overlay_Window()
    if not visible then return end
    if GUI_Work(visible) then return The_Main_Loop() end
    if open_state then reaper.defer(The_Main_Loop) else Cleanup() end
end

reaper.RecursiveCreateDirectory(data_folder, 0)
reaper.RecursiveCreateDirectory(overlays_folder, 0)
Load_FX_Dots_and_Graffiti()
reaper.atexit(Cleanup)
The_Main_Loop()
