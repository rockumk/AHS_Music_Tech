--[[
   @description ControllerFocus
   @version 1.1.6
   @author Rock Kennedy (Original by Leon Bradley)
   @about
     A control-surface bridge that maps hardware controls to the currently focused plugin.
     Requires the 'ValueVault' VST3 in the Monitoring FX chain.
   @changelog
     + Renamed to ControllerFocus
     + Added stability checks for project switching
     + Added startup safety check for ValueVault installation
     + Implemented dynamic relative pathing for templates
     + Performance optimizations
     + Republish ValueVault slot-assignment metadata after mappings are edited
     + Preserve and refresh the Monitoring FX link during same-FX republishes
     + Add confirmed Clear All for the current loaded layout
     + Capture the first moved FX parameter correctly while Learn is active
     + Add drag-to-swap and drag-between-rows insertion for assignment indexes
     + Add selectable learn target highlighting and sequential learn placement
     + Allow dragging empty index rows
     + Add stronger saturation during active fader glow
     + Match slider fill colors to the existing eight-color row markers
     + Hide the unimplemented MIX and CSTRIP navigation tabs
     + Allow learned duplicate assignments with a temporary clear-and-retarget warning
     + Treat one continuous FX movement as a single learn event
     + Detect learned button toggles by scanning focused-FX parameter changes
     + Change the Learn target highlight to a visually distinct bright turquoise
     + Add GUID-based FX identity validation and FX-chain quarantine before parameter writes
     + Guard template-loaded assignments with no current value during FX-chain quarantine
]]



--[[
    This script provides a control-surface interface in REAPER for quickly mapping
    hardware controls to the parameters of the currently focused plugin. It uses a 
    dedicated VST (ValueVault) loaded in the monitoring FX chain to store and share
    control data, allowing bidirectional parameter mapping between the focused FX 
    and the control surface.
    Author: Rock Kennedy
    Based on a version originally developed by Leon Bradley.
    Licence: GPL v3
--]]



------------------------------------------------------------
-- CONFIGURATION & CONSTANTS
------------------------------------------------------------
local SCRIPT_NAME = "ControllerFocus"

-- ValueVault VST3 Parameter Mapping
local PARAM_STATUS      = 490 -- Status (Found/Active)
local PARAM_TRACK_ID    = 491 -- Track ID
local PARAM_FX_SIGN     = 492 -- FX Index Sign
local PARAM_FX_DIGIT_1  = 493 -- FX Index (High)
local PARAM_FX_DIGIT_2  = 494 -- FX Index
local PARAM_FX_DIGIT_3  = 495 -- FX Index
local PARAM_FX_DIGIT_4  = 496 -- FX Index (Low)
local PARAM_SLOT_START  = 499 -- Where the mapped parameters begin

local NumberOfParameters = 192
local bankSize = 8 
local SameTrackCheck
local SameFXCheck
local SameFXGuidCheck
local SameFXNameCheck
local SameFXParamCountCheck
local SameFXChainCountCheck

local FX_CHAIN_QUARANTINE_SEC = 0.30
local fx_chain_quarantine_until = 0
local last_target_identity_changed_time = 0

lastFocusedFX = lastFocusedFX or nil

the_master_track = 0
the_vault_fx_index = 0

-- Variables for Nag Timer (Safety Warning)
local LastVaultWarningTime = 0

----------------- RSK VARIABLES ----------------------------------------------------
local PostSlots = true
-- Set only when the template assignment map changes while the same FX remains
-- focused.  This avoids rewriting all 192 metadata slots on every defer cycle,
-- while ensuring receiver scripts do not keep reading stale assignments.
local SlotMapPublishRequested = true

------------------------------------------------------------------------------------
-- PATH & FOLDER LOGIC
------------------------------------------------------------------------------------
local lvar = {}
local settings = {}
local paths = {}

-- Helper to find the folder where this script is currently saved
function GetScriptPath()
    local str = debug.getinfo(2, "S").source:sub(2)
    return str:match("(.*[/\\])")
end

-- Dynamically find the folder where this script is running
local script_folder = GetScriptPath()

-- Set paths relative to the script: /ControllerFocus/Resources/templates/
paths.resource_path = script_folder .. "ControllerFocus/Resources/"
paths.template_path = paths.resource_path .. "templates/"

-- Create the folders if they don't exist yet
reaper.RecursiveCreateDirectory(paths.resource_path, 1)
reaper.RecursiveCreateDirectory(paths.template_path, 1)

------------------------------------------------------------------------------------
-- VALUE VAULT LOGIC
------------------------------------------------------------------------------------

-- Function to find "ValueVault" quickly in Monitoring. 
function findValueVaultFXInMonitoring()
    local master_track = reaper.GetMasterTrack(0)
    if not master_track then return nil end
    
    -- "AddByName" with '1' means: "Find this FX. If you can't find it, ADD IT."
    local index = reaper.TrackFX_AddByName(master_track, "ValueVault", true, 1)
    
    if index == -1 then
        return nil -- VST not installed
    end
    
    -- Return the index with the magic number for Monitoring FX
    return 0x1000000 + index
end

-- Helper to update and display the runner count
local run_count = 0
function updateRunCounter()
    run_count = run_count + 1 
    return run_count
end

-- Helper to encode a large number into sign and four digit parts
function encodeLargeNumber(num)
    local sign = (num < 0) and 0.0 or 1.0
    num = math.abs(num)

    local part1 = math.floor(num / 1000000000)
    local part2 = math.floor((num % 1000000000) / 1000000)
    local part3 = math.floor((num % 1000000) / 1000)
    local part4 = num % 1000

    return sign, part1 / 1000, part2 / 1000, part3 / 1000, part4 / 1000
end

-- Function to process a track, FX index, and set the values on "ValueVault"
function processTrackFX(source_track, fx_index)
    -- Get the track index
    local track_id = reaper.GetMediaTrackInfo_Value(source_track, "IP_TRACKNUMBER")
    if track_id < 0 then track_id = 0 end
    local track_id_encoded = (track_id) / 1000 

    -- Try to find/add the vault
    local vault_fx_index = findValueVaultFXInMonitoring()
    
    -- SAFETY CHECK: If vault is missing, warn user (but only every 30 seconds)
    if vault_fx_index == nil then
        local now = reaper.time_precise()
        if now > LastVaultWarningTime + 30 then
            reaper.MB("WARNING: ValueVault VST has been disconnected or uninstalled.\n\n" ..
                      "The script can no longer communicate with your hardware.\n" ..
                      "Please ensure ValueVault is installed and available.", "Hardware Link Lost", 0)
            LastVaultWarningTime = now
        end
        return
    end

    -- Encode the FX index
    local sign, val2, val3, val4, val5 = encodeLargeNumber(fx_index)

    -- Update globals and set params
    local master_track = reaper.GetMasterTrack(0)
    the_master_track = master_track
    the_vault_fx_index = vault_fx_index
    
    -- LEGACY MAPPING: Ensures the GUI knows where to look
    ValueVault_CTL_TRACK = master_track
    ValueVault_CTL_TRACK_GUID = reaper.GetTrackGUID(master_track)
    
    -- Ensure the INF table exists for the fader logic
    local vault_guid = reaper.TrackFX_GetFXGUID(master_track, vault_fx_index)
    if not ValuteVault_CTL_TRACK_INF or ValuteVault_CTL_TRACK_INF.guids[1] ~= vault_guid then
        ValuteVault_CTL_TRACK_INF = {
            count = 1,
            guids = { vault_guid }
        }
    end

    -- Write Metadata to ValueVault (Using Constants)
    reaper.TrackFX_SetParam(master_track, vault_fx_index, PARAM_STATUS, 1) 
    reaper.TrackFX_SetParam(master_track, vault_fx_index, PARAM_TRACK_ID, track_id_encoded)
    reaper.TrackFX_SetParam(master_track, vault_fx_index, PARAM_FX_SIGN, sign)
    reaper.TrackFX_SetParam(master_track, vault_fx_index, PARAM_FX_DIGIT_1, val2)
    reaper.TrackFX_SetParam(master_track, vault_fx_index, PARAM_FX_DIGIT_2, val3)
    reaper.TrackFX_SetParam(master_track, vault_fx_index, PARAM_FX_DIGIT_3, val4)
    reaper.TrackFX_SetParam(master_track, vault_fx_index, PARAM_FX_DIGIT_4, val5)
end

-- Helper to establish the link to ValueVault (populates global variables at startup)
function EnsureVaultLink()
    local idx = findValueVaultFXInMonitoring()
    if not idx then return false end
    
    local master = reaper.GetMasterTrack(0)
    ValueVault_CTL_TRACK = master
    ValueVault_CTL_TRACK_GUID = reaper.GetTrackGUID(master)
    
    the_master_track = master
    the_vault_fx_index = idx
    
    local guid = reaper.TrackFX_GetFXGUID(master, idx)
    if not ValuteVault_CTL_TRACK_INF or ValuteVault_CTL_TRACK_INF.guids[1] ~= guid then
        ValuteVault_CTL_TRACK_INF = {
            count = 1,
            guids = { guid }
        }
    end
    return true
end

------------------------------------------------------------------------------------

data = ""

function trackExists(the_track_name)
    for i = 0, reaper.CountTracks(0) - 1 do
        local Datrack = reaper.GetTrack(0, i)
        local _, Daname = reaper.GetTrackName(Datrack)
        if Daname == the_track_name then
            return true
        end
    end
    return false
end

function runCommandIfTrackNotExists(the_track_name, commandID)
    if not trackExists(the_track_name) then
        local cmdID = reaper.NamedCommandLookup(commandID)
        reaper.Main_OnCommand(cmdID, 0)
    end
end

showFaderBoxTracks = false 

tab_automode = {"Trim/Read", "Read", "Touch", "Write", "Latch", "Latch Preview"}
tab_amcol = {"205 205 205", "128 128 128", "128 128 128", "128 128 128", "128 128 128", "160 128 255"}

local tab_fxtypeconv = {}
tab_fxtypeconv["dll"] = "vst"

lvar.deffloattime = 2
lvar.mousewheel_mult = 120

local contexts = {
    sliderctl = 0,
    sliderctl_h = 1,
    indexdrag = 2
}

-- Index-strip drag state.  Dragging begins only from the numbered strip, so the
-- established slider-drag behavior remains untouched.
index_drag = {
    active = false,
    source = nil,
    mode = nil,       -- "row" for swap/move, "insert" for shift-to-make-room
    target = nil,
    line_y = nil,
    next_scroll_time = 0,
}

learn_param_values = {}
learn_target_slot = nil
learn_duplicate_slot = nil
learn_last_captured_param = nil
learn_last_observed_touch_param = nil

pi = 3.14159265359
control_count = NumberOfParameters
control_max = 512

--------------------------------------------
--------------------------------------------

function GetTrack(t)
    local track
    if t == nil or t == 0 then
        track = reaper.GetMasterTrack(0)
    elseif type(t) == "userdata" then
        track = t
    elseif type(t) == "string" and t:sub(1, 1) == "{" then
        track = reaper.BR_GetMediaTrackByGUID(0, t)
    else
        track = reaper.GetTrack(0, t - 1)
    end
    return track
end

function SetAutoMode(trn, m)
    local track = GetTrack(trn)
    reaper.SetTrackAutomationMode(track, m)
end

function Menu_AutoMode(trn)
    local track = GetTrack(trn)
    local am = reaper.GetTrackAutomationMode(track, 0)

    local mstr = ""
    for i = 1, #tab_automode do
        if i > 1 then
            mstr = mstr .. "|"
        end
        mstr = mstr .. tab_automode[i]
    end
    gfx.x, gfx.y = mouse.mx, mouse.my
    local res = gfx.showmenu(mstr)
    return res - 1
end

function round(num, idp)
    local mult = 10 ^ (idp or 0)
    return math.floor(num * mult + 0.5) / mult
end


function GetFaderBoxVals()
    local ret = false

    if not (FFX and ValueVault_CTL_TRACK and ValuteVault_CTL_TRACK_INF) then
        return ret
    end

    fbvals = {}

    local track = reaper.GetMasterTrack(0)
    local track2, fxnum2, ident = ValidateTargetFXForParameterIO()

    if not (track and reaper.ValidatePtr(track, "MediaTrack*")) then return ret end
    if not (track2 and fxnum2 ~= nil and ident) then return ret end

    -- Do not allow controller values to be applied until ReadParamVals() has
    -- confirmed and stored the exact current target identity.  This prevents a
    -- one-cycle stale ValueVault snapshot from landing on a newly focused or
    -- renumbered FX.
    if not TargetIdentityMatchesStored(track2, fxnum2, ident) then
        return ret
    end

    local pending_writes = {}
    local changed_count = 0
    local zero_count = 0

    for fx_index, fx_guid in ipairs(ValuteVault_CTL_TRACK_INF.guids) do
        local fx_actual_index = fx_index - 1

        for i = 0, NumberOfParameters - 1 do
            local param_index = (fx_index - 1) * NumberOfParameters + i + 1
            local val = reaper.TrackFX_GetParamNormalized(track, 0x1000000 + fx_actual_index, i)
            val = round(val, 5)

            if template.pos[param_index] and tostring(template.pos[param_index].val) ~= tostring(val) then
                changed_count = changed_count + 1
                if val == 0 then zero_count = zero_count + 1 end

                pending_writes[#pending_writes + 1] = {
                    param_index = param_index,
                    val = val,
                    fx_actual_index = fx_actual_index,
                    source_param = i
                }
            end
        end
    end

    -- A reset burst from the controller/value store often looks like many
    -- assigned parameters all becoming zero at once.  This is allowed only after
    -- the target has already survived the identity gate above; after an FX-chain
    -- change or focus jump, that gate is intentionally not set until the next
    -- safe ReadParamVals() pass.
    if changed_count >= 8
        and zero_count == changed_count
        and reaper.time_precise() < (last_target_identity_changed_time or 0) + 1.0
    then
        return ret
    end

    for _, write in ipairs(pending_writes) do
        local param_index = write.param_index
        local val = write.val

        if recmode == 1 then
            if fader_touch[param_index] == nil then
                fader_touch[param_index] = true
                local env = reaper.GetFXEnvelope(track, 0x1000000 + (write.fx_actual_index or 0), write.source_param or (param_index - 1), true)
                ArmEnv(env, false)
            end
        end

        local pnum = tonumber(template.pos[param_index].pnum)

        if pnum and pnum >= 0 and pnum < ident.param_count then
            template.pos[param_index].val = val
            reaper.TrackFX_SetParamNormalized(track2, fxnum2, pnum, val)
            fbvals[param_index] = val
            template.dirty[param_index] = true

            update_fader = true
            ret = true

            if settings.floatfxgui ~= 0 then
                OpenFXGUI(track2, fxnum2)
            end
        end
    end

    return ret
end


function SetFaderBoxVal(i, v)
    if ValueVault_CTL_TRACK and ValuteVault_CTL_TRACK_INF then
        local track = reaper.GetMasterTrack(0)
        if track then
            local fxnum_index = math.floor((i - 1) / NumberOfParameters) + 1
            local pnum = (i - 1) % NumberOfParameters
            local fx_guid = ValuteVault_CTL_TRACK_INF.guids[fxnum_index]

            if fx_guid then
                local fx_index = fxnum_index - 1 
                reaper.TrackFX_SetParamNormalized(track, 0x1000000 + fx_index, pnum, v)
            end
        end
    end
end

function DBG(str)
    if str == nil then str = "nil" end
    -- reaper.ShowConsoleMsg(tostring(str) .. "\n")
end

------------------------------------------------------------
-- GUI FUNCTIONS
------------------------------------------------------------

function GetObjects()
    local obj = {}
    local y_offset = 30
    obj.sections = {}
    local num = 7

    local pw = math.floor(gfx1.main_w / 2) - 10

    fader_w = math.min(math.max(gfx1.main_w - 70 - pw, 50), 200)
    fader_h = 22
    fader_space = 2
    butt_h = 22

    pname_w = gfx1.main_w - fader_w - 70

    --pname
    obj.sections[2] = {
        x = 50,
        y = 50 + y_offset,
        w = pname_w,
        h = gfx1.main_h - 10
    }
    --slider
    obj.sections[1] = {
        x = obj.sections[2].x + obj.sections[2].w + 10,
        y = obj.sections[2].y,
        w = fader_w,
        h = obj.sections[2].h
    }

    --temp pnum
    obj.sections[4] = {
        x = 10,
        y = obj.sections[2].y,
        w = 30,
        h = gfx1.main_h - 10
    }

    --settings
    obj.sections[9] = { x = 10, y = 4, w = 40, h = butt_h }
    --learn
    obj.sections[8] = { x = 54, y = 4, w = 45, h = butt_h }
    --rec mode
    obj.sections[6] = {
        x = math.max(obj.sections[8].x + obj.sections[8].w + 10, obj.sections[1].x + obj.sections[1].w - 130) + 45,
        y = 4,
        w = 40,
        h = butt_h
    }

    -- Learn duplicate warning.  This occupies the old unused top-row space
    -- immediately to the right of LEARN and appears only while needed.
    local duplicate_x = obj.sections[8].x + obj.sections[8].w + 4
    obj.sections[10] = {
        x = duplicate_x,
        y = 4,
        w = math.max(86, math.min(150, obj.sections[6].x - duplicate_x - 4)),
        h = butt_h
    }
    --save
    obj.sections[5] = {
        x = math.max(obj.sections[8].x + obj.sections[8].w + 10, obj.sections[6].x + obj.sections[6].w + 10) - 5,
        y = 4,
        w = 47,
        h = butt_h
    }

    --fxname
    local xx = obj.sections[8].x + obj.sections[8].w + 4
    obj.sections[3] = {
        x = 10,
        y = 24 + y_offset,
        w = 222,
        h = butt_h
    }

    obj.sections[7] = {
        x = xx,
        y = 7,
        w = obj.sections[6].x - xx - 4,
        h = butt_h - 4
    }

    local nav_btn_w = 24
    local nav_btn_gap = 4
    local nav_btn_y = obj.sections[3].y - (butt_h + 6) * 2 
    local start_x = obj.sections[9].x 

    obj.sections.nav_buttons = {}

    for i = 1, 6 do
        obj.sections.nav_buttons[i] = {
            x = start_x + (i - 1) * (nav_btn_w + nav_btn_gap),
            y = nav_btn_y + y_offset,
            w = nav_btn_w,
            h = butt_h
        }
    end

    -- MIX and CSTRIP were placeholders and have not been implemented yet.
    -- Keep the six working tabs visible and omit the inactive placeholders.
    -- local sep_x = obj.sections.nav_buttons[6].x + nav_btn_w + nav_btn_gap
    -- obj.sections.nav_buttons[7] = { x = sep_x, y = nav_btn_y + y_offset, w = 30, h = butt_h }
    -- obj.sections.nav_buttons[8] = { x = sep_x + 30 + nav_btn_gap, y = nav_btn_y + y_offset, w = 58, h = butt_h }

    return obj
end

function GetGUI_vars()
    gfx.mode = 0
    local gui = {}
    gui.aa = 1
    gui.fontname = "Arial Rounded MT Bold"
    gui.fontsize_tab = 16
    gui.fontsz_knob = 16
    
    local os = reaper.GetOS()
    if os:match("OSX") or os:match("macOS") then
        gui.fontsize_tab = gui.fontsize_tab - 5
        gui.fontsz_knob = gui.fontsz_knob - 5
        gui.fontsz_get = (gui.fontsz_get or 16) - 5
    end

gui.color = {
    ["back"] = "87 109 130",
    ["back2"] = "87 109 130",
    ["black"] = "0 0 0",
    ["green"] = "87 109 130",

    -- Darker inactive colors
    ["deactive_1"] = "76 36 36",   -- red
    ["deactive_2"] = "70 46 36",   -- orange
    ["deactive_3"] = "76 72 36",   -- yellow
    ["deactive_4"] = "36 76 44",   -- green
    ["deactive_5"] = "36 62 92",   -- blue
    ["deactive_6"] = "52 36 92",   -- purple
    ["deactive_7"] = "92 36 66",   -- magenta
    ["deactive_8"] = "68 68 68",   -- neutral

    -- More saturated active colors
    ["active_1"] = "168 76 76",    -- red
    ["active_2"] = "168 102 76",   -- orange
    ["active_3"] = "168 162 76",   -- yellow
    ["active_4"] = "76 168 88",    -- green
    ["active_5"] = "76 137 200",   -- blue
    ["active_6"] = "112 76 200",   -- purple
    ["active_7"] = "200 76 139",   -- magenta
    ["active_8"] = "150 150 150",  -- neutral

    ["white"] = "255 255 255",
    ["deactivated_dark"] = "55 55 55",
    ["deactivated_light"] = "88 88 88",
    ["green_dark"] = "0 0 0",
    ["yellow"] = "87 109 130",
    ["pink"] = "87 109 130"
}
    return gui
end

function f_Get_SSV(s)
    if not s then return end
    local t = {}
    for i in s:gmatch("[%d%.]+") do
        t[#t + 1] = tonumber(i) / 255
    end
    gfx.r, gfx.g, gfx.b = t[1], t[2], t[3]
end

function f_Get_SSV_fade(s1, s2, p)
    if not s1 or not s2 then return end
    local t, d = {}, {}
    for i in s1:gmatch("[%d%.]+") do
        t[#t + 1] = tonumber(i) / 255
    end
    for i in s2:gmatch("[%d%.]+") do
        local x = #d + 1
        d[x] = (tonumber(i) / 255) - t[x]
    end
    gfx.r, gfx.g, gfx.b = t[1] + d[1] * p, t[2] + d[2] * p, t[3] + d[3] * p
end

function f_Get_SSV_lighter(s, amount)
    if not s then return end
    amount = F_limit(tonumber(amount) or 0, 0, 1)
    local t = {}
    for i in s:gmatch("[%d%.]+") do
        t[#t + 1] = tonumber(i) / 255
    end
    gfx.r = t[1] + (1 - t[1]) * amount
    gfx.g = t[2] + (1 - t[2]) * amount
    gfx.b = t[3] + (1 - t[3]) * amount
end

-- Brighten moving faders while also increasing saturation.  A direct blend
-- toward white alone makes vivid row colors look washed out.  This HSV-based
-- helper keeps the hue stable, raises saturation, and adds a modest value lift.
function f_Get_SSV_active_glow(s, amount)
    if not s then return end
    amount = F_limit(tonumber(amount) or 0, 0, 1)

    local t = {}
    for i in s:gmatch("[%d%.]+") do
        t[#t + 1] = tonumber(i) / 255
    end

    local rr, gg, bb = t[1] or 0, t[2] or 0, t[3] or 0
    local maxc = math.max(rr, gg, bb)
    local minc = math.min(rr, gg, bb)
    local delta = maxc - minc
    local hue = 0

    if delta > 0.000001 then
        if maxc == rr then
            hue = ((gg - bb) / delta) % 6
        elseif maxc == gg then
            hue = ((bb - rr) / delta) + 2
        else
            hue = ((rr - gg) / delta) + 4
        end
        hue = hue / 6
    end

    local saturation = (maxc > 0) and (delta / maxc) or 0
    local value = maxc
    saturation = math.min(1, saturation + (1 - saturation) * 0.55 * amount)
    value = math.min(1, value + (1 - value) * 0.34 * amount)

    if saturation <= 0.000001 then
        gfx.r, gfx.g, gfx.b = value, value, value
        return
    end

    local segment = (hue * 6) % 6
    local chroma = value * saturation
    local x = chroma * (1 - math.abs((segment % 2) - 1))
    local m = value - chroma
    local r1, g1, b1

    if segment < 1 then
        r1, g1, b1 = chroma, x, 0
    elseif segment < 2 then
        r1, g1, b1 = x, chroma, 0
    elseif segment < 3 then
        r1, g1, b1 = 0, chroma, x
    elseif segment < 4 then
        r1, g1, b1 = 0, x, chroma
    elseif segment < 5 then
        r1, g1, b1 = x, 0, chroma
    else
        r1, g1, b1 = chroma, 0, x
    end

    gfx.r, gfx.g, gfx.b = r1 + m, g1 + m, b1 + m
end

function GUI_DrawSoftWhiteBrim(x, y, w, h, amount)
    amount = F_limit(tonumber(amount) or 0, 0, 1)
    if amount <= 0 or w <= 0 or h <= 0 then return end

    gfx.set(1, 1, 1, 0.08 * amount)
    gfx.rect(x - 2, y - 2, w + 4, h + 4, 1)
    gfx.set(1, 1, 1, 0.18 * amount)
    gfx.rect(x - 1, y - 1, w + 2, h + 2, 1)
    gfx.a = 1
end

function GUI_text(gui, xywh, text, flags, col, tsz)
    if col == nil then col = gui.color.white end
    if tsz == nil then tsz = 0 end
    f_Get_SSV(col)
    gfx.a = 1
    gfx.setfont(1, gui.fontname, gui.fontsz_knob + tsz)
    gfx.x, gfx.y = xywh.x, xywh.y
    gfx.drawstr(text, 4, xywh.x + xywh.w, xywh.y + xywh.h)
end

function GUI_draw(obj, gui)
    gfx.mode = 4
    gfx.dest = 1

    if update_gfx or resize_display then
        gfx.setimgdim(1, -1, -1)
        gfx.setimgdim(1, gfx1.main_w, gfx1.main_h)

        f_Get_SSV(colours.mainbg)
        gfx.rect(0, 0, gfx1.main_w, gfx1.main_h, 1)
    end

    if update_gfx or update_fader then
        if update_gfx then
            GUI_DrawFXHeader(obj, gui)
            GUI_DrawButtons(obj, gui)
        end
        GUI_DrawFaders(obj, gui)
    end

    if index_drag and index_drag.active then
        GUI_DrawIndexDragOverlay(obj)
    end

    if ValueVault_CTL_TRACK == nil then
        xywh = {
            x = obj.sections[4].x,
            y = obj.sections[4].y,
            w = obj.sections[1].x + obj.sections[1].w - obj.sections[4].x,
            h = obj.sections[4].h
        }
        GUI_DrawButton(gui, xywh, "CONTROLLER NOT LINKED", "25 25 25", "255 0 0", true, 4)
    end

    gfx.dest = -1
    gfx.a = 1
    gfx.blit(1, 1, 0, 0, 0, gfx1.main_w, gfx1.main_h, 0, 0, gfx1.main_w, gfx1.main_h, 0, 0)
    update_gfx = false
    update_fader = false
    resize_display = false
end

function GUI_FlashButton(obj, gui, butt, txt, flashtime, col)
    gfx.dest = 1
    GUI_DrawButton(gui, obj.sections[butt], txt, col, "99 99 99", true, -1)
    gfx.dest = -1
    gfx.a = 1
    gfx.blit(1, 1, 0, 0, 0, gfx1.main_w, gfx1.main_h, 0, 0, gfx1.main_w, gfx1.main_h, 0, 0)
    refresh_gfx = reaper.time_precise() + flashtime
end

function GUI_DrawButtons(obj, gui)
    local c = colours.buttcol
    if recmode == 1 then c = "205 205 205" end
    GUI_DrawButton(gui, obj.sections[5], " SAVE", c, "99 99 99", true, -1)
    
    local bc = colours.buttcol
    if recmode == 1 then bc = "255 0 0" end
    GUI_DrawButton(gui, obj.sections[6], " REC", bc, "99 99 99", true, -1)

    local bc = colours.buttcol
    if lrnmode == true then bc = "255 0 0" end
    GUI_DrawButton(gui, obj.sections[8], " LEARN", bc, "99 99 99", true, -4)

    if lrnmode == true and learn_duplicate_slot then
        GUI_DrawButton(gui, obj.sections[10], " DUPLICATE! CLEAR?", "130 72 25", "255 255 255", true, -5)
    end

    local bc = colours.buttcol
    GUI_DrawButton(gui, obj.sections[9], " SETTINGS", bc, "99 99 99", true, -8)

    -- Working navigation buttons. MIX and CSTRIP remain commented out until
    -- their layouts are implemented.
    local nav_labels = {" P1", " P2", " B1", " B2", " F1", " F2"}
    for i = 1, #obj.sections.nav_buttons do
        GUI_DrawButton(gui, obj.sections.nav_buttons[i], nav_labels[i], colours.buttcol, "99 99 99", true, -1)
    end
end

function GUI_DrawButton(gui, xywh, txt, bcol, tcol, val, tsz)
    f_Get_SSV(bcol)
    gfx.rect(xywh.x, xywh.y, xywh.w, xywh.h, 1)
    GUI_text(gui, xywh, txt, 5, tcol, tsz)
end

function GUI_DrawFXHeader(obj, gui)
    if FFX then
        f_Get_SSV(colours.mainbg)
        gfx.rect(obj.sections[3].x, obj.sections[3].y, obj.sections[3].w, obj.sections[3].h, 1)
        GUI_text(gui, obj.sections[3], FFX.fxname, 5, tab_amcol[ValueVault_FX_TRACK_AM + 1], 2)
        -- Older builds always drew the parsed module-type suffix beside LEARN.
        -- Some plugins resolve that suffix as the unhelpful string "0".  Keep
        -- useful labels such as "(vst)" but suppress blank/zero placeholders.
        local fx_type_label = tostring(FFX.fxtype or "")
        if fx_type_label ~= "" and fx_type_label ~= "0" then
            GUI_text(gui, obj.sections[7], "(" .. fx_type_label .. ")", 5, "99 99 99", -5)
        end
    end
end

function GUI_DrawFaders(obj, gui)
    local viscnt = math.floor(obj.sections[1].h / (fader_h + fader_space))

    for i = 1, viscnt do
        if i + control_offs <= control_count and (update_gfx == true or (template.dirty[i + control_offs] == true) or template.sft[i + control_offs]) then
            GUI_DrawFader(obj, gui, i)
        end
    end
end

function GUI_DrawFader(obj, gui, i)
    local activeColors = {
        gui.color.active_1, gui.color.active_2, gui.color.active_3, gui.color.active_4,
        gui.color.active_5, gui.color.active_6, gui.color.active_7, gui.color.active_8
    }

    local deactivatedColors = {
        gui.color.deactive_1, gui.color.deactive_2, gui.color.deactive_3, gui.color.deactive_4,
        gui.color.deactive_5, gui.color.deactive_6, gui.color.deactive_7, gui.color.deactive_8
    }

    local slot = i + control_offs
    local y = (i - 1) * (fader_h + fader_space)
    local fv = 0
    local has_assignment = template.pos[slot] ~= nil
    local rowColorIndex = (slot - 1) % #activeColors + 1
    local rowSliderColor = activeColors[rowColorIndex]
    local glow = 0

    if has_assignment then
        fv = F_limit(tonumber(template.pos[slot].val) or 0, 0, 1) or 0
    end

    f_Get_SSV(colours.faderbg)
    gfx.rect(obj.sections[1].x, obj.sections[1].y + y, fader_w, fader_h, 1)

    if has_assignment then
        f_Get_SSV(colours.faderborder)
        gfx.rect(obj.sections[1].x, obj.sections[1].y + y, fader_w, fader_h, 1)
        f_Get_SSV(colours.faderbg2)
        gfx.rect(obj.sections[1].x + 2, obj.sections[1].y + y + 2, fader_w - 4, fader_h - 4, 1)

        local now = reaper.time_precise()
        if update_gfx == false and template.dirty[slot] == true then
            template.sft[slot] = now + fadedel_s
            template.eft[slot] = now + fadedel_e
            template.dirty[slot] = nil
            glow = 1
        elseif template.sft[slot] and template.sft[slot] > now then
            glow = 1
        elseif template.sft[slot] and template.sft[slot] <= now and template.eft[slot] > now then
            local fade = inSine((now - template.sft[slot]) / (template.eft[slot] - template.sft[slot]))
            glow = 1 - fade
        elseif template.eft[slot] and template.eft[slot] <= now then
            template.sft[slot] = nil
            template.eft[slot] = nil
            template.dirty[slot] = nil
        else
            template.dirty[slot] = nil
        end

        local fillX = obj.sections[1].x + 4
        local fillY = obj.sections[1].y + y + 4
        local fillW = (fader_w - 8) * fv
        local fillH = fader_h - 8

        -- Preserve the established value-width display, but make each slider use
        -- the same flat eight-color row cycle as its small marker.  Moving values
        -- brighten briefly and receive a restrained soft white brim.
        GUI_DrawSoftWhiteBrim(fillX, fillY, fillW, fillH, glow)
        f_Get_SSV_active_glow(rowSliderColor, glow)
        gfx.a = 1
        gfx.rect(fillX, fillY, fillW, fillH, 1)
    else
        -- Empty rows can be marked dirty after Clear. Consume that refresh flag
        -- after repainting so an empty row does not redraw forever.
        template.dirty[slot] = nil
        template.sft[slot] = nil
        template.eft[slot] = nil
    end

    local pname, col, f, bcol
    if has_assignment then
        pname = template.pos[slot].pname
        local bankIndex = math.floor((slot - 1) / bankSize) % #activeColors + 1
        col = activeColors[bankIndex]
        bcol = "0 0 0"
        f = 1
    else
        pname = ""
        local bankIndex = math.floor((slot - 1) / bankSize) % #deactivatedColors + 1
        col = deactivatedColors[bankIndex]
        bcol = "30 30 30"
        f = 1
    end

    local xywh = {
        x = obj.sections[2].x - 4,
        y = obj.sections[2].y + y,
        w = obj.sections[2].w,
        h = fader_h
    }

    f_Get_SSV(bcol)
    gfx.rect(xywh.x, xywh.y, xywh.w, xywh.h, f)
    GUI_text(gui, xywh, pname, 5, ("188 188 188"), -1)

    -- Draw the existing small vertical color bar unchanged.
    local colorBarSet = has_assignment and activeColors or deactivatedColors
    local colorBarColor = colorBarSet[rowColorIndex]

    f_Get_SSV("25 25 25")
    local barX = xywh.x + xywh.w + 4 
    local barY = xywh.y
    local barW = 10
    local barH = xywh.h
    gfx.rect(barX, barY, barW, barH, 1)

    f_Get_SSV(colorBarColor)
    barX = xywh.x + xywh.w + 7 
    barY = xywh.y + 4
    barW = 4
    barH = xywh.h - 8
    gfx.rect(barX, barY, barW, barH, 1)

    xywh = {
        x = obj.sections[4].x,
        y = obj.sections[4].y + y,
        w = obj.sections[4].w,
        h = fader_h
    }

    if recmode == 1 and fader_touch[slot] then
        col = "205 205 205"
    end
    if lrnmode == true and learn_target_slot == slot then
        -- Make the next learn destination unmistakable without changing the
        -- ordinary eight-color grouping when LEARN is not active.
        col = "0 255 210"
    end
    f_Get_SSV(col)
    gfx.rect(xywh.x, xywh.y, xywh.w, xywh.h, 1)
    if lrnmode == true and learn_target_slot == slot then
        gfx.set(1, 1, 1, 0.95)
        gfx.rect(xywh.x, xywh.y, xywh.w, xywh.h, 0)
        gfx.a = 1
    end
    GUI_text(gui, xywh, string.format("%i", round(slot)), 5, gui.color.black, 1)
end

function inCubic(t) return t ^ 3 end

function outCubic(t)
    if t < 0 then
        t = -t - 1
        return -(t ^ 3 + 1)
    else
        t = t - 1
        return t ^ 3 + 1
    end
end

function inSine(t)
    if t < 0 then
        return -(-1 * math.cos(-t * (pi / 2)) + 1)
    else
        return -1 * math.cos(t * (pi / 2)) + 1
    end
end

function outSine(t) return 1 * math.sin(t * (pi / 2)) end

function Lokasenna_Window_At_Center(w, h)
    local l, t, r, b = 0, 0, w, h
    local __, __, screen_w, screen_h = reaper.my_getViewport(l, t, r, b, l, t, r, b, 1)
    local x, y = (screen_w - w) / 2, (screen_h - h) / 2
    gfx.init(SCRIPT_NAME, w, h, 0, x, y)
end

function F_limit(val, min, max)
    if val == nil or min == nil or max == nil then return end
    local val_out = val
    if val < min then val_out = min end
    if val > max then val_out = max end
    return val_out
end

function MOUSE_slider_horiz(b, xoff)
    if mouse.LB then
        if xoff == nil then xoff = 0 end
        local mx = mouse.mx - (b.x - 200) + xoff
        return (mx) / (b.w + 400)
    end
end

function MOUSE_slider_horiz2(b, xoff)
    if mouse.LB then
        if xoff == nil then xoff = 0 end
        local mx = mouse.mx - (b.x)
        return (mx) / (b.w)
    end
end

function MOUSE_slider(b, yoff)
    if mouse.LB then
        if yoff == nil then yoff = 0 end
        local my = mouse.my - (b.y - 200) + yoff
        return (my) / (b.h + 400)
    end
end

function MOUSE_click(b)
    if mouse.mx > b.x and mouse.mx < b.x + b.w and mouse.my > b.y and mouse.my < b.y + b.h and mouse.LB and
            not mouse.last_LB then
        return true
    end
end

function MOUSE_click_RB(b)
    if mouse.mx > b.x and mouse.mx < b.x + b.w and mouse.my > b.y and mouse.my < b.y + b.h and mouse.RB and
            not mouse.last_RB then
        return true
    end
end

function MOUSE_over(b)
    if mouse.mx > b.x and mouse.mx < b.x + b.w and mouse.my > b.y and mouse.my < b.y + b.h then
        return true
    end
end

function VisibleFaderRowCount(obj)
    local available_h = math.max(fader_h + fader_space, gfx.h - obj.sections[1].y)
    return math.max(1, math.floor(available_h / (fader_h + fader_space)))
end

function ClampControlOffsetForVisibleRows(obj, offs)
    local max_offs = math.max(0, control_count - VisibleFaderRowCount(obj))
    return math.max(0, math.min(max_offs, math.floor(tonumber(offs) or 0)))
end

function ResetIndexDrag()
    index_drag.active = false
    index_drag.source = nil
    index_drag.mode = nil
    index_drag.target = nil
    index_drag.line_y = nil
    index_drag.next_scroll_time = 0
    if mouse then mouse.context = nil end
end

function BeginIndexDrag(slot)
    slot = tonumber(slot)
    -- Empty rows are intentionally draggable too.  Moving an empty row is a
    -- useful way to shift a group of assignments without inventing a temporary
    -- assignment solely as a spacer.
    if not slot or slot < 1 or slot > control_count then return end
    index_drag.active = true
    index_drag.source = slot
    index_drag.mode = "row"
    index_drag.target = slot
    index_drag.line_y = nil
    index_drag.next_scroll_time = 0
    mouse.context = contexts.indexdrag
    update_gfx = true
end

function ApplyIndexDragDrop()
    if not index_drag.active or not index_drag.source or not index_drag.target then return end

    local source = index_drag.source
    local target = index_drag.target
    local first_changed = source
    local last_changed = source

    if index_drag.mode == "row" then
        target = math.max(1, math.min(control_count, target))
        if target == source then return end

        template.pos[source], template.pos[target] = template.pos[target], template.pos[source]
        first_changed = math.min(source, target)
        last_changed = math.max(source, target)
    elseif index_drag.mode == "insert" then
        local insert_pos = math.max(1, math.min(control_count + 1, target))
        local destination = insert_pos
        if source < insert_pos then destination = insert_pos - 1 end
        destination = math.max(1, math.min(control_count, destination))
        if destination == source then return end

        local moved = template.pos[source]
        if destination < source then
            for i = source, destination + 1, -1 do
                template.pos[i] = template.pos[i - 1]
            end
        else
            for i = source, destination - 1 do
                template.pos[i] = template.pos[i + 1]
            end
        end
        template.pos[destination] = moved
        first_changed = math.min(source, destination)
        last_changed = math.max(source, destination)
    end

    FinalizeTemplateAssignmentEdit(first_changed, last_changed)
end

function FinishIndexDrag()
    ApplyIndexDragDrop()
    ResetIndexDrag()
    update_gfx = true
end

function UpdateIndexDrag(obj)
    if not index_drag.active then return end
    if not mouse.LB then
        FinishIndexDrag()
        return
    end

    local now = reaper.time_precise()
    local top = obj.sections[4].y
    local bottom = math.min(gfx.h - 1, top + VisibleFaderRowCount(obj) * (fader_h + fader_space))
    local auto_zone = 18

    if now >= (index_drag.next_scroll_time or 0) then
        local new_offs = control_offs
        if mouse.my <= top + auto_zone then
            new_offs = control_offs - 1
        elseif mouse.my >= bottom - auto_zone then
            new_offs = control_offs + 1
        end
        new_offs = ClampControlOffsetForVisibleRows(obj, new_offs)
        if new_offs ~= control_offs then
            control_offs = new_offs
            index_drag.next_scroll_time = now + 0.10
        end
    end

    local row_step = fader_h + fader_space
    local clamped_y = math.max(top, math.min(bottom - 1, mouse.my))
    local visible_row = math.floor((clamped_y - top) / row_step) + 1
    local absolute_row = control_offs + visible_row
    local within_row = (clamped_y - top) % row_step
    local row_y = top + (visible_row - 1) * row_step
    local insert_zone = 3

    absolute_row = math.max(1, math.min(control_count, absolute_row))
    if within_row <= insert_zone then
        index_drag.mode = "insert"
        index_drag.target = absolute_row
        index_drag.line_y = row_y
    elseif within_row >= fader_h - insert_zone then
        index_drag.mode = "insert"
        index_drag.target = math.min(control_count + 1, absolute_row + 1)
        index_drag.line_y = row_y + row_step
    else
        index_drag.mode = "row"
        index_drag.target = absolute_row
        index_drag.line_y = nil
    end

    -- Redraw the full backing buffer during an index drag so moving outlines or
    -- insertion lines do not leave trails behind.
    update_gfx = true
end

function GUI_DrawIndexDragOverlay(obj)
    if not index_drag.active then return end

    local row_step = fader_h + fader_space
    local list_x = obj.sections[4].x - 2
    local list_w = obj.sections[1].x + obj.sections[1].w - list_x

    local function row_y_for_slot(slot)
        local visible_row = slot - control_offs
        if visible_row < 1 or visible_row > VisibleFaderRowCount(obj) then return nil end
        return obj.sections[4].y + (visible_row - 1) * row_step
    end

    local source_y = row_y_for_slot(index_drag.source)
    if source_y then
        gfx.set(1, 0.72, 0.25, 0.95)
        gfx.rect(list_x, source_y, list_w, fader_h, 0)
    end

    if index_drag.mode == "row" and index_drag.target then
        local target_y = row_y_for_slot(index_drag.target)
        if target_y then
            gfx.set(1, 1, 1, 0.16)
            gfx.rect(list_x, target_y, list_w, fader_h, 1)
            gfx.set(1, 1, 1, 0.95)
            gfx.rect(list_x, target_y, list_w, fader_h, 0)
        end
    elseif index_drag.mode == "insert" and index_drag.line_y then
        gfx.set(1, 1, 1, 0.95)
        gfx.rect(list_x, index_drag.line_y - 1, list_w, 3, 1)
    end
    gfx.a = 1
end

function GetTrackChunk(track)
    if not track then return end
    local fast_str, track_chunk
    fast_str = reaper.SNM_CreateFastString("")
    if reaper.SNM_GetSetObjectState(track, fast_str, false, false) then
        track_chunk = reaper.SNM_GetFastString(fast_str)
    end
    reaper.SNM_DeleteFastString(fast_str)
    return track_chunk
end

function SetTrackChunk(track, track_chunk)
    if not (track and track_chunk) then return end
    local fast_str, ret
    fast_str = reaper.SNM_CreateFastString("")
    if reaper.SNM_SetFastString(fast_str, track_chunk) then
        ret = reaper.SNM_GetSetObjectState(track, fast_str, true, false)
    end
    reaper.SNM_DeleteFastString(fast_str)
    return ret
end

function GetFocusedFX()
    local FFX = nil
    local ret, trn, itmnum, fxnum = reaper.GetFocusedFX()

    -- ret: 0=no focus, 1=track FX, 2=item FX
    -- We only process if it's a Track FX (1) and we aren't in recmode
    if ret == 1 and recmode == 0 then
        local track = GetTrack(trn)
        
        if track then
            -- Prevent tracking the ValueVault plugin itself (Monitoring FX on Master)
            local is_master = (trn == 0)
            local is_monitoring = (fxnum >= 0x1000000)
            local ignore = false
            
            if is_master and is_monitoring then
                local _, fxname = reaper.TrackFX_GetFXName(track, fxnum, "")
                if fxname:match("ValueVault") then
                    ignore = true
                end
            end

            if not ignore then
                local fxguid = reaper.TrackFX_GetFXGUID(track, fxnum)
                local _, fxname = reaper.TrackFX_GetFXName(track, fxnum, "")
                
                -- Safely parse module name for templates
                local _, fxMod = reaper.BR_TrackFX_GetFXModuleName(track, fxnum, "", 128)
                local fxnm = fxname
                local fxtype = ""
                
                if fxMod and fxMod ~= "" then
                    local fxnm_match, fxtype_match = string.match(fxMod, "(.+)%.(.*)")
                    if fxnm_match then fxnm = fxnm_match end
                    if fxtype_match then fxtype = tab_fxtypeconv[fxtype_match] or fxtype_match end
                end
                
                fxname = TrimFXName(fxname)
                
                local fx_monitoring = IsMonitoringFXIndex(fxnum)
                local fx_chain_count = GetTargetFXChainCount(track, fxnum)
                local fx_param_count = reaper.TrackFX_GetNumParams(track, fxnum)

                FFX = {
                    trn = trn,
                    trguid = reaper.GetTrackGUID(track),
                    fxnum = fxnum,
                    fxname = fxname,
                    fxplug = fxnm,
                    fxguid = fxguid,
                    fxtype = fxtype,
                    paramcount = fx_param_count,
                    chaincount = fx_chain_count,
                    monitoring = fx_monitoring
                }
            end
        end
    end
    
    return FFX, ret
end

function SetTemplateParam(temppos, paramnum, paramname)
    template.pos[temppos] = {
        pnum = paramnum,
        pname = paramname,
        -- Template assignments can exist before the first safe FX-value read,
        -- especially during the new chain-change quarantine.  Use a numeric
        -- display fallback so GUI drawing never multiplies nil.
        val = 0
    }
    SlotMapPublishRequested = true
end

function MarkTemplateRowsDirty(first_row, last_row)
    first_row = math.max(1, tonumber(first_row) or 1)
    last_row = math.min(control_count, tonumber(last_row) or first_row)
    if last_row < first_row then first_row, last_row = last_row, first_row end

    for i = first_row, last_row do
        template.dirty[i] = true
        template.sft[i] = nil
        template.eft[i] = nil
    end
end

function SynchronizeFaderBoxValuesFromTemplate()
    for i = 1, control_count do
        local entry = template.pos[i]
        SetFaderBoxVal(i, entry and tonumber(entry.val) or 0)
    end
end

function FinalizeTemplateAssignmentEdit(first_row, last_row)
    MarkTemplateRowsDirty(first_row or 1, last_row or control_count)
    SlotMapPublishRequested = true
    SynchronizeFaderBoxValuesFromTemplate()
    update_fader = true
    update_gfx = true
end

function ClearTemplateSlot(i)
    i = tonumber(i)
    if not i or i < 1 or i > control_count then return end
    template.pos[i] = nil
    fader_touch[i] = nil
    SetFaderBoxVal(i, 0)
    FinalizeTemplateAssignmentEdit(i, i)
end

function ClearAllCurrentAssignments()
    for i = 1, control_count do
        template.pos[i] = nil
        fader_touch[i] = nil
        SetFaderBoxVal(i, 0)
    end
    FinalizeTemplateAssignmentEdit(1, control_count)
end

function FindFirstEmptyTemplateSlot()
    for i = 1, control_count do
        if not template.pos[i] then return i end
    end
    return nil
end

function SetLearnTargetSlot(slot)
    slot = tonumber(slot)
    if not slot or slot < 1 or slot > control_count then return false end
    learn_target_slot = math.floor(slot)
    update_gfx = true
    return true
end

function AdvanceLearnTargetSlot()
    if not learn_target_slot then return end
    if learn_target_slot < control_count then
        learn_target_slot = learn_target_slot + 1
    else
        learn_target_slot = nil
    end
    update_gfx = true
end

function GetLearnTouchedParameter()
    if not FFX then return nil end

    -- Prefer the current API when available.  GetLastTouchedFX is retained as a
    -- fallback for older REAPER versions.
    if reaper.GetTouchedOrFocusedFX then
        local retval, trackidx, itemidx, takeidx, fxidx, parm = reaper.GetTouchedOrFocusedFX(0)
        local expected_trackidx = (tonumber(FFX.trn) or 0) - 1
        if retval
            and tonumber(itemidx) == -1
            and tonumber(trackidx) == expected_trackidx
            and tonumber(fxidx) == tonumber(FFX.fxnum)
        then
            return tonumber(parm)
        end
    end

    local retval, trn, fxn, pn = reaper.GetLastTouchedFX()
    if retval and tonumber(trn) == tonumber(FFX.trn) and tonumber(fxn) == tonumber(FFX.fxnum) then
        return tonumber(pn)
    end
    return nil
end


function SnapshotLearnTargetValues()
    learn_param_values = {}
    learn_last_observed_touch_param = GetLearnTouchedParameter()
    if not FFX then return end

    local track, safe_fxnum, ident = ValidateTargetFXForParameterIO()
    if not (track and safe_fxnum ~= nil and ident) then return end

    local numparams = ident.param_count
    for p = 0, numparams - 1 do
        learn_param_values[p] = reaper.TrackFX_GetParamNormalized(track, safe_fxnum, p)
    end
end



function FindMovedLearnParameter(track, fxnum, numparams, preferred_pn)
    local changed = {}
    for p = 0, numparams - 1 do
        local current_value = reaper.TrackFX_GetParamNormalized(track, fxnum, p)
        local previous_value = learn_param_values[p]
        learn_param_values[p] = current_value
        if previous_value ~= nil and math.abs(current_value - previous_value) > 0.0000001 then
            changed[#changed + 1] = p
        end
    end

    -- When REAPER identifies the touched parameter, prefer it over secondary
    -- changes caused by a plugin internally linking more than one control.
    preferred_pn = tonumber(preferred_pn)
    if preferred_pn ~= nil and preferred_pn ~= learn_last_captured_param then
        for _, p in ipairs(changed) do
            if p == preferred_pn then return p end
        end
    end

    -- Some plugin buttons do not update REAPER's legacy last-touched report
    -- reliably, but their normalized value still changes.  The snapshot scan
    -- catches those toggles here.
    for _, p in ipairs(changed) do
        if p ~= learn_last_captured_param then return p end
    end

    return nil
end


function DismissLearnDuplicateWarning()
    if learn_duplicate_slot then
        learn_duplicate_slot = nil
        update_gfx = true
    end
end

function ClearPendingLearnDuplicate()
    local slot = tonumber(learn_duplicate_slot)
    if not slot then return end

    -- Remove only the newly learned duplicate.  The earlier assignment remains
    -- untouched, and this same row waits for the user's next learned movement.
    learn_duplicate_slot = nil
    ClearTemplateSlot(slot)
    SetLearnTargetSlot(slot)
    update_gfx = true
end

function ToggleLearnMode()
    lrnmode = not lrnmode
    lasttouched = nil
    learn_duplicate_slot = nil
    learn_last_captured_param = nil
    learn_last_observed_touch_param = nil
    if lrnmode then
        -- Begin at the first empty slot as before, but keep an explicit target
        -- so the user may click any numbered index and continue sequentially
        -- from there, overwriting existing assignments when desired.
        learn_target_slot = FindFirstEmptyTemplateSlot()
        SnapshotLearnTargetValues()
    else
        learn_param_values = {}
        learn_target_slot = nil
    end
    update_gfx = true
end


function CaptureLearnedParameterIfMoved()
    if not FFX then return end

    local track, safe_fxnum, ident = ValidateTargetFXForParameterIO()
    if not (track and safe_fxnum ~= nil and ident) then return end

    local touched_pn = GetLearnTouchedParameter()
    local touch_identity_changed = touched_pn ~= nil and touched_pn ~= learn_last_observed_touch_param
    if touched_pn ~= nil then learn_last_observed_touch_param = touched_pn end

    local numparams = ident.param_count
    local pn = FindMovedLearnParameter(track, safe_fxnum, numparams, touched_pn)

    -- Momentary plugin buttons can return to their original normalized value
    -- before the next defer cycle.  If REAPER reports a newly touched parameter,
    -- accept that identity even when the value scan did not catch the transient.
    if pn == nil and touch_identity_changed and touched_pn ~= learn_last_captured_param then
        pn = touched_pn
    end

    -- One physical slider gesture generates many intermediate values.  Learn it
    -- once, then ignore further updates from that same parameter until another
    -- parameter has been learned.  Deliberate duplicates remain possible later
    -- in the same learn session after touching a different FX control.
    if pn == nil or pn == learn_last_captured_param then return end
    if pn < 0 or pn >= ident.param_count then return end

    local current_value = reaper.TrackFX_GetParamNormalized(track, safe_fxnum, pn)
    lasttouched = {trn = FFX.trn, fxn = safe_fxnum, pn = pn}

    -- A new movement accepts any previously warned duplicate.  The old warning
    -- disappears before this movement is learned, but another warning may be
    -- raised below if the newly learned parameter is itself duplicated.
    DismissLearnDuplicateWarning()

    local i = learn_target_slot or FindFirstEmptyTemplateSlot()
    if not i then return end

    local duplicate_found = false
    for slot = 1, control_count do
        if slot ~= i and template.pos[slot] and tonumber(template.pos[slot].pnum) == pn then
            duplicate_found = true
            break
        end
    end

    local _, pname = reaper.TrackFX_GetParamName(track, safe_fxnum, pn, "")
    SetTemplateParam(i, pn, pname)
    template.pos[i].val = current_value
    SetFaderBoxVal(i, current_value)
    template.dirty[i] = true
    update_fader = true
    learn_last_captured_param = pn
    AdvanceLearnTargetSlot()

    if duplicate_found then
        -- Keep the duplicate unless the user clicks the temporary warning.
        -- The newly written row is the only row that the button may clear.
        learn_duplicate_slot = i
        update_gfx = true
    end
end



function ParamMenu()
    if FFX then
        local track, safe_fxnum, ident = ValidateTargetFXForParameterIO()
        if not (track and safe_fxnum ~= nil and ident) then return end

        local numparams = ident.param_count
        local menustr = "Clear All|Clear (" .. numparams .. ")"
        local pnames = {}

        for p = 0, numparams - 1 do
            local ret, pname = reaper.TrackFX_GetParamName(track, safe_fxnum, p, "")
            pnames[p] = pname
            menustr = menustr .. "|" .. (p + 1) .. ": " .. pname
        end

        gfx.x, gfx.y = mouse.mx, mouse.my
        local res = gfx.showmenu(menustr)
        if res > 0 then
            if res == 1 then
                return -2
            elseif res == 2 then
                return -1
            else
                local index = res - 3
                return index, pnames[index]
            end
        end
    end
end


function TrimFXName(fxname)
    fxname = fxname or ""
    local fxn = string.match(fxname, ".-: (.+) %(")
    if fxn == nil then
        fxn = string.match(fxname, ".-: (.*)")
        if fxn == nil then
            fxn = fxname
        end
    end
    local fxn = string.gsub(fxn, "/", "")
    return fxn
end


------------------------------------------------------------
-- TARGET FX IDENTITY / CHAIN-CHANGE SAFETY
------------------------------------------------------------

function ClearTargetIdentityChecks()
    SameTrackCheck = nil
    SameFXCheck = nil
    SameFXGuidCheck = nil
    SameFXNameCheck = nil
    SameFXParamCountCheck = nil
    SameFXChainCountCheck = nil
    if reaper and reaper.time_precise then
        last_target_identity_changed_time = reaper.time_precise()
    end
end

function ClearCurrentFXTarget()
    FFX = nil
    lastFocusedFX = nil
    ClearTargetIdentityChecks()

    learn_param_values = {}
    learn_last_captured_param = nil
    learn_last_observed_touch_param = nil

    template = { dirty = {}, pos = {}, sft = {}, eft = {} }

    if lvar then
        lvar.fxopentimer = nil
        lvar.fxopeninfo = nil
    end

    SlotMapPublishRequested = true
    update_gfx = true
    update_fader = true
end

function QuarantineFXChain()
    fx_chain_quarantine_until = reaper.time_precise() + FX_CHAIN_QUARANTINE_SEC
end

function FXChainIsQuarantined()
    return reaper.time_precise() < (fx_chain_quarantine_until or 0)
end

function IsMonitoringFXIndex(fxnum)
    return tonumber(fxnum) ~= nil and fxnum >= 0x1000000
end

function GetFXChainPosition(fxnum)
    fxnum = tonumber(fxnum)
    if fxnum == nil then return nil end
    if IsMonitoringFXIndex(fxnum) then
        return fxnum - 0x1000000
    end
    return fxnum
end

function MakeFXIndexFromChainPosition(was_monitoring, chain_pos)
    chain_pos = tonumber(chain_pos)
    if chain_pos == nil then return nil end
    if was_monitoring then
        return 0x1000000 + chain_pos
    end
    return chain_pos
end

function GetTargetFXChainCount(track, fxnum)
    if not (track and reaper.ValidatePtr(track, "MediaTrack*")) then return 0 end
    if IsMonitoringFXIndex(fxnum) then
        return reaper.TrackFX_GetRecCount(track)
    end
    return reaper.TrackFX_GetCount(track)
end

function FindFXIndexByGUID(track, fxguid, was_monitoring)
    if not (track and fxguid and fxguid ~= "") then return nil end

    local count = was_monitoring and reaper.TrackFX_GetRecCount(track) or reaper.TrackFX_GetCount(track)
    for i = 0, count - 1 do
        local fx_index = MakeFXIndexFromChainPosition(was_monitoring, i)
        if reaper.TrackFX_GetFXGUID(track, fx_index) == fxguid then
            return fx_index
        end
    end

    return nil
end

function GetFXIdentity(track, fxnum)
    if not (track and reaper.ValidatePtr(track, "MediaTrack*")) then return nil end

    local was_monitoring = IsMonitoringFXIndex(fxnum)
    local chain_pos = GetFXChainPosition(fxnum)
    local chain_count = GetTargetFXChainCount(track, fxnum)

    if chain_pos == nil or chain_pos < 0 or chain_pos >= chain_count then
        return nil
    end

    local full_fxnum = MakeFXIndexFromChainPosition(was_monitoring, chain_pos)
    local fxguid = reaper.TrackFX_GetFXGUID(track, full_fxnum)

    if not fxguid or fxguid == "" then
        return nil
    end

    local _, fxname = reaper.TrackFX_GetFXName(track, full_fxnum, "")
    fxname = TrimFXName(fxname)

    return {
        guid = fxguid,
        name = fxname,
        param_count = reaper.TrackFX_GetNumParams(track, full_fxnum),
        chain_count = chain_count,
        monitoring = was_monitoring
    }
end

function TargetIdentityMatchesStored(track, fxnum, ident)
    return track
        and fxnum ~= nil
        and ident
        and SameTrackCheck == track
        and SameFXCheck == fxnum
        and SameFXGuidCheck == ident.guid
        and SameFXNameCheck == ident.name
        and SameFXParamCountCheck == ident.param_count
        and SameFXChainCountCheck == ident.chain_count
end

function StoreTargetIdentityCheck(track, fxnum, ident)
    if not (track and fxnum ~= nil and ident) then return end

    if not TargetIdentityMatchesStored(track, fxnum, ident) then
        last_target_identity_changed_time = reaper.time_precise()
    end

    SameTrackCheck = track
    SameFXCheck = fxnum
    SameFXGuidCheck = ident.guid
    SameFXNameCheck = ident.name
    SameFXParamCountCheck = ident.param_count
    SameFXChainCountCheck = ident.chain_count
end

function UpdateFocusedFXIndexAfterMove(track, fxnum, ident)
    if not (FFX and fxnum ~= nil and ident) then return end

    FFX.fxnum = fxnum
    FFX.fxguid = ident.guid
    FFX.fxname = ident.name
    FFX.paramcount = ident.param_count
    FFX.chaincount = ident.chain_count
    FFX.monitoring = ident.monitoring

    if lastFocusedFX and lastFocusedFX.fxguid == FFX.fxguid then
        lastFocusedFX.fxnum = fxnum
        lastFocusedFX.fxguid = ident.guid
        lastFocusedFX.fxname = ident.name
        lastFocusedFX.paramcount = ident.param_count
        lastFocusedFX.chaincount = ident.chain_count
        lastFocusedFX.monitoring = ident.monitoring
    end
end

function ValidateTargetFXForParameterIO()
    if not FFX then return nil end
    if FXChainIsQuarantined() then return nil end

    local track = FFX.trguid and reaper.BR_GetMediaTrackByGUID(0, FFX.trguid) or GetTrack(FFX.trn)

    if not (track and reaper.ValidatePtr(track, "MediaTrack*")) then
        ClearCurrentFXTarget()
        return nil
    end

    if FFX.trguid and FFX.trguid ~= reaper.GetTrackGUID(track) then
        ClearCurrentFXTarget()
        return nil
    end

    local was_monitoring = FFX.monitoring or IsMonitoringFXIndex(FFX.fxnum)
    local chain_count = GetTargetFXChainCount(track, FFX.fxnum)

    if FFX.chaincount and chain_count ~= FFX.chaincount then
        local moved_index = FindFXIndexByGUID(track, FFX.fxguid, was_monitoring)
        QuarantineFXChain()
        ClearTargetIdentityChecks()

        if not moved_index then
            ClearCurrentFXTarget()
            return nil
        end

        local moved_ident = GetFXIdentity(track, moved_index)
        if moved_ident then
            UpdateFocusedFXIndexAfterMove(track, moved_index, moved_ident)
        end

        return nil
    end

    local ident = GetFXIdentity(track, FFX.fxnum)

    if not ident or ident.guid ~= FFX.fxguid then
        local moved_index = FindFXIndexByGUID(track, FFX.fxguid, was_monitoring)
        QuarantineFXChain()
        ClearTargetIdentityChecks()

        if not moved_index then
            ClearCurrentFXTarget()
            return nil
        end

        local moved_ident = GetFXIdentity(track, moved_index)
        if moved_ident then
            UpdateFocusedFXIndexAfterMove(track, moved_index, moved_ident)
        end

        return nil
    end

    if FFX.fxname and ident.name ~= FFX.fxname then
        ClearCurrentFXTarget()
        return nil
    end

    if FFX.paramcount and ident.param_count ~= FFX.paramcount then
        ClearCurrentFXTarget()
        return nil
    end

    UpdateFocusedFXIndexAfterMove(track, FFX.fxnum, ident)

    return track, FFX.fxnum, ident
end

function IsDifferentFocusedTarget(new_fx, old_fx)
    if not new_fx and not old_fx then return false end
    if not new_fx or not old_fx then return true end

    return new_fx.trguid ~= old_fx.trguid
        or new_fx.fxguid ~= old_fx.fxguid
        or new_fx.fxname ~= old_fx.fxname
        or new_fx.fxnum ~= old_fx.fxnum
        or new_fx.paramcount ~= old_fx.paramcount
        or new_fx.chaincount ~= old_fx.chaincount
end


function LoadFXParamTemplate(ffx)
    learn_duplicate_slot = nil
    template = {
        dirty = {},
        pos = {},
        sft = {},
        eft = {}
    }

    if ffx then
        local ffn
        if settings.usemod == 1 then
            ffn = paths.template_path .. TrimFXName(ffx.fxplug) .. "_" .. (ffx.fxtype or "") .. ".smtemp"
        else
            ffn = paths.template_path .. TrimFXName(ffx.fxname) .. "_" .. ffx.fxtype .. ".smtemp"
        end
        if reaper.file_exists(ffn) ~= true then
            ffn = paths.template_path .. TrimFXName(ffx.fxplug) .. ".smtemp"
            if reaper.file_exists(ffn) ~= true then
                return 0
            end
        end

        data = {}
        for line in io.lines(ffn) do
            local idx, val = string.match(line, "%[(.-)%](.*)") 
            if idx then
                data[idx] = val
            end
        end

        settings.floatfxgui = 0
        if data["floatgui"] then
            settings.floatfxgui = tonumber(data["floatgui"])
        end

        for i = 1, control_max do
            local pfx = "ctl_" .. i .. "_"
            local pnum = zn(data[pfx .. "pnum"])
            if pnum then
                template.pos[i] = {
                    pnum = pnum,
                    pname = zn(data[pfx .. "pname"], ""),
                    -- Loaded templates have assignments before live values are read.
                    -- Keep val numeric until ReadParamVals refreshes it from the FX.
                    val = 0
                }
            end
        end
    end
end

function nz(val, d)
    if val == nil then return d else return val end
end
function zn(val, d)
    if val == "" or val == nil then return d else return val end
end

function SaveFXParamTemplate(ffx, template)
    if ffx then
        if settings.usemod == 1 then
            ffn = paths.template_path .. TrimFXName(ffx.fxplug) .. "_" .. ffx.fxtype .. ".smtemp"
        else
            ffn = paths.template_path .. TrimFXName(ffx.fxname) .. "_" .. ffx.fxtype .. ".smtemp"
        end
        file = io.open(ffn, "w")
        file:write("[floatgui]" .. (settings.floatfxgui or 0) .. "\n")

        for i = 1, control_max do
            if template.pos[i] then
                local pfx = "ctl_" .. i .. "_"
                file:write("[" .. pfx .. "pnum]" .. template.pos[i].pnum .. "\n")
                file:write("[" .. pfx .. "pname]" .. template.pos[i].pname .. "\n")
            end
        end
        file:close()
    end
end


function ReadParamVals(upd_fb)
    if FFX then
        local track, safe_fxnum, ident = ValidateTargetFXForParameterIO()
        if not (track and safe_fxnum ~= nil and ident) then return end

        local ctltrack = GetTrack(ValueVault_CTL_TRACK)

        -- Ensure we have a valid Master Track before we try to use it.
        if not (the_master_track and reaper.ValidatePtr(the_master_track, "MediaTrack*")) then
            the_master_track = reaper.GetMasterTrack(0)
        end

        if TargetIdentityMatchesStored(track, safe_fxnum, ident) then
            -- The focused FX has not changed, but its template may have.
            -- Publish only when an edit explicitly requests it.
            PostSlots = SlotMapPublishRequested == true
        else
            processTrackFX(track, safe_fxnum)
            PostSlots = true
        end

        -- Clear the complete published map before any republish.  This removes
        -- stale entries when an assignment has been deleted.  A same-FX template
        -- edit can request a republish without first calling processTrackFX(),
        -- so refresh the ValueVault link here.
        local slot_publish_ready = false
        if PostSlots == true then
            EnsureVaultLink()
            slot_publish_ready = the_master_track
                and reaper.ValidatePtr(the_master_track, "MediaTrack*")
                and the_vault_fx_index ~= nil

            if slot_publish_ready then
                for i = 1, control_count do
                    reaper.TrackFX_SetParam(the_master_track, the_vault_fx_index, PARAM_SLOT_START + i, 0)
                end
            end
        end

        StoreTargetIdentityCheck(track, safe_fxnum, ident)

        for i = 1, control_count do
            if template.pos[i] then
                local pnum = tonumber(template.pos[i].pnum)

                if pnum and pnum >= 0 and pnum < ident.param_count then
                    local val = round(reaper.TrackFX_GetParamNormalized(track, safe_fxnum, pnum), 5)

                    if slot_publish_ready then
                        -- SAFETY: Publish only after the Monitoring FX link is valid.
                        reaper.TrackFX_SetParam(the_master_track, the_vault_fx_index, PARAM_SLOT_START + i, (pnum + 1) * .001)
                    end

                    if template.pos[i].val ~= val then
                        template.pos[i].val = val
                        template.dirty[i] = true
                        update_fader = true
                        if upd_fb == true then
                            SetFaderBoxVal(i, val)
                        end
                    end
                else
                    -- The template refers to a parameter that no longer exists on
                    -- this confirmed FX.  Do not read or write through it.
                    if slot_publish_ready then
                        reaper.TrackFX_SetParam(the_master_track, the_vault_fx_index, PARAM_SLOT_START + i, 0)
                    end
                end
            else
                if upd_fb == true then
                    -- Empty assignment rows should publish as zero; this is safe
                    -- because it writes only to ValueVault, not to the target FX.
                    SetFaderBoxVal(i, 0)
                end
            end
        end

        if slot_publish_ready then
            SlotMapPublishRequested = false
        end
    else
        -- If master track is dead, refresh it.
        if not (the_master_track and reaper.ValidatePtr(the_master_track, "MediaTrack*")) then
            the_master_track = reaper.GetMasterTrack(0)
        end

        -- Only write if we successfully got the master track.
        if the_master_track and the_vault_fx_index then
            for i = 1, control_count + 10 do
                reaper.TrackFX_SetParam(the_master_track, the_vault_fx_index, (PARAM_SLOT_START - 10) + i, 0)
            end
        end
    end
end


function OpenFXGUI(track, fxnum)
    local fxopentimerset = false
    if reaper.TrackFX_GetOpen(track, fxnum) ~= true then
        reaper.TrackFX_Show(track, fxnum, 3)
        fxopentimerset = true
    end
    if lvar.fxopentimer or fxopentimerset == true then
        lvar.fxopentimer = reaper.time_precise() + settings.floatfxgui
        lvar.fxopeninfo = {
            track = track,
            fxnum = fxnum
        }
    end
end
function CloseFXGUI(track, fxnum)
    reaper.TrackFX_Show(track, fxnum, 2)
end


function SetRecMode(m)
    if ValueVault_CTL_TRACK and FFX then
        local ctltrack = GetTrack(ValueVault_CTL_TRACK)

        if m == 0 then
            local tgttrack, tgtfx, ident = ValidateTargetFXForParameterIO()

            if not (ctltrack and tgttrack and tgtfx ~= nil and ident) then
                recmode = 0
                ClearTargetIdentityChecks()
                return
            end

            local start_time, end_time = reaper.GetSet_LoopTimeRange2(0, false, false, 0, 0, false)

            if start_time ~= end_time then
                for i = 1, control_count do
                    if fader_touch[i] == true and template.pos[i] then
                        local pnum = tonumber(template.pos[i].pnum)
                        if pnum and pnum >= 0 and pnum < ident.param_count then
                            local srcenv = reaper.GetFXEnvelope(ctltrack, math.floor((i - 1) / NumberOfParameters), (i - 1) % NumberOfParameters, false)
                            local dstenv = reaper.GetFXEnvelope(tgttrack, tgtfx, pnum, true)
                            if srcenv and dstenv then
                                CopyEnv(srcenv, dstenv, start_time, end_time, true)
                            end
                            if srcenv then
                                local br_env = reaper.BR_EnvAlloc(srcenv, false)
                                local active, visible, armed, inLane, laneHeight, defaultShape, minValue, maxValue, centerValue, type, faderScaling = reaper.BR_EnvGetProperties(br_env, true, true, true, true, 0, 0, 0, 0, 0, 0, true)
                                reaper.BR_EnvSetProperties(br_env, active, false, true, inLane, laneHeight, defaultShape, faderScaling)
                                reaper.BR_EnvFree(br_env, false)
                            end
                        end
                    end
                end
            end
            for i = 0, control_count - 1 do
                ClearEnvelope(ValueVault_CTL_TRACK, i)
            end
            reaper.UpdateArrange()
            SetAutoMode(ValueVault_CTL_TRACK, 0)
            SetAutoMode(FFX.trn, ValueVault_FX_TRACK_AM)
            reaper.Undo_EndBlock("New Knobs Record Automation", 0)
        elseif m == 1 then
            local tgttrack, tgtfx = ValidateTargetFXForParameterIO()
            if not (ctltrack and tgttrack and tgtfx ~= nil) then
                recmode = 0
                return
            end

            reaper.Undo_BeginBlock()
            for i = 1, control_count do
                if template.pos[i] then
                    local srcenv = reaper.GetFXEnvelope(ctltrack, math.floor((i - 1) / NumberOfParameters), (i - 1) % NumberOfParameters, true)
                    if srcenv then
                        local br_env = reaper.BR_EnvAlloc(srcenv, false)
                        local active, visible, armed, inLane, laneHeight, defaultShape, minValue, maxValue, centerValue, type, faderScaling = reaper.BR_EnvGetProperties(br_env, true, true, true, true, 0, 0, 0, 0, 0, 0, true)
                        reaper.BR_EnvSetProperties(br_env, active, visible, true, inLane, laneHeight, defaultShape, faderScaling)
                        reaper.BR_EnvFree(br_env, true)
                    end
                end
            end
            reaper.UpdateArrange()
            SetAutoMode(ValueVault_CTL_TRACK, ValueVault_CTL_TRACK_AM)
            SetAutoMode(FFX.trn, 5)
            fader_touch = {}
        elseif m == -1 then
            recmode = 0
            for i = 0, control_count - 1 do
                ClearEnvelope(ValueVault_CTL_TRACK, i)
            end
            reaper.UpdateArrange()
            SetAutoMode(ValueVault_CTL_TRACK, 0)
            SetAutoMode(FFX.trn, ValueVault_FX_TRACK_AM)
            reaper.Undo_EndBlock("New Knobs Record Automation", 0)
        end
    end
end


function ArmEnv(env, arm)
    if srcenv then
        local br_env = reaper.BR_EnvAlloc(srcenv, false)
        local active, visible, armed, inLane, laneHeight, defaultShape, minValue, maxValue, centerValue, type, faderScaling = reaper.BR_EnvGetProperties(br_env, true, true, true, true, 0, 0, 0, 0, 0, 0, true)
        reaper.BR_EnvSetProperties(br_env, active, visible, arm, inLane, laneHeight, defaultShape, faderScaling)
        reaper.BR_EnvFree(br_env, 1)
    end
end

function CopyEnv(srcenv, dstenv, start_time, end_time, preserve_edges)
    env_points_count = reaper.CountEnvelopePoints(srcenv)
    if env_points_count > 0 then
        retval3, valueOut3, dVdSOutOptional3, ddVdSOutOptional3, dddVdSOutOptional3 = reaper.Envelope_Evaluate(srcenv, start_time, 0, 0)
        retval4, valueOut4, dVdSOutOptional4, ddVdSOutOptional4, dddVdSOutOptional4 = reaper.Envelope_Evaluate(srcenv, end_time, 0, 0)

        if preserve_edges == true then
            retval6, valueOut6, dVdSOutOptional6, ddVdSOutOptional6, dddVdSOutOptional6 = reaper.Envelope_Evaluate(dstenv, end_time, 0, 0)
            retval5, valueOut5, dVdSOutOptional5, ddVdSOutOptional5, dddVdSOutOptional5 = reaper.Envelope_Evaluate(dstenv, start_time, 0, 0)
        end
        reaper.DeleteEnvelopePointRange(dstenv, start_time, end_time)
        for k = 0, env_points_count + 1 do
            retval, time, valueOut, shape, tension, selectedOut = reaper.GetEnvelopePoint(srcenv, k)
            if time >= start_time and time <= end_time then
                reaper.InsertEnvelopePoint(dstenv, time, valueOut, shape, tension, 1, true)
            end
        end
        if preserve_edges == true then
            reaper.InsertEnvelopePoint(dstenv, start_time, valueOut5, 0, 0, true, true)
        end
        reaper.InsertEnvelopePoint(dstenv, start_time, valueOut3, 0, 0, true, true)
        reaper.InsertEnvelopePoint(dstenv, end_time, valueOut4, 0, 0, true, true)
        if preserve_edges == true then
            reaper.InsertEnvelopePoint(dstenv, end_time, valueOut6, 0, 0, true, true)
        end
        reaper.Envelope_SortPoints(dstenv)
    end
end

function RemoveEnv(env)
    retval, xml_env = reaper.GetEnvelopeStateChunk(env, "", false)
    xml_env = xml_env:gsub("\n", "¤¤")
    retval, xml_env = reaper.SetEnvelopeStateChunk(env, xml_env, false)
    return xml_env
end

function ClearEnvelope(trn, envn)
    local track = GetTrack(trn)
    if track then
        local env = reaper.GetFXEnvelope(track, math.floor(envn / NumberOfParameters), envn % NumberOfParameters, false)
        if env then
            RemoveEnv(env)
        end
    end
end


function run()
    -- Do not overwrite the established ValueVault link here.
    -- EnsureVaultLink() and processTrackFX() maintain these globals.
    local rt = reaper.time_precise()

    if gfx.w ~= last_gfx_w or gfx.h ~= last_gfx_h or force_resize or obj == nil then
        local r = false
        if not r or gfx.dock(-1) > 0 then
            gfx1.main_w = gfx.w
            gfx1.main_h = gfx.h
            win_w = gfx.w
            win_h = gfx.h

            last_gfx_w = gfx.w
            last_gfx_h = gfx.h

            gui = GetGUI_vars()
            obj = GetObjects()

            resize_display = true
            update_gfx = true
        end
    end

    if lrnmode == false then

        -- If the link is missing or invalid, try to find it.
        if not (ValueVault_CTL_TRACK and reaper.ValidatePtr(ValueVault_CTL_TRACK, "MediaTrack*")) then
            EnsureVaultLink()
        end

        local ctlchk = (ValueVault_CTL_TRACK ~= nil)
        local track = ValueVault_CTL_TRACK

        local checkfx, ret = GetFocusedFX()

        if checkfx then
            -- Any focused-FX identity change means old controller snapshots are
            -- suspect for a short moment.  The new target must be confirmed by
            -- ReadParamVals() before controller values are allowed to apply.
            if IsDifferentFocusedTarget(checkfx, lastFocusedFX) then
                local same_plugin_identity = lastFocusedFX
                    and checkfx.trguid == lastFocusedFX.trguid
                    and checkfx.fxguid == lastFocusedFX.fxguid

                QuarantineFXChain()
                ClearTargetIdentityChecks()

                lastFocusedFX = checkfx
                FFX = checkfx

                if same_plugin_identity then
                    SlotMapPublishRequested = true
                else
                    LoadFXParamTemplate(FFX)
                end

                update_gfx = true
                update_fader = true
            else
                -- The focused FX is still the same exact identity.
                FFX = lastFocusedFX
            end
        else
            -- No new FX is actively focused right now (e.g. user clicked arrange view).
            -- Continue controlling last focused FX only if the track and exact FX
            -- identity still exist.  If the chain changed, ValidateTargetFXForParameterIO()
            -- will quarantine and either update the index by GUID or clear the target.
            if lastFocusedFX then
                FFX = lastFocusedFX
                local safe_track, safe_fxnum, safe_ident = ValidateTargetFXForParameterIO()

                if safe_track and safe_fxnum ~= nil and safe_ident then
                    FFX = lastFocusedFX
                else
                    update_gfx = true
                end
            else
                if FFX ~= nil then
                    ClearCurrentFXTarget()
                end
            end
        end

        local rv = GetFaderBoxVals()
        if recmode == 0 then
            ReadParamVals(true)
        end
    end

    GUI_draw(obj, gui)

    mouse.mx, mouse.my = gfx.mouse_x, gfx.mouse_y
    mouse.LB = gfx.mouse_cap & 1 == 1
    mouse.RB = gfx.mouse_cap & 2 == 2
    mouse.ctrl = gfx.mouse_cap & 4 == 4
    mouse.shift = gfx.mouse_cap & 8 == 8
    mouse.alt = gfx.mouse_cap & 16 == 16

    if ValueVault_CTL_TRACK then
        if lrnmode == false then
            if lvar.fxopentimer and lvar.fxopentimer < reaper.time_precise() then
                if lvar.fxopeninfo and lvar.fxopeninfo.track and reaper.ValidatePtr(lvar.fxopeninfo.track, "MediaTrack*") then
                    CloseFXGUI(lvar.fxopeninfo.track, lvar.fxopeninfo.fxnum)
                end
                lvar.fxopentimer = nil
                lvar.fxopeninfo = nil
            end

            if mouse.context == nil and gfx.mouse_wheel ~= 0 then
                local z = gfx.mouse_wheel / lvar.mousewheel_mult
                if MOUSE_over(obj.sections[2]) or MOUSE_over(obj.sections[1]) then
                    control_offs = F_limit(control_offs - z, 0, control_count - 1)
                    update_gfx = true
                end
                gfx.mouse_wheel = 0
            elseif mouse.context == nil and MOUSE_click(obj.sections[2]) then
                local i = math.floor((mouse.my - obj.sections[2].y) / (fader_h + fader_space)) + 1 + control_offs
                if i <= control_count and recmode == 0 then
                    local p, pn = ParamMenu()
                    if p then
                        if p == -2 then
                            local answer = reaper.MB(
                                "Are you sure you want to clear the current assignments?",
                                "Clear All Assignments",
                                4
                            )
                            if answer == 6 then
                                ClearAllCurrentAssignments()
                            end
                        elseif p == -1 then
                            ClearTemplateSlot(i)
                        else
                            SetTemplateParam(i, p, pn)

                            local safe_track, safe_fxnum, safe_ident = ValidateTargetFXForParameterIO()
                            if safe_track and safe_fxnum ~= nil and safe_ident and p >= 0 and p < safe_ident.param_count then
                                local val = reaper.TrackFX_GetParamNormalized(safe_track, safe_fxnum, p)
                                template.pos[i].val = val
                                SetFaderBoxVal(i, val)
                                template.dirty[i] = true
                            end
                        end
                        update_fader = true
                    end
                end
            elseif mouse.context == nil and MOUSE_click(obj.sections[1]) then
                local i = math.floor((mouse.my - obj.sections[1].y) / (fader_h + fader_space)) + 1 + control_offs
                if template.pos[i] then
                    local safe_track, safe_fxnum = ValidateTargetFXForParameterIO()
                    if safe_track and safe_fxnum ~= nil then
                        mouse.context = contexts.sliderctl
                        mouse.slideoff = math.floor(obj.sections[1].x + fader_w / 2 - mouse.mx)
                        ctlpos = tonumber(template.pos[i].val) or 0
                        slider_select = i
                        oms = mouse.shift
                    end
                end
            elseif mouse.context == nil and MOUSE_click(obj.sections[4]) then
                local i = math.floor((mouse.my - obj.sections[1].y) / (fader_h + fader_space)) + 1 + control_offs
                if recmode == 1 then
                    if fader_touch[i] then
                        fader_touch[i] = nil
                        local ctltrack = GetTrack(ValueVault_CTL_TRACK)
                        local env = reaper.GetFXEnvelope(ctltrack, 0, i - 1, true)
                        ArmEnv(env, false)
                    else
                        fader_touch[i] = true
                        local ctltrack = GetTrack(ValueVault_CTL_TRACK)
                        local env = reaper.GetFXEnvelope(ctltrack, 0, i - 1, true)
                        ArmEnv(env, false)
                    end
                    update_gfx = true
                else
                    BeginIndexDrag(i)
                end
            elseif mouse.context == nil and MOUSE_click(obj.sections[5]) then
                if recmode == 0 then
                    SaveFXParamTemplate(FFX, template)
                    GUI_FlashButton(obj, gui, 5, "SAVE", 0.1, "205 205 205")
                else
                    recmode = 0
                    SetRecMode(recmode)
                    update_gfx = true
                end
            elseif mouse.context == nil and MOUSE_click(obj.sections[6]) then
                if FFX and recmode == 0 then
                    local safe_track, safe_fxnum = ValidateTargetFXForParameterIO()
                    if safe_track and safe_fxnum ~= nil then
                        recmode = 1
                        SetRecMode(recmode)
                        update_gfx = true
                    end
                elseif FFX and recmode == 1 then
                    recmode = -1
                    SetRecMode(recmode)
                    update_gfx = true
                end
            elseif mouse.context == nil and MOUSE_click_RB(obj.sections[6]) then
                local ret = Menu_AutoMode(ValueVault_CTL_TRACK)
                if ret >= 0 then
                    ValueVault_CTL_TRACK_AM = ret
                end
            elseif mouse.context == nil and MOUSE_click(obj.sections[3]) then
                if FFX then
                    local safe_track = ValidateTargetFXForParameterIO()
                    if safe_track then
                        if ValueVault_FX_TRACK_AM == 0 then
                            ValueVault_FX_TRACK_AM = 5
                        else
                            ValueVault_FX_TRACK_AM = 0
                        end
                        SetAutoMode(FFX.trn, ValueVault_FX_TRACK_AM)
                        update_gfx = true
                    end
                end
            elseif mouse.context == nil and MOUSE_click(obj.sections[8]) then
                ToggleLearnMode()
            elseif mouse.context == nil and MOUSE_click(obj.sections[9]) then
                SettingsMenu()
            end

            if mouse.context and mouse.context == contexts.sliderctl then
                local i = slider_select
                local xywh = {
                    x = obj.sections[1].x + 4,
                    y = math.floor(obj.sections[1].y + (i - 1) * (fader_h + fader_space)),
                    w = obj.sections[1].w - 8,
                    h = fader_h
                }
                local val = MOUSE_slider_horiz2(xywh, mouse.slideoff)
                if val ~= nil then
                    if val < 0 then val = 0 end
                    if val > 1 then val = 1 end
                    if val ~= octlval then
                        local safe_track, safe_fxnum, safe_ident = ValidateTargetFXForParameterIO()
                        if safe_track and safe_fxnum ~= nil and safe_ident and template.pos[i] then
                            local pnum = tonumber(template.pos[i].pnum)
                            if pnum and pnum >= 0 and pnum < safe_ident.param_count then
                                reaper.TrackFX_SetParamNormalized(safe_track, safe_fxnum, pnum, val)
                                template.pos[i].val = val
                                SetFaderBoxVal(i, val)
                                template.dirty[i] = true
                                octlval = val
                                update_fader = true
                            else
                                mouse.context = nil
                            end
                        else
                            mouse.context = nil
                        end
                    end
                end
            elseif mouse.context and mouse.context == contexts.indexdrag then
                UpdateIndexDrag(obj)
            end
        else
            if mouse.context == nil and learn_duplicate_slot and MOUSE_click(obj.sections[10]) then
                ClearPendingLearnDuplicate()
            elseif mouse.context == nil and MOUSE_click(obj.sections[8]) then
                ToggleLearnMode()
            elseif mouse.context == nil and MOUSE_click(obj.sections[4]) then
                -- While LEARN is active, clicking an index chooses the next
                -- assignment destination.  Learning remains sequential after
                -- that selected row, and skipped rows are left untouched.
                local i = math.floor((mouse.my - obj.sections[4].y) / (fader_h + fader_space)) + 1 + control_offs
                SetLearnTargetSlot(i)
            end

            CaptureLearnedParameterIfMoved()
        end

        for i = 1, 6 do
            if mouse.context == nil and MOUSE_click(obj.sections.nav_buttons[i]) then
                control_offs = (i - 1) * math.floor(768 / (fader_h + fader_space))
                update_gfx = true
            end
        end
    end

    if not mouse.LB and not mouse.RB then
        mouse.context = nil
    end
    local char = gfx.getchar()
    if char then
        if char == 32 then
            reaper.Main_OnCommandEx(40044, 0, 0)
        end
        if char >= 0 and char ~= 27 then
            reaper.defer(run)
        end
    else
        reaper.defer(run)
    end
    gfx.update()
    mouse.last_LB = mouse.LB
    mouse.last_RB = mouse.RB
    mouse.last_x = mouse.mx
    mouse.last_y = mouse.my
    if mouse.LB then
        mouse.lastLBclicktime = rt
    end
    gfx.mouse_wheel = 0

    if refresh_gfx and mouse.context == nil and reaper.time_precise() >= refresh_gfx then
        refresh_gfx = nil
        update_gfx = true
    end

    for i = 1, control_count do
        if template.sft[i] and template.sft[i] <= reaper.time_precise() and template.eft[i] > reaper.time_precise() then
            update_fader = true
            break
        end
    end
end


function quit()
    SaveSettings()
    gfx.quit()
end

function GES(key, nilallowed)
    if nilallowed == nil then nilallowed = false end
    local val = reaper.GetExtState(SCRIPT, key)
    if nilallowed then
        if val == "" then val = nil end
    end
    return val
end

function SettingsMenu()
    local tick = ""
    if settings.floatfxgui ~= 0 then tick = "!" end
    local mnd = ""
    if settings.usemod == 1 then mnd = "!" end
    if settings.autohideFaderBoxTracks ~= 0 then AFT = "!" end

    local mstr = tick .. "Float FX GUI||Float time (" .. settings.floatfxgui .. " secs)||" .. mnd .. "Use Module Name Detection||" .. AFT .. "Autohide Faderbox Tracks"
    gfx.x = mouse.mx
    gfx.y = mouse.my
    local res = gfx.showmenu(mstr)
    if res > 0 then
        if res == 1 then
            if settings.floatfxgui == 0 then
                settings.floatfxgui = lvar.deffloattime
            else
                settings.floatfxgui = 0
            end
        elseif res == 2 then
            local ret, tm = reaper.GetUserInputs("Set float time (secs)", 1, "Time (secs):", tostring(settings.floatfxgui))
            if ret == true then
                settings.floatfxgui = tonumber(tm)
                lvar.deffloattime = settings.floatfxgui
            end
        elseif res == 3 then
            settings.usemod = 1 - settings.usemod
        elseif res == 4 then
            if settings.autohideFaderBoxTracks == 1 then
                settings.autohideFaderBoxTracks = 0
                showFaderBoxTracks = true
                AFT = ""
            else
                settings.autohideFaderBoxTracks = 1
                showFaderBoxTracks = false
                AFT = "!"
            end
        end
    end
end

function SaveSettings()
    a, x, y, w, h = gfx.dock(-1, 1, 1, 1, 1)
    if gfx1 then
        reaper.SetExtState(SCRIPT, "dock", nz(a, 0), true)
        reaper.SetExtState(SCRIPT, "win_x", nz(x, 0), true)
        reaper.SetExtState(SCRIPT, "win_y", nz(y, 0), true)
        reaper.SetExtState(SCRIPT, "win_w", nz(gfx1.main_w, 400), true)
        reaper.SetExtState(SCRIPT, "win_h", nz(gfx1.main_h, 450), true)
        reaper.SetExtState(SCRIPT, "usemod", nz(settings.usemod, 1), true)
    end
end

function LoadSettings()
    local x, y = GES("win_x", true), GES("win_y", true)
    local ww, wh = GES("win_w", true), GES("win_h", true)
    local d = GES("dock", true)
    settings.usemod = tonumber(GES("usemod", true)) or 1

    if x == nil then x = 0 end
    if y == nil then y = 0 end
    if d == nil then d = gfx.dock(-1) end
    if ww ~= nil and wh ~= nil then
        gfx1 = {
            main_w = tonumber(ww),
            main_h = tonumber(wh)
        }
        gfx.init(SCRIPT_NAME, gfx1.main_w, gfx1.main_h, 0, x, y)
        gfx.dock(d)
    else
        gfx1 = {main_w = 400, main_h = 450}
        Lokasenna_Window_At_Center(gfx1.main_w, gfx1.main_h)
    end
end

------------------------------------------------------------
-- STARTUP SAFETY & AUTO-INSTALL CHECK
------------------------------------------------------------
function EnsureValueVault()
    -- CONFIG: LINKS
    local DOWNLOAD_URL_PC  = "https://rockkennedy.com/ValueVault_PC.zip"
    local DOWNLOAD_URL_MAC = "https://rockkennedy.com/ValueVault_MAC.zip"

    local master = reaper.GetMasterTrack(0)
    if not master then return false end

    -- 1. Try to Find or Add "ValueVault" in Monitoring Chain
    local fx_index = reaper.TrackFX_AddByName(master, "ValueVault", true, 1)

    -- 2. If index is -1, the VST is not installed on the computer
    if fx_index == -1 then
        local os = reaper.GetOS()
        local url = DOWNLOAD_URL_PC
        if os:match("OSX") or os:match("macOS") then
            url = DOWNLOAD_URL_MAC
        end

        reaper.MB("The 'ValueVault' VST could not be loaded.\n\n" ..
                  "The script tried to auto-load it into the Monitoring FX chain,\n" ..
                  "but the plugin does not seem to be installed on your system.\n\n" ..
                  "Click OK to get the download link.", "Critical Error", 0)

        reaper.GetUserInputs("Download ValueVault", 1, "Copy Link (Ctrl+C):,extrawidth=400", url)
        
        return false -- Stop the script
    end

    -- 3. Ensure it's enabled
    reaper.TrackFX_SetEnabled(master, 0x1000000 + fx_index, true)
    return true
end

------------------------------------------------------------

SCRIPT = SCRIPT_NAME
ValueVault_CTL_TRACK_AM = 4
ValueVault_FX_TRACK_AM = 0
ValueVault_FX_TRACK_DEFAM = 0

flashctl = {}
fader_touch = {}

settings.hidectltrack = true
settings.floatfxgui = 0
settings.usemod = 1
settings.autohideFaderBoxTracks = 1

-- Try to link immediately at startup
EnsureVaultLink()
local track = ValueVault_CTL_TRACK 

ctltrchecktime = reaper.time_precise()

recmode = 0
lrnmode = false
learn_target_slot = nil
learn_duplicate_slot = nil
learn_last_captured_param = nil
learn_last_observed_touch_param = nil

control_offs = 0

fadedel_s = 0.2
fadedel_e = fadedel_s + 0.4

FFX = nil
template = {
    dirty = {},
    pos = {},
    sft = {},
    eft = {}
}

colours = {
    faderborder = "25 25 25",
    fader = "99 99 99",
    fader_inactive = "0 80 255",
    faderbg = "35 35 35",
    faderbg2 = "0 0 0",
    mainbg = "35 35 35",
    buttcol = "25 25 25",
    faderlit = "87 109 130",
    pnamelit = "107 129 150"
}

update_gfx = true
resize_display = true

if EnsureValueVault() then
    LoadSettings()
    mouse = {}
    run()
    reaper.atexit(quit)
end
