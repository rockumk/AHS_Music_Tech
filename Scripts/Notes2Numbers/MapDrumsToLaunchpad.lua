-- @description MapDrumsToNovation_Unified
-- @version 2.2

local PAD_MAP = {
    [1] = { 0,  8, 16 }, [2] = {1, 9, 17 }, [3] = {2, 10, 18}, [4] = { 3, 11, 19 },
    [5] = { 4, 12, 20}, [6] = { 5, 13, 21},[7] = { 6, 14, 22}, [8] = { 7, 15, 23},
    [9] = { 24, 32, 40},[10] = { 25, 33, 41}, [11] = { 26, 34, 42}, [12] = { 27, 35, 43},
    [13] = { 28, 36, 44}, [14] = { 29, 37, 45},[15] = { 30, 38, 46}, [16] = { 31, 39, 47},
}

local LP_PALETTE = {
    red=72,["deep orange"]=60, orange=10, amber=126, yellow=124, lime=17, green=25, mint=77, 
    cyan=37, sky=38, blue=42, indigo=92, purple=93, violet=81, magenta=53, rose=58, gray=2, 
    grey=2, white=3, off=0
}

local function trim(s)
    return (s or ""):match("^%s*(.-)%s*$")
end

local function clean_file_text(content)
    if not content then return "" end
    if content:sub(1,3) == "\239\187\191" then content = content:sub(4) end
    content = content:gsub("\r\n", "\n")
    content = content:gsub("\r", "\n")
    content = content:gsub("\t", " ")
    content = content:gsub("\194\160", " ")
    content = content:gsub("%z", "")
    return content
end

-- device_type expects "M" (Mini), "X" (X), "P" (Pro), or "K" (Launchkey MK4)
function GenerateSysexFromFile(filename, custom_slot, device_type)
    custom_slot = custom_slot or 1
    device_type = string.upper(device_type or "X") -- Defaults to X if nothing is passed

    local file = io.open(filename, "rb")
    if not file then return nil end
    local content = file:read("*a")
    file:close()

    content = clean_file_text(content)

    -- 1. PARSE TEXT FILE AND MAP PADS
    local col, row, last_color = 0, 0, nil
    
    local pads = {} -- Array for 64-pad grids
    for i = 0, 63 do pads[i] = { mapped = false } end
    
    local lk_pads = {} -- Array for 16-pad grids (Launchkey)
    for i = 0, 15 do lk_pads[i] = { mapped = false } end
    local seen_colors = {}
    local lk_pad_idx = 0

    for line in content:gmatch("[^\n]+") do
        local raw = trim(line)
        if raw ~= "" and not raw:match("^//") then
            raw = raw:gsub("[%c]", "")
            local note_str, color_str = raw:match("^(%d+)%s+.-%s*//%s*(.-)%s*$")

            if note_str and color_str then
                local note_num = tonumber(note_str)
                local color_key = trim(color_str):lower()
                local color_val = LP_PALETTE[color_key]

                if color_val then
                    -- === Logic for 64-pad Grid ===
                    if color_key ~= last_color then
                        col = col + 1
                        row = 0
                        last_color = color_key
                    end
                    row = row + 1
                    local idx = PAD_MAP[col] and PAD_MAP[col][row] or nil
                    if idx then
                        pads[idx] = { mapped = true, color = color_val, note = note_num }
                    end

                    -- === Logic for 16-pad Grid (First of each color) ===
                    if not seen_colors[color_key] and lk_pad_idx < 16 then
                        seen_colors[color_key] = true
                        lk_pads[lk_pad_idx] = { mapped = true, color = color_val, note = note_num }
                        lk_pad_idx = lk_pad_idx + 1
                    end
                end
            end
        end
    end

    -- 2. BUILD SYSEX BASED ON TARGET DEVICE
    local bytes = {}
    local base_name = filename:match("([^/\\]+)%.[^%.]+$") or filename:match("([^/\\]+)$") or ""

    if device_type == "K" then
        -- ==========================================
        -- LAUNCHKEY MK4 LOGIC (16 Pads)
        -- ==========================================
        bytes = { 
            0xF0, 0x00, 0x20, 0x29, 0x02, 0x14, 0x05, 0x00, 0x45, 0x01, 
            0x7F, 0x00, 0x1A, 0x01, 0x1A, 0x03 + custom_slot, 0x42, 0x07, 0x33, 0x20, 0x10, 0x2A 
        }

        -- Exact 15-character name padding (Space terminated)
        local short_name = base_name:sub(1, 15)
        for i = 1, 15 do
            bytes[#bytes+1] = (i <= #short_name) and string.byte(short_name, i) or 32
        end

        -- 16 Pad Blocks
        for i = 0, 15 do
            if lk_pads[i].mapped then
                local p = lk_pads[i]
                local block = { 0x48, i, 0x01, p.color, 0x00, 0x10, 0x00, 0x00, 0x00, p.note }
                for b = 1, #block do bytes[#bytes+1] = block[b] end
            else
                -- Unassigned pad fallback to MK3 standard unassigned block
                bytes[#bytes+1] = 0x40
                bytes[#bytes+1] = i
            end
        end

        -- Launchkey Footer block (Potentially Encoder/Fader unassigned blocks)
        for i = 0, 15 do
            bytes[#bytes+1] = 0x60
            bytes[#bytes+1] = i
        end

    elseif device_type == "P" then
        -- ==========================================
        -- LAUNCHPAD PRO [MK3] LOGIC
        -- ==========================================
        bytes = { 0xF0, 0x00, 0x20, 0x29, 0x02, 0x0E, 0x05, custom_slot, 0x7F, 0x2A }

        -- 16-character name padding (Null terminated)
        local short_name = base_name:sub(1, 16)
        for i = 1, 16 do
            bytes[#bytes+1] = (i <= #short_name) and string.byte(short_name, i) or 0x00
        end

        -- Header Config
        local header_pad = { 0x00, 0x7F, 0x00, 0x00, 0x05 }
        for b = 1, #header_pad do bytes[#bytes+1] = header_pad[b] end

        -- Pad Blocks (8-bytes per pad, mapping row by row)
        for r = 7, 0, -1 do
            for c = 0, 7 do
                local i = r * 8 + c
                local pad_id = (r + 1) * 10 + (c + 1)
                
                if pads[i].mapped then
                    local p = pads[i]
                    local block = { pad_id, 0x00, 0x01, p.note, 0x00, 0x00, 0x00, p.color }
                    for b = 1, #block do bytes[#bytes+1] = block[b] end
                else
                    local block = { pad_id, 0x7F, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 }
                    for b = 1, #block do bytes[#bytes+1] = block[b] end
                end
            end
        end

    else
        -- ==========================================
        -- LAUNCHPAD MINI MK3 & X LOGIC
        -- ==========================================
        local dev_id = (device_type == "M") and 0x0D or 0x0C
        bytes = { 0xF0, 0x00, 0x20, 0x29, 0x02, dev_id, 0x20, 0x00, 0x45, 0x40, 0x03 + custom_slot, 0x20, 0x10, 0x2A }

        -- 14-character name padding (Space terminated)
        local short_name = base_name:sub(-14)
        for i = 1, 14 do
            bytes[#bytes+1] = (i <= #short_name) and string.byte(short_name, i) or 32
        end
        bytes[#bytes+1] = 32
        bytes[#bytes+1] = 32
        bytes[#bytes+1] = 0x01
        bytes[#bytes+1] = 0x00

        -- Pad Blocks (10-bytes per assigned pad, 2 per unassigned)
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

        -- Footer (Only used by X and Mini)
        local footer = {
            0x40,0x40,0x40,0x41,0x40,0x42,0x40,0x43,0x40,0x44,0x40,0x45,0x40,0x46,0x40,0x47,
            0x00,0x15,0x01,0x15,0x02,0x00,0x06,0x00,0x07,0x00,0x08,0x00,0x05,0x00,0x04,0x40
        }
        for b = 1, #footer do bytes[#bytes+1] = footer[b] end
    end

    -- Universal Termination Byte
    bytes[#bytes+1] = 0xF7

    -- 3. CONVERT TO STRING AND RETURN
    local chars = {}
    for i = 1, #bytes do chars[i] = string.char(bytes[i]) end
    return table.concat(chars)
end

return {
    GenerateSysexFromFile = GenerateSysexFromFile
}
