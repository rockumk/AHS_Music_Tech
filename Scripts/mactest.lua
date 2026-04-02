--desc:mactest
--version: 1.2
--author: Rock Kennedy

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
        -- Gather raw tracking data safely
        local ret, left, top, right, bottom = reaper.JS_Window_GetRect(hwnd)
        left = left or 0
        top = top or 0
        right = right or 0
        bottom = bottom or 0
        
        -- Safely attempt ClientToScreen (caused the nil crash previously)
        local ret_c, cx, cy = reaper.JS_Window_ClientToScreen(hwnd, 0, 0)
        cx = cx or left
        cy = cy or top
        
        -- Get Screen/Viewport Height safely
        local viewport = reaper.ImGui_GetMainViewport(ctx)
        local vw, vh = 1080, 1080 
        if reaper.ImGui_Viewport_GetSize then
            vw, vh = reaper.ImGui_Viewport_GetSize(viewport)
        end
        if not vh then vh = 1080 end

        -- 6 Distinct Mathematical Methods
        local methods = {
            { name = "1 RED",    color = 0xFF0000FF, x = left, y = top },
            { name = "2 ORANGE", color = 0xFF8800FF, x = left + 40, y = bottom },
            { name = "3 YELLOW", color = 0xFFFF00FF, x = left + 80, y = top - 30 },
            { name = "4 GREEN",  color = 0x00FF00FF, x = left + 120, y = top + 30 },
            { name = "5 BLUE",   color = 0x0000FFFF, x = left, y = vh - bottom }, 
            { name = "6 PURPLE", color = 0x800080FF, x = left + 40, y = vh - top }
        }

        for i, m in ipairs(methods) do
            reaper.ImGui_SetNextWindowPos(ctx, m.x or 0, m.y or 0)
            reaper.ImGui_SetNextWindowSize(ctx, 35, 35)
            
            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_WindowBg(), m.color)
            
            local flags = reaper.ImGui_WindowFlags_NoDecoration() | 
                          reaper.ImGui_WindowFlags_TopMost() | 
                          reaper.ImGui_WindowFlags_NoInputs() |
                          reaper.ImGui_WindowFlags_NoSavedSettings()
            
            local visible, open = reaper.ImGui_Begin(ctx, m.name .. " (Test)", true, flags)
            if visible then
                reaper.ImGui_Text(ctx, string.sub(m.name, 1, 1))
                reaper.ImGui_End(ctx)
            end
            reaper.ImGui_PopStyleColor(ctx)
        end

        -- LIVE DATA READOUT
        local flags = reaper.ImGui_WindowFlags_TopMost() | reaper.ImGui_WindowFlags_AlwaysAutoResize()
        local visible, open = reaper.ImGui_Begin(ctx, "Mac Coordinate Readout", true, flags)
        if visible then
            reaper.ImGui_Text(ctx, "Drag the plugin window around and watch these numbers:")
            reaper.ImGui_Separator(ctx)
            reaper.ImGui_Text(ctx, string.format("Top Edge: %s", tostring(top)))
            reaper.ImGui_Text(ctx, string.format("Bottom Edge: %s", tostring(bottom)))
            reaper.ImGui_Text(ctx, string.format("Viewport Height: %s", tostring(vh)))
            reaper.ImGui_Separator(ctx)
            reaper.ImGui_Text(ctx, "Watch the squares. Do any of them perfectly track the window?")
            reaper.ImGui_End(ctx)
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
