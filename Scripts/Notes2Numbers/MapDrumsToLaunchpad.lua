-- @description MapDrumsToLaunchpad
-- @version 1.3


local PAD_MAP = {
    [1] = { 0,  8, 16 }, [2] = {1, 9, 17 }, [3] = {2, 10, 18}, [4] = { 3, 11, 19 },
    [5] = { 4, 12, 20}, [6] = { 5, 13, 21}, [7] = { 6, 14, 22}, [8] = { 7, 15, 23},
    [9] = { 24, 32, 40}, [10] = { 25, 33, 41}, [11] = { 26, 34, 42}, [12] = { 27, 35, 43},
    [13] = { 28, 36, 44}, [14] = { 29, 37, 45}, [15] = { 30, 38, 46}, [16] = { 31, 39, 47},
}

local LP_PALETTE = {
    red=72, ["deep orange"]=60, orange=10, amber=126, yellow=124, lime=17, green=25, mint=77, 
	cyan=37, sky=38, blue=42, indigo=92, purple=93, violet=81, magenta=53, rose=58, gray=2, 
	grey=2, white=3, off=0
}

local LP_TPALETTE = {
    red=5, ["deep orange"]=84, orange=108, amber=126, yellow=124, lime=17, green=25, mint=77, 
	cyan=37, sky=37, blue=42, indigo=92, purple=93, violet=81, magenta=53, rose=58, gray=2, 
	grey=2, white=3, off=0
}




local function trim(s)
    return (s or ""):match("^%s*(.-)%s*$")
end

local function clean_file_text(content)
    if not content then return "" end

    if content:sub(1,3) == "\239\187\191" then
        content = content:sub(4)
    end

    content = content:gsub("\r\n", "\n")
    content = content:gsub("\r", "\n")
    content = content:gsub("\t", " ")
    content = content:gsub("\194\160", " ")
    content = content:gsub("%z", "")

    return content
end

local function bytes_to_hex_string(bytes)
    local hex = {}
    for i = 1, #bytes do
        hex[i] = string.format("%02X", bytes[i])
    end
    return table.concat(hex, " ")
end

local function string_to_hex_string(s)
    local bytes = { string.byte(s, 1, #s) }
    return bytes_to_hex_string(bytes)
end

function GenerateSysexFromFile(filename, custom_slot)
    custom_slot = custom_slot or 1

    local file = io.open(filename, "rb")
    if not file then
        reaper.ShowConsoleMsg("Error: Could not open file " .. tostring(filename) .. "\n")
        return nil
    end

    local content = file:read("*a")
    file:close()

    content = clean_file_text(content)

    local kit_name = filename:match("([^/\\]+)%.[^%.]+$") or filename:match("([^/\\]+)$") or "Custom Kit"

    --reaper.ClearConsole()
    --reaper.ShowConsoleMsg("==================================================\n")
    --reaper.ShowConsoleMsg("FILE ANALYSIS: " .. tostring(filename) .. "\n")
    --reaper.ShowConsoleMsg("KIT NAME: " .. kit_name .. "\n")
    --reaper.ShowConsoleMsg("==================================================\n\n")

    --reaper.ShowConsoleMsg("NORMALIZED LINES:\n")
    local line_num = 0
    for line in content:gmatch("[^\n]+") do
        line_num = line_num + 1
        local raw = trim(line)
        --reaper.ShowConsoleMsg(string.format("%02d | [%s]\n", line_num, raw))
    end
    --reaper.ShowConsoleMsg("\n")

    local col, row, last_color = 0, 0, nil
    local pads = {}
    for i = 0, 63 do pads[i] = { mapped = false } end

    --reaper.ShowConsoleMsg("PARSE / PLACEMENT TRACE:\n")

    line_num = 0
    for line in content:gmatch("[^\n]+") do
        line_num = line_num + 1
        local raw = trim(line)

        if raw ~= "" and not raw:match("^//") then
            raw = raw:gsub("[%c]", "")

            local note_str, color_str = raw:match("^(%d+)%s+.-%s*//%s*(.-)%s*$")

            if note_str and color_str then
                local note_num = tonumber(note_str)
                local color_key = trim(color_str):lower()
                local color_val = LP_PALETTE[color_key]

                if color_val then
                    local new_col = false
                    if color_key ~= last_color then
                        col = col + 1
                        row = 0
                        last_color = color_key
                        new_col = true
                    end

                    row = row + 1
                    local idx = PAD_MAP[col] and PAD_MAP[col][row] or nil



                    if idx then
                        pads[idx] = {
                            mapped = true,
                            color = color_val,
                            note = note_num
                        }
                    else
                        --reaper.ShowConsoleMsg("     >>> SKIPPED: no PAD_MAP entry for this COL/ROW\n")
                    end
                else

                end
            else

            end
        end
    end

    --reaper.ShowConsoleMsg("\nFINAL PAD ASSIGNMENTS:\n")


    local bytes = {
        0xF0, 0x00, 0x20, 0x29, 0x02, 0x0D, 0x20, 0x00, 0x45, 0x40,
        0x03 + custom_slot, 0x20, 0x10, 0x2A
    }





local base_name = filename:match("([^/\\]+)%.[^%.]+$") or filename:match("([^/\\]+)$") or ""
local short_name = base_name:sub(-14)

for i = 1, 14 do
    bytes[#bytes+1] = (i <= #short_name) and string.byte(short_name, i) or 32
end
bytes[#bytes+1] = 32
bytes[#bytes+1] = 32

bytes[#bytes+1] = 0x01
bytes[#bytes+1] = 0x00


















    for i = 0, 63 do
        if pads[i].mapped then
            local p = pads[i]
            local block = { 0x48, i, 0x01, p.color, 0x00, 0x10, 0x00, 0x00, 0x00, p.note }
            for b = 1, #block do bytes[#bytes+1] = block[b] end
        else
            bytes[#bytes+1] = 0x40
            bytes[#bytes+1] = i
        end
    end

local footer = {
    0x40,0x40,0x40,0x41,0x40,0x42,0x40,0x43,0x40,0x44,0x40,0x45,0x40,0x46,0x40,0x47,
    0x00,0x15,0x01,0x15,0x02,0x00,0x06,0x00,0x07,0x00,0x08,0x00,0x05,0x00,0x04,0x40,0xF7
}
    for b = 1, #footer do bytes[#bytes+1] = footer[b] end

    local chars = {}
    for i = 1, #bytes do chars[i] = string.char(bytes[i]) end
    local sysex = table.concat(chars)

    --reaper.ShowConsoleMsg("\nGENERATED HEX:\n")
    --reaper.ShowConsoleMsg(string_to_hex_string(sysex) .. "\n")

    return sysex
end

return {
    GenerateSysexFromFile = GenerateSysexFromFile
}
