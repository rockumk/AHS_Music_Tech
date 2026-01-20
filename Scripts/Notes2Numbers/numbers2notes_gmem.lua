-- @description numbers2notes_gmem
-- @version 1.1
-- @author Rock Kennedy
-- @about
--   # numbers2notes_gmem
--   Numbers2Notes Support File.
-- @changelog
--   + First version







local export = {}

local note_map = {
    ["C"]=0, ["C#"]=1, ["Db"]=1, ["D"]=2, ["D#"]=3, ["Eb"]=3,
    ["E"]=4, ["F"]=5, ["F#"]=6, ["Gb"]=6, ["G"]=7, ["G#"]=8, ["Ab"]=8,
    ["A"]=9, ["A#"]=10, ["Bb"]=10, ["B"]=11, ["Cb"]=11
}

local function normalize_key(k)
    if not k then return "C" end
    return k:gsub("%s+", "")
end

-- =========================================================
-- 1. ANALYZE (Unchanged)
-- =========================================================
function export.Analyze(take, current_key_string)
    local r = reaper
    if not take or not r.ValidatePtr(take, "MediaItem_Take*") then return 0, 0 end

    local clean_key = normalize_key(current_key_string)
    local rel_tonic = note_map[clean_key] or 0
    
    local scores = {}
    for i = 0, 11 do scores[i] = 0 end

    local _, notecnt, _, _ = r.MIDI_CountEvts(take)
    if notecnt == 0 then return rel_tonic, rel_tonic end

    local start_qn = r.MIDI_GetProjQNFromPPQPos(take, 0)
    local ppq_per_qn = r.MIDI_GetPPQPosFromProjQN(take, start_qn + 1) - r.MIDI_GetPPQPosFromProjQN(take, start_qn)
    local ticks_per_bar = ppq_per_qn * 4
    
    for i = 0, notecnt - 1 do
        local _, _, _, startppq, endppq, _, pitch, _ = r.MIDI_GetNote(take, i)
        local duration = endppq - startppq
        local bar_num_abs = math.floor(startppq / ticks_per_bar)
        local bar_in_phrase = bar_num_abs % 4
        
        local weight = 1
        if bar_in_phrase == 0 then weight = 2 end 
        if bar_in_phrase == 3 then weight = 4 end 
        
        local pc = pitch % 12
        scores[pc] = scores[pc] + (duration * weight)
    end

    local modal_center = rel_tonic
    local max_score = -1
    for i = 0, 11 do
        if scores[i] > max_score then max_score = scores[i]; modal_center = i; end
    end
    
    return rel_tonic, modal_center
end

-- =========================================================
-- 2. SEND CHORDS (Offset -0.0625 / 1/64th Note)
-- =========================================================
function export.SendToGMEM(take, rel_tonic, modal_center)
    local r = reaper
    if not take or not r.ValidatePtr(take, "MediaItem_Take*") then return end

    r.gmem_attach('ProjectSwing')
    local OFFSET = 3000000
    
    local _, notecnt, _, _ = r.MIDI_CountEvts(take)
    
    r.gmem_write(OFFSET + 1, notecnt)
    r.gmem_write(OFFSET + 2, rel_tonic)
    r.gmem_write(OFFSET + 3, modal_center)
    
    local idx = OFFSET + 10
    
    -- TIMING OFFSET: 1/64th Note
    local CHORD_LOOKAHEAD = 0.0625 
    
    for i = 0, notecnt - 1 do
        local _, _, _, startppq, endppq, _, pitch, vel = r.MIDI_GetNote(take, i)
        
        local start_qn = r.MIDI_GetProjQNFromPPQPos(take, startppq)
        local end_qn   = r.MIDI_GetProjQNFromPPQPos(take, endppq)
        
        -- Apply Offset
        local adj_start = start_qn - CHORD_LOOKAHEAD
        if adj_start < 0 then adj_start = 0 end
        
        -- Note: We generally don't shift the END time, or notes might overlap.
        -- Keeping end_qn 'true' allows the Arp to sustain until the actual end.
        
        r.gmem_write(idx,     pitch)
        r.gmem_write(idx + 1, adj_start)
        r.gmem_write(idx + 2, end_qn)
        r.gmem_write(idx + 3, vel) 
        idx = idx + 4 
    end
    
    r.gmem_write(OFFSET, 1) 
end

-- =========================================================
-- 3. SEND SCALE MAP (Offset -0.09375 / Dotted 1/64th)
-- =========================================================
function export.SendScaleToGMEM(take, rel_tonic)
    local r = reaper
    if not take or not r.ValidatePtr(take, "MediaItem_Take*") then return end

    r.gmem_attach('ProjectSwing')
    local OFFSET = 3100000 
    
    local _, notecnt, _, _ = r.MIDI_CountEvts(take)
    local scale_entries = 0
    local header_idx = OFFSET + 1
    local write_idx = OFFSET + 2
    local PARENT_MASK = 2741 
    local last_mask = -1 
    
    -- TIMING OFFSET: Dotted 1/64th Note (1.5 * 0.0625)
    local SCALE_LOOKAHEAD = 0.09375
    
    local i = 0
    while i < notecnt do
        local _, _, _, startppq, endppq, _, pitch, vel = r.MIDI_GetNote(take, i)
        
        if vel == 89 then -- ROOTS ONLY
            
            -- 1. Init
            local key_slots = {}
            for k = 0, 11 do
                local key_interval = (k - rel_tonic + 12) % 12
                if (PARENT_MASK & (1 << key_interval)) ~= 0 then
                    key_slots[k] = true
                else
                    key_slots[k] = false
                end
            end
            
            -- 2. Inject
            local j = i
            while j < notecnt do
                local _, _, _, s2, _, _, p2, v2 = r.MIDI_GetNote(take, j)
                if math.abs(s2 - startppq) > 10 then break end 
                key_slots[p2 % 12] = true 
                j = j + 1
            end
            
            -- 3. Cleanup
            for k = 0, 11 do
                if key_slots[k] == true then
                    local interval = (k - rel_tonic + 12) % 12
                    if interval == 1 then key_slots[(rel_tonic + 2) % 12] = false end
                    if interval == 3 then key_slots[(rel_tonic + 4) % 12] = false end
                    if interval == 6 then key_slots[(rel_tonic + 7) % 12] = false end
                    if interval == 8 then key_slots[(rel_tonic + 9) % 12] = false end
                    if interval == 10 then key_slots[(rel_tonic + 11) % 12] = false end
                end
            end
            
            -- 4. Build
            local final_mask = 0
            for k = 0, 11 do
                if key_slots[k] == true then
                    local interval = (k - rel_tonic + 12) % 12
                    final_mask = final_mask | (1 << interval)
                end
            end
            
            -- 5. WRITE WITH TIMING OFFSET
            if final_mask ~= last_mask then
                
                local start_qn = r.MIDI_GetProjQNFromPPQPos(take, startppq)
                local adjusted_start = start_qn - SCALE_LOOKAHEAD
                if adjusted_start < 0 then adjusted_start = 0 end
                
                r.gmem_write(write_idx, adjusted_start)
                r.gmem_write(write_idx + 1, final_mask)
                
                write_idx = write_idx + 2
                scale_entries = scale_entries + 1
                
                last_mask = final_mask
            end
        end
        i = i + 1
    end
    
    r.gmem_write(header_idx, scale_entries)
    r.gmem_write(OFFSET, 1) 
end

return export
