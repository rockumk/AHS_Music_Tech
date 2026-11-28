-- @description numbers2notes_gmem
-- @version 1.9.22
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
-- The native legacy dialog may remember an unrelated directory. Use an
-- explicit initial folder when js_ReaScriptAPI is installed.
local function browse_pattern_file(dir,title,extension)
    local r=reaper
    if r.JS_Dialog_BrowseForOpenFiles then
        local filter="N2N pattern files (*"..extension..")\0*"..extension.."\0"
        local result,path=r.JS_Dialog_BrowseForOpenFiles(title,dir,"",filter,false)
        return result>0 and path and path~="",path
    end
    return r.GetUserFileNameForRead(dir.."/",title,extension)
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
                accepted,path=browse_pattern_file(dir,"Load "..kind.." pattern"..(is_arp and " ("..ARP_MODES[mode]..")" or ""),extension)
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
local fx_hover, hover_until, hover_pos, id_popup, id_popup_open, id_suggestion
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
local function is_topline(tr,name)
    if name=="__N2N_Topline_Hidden" or name=="__N2N_Melody_Engine_Hidden" then return false end
    local _,tag=reaper.GetSetMediaTrackInfo_String(tr,"P_EXT:N2N:TOPLINE","",false)
    local _,recipe=reaper.GetSetMediaTrackInfo_String(tr,"P_EXT:N2N:ID","",false)
    return tag=="1" or (recipe or ""):match("^41_")~=nil
        or (name or ""):lower():find("n2n topline",1,true)~=nil
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
        if is_topline(tr,name) then
            result[#result+1]={track=tr,guid=reaper.GetTrackGUID(tr),name=name,number=i+1,kind="Topline",r=red,g=green,b=blue}
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
-- UI requests from the arranger: per-instance key, command, timestamp, payload.
-- 1 instrument, 2 hub, 3 mixer, 4 section playback (tab*3 + pre-roll bars), 5 stop, 6 pause.
local HUB_UI_BASE=8320000
local pending_arranger_play
-- Negative payload is a failure acknowledgement, consumed by the requesting FX.
local function arranger_play_failed(id,key,stamp,payload)
    local r=reaper
    local base=HUB_UI_BASE+4+(id-1)*4
    if r.gmem_read(base)==key and r.gmem_read(base+1)==0
        and r.gmem_read(base+2)==stamp and r.gmem_read(base+3)==payload then
        r.gmem_write(base+3,-payload)
    end
end
local function service_pending_arranger_play(project,now)
    local p=pending_arranger_play
    if not p then return end
    local r=reaper
    if p.project~=project or r.gmem_read(REG_BASE+p.id)~=p.key then
        pending_arranger_play=nil
        return
    end
    if now>=p.deadline then
        pending_arranger_play=nil
        arranger_play_failed(p.id,p.key,p.stamp,p.payload)
        return
    end
    -- A separate defer iteration, a short settle interval and confirmed stop
    -- prevent a seek during playback and give REAPER time to flush old notes.
    if now<p.ready or r.GetPlayStateEx(project)~=0 then return end
    pending_arranger_play=nil
    r.SetEditCurPos2(project,p.target,true,false)
    r.Main_OnCommand(1007,0)
end
local function play_arranger_section(project, id, key, stamp, payload, stretched_index)
    local r=reaper
    if type(stretched_index)~="function" or payload~=math.floor(payload) or payload<3 or payload>236 then return end
    local tab,preroll=math.floor(payload/3),payload%3
    -- Rebuild from the active project's rendered regions before resolving the request.
    if not export.PublishSongForm(stretched_index,true) or r.gmem_read(FORM_BASE+10+id)~=key then
        arranger_play_failed(id,key,stamp,payload)
        return
    end
    local pos=(r.GetPlayStateEx(project)&1)~=0 and r.GetPlayPositionEx(project) or r.GetCursorPositionEx(project)
    local q=r.TimeMap2_timeToQN(project,pos)
    local first,upcoming,current
    local count=math.min(FORM_MAX,math.max(0,math.floor(r.gmem_read(FORM_BASE+2))))
    for i=0,count-1 do
        local p=FORM_BASE+1024+i*3
        local a,b,t=r.gmem_read(p),r.gmem_read(p+1),r.gmem_read(p+2)
        if t==tab then
            first=first or a
            if q>=a-1e-8 and q<b-1e-8 then current=a;break end
            if a>=q-1e-8 and not upcoming then upcoming=a end
        end
    end
    local start=current or upcoming or first
    if not start then
        arranger_play_failed(id,key,stamp,payload)
        return
    end
    local target=r.TimeMap2_QNToTime(project,start)
    if preroll>0 then
        local _,measure=r.TimeMap2_timeToBeats(project,target)
        target=r.TimeMap2_beatsToTime(project,0,math.max(0,measure-preroll))
    end
    pending_arranger_play=nil
    target=math.max(0,target)
    if r.GetPlayStateEx(project)~=0 then
        r.Main_OnCommand(1016,0)
        local now=r.time_precise()
        pending_arranger_play={project=project,id=id,key=key,stamp=stamp,payload=payload,
            target=target,ready=now+0.05,deadline=now+2}
    else
        r.SetEditCurPos2(project,target,true,false)
        r.Main_OnCommand(1007,0)
    end
end
function export.ServiceArrangerUIRequests(stretched_index)
    local r=reaper
    local project=r.EnumProjects(-1,"")
    local now=r.time_precise()
    r.gmem_attach("N2N_Ecosystem_RSKennedy")
    r.gmem_write(HUB_UI_BASE,now)
    local raise,mix=false,false
    for id=1,512 do
        local base=HUB_UI_BASE+4+(id-1)*4
        local cmd=r.gmem_read(base+1)
        if cmd~=0 then
            local key,stamp,payload=r.gmem_read(base),r.gmem_read(base+2),r.gmem_read(base+3)
            r.gmem_write(base+1,0)
            if (cmd==1 or cmd==2 or cmd==3 or cmd==4 or cmd==5 or cmd==6) and key>0 and key==r.gmem_read(REG_BASE+id) and math.abs(now-stamp)<2 then
                local inventory,counts=scan(project)
                if counts[id]==1 then
                    for _,t in ipairs(inventory) do
                        if t.id==id and locate(t) then
                            if cmd==2 then raise=true
                            elseif cmd==3 then mix=true
                            elseif cmd==4 then play_arranger_section(project,id,key,stamp,payload,stretched_index)
                            elseif cmd==5 then
                                pending_arranger_play=nil
                                r.Main_OnCommand(1016,0)
                            elseif cmd==6 then
                                pending_arranger_play=nil
                                local state=r.GetPlayStateEx(project)
                                -- Pause is not a toggle: never resume an already paused transport.
                                if (state&1)~=0 and (state&2)==0 then r.OnPauseButtonEx(project) end
                            else
                                local tr=t.track
                                local fx=r.TrackFX_GetInstrument(tr)
                                if fx<0 then
                                    -- Some N2N recipes put the arranger on a MIDI-only track.
                                    -- Follow only an unambiguous direct MIDI send.
                                    local dest,ambiguous
                                    for i=0,r.GetTrackNumSends(tr,0)-1 do
                                        if r.GetTrackSendInfo_Value(tr,0,i,"B_MUTE")==0 and (math.floor(r.GetTrackSendInfo_Value(tr,0,i,"I_MIDIFLAGS"))&31)~=31 then
                                            local d=r.GetTrackSendInfo_Value(tr,0,i,"P_DESTTRACK")
                                            if d and r.ValidatePtr2(project,d,"MediaTrack*") and r.TrackFX_GetInstrument(d)>=0 then
                                                if dest and dest~=d then ambiguous=true end
                                                dest=d
                                            end
                                        end
                                    end
                                    if dest and not ambiguous then tr=dest;fx=r.TrackFX_GetInstrument(tr) end
                                end
                                if fx>=0 then
                                    r.TrackFX_Show(tr,fx,3)
                                    local hwnd=r.TrackFX_GetFloatingWindow(tr,fx)
                                    if hwnd then
                                        if r.JS_Window_SetZOrder then r.JS_Window_SetZOrder(hwnd,"TOP") end
                                        if r.JS_Window_SetForeground then r.JS_Window_SetForeground(hwnd) end
                                        if r.JS_Window_SetFocus then r.JS_Window_SetFocus(hwnd) end
                                    end
                                else r.MB("No unique instrument found for "..t.name..".","Numbers2Notes",0) end
                            end
                            break
                        end
                    end
                end
            end
        end
    end
    service_pending_arranger_play(project,now)
    return raise,mix
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
        if t.id and t.id>=1 and t.id<=512 and duplicate[t.id]==1 then slots[t.id]=t end
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
local function find_script(wanted)
    local r=reaper
    local function search(dir,depth)
        if depth>7 then return end
        local i=0
        while true do
            local file=r.EnumerateFiles(dir,i)
            if not file then break end
            local name=file:lower():gsub("[%s_%-]","")
            if name==wanted..".lua" or name==wanted then return dir.."/"..file end
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
    return search(r.GetResourcePath().."/Scripts",0)
end
-- Shared launcher for the chart, mixer and standalone Topline editor.
-- ReaImGui scripts use their own focus mailbox, avoiding a JS extension
-- dependency for those windows. Topline's native gfx window uses JS focus.
function export.OpenEditor(wanted,title)
    local r=reaper
    local sec="N2N_EDITOR_WINDOWS"
    local heartbeat=tonumber(r.GetExtState(sec,wanted..":heartbeat"))
    if heartbeat and math.abs(r.time_precise()-heartbeat)<3 then
        r.SetExtState(sec,wanted..":focus",tostring(r.time_precise()),false)
        return
    end
    if wanted=="n2ntopline" then
        local top="N2N_TOPLINE_HUB"
        local hb=tonumber(r.GetExtState(top,"heartbeat"))
        if hb and math.abs(r.time_precise()-hb)<3 then
            r.SetExtState(top,"focus",tostring(r.time_precise()),false)
            if r.JS_Window_Find and r.JS_Window_SetFocus then
                local hwnd=r.JS_Window_Find(title,true)
                if hwnd then r.JS_Window_SetFocus(hwnd) end
            end
            return
        end
    end
    if r.JS_Window_Find and r.JS_Window_SetFocus then
        local hwnd=r.JS_Window_Find(title,true)
        if hwnd then r.JS_Window_SetFocus(hwnd);return end
    end
    local path
    if wanted=="n2ntopline" or wanted=="n2nmix" then
        local source=debug.getinfo(1,"S").source:gsub("^@",""):gsub("\\","/")
        local parent=source:match("^(.*)/Notes2Numbers/[^/]+$")
        if parent then
            local candidate=parent.."/"..title..".lua"
            local file=io.open(candidate,"rb")
            if file then file:close();path=candidate end
        end
    end
    path=path or find_script(wanted)
    if not path then r.MB("Install "..title..".lua first.","Numbers2Notes",0);return end
    local cmd=r.AddRemoveReaScript(true,0,path,true)
    if cmd and cmd>0 then r.Main_OnCommand(cmd,0)
    else r.MB("Could not launch "..title..".","Numbers2Notes",0) end
end
local function launch_cue()
    local r=reaper
    local path=find_script("n2ncue")
    if not path then
        local accepted
        accepted,path=r.GetUserFileNameForRead(r.GetResourcePath().."/Scripts/","Locate installed N2NCue script",".lua")
        if not accepted then return end
    end
    local cmd=r.AddRemoveReaScript(true,0,path,true)
    if cmd and cmd>0 then r.Main_OnCommand(cmd,0) else r.MB("Could not launch N2NCue.","N2N Tracks",0) end
end
-- Topline is region based, rather than a library of repeating A-D patterns.
local function valid_topline(t)
    return reaper.ValidatePtr2(reaper.EnumProjects(-1,""),t.track,"MediaTrack*")
        and reaper.GetTrackGUID(t.track)==t.guid
end
local function launch_topline(t,region)
    local r=reaper
    if not valid_topline(t) then return end
    local project=r.EnumProjects(-1,"")
    local sec="N2N_TOPLINE_HUB"
    local owner=r.GetExtState(sec,"owner")
    local heartbeat=tonumber(r.GetExtState(sec,"heartbeat"))
    local running=owner~="" and heartbeat and math.abs(r.time_precise()-heartbeat)<2
    if running and owner:match("^[^\t]+")~=tostring(project) then
        r.MB("Close Topline in the other project before opening this track.","N2N Topline",0)
        return
    end
    local path
    if not running then
        if r.JS_Window_Find and r.JS_Window_Find("N2N Topline",true) then
            r.MB("Close the existing Topline window and reopen it from Tracks to enable navigation.","N2N Topline",0)
            return
        end
        -- Prefer the script beside this package before searching other scripts.
        local source=debug.getinfo(1,"S").source:sub(2)
        local dir=source:match("^(.*[/\\])")
        local sibling=dir and dir.."../N2N Topline.lua"
        if sibling then local file=io.open(sibling,"rb"); if file then file:close(); path=sibling end end
        path=path or find_script("n2ntopline")
        if not path then
            r.MB("Install N2N Topline.lua first.","N2N Tracks",0)
            return
        end
    end
    r.GetSetMediaTrackInfo_String(t.track,"P_EXT:N2N:TOPLINE","1",true)
    r.SetExtState(sec,"request",table.concat({tostring(project),t.guid,tostring(region or -1),tostring(r.time_precise())},"\t"),false)
    if not running then
        local cmd=r.AddRemoveReaScript(true,0,path,true)
        if cmd and cmd>0 then r.Main_OnCommand(cmd,0)
        else r.DeleteExtState(sec,"request",false); r.MB("Could not launch N2N Topline.","N2N Tracks",0) end
    end
end
local function topline_regions()
    local r=reaper
    local list,i={},0
    while true do
        local ok,is_region,pos,ending,name,id,native=r.EnumProjectMarkers3(0,i)
        if ok==0 then break end
        if is_region and ending>pos then
            local rr,gg,bb=.45,.52,.62
            if native and native~=0 then local a,b,c=r.ColorFromNative(native); rr,gg,bb=a/255,b/255,c/255 end
            list[#list+1]={pos=pos,id=id,name=name~="" and name or "Region "..id,r=rr,g=gg,b=bb}
        end
        i=i+1
    end
    table.sort(list,function(a,b) return a.pos==b.pos and a.id<b.id or a.pos<b.pos end)
    return list
end
local function topline_grid(ctx,t,regions,width,scale,gap)
    local r=reaper
    local x=r.ImGui_GetCursorPosX(ctx)
    local cols=7
    local w=(width-(cols-1)*gap)/cols
    local h=math.floor(10*scale+.5)
    if #regions==0 then
        r.ImGui_TextDisabled(ctx,"No song regions. Render the song form first.")
        return
    end
    for i,sec in ipairs(regions) do
        if (i-1)%cols~=0 then r.ImGui_SameLine(ctx) else r.ImGui_SetCursorPosX(ctx,x) end
        local label=sec.name:gsub("Pre%-Chorus","Pre"):gsub("Breakdown","Break"):gsub("Count%-In","Count")
        while #label>0 and r.ImGui_CalcTextSize(ctx,label)>w-4 do
            local p=utf8.offset(label,-1); label=label:sub(1,(p or #label)-1)
        end
        r.ImGui_PushStyleColor(ctx,r.ImGui_Col_Button(),color(sec.r,sec.g,sec.b))
        r.ImGui_PushStyleColor(ctx,r.ImGui_Col_ButtonHovered(),color(math.min(1,sec.r+.12),math.min(1,sec.g+.12),math.min(1,sec.b+.12)))
        r.ImGui_PushStyleColor(ctx,r.ImGui_Col_ButtonActive(),color(sec.r*.85,sec.g*.85,sec.b*.85))
        r.ImGui_PushStyleColor(ctx,r.ImGui_Col_Text(),(sec.r*.299+sec.g*.587+sec.b*.114)>.55 and 0x101010FF or 0xFFFFFFFF)
        if r.ImGui_Button(ctx,label.."##topline_region_"..sec.id,w,h) then launch_topline(t,sec.id) end
        r.ImGui_PopStyleColor(ctx,4)
        if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx,sec.name.."\nOpen this region in N2N Topline") end
    end
end
-- Independent Tracks-tab zoom. Fonts are attached once, outside the frame.
local TRACK_SCALE_MIN, TRACK_SCALE_MAX, TRACK_SCALE_STEP, TRACK_SCALE_DEFAULT = 75, 175, 5, 170
local track_scale = tonumber(reaper.GetExtState("Numbers2Notes","TracksPanelScale")) or TRACK_SCALE_DEFAULT
track_scale = math.max(TRACK_SCALE_MIN, math.min(TRACK_SCALE_MAX,
    math.floor(track_scale/TRACK_SCALE_STEP+.5)*TRACK_SCALE_STEP))
local track_fonts, track_small_fonts = {}, {}
-- Header rectangle widths in unscaled pixels, in display order.
-- The five footer fields show/edit their actual scaled pixel widths.
-- User-approved widths at 170%; normalize to the zoom reference.
local header_defaults={278/1.7,91/1.7,91/1.7,44/1.7,44/1.7}
local HEADER_WIDTH_KEY="TracksHeaderWidthV2"
local header_widths={}
for i,default in ipairs(header_defaults) do
    header_widths[i]=math.max(10,math.min(500,tonumber(reaper.GetExtState("Numbers2Notes",HEADER_WIDTH_KEY..i)) or default))
end
function export.InitTrackFonts(ctx, family, normal_size, small_size)
    local cache = {}
    local function font_at(size)
        size=math.max(7,math.floor(size+.5))
        if not cache[size] then
            cache[size]=reaper.ImGui_CreateFont(family,size)
            reaper.ImGui_Attach(ctx,cache[size])
        end
        return cache[size]
    end
    for percent=TRACK_SCALE_MIN,TRACK_SCALE_MAX,TRACK_SCALE_STEP do
        -- Shorter header row, smaller header font; pattern labels unchanged.
        local text_scale=.85+(percent-100)*.002
        track_fonts[percent]=font_at(normal_size*text_scale)
        track_small_fonts[percent]=font_at(small_size*(1+(percent-100)*.003))
    end
end
local function adjust_track_scale(delta)
    track_scale=math.max(TRACK_SCALE_MIN,math.min(TRACK_SCALE_MAX,track_scale+delta))
    reaper.SetExtState("Numbers2Notes","TracksPanelScale",tostring(track_scale),true)
end
local function pattern_grid(ctx,t,width,scale,gap)
    local r=reaper
    local dl=r.ImGui_GetWindowDrawList(ctx)
    local x,y=r.ImGui_GetCursorScreenPos(ctx)
    -- Seven section groups separated by the same gap as the header.
    -- The final two single-button groups each get half a full group.
    local groupw=(width-6*gap)/6
    local lastw=groupw/2
    local h=math.floor(10*scale+.5)
    local known=t.id>=1 and t.id<=512 and duplicate[t.id]==1 and r.gmem_read(REG_BASE+t.id)>0 and r.TrackFX_GetEnabled(t.track,t.fx) and not r.TrackFX_GetOffline(t.track,t.fx)
    local bits={}
    if known then for i=0,3 do bits[i]=math.floor(r.gmem_read(INV_BASE+(t.id-1)*4+i)) end end
    local mx,my=r.ImGui_GetMousePos(ctx)
    local hovered
    for row,gs in ipairs(groups) do
        for gi,g in ipairs(gs) do
            local gx=x+(gi<=5 and (gi-1)*(groupw+gap) or 5*(groupw+gap)+(gi-6)*(lastw+gap))
            local gw=gi<=5 and groupw or lastw
            local first=g[2]==4 and math.min(15*scale,gw*.4,(gw-3*gap)*.55) or gw
            local mini=(gw-first-3*gap)/3
            for v=0,g[2]-1 do
                local bx=gx+(v==0 and 0 or first+gap+(v-1)*(mini+gap))
                local bw=v==0 and first or mini
                local by=y+(row-1)*(h+gap)
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
    r.ImGui_InvisibleButton(ctx,"##pattern_grid",width,3*h+2*gap+math.max(0,math.floor(2*scale+.5)+2*math.floor(scale+.5)-2*gap))
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
export.ToplineFooterLauncher=true
function export.DrawTracks(ctx,font,open_topline)
    local r=reaper
    local percent=track_scale
    local scale=percent/100
    local normal_font=track_fonts[percent]
    local small_font=track_small_fonts[percent] or font
    local function px(n) return math.max(1,math.floor(n*scale+.5)) end
    export.PublishTrackIdentity(false)
    -- Match the Render Feedback tab's heading and 592 x 598 content area.
    local panel_width,panel_height=592,598
    local footer_height,footer_gap=22,5
    -- The original Render box is the TOTAL vertical budget, including footer.
    local list_height=panel_height-footer_height-footer_gap-4
    r.ImGui_Dummy(ctx,0,0)
    r.ImGui_TextColored(ctx,0xE6E6E6FF,"Tracks:")
    r.ImGui_SameLine(ctx)
    local conflict_count=0
    for id,n in pairs(duplicate) do if n>1 or id<1 or id>512 then conflict_count=conflict_count+1 end end
    if conflict_count>0 then
        r.ImGui_TextColored(ctx,0xFF7777FF,("%d ID conflict(s)"):format(conflict_count))
    else r.ImGui_TextColored(ctx,0xA0E0A0FF,("%d instances | IDs OK"):format(#tracks)) end
    r.ImGui_SameLine(ctx)
    r.ImGui_PushStyleVar(ctx,r.ImGui_StyleVar_FramePadding(),2,0)
    if r.ImGui_SmallButton(ctx,"Refresh") then export.PublishTrackIdentity(true) end
    r.ImGui_PopStyleVar(ctx)
    local box_x=r.ImGui_GetCursorPosX(ctx)
    if normal_font then r.ImGui_PushFont(ctx,normal_font) end
    -- Four pixels at 170%: old two-pixel vertical gap plus two.
    -- All intra-track gaps, including between variants, are identical.
    local track_gap=math.max(1,math.floor(4*percent/170+.5))
    r.ImGui_PushStyleVar(ctx,r.ImGui_StyleVar_ItemSpacing(),track_gap,track_gap)
    r.ImGui_PushStyleVar(ctx,r.ImGui_StyleVar_FramePadding(),px(2),px(1))
    r.ImGui_PushStyleVar(ctx,r.ImGui_StyleVar_WindowPadding(),4,4)
    r.ImGui_PushStyleColor(ctx,r.ImGui_Col_ChildBg(),0x000000FF)
    local row_height=px(14)
    local actual_widths={}
    local max_header_width=0
    local border_flag=r.ImGui_ChildFlags_Borders and r.ImGui_ChildFlags_Borders()
        or r.ImGui_ChildFlags_Border and r.ImGui_ChildFlags_Border() or true
    local visible=r.ImGui_BeginChild(ctx,"##N2NTrackScroll",panel_width,list_height,border_flag,r.ImGui_WindowFlags_AlwaysVerticalScrollbar())
    if visible then
        -- Measure once at the child's starting cursor, not after the previous
        -- track's buttons or separator. All tracks share one fixed geometry.
        local row_x=r.ImGui_GetCursorPosX(ctx)
        local available=r.ImGui_GetContentRegionAvail(ctx)
        max_header_width=math.floor(available-4*track_gap)
        local total=0
        for i,v in ipairs(header_widths) do actual_widths[i]=px(v); total=total+actual_widths[i] end
        -- Fit a narrower host viewport without letting the header overflow.
        if total>max_header_width then
            local overflow=total-max_header_width
            for i=1,5 do
                local reduction=math.min(overflow,math.max(0,actual_widths[i]-px(10)))
                actual_widths[i]=actual_widths[i]-reduction
                overflow=overflow-reduction
            end
        end
        local namew,arpw,instw,idw,fxw=table.unpack(actual_widths)
        local width=namew+arpw+instw+idw+fxw+4*track_gap
        -- Avoid shrinking the pattern buttons to an unusable width when
        -- experimenting with exceptionally narrow header fields.
        local pattern_width=math.min(available,math.max(width,px(200)))
        local regions
        for _,t in ipairs(tracks) do
            local top=t.kind=="Topline"
            local fx=not top and locate(t)
            if (top and valid_topline(t)) or fx then
                if not top then t.fx=fx end
                r.ImGui_SetCursorPosX(ctx,row_x)
                r.ImGui_PushID(ctx,t.guid)
                local label=("%d. %s"):format(t.number,t.name)
                if r.ImGui_CalcTextSize(ctx,label)>namew-px(4) then
                    while #label>0 and r.ImGui_CalcTextSize(ctx,label.."…")>namew-px(4) do
                        local pos=utf8.offset(label,-1)
                        label=label:sub(1,(pos or #label)-1)
                    end
                    label=label.."…"
                end
                local lum=t.r*.299+t.g*.587+t.b*.114
                -- Entire header uses the track's color, including hover/press.
                r.ImGui_PushStyleColor(ctx,r.ImGui_Col_Button(),color(t.r,t.g,t.b))
                r.ImGui_PushStyleColor(ctx,r.ImGui_Col_ButtonHovered(),color(math.min(1,t.r+.12),math.min(1,t.g+.12),math.min(1,t.b+.12)))
                r.ImGui_PushStyleColor(ctx,r.ImGui_Col_ButtonActive(),color(t.r*.85,t.g*.85,t.b*.85))
                r.ImGui_PushStyleColor(ctx,r.ImGui_Col_Text(),lum>.55 and 0x101010FF or 0xFFFFFFFF)
                r.ImGui_PushStyleVar(ctx,r.ImGui_StyleVar_ButtonTextAlign(),0,.5)
                if r.ImGui_Button(ctx,label,namew,row_height) then
                    r.SetOnlyTrackSelected(t.track)
                    r.TrackList_AdjustWindows(false)
                end
                r.ImGui_PopStyleVar(ctx)
                if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx,t.name) end
                r.ImGui_SameLine(ctx)
                if r.ImGui_Button(ctx,t.kind,arpw,row_height) then
                    if top then launch_topline(t) else open_fx(t.track,fx) end
                end
                r.ImGui_SameLine(ctx)
                local inst=r.TrackFX_GetInstrument(t.track)
                if inst<0 or inst==fx then r.ImGui_BeginDisabled(ctx) end
                if r.ImGui_Button(ctx,"Instrument",top and instw+idw+track_gap or instw,row_height) then open_fx(t.track,inst) end
                if inst<0 or inst==fx then r.ImGui_EndDisabled(ctx) end
                if not top then
                r.ImGui_SameLine(ctx)
                local bad=(duplicate[t.id] or 0)>1 or t.id<1 or t.id>512
                if bad then
                    r.ImGui_PushStyleVar(ctx,r.ImGui_StyleVar_FrameBorderSize(),2)
                    r.ImGui_PushStyleColor(ctx,r.ImGui_Col_Border(),0xFF3333FF)
                end
                if r.ImGui_Button(ctx,"ID "..t.id,idw,row_height) then id_popup=t; id_popup_open=true; id_suggestion=find_free_id() end
                if bad then
                    r.ImGui_PopStyleColor(ctx)
                    r.ImGui_PopStyleVar(ctx)
                    if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx,"Instance ID conflict") end
                end
                end
                r.ImGui_SameLine(ctx)
                -- Hover alone opens the interactive flyout. There is no click-open menu.
                r.ImGui_Button(ctx,"FX",fxw,row_height)
                if r.ImGui_IsItemHovered(ctx) then
                    if not fx_hover or fx_hover.guid~=t.guid then
                        local right=r.ImGui_GetItemRectMax(ctx)
                        local _,top=r.ImGui_GetItemRectMin(ctx)
                        hover_pos={right+3,top}
                    end
                    fx_hover=t
                    hover_until=r.time_precise()+.5
                end
                r.ImGui_PopStyleColor(ctx,4)
                r.ImGui_SetCursorPosX(ctx,row_x)
                if small_font then r.ImGui_PushFont(ctx,small_font) end
                if top then
                    regions=regions or topline_regions()
                    topline_grid(ctx,t,regions,pattern_width,scale,track_gap)
                else pattern_grid(ctx,t,pattern_width,scale,track_gap) end
                if small_font then r.ImGui_PopFont(ctx) end
                r.ImGui_SetCursorPosX(ctx,row_x)
                r.ImGui_Separator(ctx)
                r.ImGui_PopID(ctx)
            end
        end
        r.ImGui_EndChild(ctx)
    end
    r.ImGui_PopStyleColor(ctx)
    r.ImGui_PopStyleVar(ctx,3)
    if normal_font then r.ImGui_PopFont(ctx) end
    -- Launch advanced cueing in place of the temporary width fields.
    -- Draw both launchers consecutively, separated by a real layout spacer.
    local zoom_button,readout_width,launcher_width=24,52,196
    local topline_width=math.max(220,r.ImGui_CalcTextSize(ctx,"Open N2N Topline Editor")+12)
    local spacer=math.max(1,math.floor((panel_width-launcher_width-topline_width-2*zoom_button-readout_width-18)/2))
    local readout=("%d%%"):format(percent)
    r.ImGui_PushStyleVar(ctx,r.ImGui_StyleVar_ItemSpacing(),3,1)
    r.ImGui_PushStyleVar(ctx,r.ImGui_StyleVar_FramePadding(),2,2)
    r.ImGui_SetCursorPosY(ctx,r.ImGui_GetCursorPosY(ctx)+footer_gap)
    r.ImGui_SetCursorPosX(ctx,box_x)
    if r.ImGui_Button(ctx,"N2N Advanced Cueing",launcher_width,footer_height) then launch_cue() end
    if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx,"Open N2NCue for manual cue placement and live cueing") end
    r.ImGui_SameLine(ctx)
    r.ImGui_Dummy(ctx,spacer,1)
    r.ImGui_SameLine(ctx)
    if r.ImGui_Button(ctx,"Open N2N Topline Editor",topline_width,footer_height) then
        if open_topline then open_topline() else export.OpenEditor("n2ntopline","N2N Topline") end
    end
    r.ImGui_SameLine(ctx)
    r.ImGui_Dummy(ctx,spacer,1)
    r.ImGui_SameLine(ctx)
    if percent<=TRACK_SCALE_MIN then r.ImGui_BeginDisabled(ctx) end
    if r.ImGui_Button(ctx,"-##track_zoom",zoom_button,footer_height) then adjust_track_scale(-TRACK_SCALE_STEP) end
    if percent<=TRACK_SCALE_MIN then r.ImGui_EndDisabled(ctx) end
    r.ImGui_SameLine(ctx)
    if r.ImGui_Button(ctx,readout.."##track_zoom_reset",readout_width,footer_height) then adjust_track_scale(TRACK_SCALE_DEFAULT-percent) end
    if r.ImGui_IsItemHovered(ctx) then
        r.ImGui_SetTooltip(ctx,("Tracks size: %d%% | Target row width: %.0f px\nClick to reset to %d%%"):format(percent,px(340),TRACK_SCALE_DEFAULT))
    end
    r.ImGui_SameLine(ctx)
    if percent>=TRACK_SCALE_MAX then r.ImGui_BeginDisabled(ctx) end
    if r.ImGui_Button(ctx,"+##track_zoom",zoom_button,footer_height) then adjust_track_scale(TRACK_SCALE_STEP) end
    if percent>=TRACK_SCALE_MAX then r.ImGui_EndDisabled(ctx) end
    r.ImGui_PopStyleVar(ctx,2)
    if id_popup then
        if id_popup_open then r.ImGui_OpenPopup(ctx,"N2N Instance ID"); id_popup_open=false end
        if r.ImGui_BeginPopupModal(ctx,"N2N Instance ID",nil,r.ImGui_WindowFlags_AlwaysAutoResize()) then
            local t=id_popup
            local fx=locate(t)
            r.ImGui_Text(ctx,t.name.." | "..t.kind.." | ID "..t.id)
            for _,other in ipairs(tracks) do
                if other.id==t.id and other.guid~=t.guid then r.ImGui_TextColored(ctx,0xFF7777FF,"Conflict: "..other.name.." ("..other.kind..")") end
            end
            r.ImGui_TextWrapped(ctx,"Assign a free ID while transport is stopped. Existing patterns are preserved.")
            local free=id_suggestion
            local disabled=not fx or not free or r.GetPlayState()~=0
            if disabled then r.ImGui_BeginDisabled(ctx) end
            if r.ImGui_Button(ctx,free and ("Assign ID "..free) or "No free registered ID") then
                local now_free=find_free_id()
                if now_free==free then
                    r.Undo_BeginBlock()
                    local ok=r.TrackFX_SetParam(t.track,fx,4,free)
                    r.Undo_EndBlock("N2N: Reassign arranger instance ID",-1)
                    export.PublishTrackIdentity(true)
                    if ok then id_popup=nil; r.ImGui_CloseCurrentPopup(ctx)
                    else r.MB("The instance rejected the ID change.","N2N Tracks",0) end
                else id_suggestion=now_free end
            end
            if disabled then r.ImGui_EndDisabled(ctx) end
            r.ImGui_SameLine(ctx)
            if r.ImGui_Button(ctx,"Close") then id_popup=nil; r.ImGui_CloseCurrentPopup(ctx) end
            r.ImGui_EndPopup(ctx)
        else id_popup=nil end
    end
    -- Use an input-capable floating window, rather than a menu or a
    -- standard tooltip (which cannot receive clicks reliably).
    if id_popup then fx_hover=nil end
    if fx_hover and r.time_precise()<=hover_until and
        ((fx_hover.kind=="Topline" and valid_topline(fx_hover)) or locate(fx_hover)) then
        local t=fx_hover
        r.ImGui_SetNextWindowPos(ctx,hover_pos[1],hover_pos[2])
        local flags=r.ImGui_WindowFlags_NoTitleBar()|r.ImGui_WindowFlags_AlwaysAutoResize()|r.ImGui_WindowFlags_NoSavedSettings()|r.ImGui_WindowFlags_NoFocusOnAppearing()|r.ImGui_WindowFlags_NoMove()|r.ImGui_WindowFlags_NoResize()
        local vis=r.ImGui_Begin(ctx,"##N2NHoverFX",nil,flags)
        if vis then
            -- Keep the flyout alive as the mouse travels from the FX
            -- button into the window or interacts with its rows.
            if r.ImGui_IsWindowHovered(ctx) then hover_until=r.time_precise()+.5 end
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
                    hover_until=r.time_precise()+.5
                end
                r.ImGui_PopStyleColor(ctx)
                r.ImGui_PopID(ctx)
            end
            r.ImGui_Separator(ctx)
            r.ImGui_TextDisabled(ctx,"Click: Open   Shift+Click: Bypass")
            r.ImGui_End(ctx)
        end
    else fx_hover=nil end
end


-- =========================================================
-- Drum pattern-set backup: immutable per-section files and complete manifests.
-- No REAPER FX presets, state-chunk replacement, or executable serialization.
-- =========================================================
local drum_bank={base=6600000,data=6604096,maxvalues=65544,interval=30,keep=8,
    due={},observed={},poll=0,serial=0}
local DB=drum_bank
DB.setsig="N2N_DRUM_SET 1\n"
DB.idxsig="N2N_DRUM_INDEX 1\n"
function DB.slot(id) return DB.base+32+(id-1)*4 end
function DB.status(id,value) reaper.gmem_write(DB.base+2080+id,value) end
function DB.safe_id(value)
    local v=tostring(value or ""):gsub("[^%w%-]","")
    if v=="" then error("Missing project, track or FX identity",0) end
    return v
end
function DB.project_id(project)
    local r=reaper
    local _,path=r.EnumProjects(-1,"")
    local ok,id=r.GetProjExtState(project,"N2N_DrumSet","id")
    local _,oldpath=r.GetProjExtState(project,"N2N_DrumSet","path")
    -- Save As creates an independent backup family; the first Save of an
    -- unsaved project keeps its original ID. Store the identity in the RPP.
    if ok==0 or id=="" or (oldpath~="" and path~="" and oldpath~=path) then
        id=r.genGuid()
        r.SetProjExtState(project,"N2N_DrumSet","id",id)
        r.MarkProjectDirty(project)
    end
    if path~=oldpath then
        r.SetProjExtState(project,"N2N_DrumSet","path",path)
        r.MarkProjectDirty(project)
    end
    return DB.safe_id(id)
end
function DB.folder(project,t)
    local r=reaper
    local dir=r.GetResourcePath().."/Data/AHS_Music_Tech/DrumArranger/Backups/"
        ..DB.project_id(project).."/"..DB.safe_id(r.GetTrackGUID(t.track)).."_"..DB.safe_id(t.guid)
    r.RecursiveCreateDirectory(dir,0)
    return dir
end
function DB.kit(t)
    local fx=locate(t)
    if fx==nil then error("Drum Arranger no longer exists",0) end
    local _,name=reaper.TrackFX_GetFormattedParamValue(t.track,fx,9,"")
    return name or ""
end
function DB.read(path,limit)
    local f,err=io.open(path,"rb")
    if not f then error(err or ("Cannot open "..path),0) end
    local data=f:read(limit+1);f:close()
    if not data or #data>limit then error("Invalid or oversized drum set file: "..path,0) end
    return data
end
function DB.write_new(path,data)
    local tmp=path..".tmp"
    local f,err=io.open(tmp,"wb")
    if not f then error(err or "Cannot write drum backup",0) end
    local ok,why=f:write(data);local closed,cerr=f:close()
    if not ok or not closed then os.remove(tmp);error(why or cerr or "Incomplete drum backup",0) end
    local renamed,msg=os.rename(tmp,path)
    if not renamed then os.remove(tmp);error(msg or "Cannot finalize drum backup",0) end
end
function DB.write_manual(path,data)
    local f=io.open(path,"rb")
    if not f then DB.write_new(path,data);return end
    f:close()
    -- Preserve the previous file even on Windows, where rename does not
    -- replace an existing destination. User already confirmed overwrite.
    local old=path..".old_"..DB.safe_id(reaper.genGuid())
    local moved,err=os.rename(path,old)
    if not moved then error(err or "Cannot protect previous pattern set",0) end
    local ok,why=pcall(DB.write_new,path,data)
    if not ok then os.rename(old,path);error(why,0) end
    os.remove(old)
end
function DB.values(data,record)
    if type(data)~="string" or #data%8~=0 or #data>DB.maxvalues*8 then error("Invalid drum record size",0) end
    local a={}
    for i=1,#data,8 do
        local v=string.unpack("<d",data,i)
        if not valid_number(v,-1000000,1000000) then error("Invalid number in drum record",0) end
        a[#a+1]=v
    end
    local function integer(v,lo,hi) return valid_number(v,lo,hi) and v%1==0 end
    if record==-1 then
        if #a<1417 or #a>35000 then error("Invalid drum settings record",0) end
        local ranges={{1,127},{0,25},{0,4},{1,4},{0,100},{1,128},{0,128},{0,1},{10,30}}
        for i,v in ipairs(ranges) do if not valid_number(a[i],v[1],v[2]) then error("Invalid drum global setting",0) end end
        for row=1,128 do
            if not integer(a[9+256+row],-1,127) or not integer(a[9+384+row],1,16) then error("Invalid drum row map",0) end
        end
        local pos=1290
        for row=1,128 do
            local n=a[pos]
            if not integer(n,0,255) or pos+n>#a then error("Invalid drum row name",0) end
            for j=1,n do if not integer(a[pos+j],0,255) then error("Invalid drum row name byte",0) end end
            pos=pos+n+1
        end
        if pos~=#a+1 then error("Invalid trailing row settings",0) end
    else
        if #a<7 or not integer(a[7],0,16384) or #a~=7+a[7]*4 then error("Invalid drum section record",0) end
        if not integer(a[1],0,4) or not integer(a[2],-1,4) or not valid_number(a[3],-1,25)
            or not valid_number(a[4],-1,100) or not integer(a[5],0,1) or not integer(a[6],0,3) then error("Invalid section settings",0) end
        local last=-1
        for i=8,#a,4 do
            if not integer(a[i],0,16383) or a[i]<=last or not valid_number(a[i+1],0,127)
                or not valid_number(a[i+2],0,127) or not valid_number(a[i+3],0,1000000) then error("Invalid drum step",0) end
            last=a[i]
        end
    end
    return a
end
function DB.pack_set(snapshot)
    local out={DB.setsig,string.pack("<s4",snapshot.kit)}
    for i=1,81 do out[#out+1]=string.pack("<s4",snapshot.records[i]) end
    return table.concat(out)
end
function DB.unpack_set(data)
    if data:sub(1,#DB.setsig)~=DB.setsig then error("Not an N2N drum pattern set",0) end
    local kit,pos=string.unpack("<s4",data,#DB.setsig+1)
    if #kit>4096 then error("Invalid kit name",0) end
    local snapshot={kit=kit,records={}}
    for i=1,81 do
        local blob;blob,pos=string.unpack("<s4",data,pos)
        DB.values(blob,i-2)
        snapshot.records[i]=blob
    end
    if pos~=#data+1 then error("Unexpected data in drum pattern set",0) end
    return snapshot
end
function DB.list(dir,prefix)
    local r=reaper
    local out={}
    r.EnumerateFiles(dir,-1)
    local i=0
    while true do
        local name=r.EnumerateFiles(dir,i)
        if not name then break end
        if name:match("^"..prefix.."_%d+%.n2idx$") then out[#out+1]=name end
        i=i+1
    end
    table.sort(out,function(a,b) return a>b end)
    return out
end
function DB.index(dir,name,load_records)
    local data=DB.read(dir.."/"..name,16384)
    if data:sub(1,#DB.idxsig)~=DB.idxsig then error("Invalid drum backup index",0) end
    local key,epoch,kit,pos=string.unpack("<dds4",data,#DB.idxsig+1)
    if #kit>4096 then error("Invalid backup kit name",0) end
    local a={kit=kit,key=key,epoch=epoch,names={},records={},index=data}
    for i=1,81 do
        local file;file,pos=string.unpack("<s4",data,pos)
        if not file:match("^record_%d+_%d+%.bin$") then error("Invalid drum backup record name",0) end
        a.names[i]=file
        if load_records then
            local blob=DB.read(dir.."/"..file,DB.maxvalues*8)
            DB.values(blob,i-2)
            a.records[i]=blob
        end
    end
    if pos~=#data+1 then error("Invalid drum backup index tail",0) end
    return a
end
function DB.cleanup(dir)
    local names=DB.list(dir,"manifest")
    local pins=DB.list(dir,"protected")
    local refs={}
    -- Only prune after *every* retained index is readable. Never remove an
    -- old section blob still referenced by a retained backup.
    local function preserve(name)
        local a=DB.index(dir,name,false)
        for _,file in ipairs(a.names) do refs[file]=true end
    end
    for i=1,math.min(DB.keep,#names) do preserve(names[i]) end
    if pins[1] then preserve(pins[1]) end
    for i=DB.keep+1,#names do
        if not os.remove(dir.."/"..names[i]) then return end
    end
    for i=2,#pins do if not os.remove(dir.."/"..pins[i]) then return end end
    local files={}
    reaper.EnumerateFiles(dir,-1)
    local i=0
    while true do
        local name=reaper.EnumerateFiles(dir,i)
        if not name then break end
        if name:match("^record_%d+_%d+%.bin$") and not refs[name] then files[#files+1]=name end
        i=i+1
    end
    for _,name in ipairs(files) do os.remove(dir.."/"..name) end
end
function DB.commit_backup(session)
    local dir,records=session.dir,session.records
    local list=DB.list(dir,"manifest")
    local previous=list[1] and DB.index(dir,list[1],true) or nil
    local changed=not previous or previous.kit~=session.kit
    for i=1,81 do if not previous or records[i]~=previous.records[i] then changed=true;break end end
    local observed=DB.observed[dir] or previous
    if not changed then DB.observed[dir]={key=session.key,epoch=session.epoch};return end
    local last=list[1] and tonumber(list[1]:match("_(%d+)")) or 0
    local pins=DB.list(dir,"protected")
    local lastpin=pins[1] and tonumber(pins[1]:match("_(%d+)")) or 0
    local revision=string.format("%015.0f",math.max(os.time()*1000,last+1,lastpin+1))
    local refs={}
    -- State loads (including native presets/undo/project reopen) may replace
    -- every section. Pin the last pre-load snapshot before advancing Latest.
    if previous and observed and (observed.key~=session.key or observed.epoch~=session.epoch) then
        DB.write_new(dir.."/protected_"..revision..".n2idx",previous.index)
    end
    for i=1,81 do
        if previous and records[i]==previous.records[i] then refs[i]=previous.names[i]
        else
            local file="record_"..revision.."_"..i..".bin"
            DB.write_new(dir.."/"..file,records[i])
            refs[i]=file
        end
    end
    local out={DB.idxsig,string.pack("<dds4",session.key,session.epoch,session.kit)}
    for _,file in ipairs(refs) do out[#out+1]=string.pack("<s4",file) end
    -- Publish a complete manifest last; incomplete writes never replace Latest.
    DB.write_new(dir.."/manifest_"..revision..".n2idx",table.concat(out))
    DB.observed[dir]={key=session.key,epoch=session.epoch}
    pcall(DB.cleanup,dir)
end
function DB.send(session,op,record,blob)
    local r=reaper
    if r.gmem_read(DB.base)~=0 then error("Drum-set transfer mailbox is occupied",0) end
    local values=blob and DB.values(blob,record) or nil
    if values then for i,v in ipairs(values) do r.gmem_write(DB.data+i-1,v) end end
    r.gmem_write(DB.base+1,session.id);r.gmem_write(DB.base+2,session.key)
    r.gmem_write(DB.base+3,record or -1);r.gmem_write(DB.base+4,values and #values or 0)
    r.gmem_write(DB.base+5,0);r.gmem_write(DB.base+6,session.token)
    session.pending=op;session.deadline=r.time_precise()+4
    r.gmem_write(DB.base,op)
end
function DB.live(session)
    local r=reaper
    if r.EnumProjects(-1,"")~=session.project or r.gmem_read(REG_BASE+session.id)~=session.key then return false end
    local fx=locate(session.t)
    if fx==nil or math.floor(r.TrackFX_GetParam(session.t.track,fx,4)+.5)~=session.id then return false end
    local addr=DB.slot(session.id)
    return r.gmem_read(addr)==session.key and math.abs(r.time_precise()-r.gmem_read(addr+1))<4
end
function DB.abort(message)
    local r=reaper
    local s=DB.active
    if not s then return end
    if r.gmem_read(DB.base+6)==s.token then r.gmem_write(DB.base,0) end
    DB.status(s.id,-1)
    DB.due[s.duekey]=r.time_precise()+DB.interval
    DB.active=nil
    if s.manual then r.MB(tostring(message),"Drum Pattern Set",0) end
end
function DB.finish(session)
    DB.status(session.id,1)
    DB.due[session.duekey]=reaper.time_precise()+DB.interval
    DB.active=nil
end
function DB.manual_choice(session,cmd)
    local r=reaper
    local dir=r.GetResourcePath().."/Data/AHS_Music_Tech/DrumArranger/Pattern Sets"
    r.RecursiveCreateDirectory(dir,0)
    if cmd==1 then
        local accepted,name=r.GetUserInputs("Save Drum Pattern Set",1,"Set name:","My Arrangement")
        if not accepted then return false end
        name=name:match("^%s*(.-)%s*$")
        if name=="" or name=="." or name==".." or name:find("[/\\:*?\"<>|%c]") then error("Invalid pattern set name",0) end
        if name:sub(-10):lower()~=".n2drumset" then name=name..".n2drumset" end
        session.savepath=dir.."/"..name
        local f=io.open(session.savepath,"rb")
        if f then f:close();if r.MB("Replace the existing pattern set?","Save Pattern Set",4)~=6 then return false end end
    else
        if r.GetPlayStateEx(session.project)~=0 then error("Stop playback before loading or restoring a drum pattern set.",0) end
        if cmd==2 then
            local accepted,path=browse_pattern_file(dir,"Load Drum Pattern Set",".n2drumset")
            if not accepted then return false end
            session.target=DB.unpack_set(DB.read(path,45000000))
        else
            local names=DB.list(session.dir,cmd==5 and "protected" or "manifest")
            local name=names[cmd==4 and 2 or 1]
            if not name then error("No matching recovery backup exists yet.",0) end
            session.target=DB.index(session.dir,name,true)
        end
        if session.target.kit~=session.kit then
            error("This set uses drum map:\n"..session.target.kit.."\n\nSelect that file in Drum Arranger first, then try again. No patterns were changed.",0)
        end
        if r.MB("Replace all section patterns and row settings? The current arrangement will be backed up first.","Load Drum Pattern Set",4)~=6 then return false end
    end
    return true
end
function DB.begin(project,t,cmd,key)
    local r=reaper
    DB.serial=(DB.serial%1000000000)+1
    local token=math.floor(r.time_precise()*1000)%1000000000+DB.serial
    local session={project=project,t=t,id=t.id,key=key,token=token,manual=cmd>0,
        duekey=tostring(project)..":"..t.guid,phase="capture",record=-1,records={}}
    DB.active=session
    session.dir=DB.folder(project,t);session.kit=DB.kit(t)
    if cmd>0 and not DB.manual_choice(session,cmd) then DB.active=nil;return end
    DB.status(t.id,2)
    DB.send(session,1,-1)
end
function DB.advance(session)
    local r=reaper
    if not DB.live(session) then error("Drum Arranger became unavailable during transfer.",0) end
    local op=r.gmem_read(DB.base)
    if r.gmem_read(DB.base+6)~=session.token then error("Drum-set transfer ownership changed.",0) end
    if op==-1 then error("Drum Arranger rejected the pattern-set operation; no staged load was committed.",0) end
    local expected=session.pending==1 and 2 or session.pending==6 and 7 or 5
    if op~=expected then
        if r.time_precise()>session.deadline then error("Drum-set transfer timed out. Enable FX processing while stopped and retry.",0) end
        return
    end
    if session.phase=="capture" then
        local n=r.gmem_read(DB.base+4)
        local epoch=r.gmem_read(DB.base+5)
        if not valid_number(n,1,DB.maxvalues) or n%1~=0 then error("Invalid drum transfer size",0) end
        if session.epoch~=nil and session.epoch~=epoch then error("Drum state changed during backup; retrying on next cycle.",0) end
        session.epoch=epoch
        local parts={}
        for i=0,n-1 do parts[i+1]=string.pack("<d",r.gmem_read(DB.data+i)) end
        local blob=table.concat(parts)
        DB.values(blob,session.record)
        session.records[session.record+2]=blob
        r.gmem_write(DB.base,0)
        if session.record<79 then
            session.record=session.record+1;DB.send(session,1,session.record);return
        end
        if DB.kit(session.t)~=session.kit then error("Drum map changed during backup; retrying on next cycle.",0) end
        DB.commit_backup(session)
        if session.savepath then DB.write_manual(session.savepath,DB.pack_set(session)) end
        if not session.target then DB.finish(session);return end
        -- Begin staged load only after complete, successful pre-load backup.
        if r.GetPlayStateEx(session.project)~=0 then error("Transport started; pattern set was not loaded.",0) end
        session.phase="stage";session.record=-1
        DB.send(session,3,-1);return
    end
    r.gmem_write(DB.base,0)
    if session.pending==6 then
        r.MarkProjectDirty(session.project)
        DB.finish(session);return
    end
    if session.pending==3 then
        if r.gmem_read(DB.base+5)~=session.epoch then error("Drum state changed before load; no patterns were changed.",0) end
        session.record=-1
    else session.record=session.record+1 end
    if r.GetPlayStateEx(session.project)~=0 or DB.kit(session.t)~=session.kit then error("Transport or kit changed during load; no staged load was committed.",0) end
    if session.record<=79 then DB.send(session,4,session.record,session.target.records[session.record+2])
    else DB.send(session,6,-1) end
end
function DB.tick()
    local r=reaper
    r.gmem_attach("N2N_Ecosystem_RSKennedy")
    local now=r.time_precise()
    r.gmem_write(DB.base+8,now)
    local project=r.EnumProjects(-1,"")
    if DB.project~=project then
        if DB.active then DB.abort("Project changed; transfer cancelled.") end
        DB.project=project;DB.poll=0;r.gmem_write(DB.base,0)
    end
    if DB.active then DB.advance(DB.active);return end
    if now<DB.poll then return end
    DB.poll=now+.25
    local inventory,counts=scan(project)
    local automatic,auto_key
    for _,t in ipairs(inventory) do
        if t.kind=="DRUM" and t.id>=1 and t.id<=512 and counts[t.id]==1 then
            local addr=DB.slot(t.id)
            local key=r.gmem_read(REG_BASE+t.id)
            if key>0 and key==r.gmem_read(addr) and math.abs(now-r.gmem_read(addr+1))<3 then
                local cmd=r.gmem_read(addr+2)
                if cmd>=1 and cmd<=5 then
                    r.gmem_write(addr+2,0)
                    if math.abs(now-r.gmem_read(addr+3))<30 then DB.begin(project,t,cmd,key);return end
                end
                local due=DB.due[tostring(project)..":"..t.guid] or 0
                if not automatic and now>=due then automatic=t;auto_key=key end
            end
        end
    end
    if automatic then DB.begin(project,automatic,0,auto_key) end
end
function export.ServiceDrumPatternSets()
    local ok,err=pcall(DB.tick)
    if not ok then
        if DB.active then DB.abort(err)
        else DB.poll=reaper.time_precise()+DB.interval end
    end
end


-- Drum map is authoritative. Do not monitor instrument preset changes or
-- set a Drum Arranger FX preset: that could replace all serialized patterns.
local kit_sync={poll=0,seen={},project=nil}
function kit_sync.map_name(track,fx)
    local ok,name=reaper.TrackFX_GetFormattedParamValue(track,fx,9,"")
    if not ok then return "" end
    return (name or ""):gsub("\\","/"):match("([^/]+)$") or ""
end
function kit_sync.monster_name(name)
    local n=name:lower()
    return n:find("monster drum",1,true)~=nil
end
function kit_sync.instrument(project,track)
    local r=reaper
    local function find(t)
        local matches={}
        for fx=0,r.TrackFX_GetCount(t)-1 do
            local ok,name=r.TrackFX_GetFXName(t,fx,"")
            if ok and kit_sync.monster_name(name or "") then matches[#matches+1]=fx end
        end
        return matches
    end
    local list=find(track)
    if #list==1 then return track,list[1] end
    if #list>1 then return nil,nil,"More than one Monster Drums instance on the track" end
    local dest,destfx
    for i=0,r.GetTrackNumSends(track,0)-1 do
        if r.GetTrackSendInfo_Value(track,0,i,"B_MUTE")==0 and (math.floor(r.GetTrackSendInfo_Value(track,0,i,"I_MIDIFLAGS"))&31)~=31 then
            local d=r.GetTrackSendInfo_Value(track,0,i,"P_DESTTRACK")
            if d and r.ValidatePtr2(project,d,"MediaTrack*") then
                local m=find(d)
                if #m>1 or (#m==1 and dest and dest~=d) then return nil,nil,"Ambiguous Monster Drums destination" end
                if #m==1 then dest,destfx=d,m[1] end
            end
        end
    end
    return dest,destfx
end
function kit_sync.apply(project,t,map)
    local r=reaper
    local preset=map:gsub("%.[Tt][Xx][Tt]$","")
    -- The bundled Monster kit map names use [CATEGORY] NN Preset Name.
    -- Generic note maps and other manufacturers' kits do not imply a Monster preset.
    if not preset:match("^%[[^%]]+%]%s+%d%d%s+") then return true end
    local track,fx,why=kit_sync.instrument(project,t.track)
    if not track then return false,why or "No unambiguous Monster Drums instrument found" end
    local _,current=r.TrackFX_GetPreset(track,fx,"")
    if current==preset or current==map then return true end
    local ok=r.TrackFX_SetPreset(track,fx,preset)
    if not ok and map~=preset then ok=r.TrackFX_SetPreset(track,fx,map) end
    if not ok then return false,"Monster Drums preset not found: "..preset end
    r.MarkProjectDirty(project)
    return true
end
function export.ServiceDrumKitSync()
    local r=reaper
    r.gmem_attach("N2N_Ecosystem_RSKennedy")
    local now=r.time_precise()
    -- Also informs the optional Launchpad companion that the hub owns preset changes.
    r.gmem_write(6600009,now)
    if now<kit_sync.poll then return end
    kit_sync.poll=now+.5
    local project=r.EnumProjects(-1,"")
    if kit_sync.project~=project then kit_sync.project=project;kit_sync.seen={} end
    local inventory,counts=scan(project)
    local alive={}
    for _,t in ipairs(inventory) do
        if t.kind=="DRUM" and t.id>=1 and t.id<=512 and counts[t.id]==1 then
            local fx=locate(t)
            if fx~=nil then
                local map=kit_sync.map_name(t.track,fx)
                local guid=t.guid
                local key="map:"..guid
                local state=kit_sync.seen[guid]
                alive[guid]=true
                if not state then
                    local ok,last=r.GetProjExtState(project,"N2N_DrumKitSync",key)
                    -- First encounter establishes a baseline instead of overriding
                    -- a user's existing instrument preset on project open.
                    state={last=ok>0 and last or map}
                    kit_sync.seen[guid]=state
                    if ok==0 and map~="" then
                        r.SetProjExtState(project,"N2N_DrumKitSync",key,map)
                        r.MarkProjectDirty(project)
                    end
                end
                if map~="" and map~=state.last and r.GetPlayStateEx(project)==0 then
                    local ok,why=kit_sync.apply(project,t,map)
                    -- One attempt per deliberate selection: a missing preset must
                    -- not loop or replace an unrelated instrument.
                    state.last=map
                    r.SetProjExtState(project,"N2N_DrumKitSync",key,map)
                    r.MarkProjectDirty(project)
                    r.gmem_write(6602600+t.id,ok and 1 or -1)
                    if not ok then r.MB(why.."\n\nDrum Arranger patterns were not changed by synchronization.","N2N Drum Kit Sync",0) end
                end
            end
        end
    end
    for guid in pairs(kit_sync.seen) do if not alive[guid] then kit_sync.seen[guid]=nil end end
end

return export