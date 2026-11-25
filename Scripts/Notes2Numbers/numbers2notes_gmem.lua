-- @description numbers2notes_gmem
-- @version 1.9
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
    local regions, keys, spans, id_counts = {}, {}, {}, {}
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
            if name:lower():find("n2n drum arranger",1,true) or name:lower():find("n2n arp",1,true) then
                local id=math.floor(r.TrackFX_GetParam(tr,fx,4)+0.5)
                if id>=1 and id<=512 then
                    local key=r.gmem_read(8000000+id)
                    id_counts[id]=(id_counts[id] or 0)+1
                    if key>0 then keys[id]=key end
                end
            end
        end
    end
    for id,n in pairs(id_counts) do if n>1 then keys[id]=nil end end
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
local DRUM_LIB, ARP_LIB=6200000,6400000
local function valid_number(n,a,b)
    return type(n)=="number" and n==n and n>=a and n<=b
end
local ARP_MODES = {[0]="Chords", [1]="Split", [2]="Bass"}
-- Catalogues occupy the space after the sparse payload, inside each mailbox.
-- Each mode: revision, count, then up to 100 records of 100 bytes (length + text).
local CATALOG_OFFSET, CATALOG_STRIDE, CATALOG_MAX, RECORD_SIZE = 100000, 16384, 100, 100
local catalogues, catalog_poll = {}, -math.huge
local function pattern_path(is_arp, mode, factory)
    local p=reaper.GetResourcePath().."/Data/AHS_Music_Tech/"..(is_arp and "Arp" or "DrumArranger").."/Patterns"
    if factory then p=p.."/Factory" end
    if is_arp then p=p.."/"..(ARP_MODES[mode] or ARP_MODES[0]) end
    reaper.RecursiveCreateDirectory(p,0)
    return p
end
local function update_catalogue(LIB,is_arp,mode)
    local r=reaper
    local dir=pattern_path(is_arp,mode,true)
    local extension=is_arp and ".n2arppat" or ".n2drumpat"
    local names={}
    -- Reset REAPER's cached directory enumeration before rescanning.
    r.EnumerateFiles(dir,-1)
    local i=0
    while true do
        local name=r.EnumerateFiles(dir,i)
        if not name then break end
        if name:sub(-#extension):lower()==extension then names[#names+1]=name end
        i=i+1
    end
    table.sort(names,function(a,b) if a:lower()==b:lower() then return a<b end return a:lower()<b:lower() end)
    while #names>CATALOG_MAX do names[#names]=nil end
    local base=LIB+CATALOG_OFFSET+mode*CATALOG_STRIDE
    local key=table.concat(names,"\0")
    local previous=catalogues[base]
    if previous and previous.key==key and r.gmem_read(base)==previous.rev then return end
    local rev=math.floor(r.gmem_read(base)/2)*2+2
    if rev<2 or rev>2000000000 then rev=2 end
    r.gmem_write(base,rev-1)
    for index,name in ipairs(names) do
        local label=name:sub(1,-#extension-1):gsub("[%c|]"," ")
        if #label>=RECORD_SIZE then
            local pos=100
            while pos>1 and (label:byte(pos) or 0)>=128 and (label:byte(pos) or 0)<192 do pos=pos-1 end
            label=label:sub(1,pos-1)
        end
        local addr=base+2+(index-1)*RECORD_SIZE
        r.gmem_write(addr,#label)
        for j=1,#label do r.gmem_write(addr+j,label:byte(j)) end
    end
    r.gmem_write(base+1,#names)
    catalogues[base]={key=key,rev=rev,names=names,dir=dir}
    r.gmem_write(base,rev)
end
local function service_pattern_library(LIB,is_arp)
    local r=reaper
    local kind=is_arp and "arp" or "drum"
    local extension=is_arp and ".n2arppat" or ".n2drumpat"
    local signature=is_arp and "N2N_ARP_PATTERN 1" or "N2N_DRUM_PATTERN 1"
    r.gmem_attach("N2N_Ecosystem_RSKennedy")
    r.gmem_write(LIB+8,r.time_precise())
    local op=r.gmem_read(LIB)
    if op==3 and (r.time_precise()-r.gmem_read(LIB+11)>30 or r.gmem_read(8000000+math.floor(r.gmem_read(LIB+1)))~=r.gmem_read(LIB+12)) then
        r.gmem_write(LIB,0)
        return
    end
    if op~=1 and op~=2 and op~=4 and op~=6 and op~=7 then return end
    local id=math.floor(r.gmem_read(LIB+1))
    if id<1 or id>512 or r.gmem_read(8000000+id)~=r.gmem_read(LIB+12) then
        r.gmem_write(LIB,0)
        return
    end
    r.gmem_write(LIB,5)
    local ok,err=pcall(function()
        local mode=is_arp and math.floor(r.gmem_read(LIB+13)) or 0
        if not ARP_MODES[mode] then error("Invalid Arp mode") end
        local factory=op==4 or op==6 or op==7
        local dir=pattern_path(is_arp,mode,factory)
        if op==1 or op==4 then
            local accepted,name=r.GetUserInputs((op==4 and "Export factory " or "Save ")..kind.." pattern"..(is_arp and " ("..ARP_MODES[mode]..")" or ""),1,"Pattern name:", "My Pattern")
            if not accepted then r.gmem_write(LIB,0); return end
            name=name:match("^%s*(.-)%s*$")
            if name=="" or name:find("[/\\:*?\"<>|%c]") or name=="." or name==".." then error("Invalid pattern name") end
            local path=dir.."/"..name..extension
            local old=io.open(path,"rb")
            if old then old:close(); if r.MB("Replace the existing pattern?","Save Pattern",4)~=6 then r.gmem_write(LIB,0); return end end
            local file,why=io.open(path,"wb")
            if not file then error(why or "Cannot save pattern") end
            file:write(signature,"\n")
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
            if op==4 then update_catalogue(LIB,is_arp,mode) end
        else
            local path
            if op==6 then
                local base=LIB+CATALOG_OFFSET+mode*CATALOG_STRIDE
                local cat=catalogues[base]
                local index=math.floor(r.gmem_read(LIB+14))
                if not cat or cat.rev~=r.gmem_read(LIB+15) or not cat.names[index] then
                    error("Factory catalogue changed. Please reopen LIBRARY.")
                end
                path=cat.dir.."/"..cat.names[index]
            else
                local accepted
                accepted,path=r.GetUserFileNameForRead(dir.."/","Load "..kind.." pattern"..(is_arp and " ("..ARP_MODES[mode]..")" or ""),extension)
                if not accepted then r.gmem_write(LIB,0); return end
            end
            local file,why=io.open(path,"rb"); if not file then error(why or "Cannot open pattern") end
            local data=file:read(2097153); file:close()
            if not data or #data>2097152 then error("Pattern file is too large") end
            local lines={}
            for line in data:gmatch("[^\r\n]+") do lines[#lines+1]=line end
            if lines[1]~=signature then error("Unrecognized pattern format") end
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
            r.gmem_write(LIB+11,r.time_precise())
            r.gmem_write(LIB,3)
        end
    end)
    if not ok then r.gmem_write(LIB,0); r.MB(tostring(err),kind.." Pattern Library",0) end
end


function export.ServicePatternLibrary()
    local r=reaper
    r.gmem_attach("N2N_Ecosystem_RSKennedy")
    if r.time_precise()-catalog_poll>=2 then
        catalog_poll=r.time_precise()
        -- Directory access failures must not interfere with song-form publishing.
        pcall(update_catalogue,DRUM_LIB,false,0)
        for mode=0,2 do pcall(update_catalogue,ARP_LIB,true,mode) end
    end
    service_pattern_library(DRUM_LIB,false)
    service_pattern_library(ARP_LIB,true)
end

-- 6. Shared track inventory and compact management panel.
local INFO_BASE, REG_BASE, INV_BASE, EDIT_BASE = 8200000, 8000000, 7500000, 8300000
local tracks, duplicate, last_project_tracks = {}, {}, nil
local identity_last_poll = -math.huge
local fx_hover, hover_until, hover_pos, id_popup
local function kind_of(track,fx)
    local ok, name = reaper.TrackFX_GetFXName(track,fx,"")
    if reaper.TrackFX_GetNamedConfigParm then
        local got, ident = reaper.TrackFX_GetNamedConfigParm(track,fx,"fx_ident")
        if got and ident and ident~="" then name=(name or "").." "..ident end
    end
    if not ok or not name then return end
    local lower=name:lower()
    if lower:find("n2n drum arranger",1,true) then return "DRUM" end
    if lower:find("n2n arp",1,true) then return "ARP" end
end
local function scan(project)
    local result, counts={},{}
    for i=0,reaper.CountTracks(project)-1 do
        local tr=reaper.GetTrack(project,i)
        local _,name=reaper.GetTrackName(tr)
        local native=reaper.GetTrackColor(tr)
        local red,green,blue=.5,.5,.5
        if native and native~=0 then
            local rr,gg,bb=reaper.ColorFromNative(native)
            red,green,blue=rr/255,gg/255,bb/255
        end
        for fx=0,reaper.TrackFX_GetCount(tr)-1 do
            local kind=kind_of(tr,fx)
            if kind then
                local id=math.floor(reaper.TrackFX_GetParam(tr,fx,4)+.5)
                local guid=reaper.TrackFX_GetFXGUID(tr,fx)
                result[#result+1]={track=tr,fx=fx,guid=guid,name=name,number=i+1,kind=kind,id=id,r=red,g=green,b=blue}
                counts[id]=(counts[id] or 0)+1
            end
        end
    end
    return result,counts
end
local function locate(t)
    local project=reaper.EnumProjects(-1,"")
    if not t or not reaper.ValidatePtr2(project,t.track,"MediaTrack*") then return end
    for fx=0,reaper.TrackFX_GetCount(t.track)-1 do
        if reaper.TrackFX_GetFXGUID(t.track,fx)==t.guid then return fx end
    end
end
function export.PublishTrackIdentity(force)
    local r=reaper
    local now=r.time_precise()
    local project=r.EnumProjects(-1,"")
    if not force and project==last_project_tracks and now-identity_last_poll<.5 then return end
    identity_last_poll,last_project_tracks=now,project
    r.gmem_attach("N2N_Ecosystem_RSKennedy")
    tracks,duplicate=scan(project)
    local slots={}
    for _,t in ipairs(tracks) do
        if t.id>=1 and t.id<=512 and duplicate[t.id]==1 then slots[t.id]=t end
    end
    -- Clear stale identities on the first scan and on project/track changes.
    for id=1,512 do
        local t=slots[id]
        local values=t and {t.number,t.r,t.g,t.b} or {0,0,0,0}
        local base=INFO_BASE+(id-1)*4
        for j=1,4 do
            if r.gmem_read(base+j-1)~=values[j] then r.gmem_write(base+j-1,values[j]) end
        end
    end
end
local groups={
    {{26,1,"Def",.7,.7,.9,25},{5,4,"V",.5,.7,1,36},{9,4,"P",.5,.7,1,48},{13,4,"C",1,.4,.4,60},{17,4,"B",1,.9,.2,72},{27,1,"U1",.55,.55,.55,27},{75,1,"D",.55,.55,.55,84}},
    {{77,1,"#",.7,.7,.7,86},{32,4,"V",.5,.7,1,40},{36,4,"P",.5,.7,1,52},{40,4,"C",1,.4,.4,64},{44,4,"S",.2,.8,.3,76},{28,1,"U2",.55,.55,.55,28},{76,1,"X",.55,.55,.55,85}},
    {{1,4,"I",.2,1,1,11},{59,4,"V",.5,.7,1,44},{63,4,"P",.5,.7,1,56},{67,4,"C",1,.4,.4,68},{71,4,"O",.5,.8,.7,80},{29,1,"U3",.55,.55,.55,29},{78,1,"F",.55,.55,.55,87}}
}
local names={{"Default","Verse 1","Pre-Chorus 1","Chorus 1","Bridge","User 1","Drop"},{"Count-In","Verse 2","Pre-Chorus 2","Chorus 2","Solo","User 2","Breakdown"},{"Intro","Verse 3","Pre-Chorus 3","Chorus 3","Outro","User 3","Fadeout"}}
local function color(r,g,b,a)
    return reaper.ImGui_ColorConvertDouble4ToU32(r,g,b,a or 1)
end
local function open_fx(track,fx)
    if fx and fx>=0 then reaper.TrackFX_Show(track,fx,3) end
end
local function find_free_id()
    local used={}
    local i=0
    while true do
        local proj=reaper.EnumProjects(i,"")
        if not proj then break end
        local _,counts=scan(proj)
        for id in pairs(counts) do used[id]=true end
        i=i+1
    end
    for id=1,512 do
        if not used[id] and reaper.gmem_read(REG_BASE+id)==0 then return id end
    end
end
local function launch_cue()
    local r=reaper
    local function search(dir,depth)
        if depth>7 then return end
        local i=0
        while true do
            local file=r.EnumerateFiles(dir,i)
            if not file then break end
            local name=file:lower():gsub("[%s_%-]","")
            if name=="n2ncue.lua" or name=="n2ncue" then return dir.."/"..file end
            i=i+1
        end
        i=0
        while true do
            local sub=r.EnumerateSubdirectories(dir,i)
            if not sub then break end
            local found=search(dir.."/"..sub,depth+1)
            if found then return found end
            i=i+1
        end
    end
    local path=search(r.GetResourcePath().."/Scripts",0)
    if not path then
        local accepted
        accepted,path=r.GetUserFileNameForRead(r.GetResourcePath().."/Scripts/","Locate installed N2NCue script",".lua")
        if not accepted then return end
    end
    local cmd=r.AddRemoveReaScript(true,0,path,true)
    if cmd and cmd>0 then r.Main_OnCommand(cmd,0) else r.MB("Could not launch N2NCue.","N2N Tracks",0) end
end
local function pattern_grid(ctx,t,width)
    local r=reaper
    local dl=r.ImGui_GetWindowDrawList(ctx)
    local x,y=r.ImGui_GetCursorScreenPos(ctx)
    local groupw=(width-4)/6
    local lastw=groupw/2
    local h=10
    local known=t.id>=1 and t.id<=512 and duplicate[t.id]==1 and r.gmem_read(REG_BASE+t.id)>0 and r.TrackFX_GetEnabled(t.track,t.fx)
    local bits={}
    if known then for i=0,3 do bits[i]=math.floor(r.gmem_read(INV_BASE+(t.id-1)*4+i)) end end
    local mx,my=r.ImGui_GetMousePos(ctx)
    local hovered
    for row,gs in ipairs(groups) do
        for gi,g in ipairs(gs) do
            local gx=x+(gi<=5 and (gi-1)*groupw or 5*groupw+(gi-6)*lastw)
            local gw=gi<=5 and groupw or lastw
            local first=g[2]==4 and math.min(15,gw*.4) or gw-2
            local mini=(gw-first-5)/3
            for v=0,g[2]-1 do
                local bx=gx+(v==0 and 0 or first+1+(v-1)*(mini+1))
                local bw=v==0 and first or mini
                local by=y+(row-1)*(h+2)
                local bit=t.kind=="DRUM" and g[7]+v or g[1]+v
                local populated=known and ((bits[bit//32] or 0)&(1<<(bit%32)))~=0
                local shade=populated and 1 or .4
                r.ImGui_DrawList_AddRectFilled(dl,bx,by,bx+bw,by+h,color(g[4]*shade,g[5]*shade,g[6]*shade))
                if populated then r.ImGui_DrawList_AddRect(dl,bx+.5,by+.5,bx+bw-.5,by+h-.5,0xFFFFFFFF) end
                if v==0 then
                    local tw,th=r.ImGui_CalcTextSize(ctx,g[3])
                    if tw<=bw then
                        local lum=(g[4]*.299+g[5]*.587+g[6]*.114)*shade
                        r.ImGui_DrawList_AddText(dl,bx+(bw-tw)/2,by+(h-th)/2,lum>.57 and 0x101010FF or 0xFFFFFFFF,g[3])
                    end
                end
                if mx>=bx and mx<bx+bw and my>=by and my<by+h then
                    hovered={tab=g[1]+v,label=names[row][gi]..(g[2]==4 and " "..string.char(65+v) or ""),populated=populated}
                end
            end
        end
    end
    r.ImGui_InvisibleButton(ctx,"##pattern_grid",width,3*(h+2))
    if hovered and r.ImGui_IsItemHovered(ctx) then
        r.ImGui_SetTooltip(ctx,hovered.label..(not known and " (inventory unavailable)" or hovered.populated and " (populated)" or " (empty / inherited)").."\nClick to open pattern for editing")
        if r.ImGui_IsItemClicked(ctx,0) then
            local fx=locate(t)
            if fx then
                if known then
                    local base=EDIT_BASE+(t.id-1)*2
                    r.gmem_write(base,r.gmem_read(REG_BASE+t.id))
                    r.gmem_write(base+1,hovered.tab+1)
                end
                open_fx(t.track,fx)
            end
        end
    end
end
function export.DrawTracks(ctx,font)
    local r=reaper
    export.PublishTrackIdentity(false)
    local conflict_count=0
    for id,n in pairs(duplicate) do if n>1 or id<1 or id>512 then conflict_count=conflict_count+1 end end
    if conflict_count>0 then
        r.ImGui_TextColored(ctx,0xFF7777FF,("%d ID conflict(s)"):format(conflict_count))
    else r.ImGui_TextColored(ctx,0xA0E0A0FF,("%d instances | IDs OK"):format(#tracks)) end
    r.ImGui_SameLine(ctx)
    if r.ImGui_SmallButton(ctx,"Refresh") then export.PublishTrackIdentity(true) end
    r.ImGui_PushStyleVar(ctx,r.ImGui_StyleVar_ItemSpacing(),2,1)
    r.ImGui_PushStyleVar(ctx,r.ImGui_StyleVar_FramePadding(),2,1)
    local visible=r.ImGui_BeginChild(ctx,"##N2NTrackScroll",0,-29,0)
    if visible then
        for _,t in ipairs(tracks) do
            local fx=locate(t)
            if fx then
                t.fx=fx
                r.ImGui_PushID(ctx,t.guid)
                local width=r.ImGui_GetContentRegionAvail(ctx)
                local fxw,idw,instw,arpw=25,44,35,40
                local namew=math.max(40,width-fxw-idw-instw-arpw-8)
                local label=("%d. %s"):format(t.number,t.name)
                while #label>4 and r.ImGui_CalcTextSize(ctx,label)>namew-4 do
                    label=label:sub(1,-2)
                    while #label>0 and label:byte(-1)>=128 and label:byte(-1)<192 do label=label:sub(1,-2) end
                end
                if label~=(("%d. %s"):format(t.number,t.name)) then label=label.."…" end
                local lum=t.r*.299+t.g*.587+t.b*.114
                r.ImGui_PushStyleColor(ctx,r.ImGui_Col_Button(),color(t.r,t.g,t.b))
                r.ImGui_PushStyleColor(ctx,r.ImGui_Col_Text(),lum>.55 and 0x101010FF or 0xFFFFFFFF)
                if r.ImGui_Button(ctx,label,namew,19) then
                    r.SetOnlyTrackSelected(t.track)
                    r.Main_OnCommand(40913,0)
                end
                r.ImGui_PopStyleColor(ctx,2)
                if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx,t.name) end
                r.ImGui_SameLine(ctx)
                if r.ImGui_Button(ctx,t.kind,arpw,19) then open_fx(t.track,fx) end
                r.ImGui_SameLine(ctx)
                local inst=r.TrackFX_GetInstrument(t.track)
                if inst<0 or inst==fx then r.ImGui_BeginDisabled(ctx) end
                if r.ImGui_Button(ctx,"INST",instw,19) then open_fx(t.track,inst) end
                if inst<0 or inst==fx then r.ImGui_EndDisabled(ctx) end
                r.ImGui_SameLine(ctx)
                local bad=(duplicate[t.id] or 0)>1 or t.id<1 or t.id>512
                if bad then r.ImGui_PushStyleColor(ctx,r.ImGui_Col_Button(),0xA82828FF) end
                if r.ImGui_Button(ctx,"ID "..t.id,idw,19) then id_popup=t end
                if bad then r.ImGui_PopStyleColor(ctx) end
                r.ImGui_SameLine(ctx)
                local clicked=r.ImGui_Button(ctx,"FX",fxw,19)
                if clicked or r.ImGui_IsItemHovered(ctx) then
                    fx_hover=t
                    hover_until=r.time_precise()+.35
                    local _,bottom=r.ImGui_GetItemRectMax(ctx)
                    local left=r.ImGui_GetItemRectMin(ctx)
                    hover_pos={left,bottom}
                end
                if font then r.ImGui_PushFont(ctx,font) end
                pattern_grid(ctx,t,math.max(150,width))
                if font then r.ImGui_PopFont(ctx) end
                r.ImGui_Separator(ctx)
                r.ImGui_PopID(ctx)
            end
        end
    end
    r.ImGui_EndChild(ctx)
    if r.ImGui_Button(ctx,"OPEN N2NCUE",-1,22) then launch_cue() end
    r.ImGui_PopStyleVar(ctx,2)
    if id_popup then
        r.ImGui_OpenPopup(ctx,"N2N Instance ID")
        if r.ImGui_BeginPopupModal(ctx,"N2N Instance ID",true,r.ImGui_WindowFlags_AlwaysAutoResize()) then
            local t=id_popup
            local fx=locate(t)
            r.ImGui_Text(ctx,t.name.." | "..t.kind.." | ID "..t.id)
            for _,other in ipairs(tracks) do
                if other.id==t.id and other.guid~=t.guid then r.ImGui_TextColored(ctx,0xFF7777FF,"Conflict: "..other.name.." ("..other.kind..")") end
            end
            r.ImGui_TextWrapped(ctx,"Assign a free ID while transport is stopped. Existing patterns are preserved.")
            local free=find_free_id()
            local disabled=not fx or not free or r.GetPlayState()~=0
            if disabled then r.ImGui_BeginDisabled(ctx) end
            if r.ImGui_Button(ctx,free and ("Assign ID "..free) or "No free registered ID") then
                r.Undo_BeginBlock()
                r.TrackFX_SetParam(t.track,fx,4,free)
                r.Undo_EndBlock("N2N: Reassign arranger instance ID",-1)
                export.PublishTrackIdentity(true)
                id_popup=nil; r.ImGui_CloseCurrentPopup(ctx)
            end
            if disabled then r.ImGui_EndDisabled(ctx) end
            r.ImGui_SameLine(ctx)
            if r.ImGui_Button(ctx,"Close") then id_popup=nil; r.ImGui_CloseCurrentPopup(ctx) end
            r.ImGui_EndPopup(ctx)
        else id_popup=nil end
    end
    if fx_hover and r.time_precise()<=hover_until and locate(fx_hover) then
        local t=fx_hover
        r.ImGui_SetNextWindowPos(ctx,hover_pos[1],hover_pos[2])
        local flags=r.ImGui_WindowFlags_NoTitleBar()|r.ImGui_WindowFlags_AlwaysAutoResize()|r.ImGui_WindowFlags_NoSavedSettings()|r.ImGui_WindowFlags_NoFocusOnAppearing()
        local vis=r.ImGui_Begin(ctx,"##N2NHoverFX",true,flags)
        if vis then
            if r.ImGui_IsWindowHovered(ctx) then hover_until=r.time_precise()+.35 end
            r.ImGui_Text(ctx,t.name.." FX")
            r.ImGui_Separator(ctx)
            for fx=0,r.TrackFX_GetCount(t.track)-1 do
                local _,name=r.TrackFX_GetFXName(t.track,fx,"")
                local enabled=r.TrackFX_GetEnabled(t.track,fx)
                local offline=r.TrackFX_GetOffline(t.track,fx)
                r.ImGui_PushID(ctx,fx)
                r.ImGui_PushStyleColor(ctx,r.ImGui_Col_Text(),offline and 0xFF6666FF or enabled and 0xFFFFFFFF or 0x888888FF)
                if r.ImGui_Selectable(ctx,(offline and "[Offline] " or enabled and "" or "[Bypassed] ")..name,false) then
                    if (r.ImGui_GetKeyMods(ctx)&r.ImGui_Mod_Shift())~=0 then
                        if not offline then
                            r.Undo_BeginBlock()
                            r.TrackFX_SetEnabled(t.track,fx,not enabled)
                            r.Undo_EndBlock("N2N: Toggle FX bypass",-1)
                        end
                    else open_fx(t.track,fx) end
                    hover_until=r.time_precise()+.35
                end
                r.ImGui_PopStyleColor(ctx)
                r.ImGui_PopID(ctx)
            end
            r.ImGui_Separator(ctx)
            r.ImGui_TextDisabled(ctx,"Click: Open   Shift+Click: Bypass")
        end
        r.ImGui_End(ctx)
    else fx_hover=nil end
end

return export