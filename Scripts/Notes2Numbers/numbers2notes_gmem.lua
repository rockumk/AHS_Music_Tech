-- @description numbers2notes_gmem
-- @version 1.5
-- @author Rock Kennedy
-- @noindex
-- @about
--   # numbers2notes_gmem
--   Numbers2Notes Support File.
-- @changelog
--   + First version




-- RESERVE local REC_CUES_ON = 5000100;


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

    r.gmem_attach('N2N_Ecosystem_RSKennedy')
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

    r.gmem_attach('N2N_Ecosystem_RSKennedy')
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


-- 4. Shared song-form protocol. Actual quarter-note boundaries, no MIDI cue track.
-- 6000000: magic, revision (odd while writing), entry count; 6000011..6000522 instance keys.
-- 6001024: triples {start QN, end QN, drum pattern slot}. 4096 spans maximum.
local FORM_BASE, FORM_MAX = 6000000, 4096
local last_sig, last_project, last_poll = nil, nil, -math.huge
local function section_slot(name)
    local n = (name or ""):upper():match("^%s*(.-)%s*$")
    n = n:gsub("^%{(.*)%}$", "%1")
    if n == "#" or n == "COUNT IN" or n == "COUNT-IN" then return 77, false end
    if n == "D" or n == "DROP" then return 75, false end
    if n == "X" or n == "BREAKDOWN" then return 76, false end
    if n == "F" or n == "FADEOUT" then return 78, false end
    if n == "1" or n == "USER 1" then return 27, false end
    if n == "2" or n == "USER 2" then return 28, false end
    if n == "3" or n == "USER 3" then return 29, false end
    if n == "I" or n == "INTRO" then return 1, true end
    if n == "B" or n == "BRIDGE" or n == "M" or n == "MIDDLE 8" then return 17, true end
    if n == "S" or n == "SOLO" then return 44, true end
    if n == "O" or n == "OUTRO" then return 71, true end
    local prefixes = {
        {{"V","VERSE"},{5,32,59}},
        {{"P","PC","PRE","PRE-CHORUS","PRE CHORUS","R","RAMP"},{9,36,63}},
        {{"C","CHORUS"},{13,40,67}},
    }
    for _, family in ipairs(prefixes) do
        for _, p in ipairs(family[1]) do
            for i=1,3 do
                if n == p..i or n == p.." "..i or (i==1 and n==p) then
                    return family[2][i], true
                end
            end
        end
    end
    return 26, false
end
export.SectionSlot = section_slot

function export.PublishSongForm(stretched_index, force)
    local r = reaper
    local now = r.time_precise()
    if not force and now-last_poll < 0.5 then return end
    last_poll = now
    r.gmem_attach("N2N_Ecosystem_RSKennedy")
    local project = r.EnumProjects(-1, "")
    local regions, keys, spans = {}, {}, {}
    local _, markers, count = r.CountProjectMarkers(project)
    for i=0, markers+count-1 do
        local _, is_region, pos, finish, name = r.EnumProjectMarkers3(project,i)
        if is_region and finish>pos then
            regions[#regions+1] = {r.TimeMap2_timeToQN(project,pos),r.TimeMap2_timeToQN(project,finish),name or ""}
        end
    end
    table.sort(regions,function(a,b) if a[1]==b[1] then return a[2]<b[2] end return a[1]<b[1] end)
    local function add(a,b,t,merge)
        if b<=a+1e-8 then return end
        local prev=spans[#spans]
        if merge and prev and prev[3]==t and math.abs(prev[2]-a)<1e-7 then prev[2]=b
        else spans[#spans+1]={a,b,t} end
    end
    for i,region in ipairs(regions) do
        local a,b=region[1],region[2]
        if regions[i+1] then b=math.min(b,regions[i+1][1]) end
        local prior=spans[#spans]
        if prior and a>prior[2]+1e-8 then add(prior[2],a,26,false) end
        local slot,variants=section_slot(region[3])
        if b>a+1e-8 then
            if variants then
                local phrases=math.max(1,math.ceil((b-a-1e-8)/16))
                if phrases>FORM_MAX then return false,"Song form exceeds 4096 spans" end
                for p=0,phrases-1 do
                    local v=stretched_index(p,phrases)
                    add(a+p*16,math.min(b,a+(p+1)*16),slot+v,p>0)
                end
            else add(a,b,slot,false) end
        end
        if #spans>FORM_MAX then return false,"Song form exceeds 4096 spans" end
    end
    for i=0,r.CountTracks(project)-1 do
        local tr=r.GetTrack(project,i)
        for fx=0,r.TrackFX_GetCount(tr)-1 do
            local _,name=r.TrackFX_GetFXName(tr,fx,"")
            if name:lower():find("n2n drum arranger",1,true) then
                local id=math.floor(r.TrackFX_GetParam(tr,fx,4)+0.5)
                if id>=1 and id<=512 then
                    local key=r.gmem_read(8000000+id)
                    if key>0 then keys[id]=key end
                end
            end
        end
    end
    local sig={tostring(project)}
    for _,v in ipairs(spans) do sig[#sig+1]=string.format("%.12f:%.12f:%d",v[1],v[2],v[3]) end
    for i=1,512 do if keys[i] then sig[#sig+1]=i..":"..keys[i] end end
    sig=table.concat(sig,"|")
    if not force and sig==last_sig and project==last_project then return true end
    local rev=math.floor(r.gmem_read(FORM_BASE+1)/2)*2+2
    r.gmem_write(FORM_BASE+1,rev-1)
    r.gmem_write(FORM_BASE,0x4E324631)
    r.gmem_write(FORM_BASE+2,#spans)
    for i=1,512 do r.gmem_write(FORM_BASE+10+i,keys[i] or 0) end
    for i,v in ipairs(spans) do
        local p=FORM_BASE+1024+(i-1)*3
        for j=1,3 do r.gmem_write(p+j-1,v[j]) end
    end
    r.gmem_write(FORM_BASE+1,rev)
    last_sig,last_project=sig,project
    return true
end

-- 5. Pattern library mailbox, serviced only while the Numbers2Notes GUI is running.
-- Sparse note/channel/step/velocity/grid/duration tuples; never execute loaded text.
local LIB=6200000
local function valid_number(n,a,b)
    return type(n)=="number" and n==n and n>=a and n<=b
end
local function pattern_path()
    local p=reaper.GetResourcePath().."/Data/AHS_Music_Tech/DrumArranger/Patterns"
    reaper.RecursiveCreateDirectory(p,0)
    return p
end
function export.ServicePatternLibrary()
    local r=reaper
    r.gmem_attach("N2N_Ecosystem_RSKennedy")
    r.gmem_write(LIB+8,r.time_precise())
    local op=r.gmem_read(LIB)
    if op~=1 and op~=2 then return end
    r.gmem_write(LIB,5)
    local ok,err=pcall(function()
        local dir=pattern_path()
        if op==1 then
            local accepted,name=r.GetUserInputs("Save drum pattern",1,"Pattern name:", "My Pattern")
            if not accepted then r.gmem_write(LIB,0); return end
            name=name:match("^%s*(.-)%s*$")
            if name=="" or name:find("[/\\:*?\"<>|%c]") or name=="." or name==".." then error("Invalid pattern name") end
            local path=dir.."/"..name..".n2drumpat"
            local old=io.open(path,"rb")
            if old then old:close(); if r.MB("Replace the existing pattern?","Save Pattern",4)~=6 then r.gmem_write(LIB,0); return end end
            local file,why=io.open(path,"wb")
            if not file then error(why or "Cannot save pattern") end
            file:write("N2N_DRUM_PATTERN 1\n")
            local header={}
            for i=3,7 do header[#header+1]=r.gmem_read(LIB+i) end
            header[#header+1]=r.gmem_read(LIB+10)
            local n=math.max(0,math.min(16384,math.floor(r.gmem_read(LIB+9))))
            header[#header+1]=n
            file:write(table.concat(header," "),"\n")
            for i=0,n-1 do
                local row={}
                for j=0,5 do row[#row+1]=r.gmem_read(LIB+16+i*6+j) end
                file:write(table.concat(row," "),"\n")
            end
            local closed,why=file:close(); if not closed then error(why or "Could not finish writing") end
            r.gmem_write(LIB,0)
        else
            local accepted,path=r.GetUserFileNameForRead(dir.."/","Load drum pattern",".n2drumpat")
            if not accepted then r.gmem_write(LIB,0); return end
            local file,why=io.open(path,"rb"); if not file then error(why or "Cannot open pattern") end
            local data=file:read(2097153); file:close()
            if not data or #data>2097152 then error("Pattern file is too large") end
            local lines={}
            for line in data:gmatch("[^\r\n]+") do lines[#lines+1]=line end
            if lines[1]~="N2N_DRUM_PATTERN 1" then error("Unrecognized pattern format") end
            local function fields(line,n)
                local out={}
                for v in (line or ""):gmatch("%S+") do
                    local x=tonumber(v); if not x or x~=x or math.abs(x)==math.huge then error("Invalid pattern number") end
                    out[#out+1]=x
                end
                if #out~=n then error("Invalid pattern record") end
                return out
            end
            local h=fields(lines[2],7)
            local n=h[7]
            if not(valid_number(h[1],1,4) and h[1]%1==0 and ({[8]=true,[12]=true,[16]=true,[24]=true,[32]=true})[h[2]]
                and valid_number(h[3],0,25) and valid_number(h[4],0,100) and (h[5]==0 or h[5]==1)
                and (h[6]==0 or h[6]==2) and valid_number(n,0,16384) and n%1==0 and #lines==n+2) then error("Invalid pattern header") end
            local rows={}
            for i=1,n do
                local v=fields(lines[i+2],6)
                if not(valid_number(v[1],0,127) and v[1]%1==0 and valid_number(v[2],1,16) and v[2]%1==0
                    and valid_number(v[3],0,127) and v[3]%1==0 and valid_number(v[4],0,127)
                    and valid_number(v[5],0,127) and valid_number(v[6],0,128)) then error("Invalid pattern step") end
                rows[i]=v
            end
            for i=1,5 do r.gmem_write(LIB+2+i,h[i]) end
            r.gmem_write(LIB+10,h[6]); r.gmem_write(LIB+9,n)
            for i,v in ipairs(rows) do for j=1,6 do r.gmem_write(LIB+16+(i-1)*6+j-1,v[j]) end end
            r.gmem_write(LIB,3)
        end
    end)
    if not ok then r.gmem_write(LIB,0); r.MB(tostring(err),"Drum Pattern Library",0) end
end

return export