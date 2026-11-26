-- @description N2N Mix - section loudness diagnostic
-- @version 0.1.0
-- @noindex
-- This prototype does not alter faders, MIDI, existing envelopes or routing.
-- It temporarily appends stereo meters, tests reporting, then removes them.
local r=reaper
local NS="N2N_Mix_Analysis_v1"
local N2N="N2N_Ecosystem_RSKennedy"
local MAX=256
local proj=r.EnumProjects(-1,"")
if not r.ImGui_CreateContext then
  r.MB("ReaImGui is required.","N2N Mix",0); return
end
local ctx=r.ImGui_CreateContext("N2N Mix - Analysis Test")
local sections,tracks={},{}
local run,token,mode=nil,0,""
local status="Ready. No faders or existing automation will be changed."
local native_stats=""
local ended=0
local restore=nil
local summary={}
local function attach() r.gmem_attach(NS) end
local function read_structure()
  -- N2N currently creates its named section regions from the form map.
  -- Its existing harmony gmem export gives us the song-end cross-check.
  local out={}
  local i=0
  while true do
    local ok,isrgn,a,b,name,id,color=r.EnumProjectMarkers3(proj,i)
    if ok==0 then break end
    if isrgn and b>a then
      out[#out+1]={a=a,b=b,name=name~="" and name or ("Region "..id),id=id,color=color}
    end
    i=i+1
  end
  table.sort(out,function(a,b) return a.a<b.a end)
  if #out==0 then return nil,"Build a Numbers2Notes arrangement with section regions first." end
  if #out>MAX then return nil,"Too many sections (maximum 256)." end
  for j,s in ipairs(out) do
    if s.a<0 or (j>1 and s.a<out[j-1].b-0.00001) then
      return nil,"Overlapping or negative-time regions are not supported in this diagnostic."
    end
  end
  r.gmem_attach(N2N)
  local cnt=math.floor(r.gmem_read(3000001) or 0)
  local qn=0
  if cnt>0 and cnt<=8192 then
    for j=0,cnt-1 do qn=math.max(qn,r.gmem_read(3000012+j*4)) end
  end
  attach()
  local msg=qn>0 and string.format("N2N harmony ends at %.2f QN; section regions end at %.2f QN.",
    qn,r.TimeMap2_timeToQN(proj,out[#out].b)) or "N2N harmony gmem not populated; using project section regions."
  return out,msg
end
local function action_by_name(name)
  local sec=r.SectionFromUniqueID(0)
  for i=0,100000 do
    local cmd,n=r.kbd_enumerateActions(sec,i)
    if not cmd or cmd<=0 then break end
    if n==name then return cmd end
  end
end
local function find_fx(row)
  if not r.ValidatePtr2(proj,row.track,"MediaTrack*") then return nil end
  for j=r.TrackFX_GetCount(row.track)-1,0,-1 do
    if r.TrackFX_GetFXGUID(row.track,j)==row.fxguid then return j end
  end
end
local function remove_meters()
  r.PreventUIRefresh(1)
  for _,t in ipairs(tracks) do
    if t.fxguid then
      local j=find_fx(t)
      if j then r.TrackFX_Delete(t.track,j) end
      t.fxguid=nil
    end
  end
  r.PreventUIRefresh(-1)
  r.UpdateArrange()
end
local function poll_reports()
  attach()
  local done,total=0,0
  for _,t in ipairs(tracks) do
    for j,s in ipairs(sections) do
      total=total+1
      local addr=4096+((t.slot-1)*256+j-1)*8
      if t.installed and r.gmem_read(addr)==token then
        local n,rate=r.gmem_read(addr+4),r.gmem_read(addr+5)
        local coverage=rate>0 and n/rate/(s.b-s.a) or 0
        t.results[j]={state=r.gmem_read(addr+1),lufs=r.gmem_read(addr+2),
          peak=r.gmem_read(addr+3),samples=n,rate=rate,windows=r.gmem_read(addr+6),
          coverage=coverage}
      end
      if t.results[j] then done=done+1 end
    end
  end
  return done,total
end
-- One writer per slot; JSFX publishes the run token after its payload.
local function restore_transport()
  if not restore then return end
  if mode=="Real time" then
    r.OnStopButtonEx(proj)
    r.GetSetRepeatEx(proj,restore.repeat_state)
    r.SetEditCurPos2(proj,restore.cursor,false,false)
  end
  if restore.a then
    r.GetSet_LoopTimeRange2(proj,true,false,restore.a,restore.b,false)
  end
  restore=nil
end
local function finish(reason)
  if not run then return end
  local done,total=poll_reports()
  attach(); r.gmem_write(0,0)
  restore_transport()
  remove_meters()
  local partial,silent,invalid=0,0,0
  for _,t in ipairs(tracks) do
    for _,v in pairs(t.results) do
      if math.abs(v.coverage-1)>0.02 then partial=partial+1 end
      if v.state==2 then silent=silent+1 end
      if v.state>=3 then invalid=invalid+1 end
    end
  end
  status=string.format("%s: %d/%d reports, %d missing, %d partial, %d below gate, %d invalid. %.2f s elapsed.",
    reason,done,total,total-done,partial,silent,invalid,r.time_precise()-run)
  run=nil
end
local function add_track(t,slot)
  local _,name=r.GetTrackName(t)
  local row={track=t,name=name,slot=slot,results={},channels=r.GetMediaTrackInfo_Value(t,"I_NCHAN")}
  -- Explicitly append a fresh instance, never reuse or overwrite an existing one.
  local at=-1000-r.TrackFX_GetCount(t)
  local fx=r.TrackFX_AddByName(t,"JS: N2N Mix Meter.jsfx",false,at)
  if fx<0 then fx=r.TrackFX_AddByName(t,"JS: N2N Mix Meter (diagnostic)",false,at) end
  if fx>=0 then
    row.fxguid=r.TrackFX_GetFXGUID(t,fx)
    r.TrackFX_SetParam(t,fx,0,0)
    r.TrackFX_SetParam(t,fx,1,slot)
    r.TrackFX_SetParam(t,fx,2,token)
    row.installed=true
  end
  return row
end
local function start(which)
  if run then return end
  if r.EnumProjects(-1,"")~=proj or r.GetPlayStateEx(proj)~=0 then
    status="Stop transport and keep this project active before testing."; return
  end
  if math.abs(r.Master_GetPlayRate(proj)-1)>0.0001 then
    status="Set project playback rate to 1.0 for this diagnostic."; return
  end
  local list,msg=read_structure()
  if not list then status=msg;return end
  local eligible={}
  for i=0,r.CountTracks(proj)-1 do
    local t=r.GetTrack(proj,i)
    if r.GetMediaTrackInfo_Value(t,"B_SHOWINMIXER")>0 then eligible[#eligible+1]=t end
  end
  if #eligible==0 or #eligible>MAX then status="Need 1 to 256 MCP-visible tracks.";return end
  local cmd
  if which=="Offline" then
    cmd=action_by_name("Calculate loudness of master mix within time selection via dry run render")
    if not cmd then status="Native master time-selection dry-run action not found. Use real time.";return end
  end
  sections,tracks,summary=list,{},{}
  native_stats=""
  mode=which
  attach()
  if r.gmem_read(0)==1 then status="Another N2N Mix analysis is armed. Close it first.";return end
  token=(math.floor(r.time_precise()*1000)%800000)+1
  if token==r.gmem_read(1) then token=token+1 end
  r.gmem_write(0,0);r.gmem_write(1,token);r.gmem_write(2,#sections)
  for j,s in ipairs(sections) do
    r.gmem_write(16+2*(j-1),s.a);r.gmem_write(17+2*(j-1),s.b)
  end
  for i=1,#eligible do
    for j=1,#sections do r.gmem_write(4096+((i-1)*256+j-1)*8,0) end
  end
  r.PreventUIRefresh(1)
  for i,t in ipairs(eligible) do tracks[i]=add_track(t,i) end
  r.PreventUIRefresh(-1)
  local installed=0
  for _,t in ipairs(tracks) do if t.installed then installed=installed+1 end end
  if installed==0 then
    status="Could not insert the diagnostic JSFX. Install Effects/N2N Mix Meter.jsfx first."
    remove_meters();return
  end
  restore={cursor=r.GetCursorPositionEx(proj),repeat_state=r.GetSetRepeatEx(proj,-1)}
  run=r.time_precise()
  ended=0
  r.gmem_write(0,1)
  status=which.." analysis: "..msg
  if which=="Real time" then
    r.GetSetRepeatEx(proj,0)
    r.SetEditCurPos2(proj,sections[1].a,false,false)
    r.OnPlayButtonEx(proj)
  else
    restore.a,restore.b=r.GetSet_LoopTimeRange2(proj,false,false,0,0,false)
    r.GetSet_LoopTimeRange2(proj,true,false,sections[1].a,sections[#sections].b+0.1,false)
    -- Defer once so the interface can display the armed state first.
    r.defer(function()
      if not run then return end
      local ok,err=pcall(function()
        local _,stats=r.GetSetProjectInfo_String(proj,"RENDER_STATS",tostring(cmd),false)
        native_stats=stats or ""
      end)
      if run then finish(ok and "Offline dry run returned" or ("Offline error: "..tostring(err))) end
    end)
  end
end
local function cell_text(t,j)
  if not t.installed and not t.results[j] then return "No FX",0xE2A070FF end
  local v=t.results[j]
  if not v then return run and "..." or "Missing",0x999999FF end
  if math.abs(v.coverage-1)>0.02 then return string.format("Partial %.0f%%",v.coverage*100),0xE2A070FF end
  if v.state==2 then return "OK: quiet",0x85C8A0FF end
  if v.state>=3 then return "Invalid",0xE2A070FF end
  return string.format("OK %.1f",v.lufs),0x85C8A0FF
end
local function copy_report()
  local a={status,"Mode: "..mode,"Track\tSection\tStatus\tLUFS-I\tSample peak dBFS\tCoverage\tSample rate\tWindows"}
  for _,t in ipairs(tracks) do for j,s in ipairs(sections) do
    local v=t.results[j]
    local label=cell_text(t,j)
    a[#a+1]=table.concat({t.name,s.name,label,v and v.state==1 and string.format("%.2f",v.lufs) or "",
      v and v.peak>-999 and string.format("%.2f",v.peak) or "",v and string.format("%.2f%%",v.coverage*100) or "",
      v and v.rate or "",v and v.windows or ""},"\t")
  end end
  if native_stats~="" then a[#a+1]="Native render stats: "..native_stats end
  r.ShowConsoleMsg(table.concat(a,"\n").."\n")
end
local function loop()
  if r.EnumProjects(-1,"")~=proj then
    if run then finish("Project changed") end
    return
  end
  local done,total=0,0
  if #tracks>0 then done,total=poll_reports() end
  if run and mode=="Real time" then
    if r.GetPlayStateEx(proj)&1==0 then
      if r.time_precise()-run>0.5 then finish("Playback stopped") end
    elseif r.GetPlayPositionEx(proj)>=sections[#sections].b+0.05 then
      finish("Real-time analysis complete")
    end
  end
  r.ImGui_SetNextWindowSize(ctx,1000,480,r.ImGui_Cond_FirstUseEver())
  local visible,open=r.ImGui_Begin(ctx,"N2N Mix - Analysis Test",true)
  if visible then
    if not run then
      if r.ImGui_Button(ctx,"Offline dry run") then start("Offline") end
      r.ImGui_SameLine(ctx)
      if r.ImGui_Button(ctx,"Real-time test") then start("Real time") end
    else
      if r.ImGui_Button(ctx,"Cancel") then finish("Cancelled") end
    end
    r.ImGui_SameLine(ctx)
    if r.ImGui_Button(ctx,"Report to console") then copy_report() end
    r.ImGui_TextWrapped(ctx,status)
    if total>0 then
      r.ImGui_ProgressBar(ctx,done/total,-1,0,string.format("%d / %d section reports",done,total))
    end
    r.ImGui_TextWrapped(ctx,"Stereo channels 1/2; sample peak only. OK = completed report. Missing is not silence. No mix changes.")
    if #sections>0 and r.ImGui_BeginChild(ctx,"##grid",0,0,0,r.ImGui_WindowFlags_HorizontalScrollbar()) then
      local width=112
      r.ImGui_Text(ctx,"Track")
      for j,s in ipairs(sections) do r.ImGui_SameLine(ctx,220+(j-1)*width);r.ImGui_Text(ctx,s.name) end
      for _,t in ipairs(tracks) do
        r.ImGui_Text(ctx,t.name)
        if t.channels>2 then r.ImGui_SameLine(ctx);r.ImGui_Text(ctx,"[1/2]") end
        for j=1,#sections do
          r.ImGui_SameLine(ctx,220+(j-1)*width)
          local label,color=cell_text(t,j)
          r.ImGui_TextColored(ctx,color,label)
          if r.ImGui_IsItemHovered(ctx) and t.results[j] then
            local v=t.results[j]
            r.ImGui_SetTooltip(ctx,string.format("LUFS-I %.2f | sample peak %.2f dBFS\nCoverage %.2f%% | %d windows",v.lufs,v.peak,v.coverage*100,v.windows))
          end
        end
      end
      r.ImGui_EndChild(ctx)
    end
    r.ImGui_End(ctx)
  end
  if open then r.defer(loop) end
end
r.atexit(function()
  if run then finish("Closed") else remove_meters() end
end)
loop()
