local reaper = reaper
package.path = package.path .. ";" .. reaper.ImGui_GetBuiltinPath() .. "/?.lua"
local ImGui = require("imgui")

local ctx = reaper.ImGui_CreateContext("Coordinate Test")

function loop()
    -- Close the script if ESC is pressed
    if reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_Escape()) then return end

    local retval, track_idx, item_idx, fx_idx = reaper.GetFocusedFX2()
    local hwnd = nil
    
    -- Check if we have a valid focused FX window
    if retval & 1 == 1 and track_idx > 0 then
        local track = reaper.GetTrack(0, track_idx - 1)
        hwnd = reaper.TrackFX_GetFloatingWindow(track, fx_idx)
    end

    if hwnd then
        -- Gather all the raw tracking data
        local ret, left, top, right, bottom = reaper.JS_Window_GetRect(hwnd)
        local ret_c, cx, cy = reaper.JS_Window_ClientToScreen(hwnd, 0, 0)
        
        -- Get Screen/Viewport Height
        local viewport = reaper.ImGui_GetMainViewport(ctx)
        local vw, vh = reaper.ImGui_Viewport_GetSize(viewport)
        
        -- 6 Distinct Mathematical Methods
        local methods = {
            { name = "1", color = 0xFF0000FF, x = left,       y = top },                 -- RED
            { name = "2", color = 0xFF8800FF, x = left + 30,  y = bottom },              -- ORANGE
            { name = "3", color = 0xFFFF00FF, x = left + 60,  y = cy },                  -- YELLOW
            { name = "4", color = 0x00FF00FF, x = left + 90,  y = vh - top },            -- GREEN
            { name = "5", color = 0x0000FFFF, x = left + 120, y = vh - bottom },         -- BLUE
            { name = "6", color = 0x800080FF, x = left + 150, y = (vh - top) - 30 }      -- PURPLE
        }

        for i, m in ipairs(methods) do
            reaper.ImGui_SetNextWindowPos(ctx, m.x, m.y)
            reaper.ImGui_SetNextWindowSize(ctx, 25, 25)
            
            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_WindowBg(), m.color)
            
            local flags = reaper.ImGui_WindowFlags_NoDecoration() | 
                          reaper.ImGui_WindowFlags_TopMost() | 
                          reaper.ImGui_WindowFlags_NoInputs() |
                          reaper.ImGui_WindowFlags_NoSavedSettings()
            
            local visible, open = reaper.ImGui_Begin(ctx, m.name .. " (Test)", true, flags)
            if visible then
                reaper.ImGui_Text(ctx, m.name)
                reaper.ImGui_End(ctx)
            end
            reaper.ImGui_PopStyleColor(ctx)
        end
    else
        -- Show instructions if no FX is focused
        local flags = reaper.ImGui_WindowFlags_TopMost() | reaper.ImGui_WindowFlags_AlwaysAutoResize()
        local visible, open = reaper.ImGui_Begin(ctx, "Test Instructions", true, flags)
        if visible then
            reaper.ImGui_Text(ctx, "Please click/focus a floating FX window.\nPress ESC to close this test.")
            reaper.ImGui_End(ctx)
        end
    end

    reaper.defer(loop)
end

reaper.defer(loop)
