-- @description N2N Mix
-- @version 0.1.0
-- @noindex
-- First functional test. Requires the unchanged N2N Mix Meter.jsfx and ReaImGui.
local r=reaper
local proj=r.EnumProjects(-1,"")
local NS="N2N_Mix_Analysis_v1"
local STORE="N2N Mix v1"
local MAX=256
local FXNAME="N2N Mix Meter"
local roles={"Lead Vocal","Lead Instrument / Topline","Drums","Bass","Primary Accompaniment","Background Vocals","Secondary Accompaniment","Traditional Arpeggiator","Pad / Texture","Effects","Unclassified","Buss"}
local defaults={-22,-24,-25,-25,-27,-28,-30,-32,-35,-40,-30,-27}
local intensity={-3,0,2,4}
local intens_names={"Soft","Normal","Strong","Very Strong"}
local levels={-60,-10,-5,0,5,10,15,20}
local simple={"0","vv","v","•","^","^^","^^^","★"}
local trad={"0","p","mp","•","mf","f","ff","★"}
local presets={{"YouTube",-14},{"Spotify",-14},{"Apple Music",-16},{"General streaming",-14},{"Dynamic master",-18},{"Premaster",-20},{"EBU R128",-23},{"Custom",-16}}
local sections,rows,master,groups={}, {},nil,{}
local job,pass=nil,nil
local status="Ready."
local log={}
local traditional=false
local tool=4
local expanded={}
local dirty={}
local transition_start=nil
local last_paint=nil
local preset=1
local custom=-16
local peak_ceiling=-2 -- sample-peak guard; not a true-peak guarantee
local selected_mode="Offline"
local last_stats=""
local last_verified=""
local ctx
local function note(s) log[#log+1]=s; status=s end
local function clamp(x,a,b) return math.max(a,math.min(b,x)) end
local function get(k,d)
  local ok,v=r.GetProjExtState(proj,STORE,k)
  if ok>0 then return v end
  return d
end
local function put(k,v) r.SetProjExtState(proj,STORE,k,tostring(v)) end
local function num(k,d) return tonumber(get(k,"")) or d end
local function attach() r.gmem_attach(NS) end
local function valid(t) return r.ValidatePtr2(proj,t,"MediaTrack*") end
local function stopped() return r.EnumProjects(-1,"")==proj and r.GetPlayStateEx(proj)==0 end
local function track_key(t) return r.GetTrackGUID(t) end
local function fx_index(t)
  if not valid(t.track) or not t.fxguid then return nil end
  for i=0,r.TrackFX_GetCount(t.track)-1 do
    if r.TrackFX_GetFXGUID(t.track,i)==t.fxguid then return i end
  end
end
local function read_sections()
  local a={}
  local i=0
  while true do
    local ok,region,x,y,name,id,col=r.EnumProjectMarkers3(proj,i)
    if ok==0 then break end
    if region and y>x then a[#a+1]={a=x,b=y,name=name~="" and name or ("Region "..id),id=id,color=col} end
    i=i+1
  end
  table.sort(a,function(x,y) return x.a<y.a end)
  if #a==0 or #a>MAX then return nil,"Need 1–256 non-overlapping N2N section regions." end
  for j,s in ipairs(a) do
    if s.a<0 or (j>1 and s.a<a[j-1].b-0.00001) then return nil,"Overlapping or negative-time regions are not supported." end
    s.key=string.format("%d:%s:%.6f:%.6f",s.id,s.name,s.a,s.b)
    s.countin=s.name:lower():gsub("[^a-z]","")=="countin"
    s.int=clamp(num("int:"..s.key,2),1,4)
    s.bars={}
    local q=r.TimeMap2_timeToQN(proj,s.a)
    local qend=r.TimeMap2_timeToQN(proj,s.b)
    local start=s.a
    -- N2N generates 4/4; subdivide each generated region in four quarter notes.
    while start<s.b-0.00001 do
      q=math.min(q+4,qend)
      local e=math.min(s.b,r.TimeMap2_QNToTime(proj,q))
      if e<=start+0.000001 then e=s.b end
      s.bars[#s.bars+1]={a=start,b=e}
      start=e
      if #s.bars>4096 then return nil,"Section too long for grid." end
    end
  end
  return a
end
local function role_guess(t,name,bus)
  local n=name:lower()
  if n:find("lexikan",1,true) or n:find("reverb",1,true) or n:find("delay return",1,true) or n:find("fx return",1,true) or n:find("effects",1,true) then return 10 end
  if n:find("topline",1,true) then return 2 end
  if n:find("background vocal",1,true) or n:find("backing vocal",1,true) or n:find("bg vocal",1,true) then return 6 end
  if n:find("vocal",1,true) then return 1 end
  if n:find("drum",1,true) then return 3 end
  if n:find("chord",1,true) then return 5 end -- chord-bass is accompaniment
  if n:find("bass",1,true) then return 4 end
  if n:find("pad",1,true) or n:find("texture",1,true) then return 9 end
  if n:find("arp",1,true) and not n:find("n2n",1,true) then return 8 end
  for i=0,r.TrackFX_GetCount(t)-1 do
    local _,fx=r.TrackFX_GetFXName(t,i,"")
    fx=fx:lower()
    if fx:find("drum arranger",1,true) then return 3 end
    if fx:find("n2n arp",1,true) then return 5 end
  end
  return bus and 12 or 11
end
local function get_owned(t)
  local _,g=r.GetSetMediaTrackInfo_String(t,"P_EXT:N2N_MIX_FX","",false)
  return g~="" and g or nil
end
local function refresh()
  local a,err=read_sections()
  if not a then status=err;return false end
  sections=a; rows={}; groups={}; dirty={}; transition_start=nil
  local byptr={}
  for i=0,r.CountTracks(proj)-1 do
    local t=r.GetTrack(proj,i)
    if r.GetMediaTrackInfo_Value(t,"B_SHOWINMIXER")>0 then
      local _,name=r.GetTrackName(t)
      local row={track=t,key=track_key(t),name=name,fxguid=get_owned(t),cells={},base={},reports={},deps={},depth=0}
      row.bus=r.GetMediaTrackInfo_Value(t,"I_FOLDERDEPTH")>0
      for k=0,r.GetTrackNumSends(t,-1)-1 do
        if r.GetTrackSendInfo_Value(t,-1,k,"I_SRCCHAN")>=0 and r.GetTrackSendInfo_Value(t,-1,k,"B_MUTE")==0 then row.bus=true;break end
      end
      row.role=clamp(num("role:"..row.key,role_guess(t,name,row.bus)),1,#roles)
      row.target=num("target:"..row.key,defaults[row.role])
      row.bus=row.bus or row.role==10 or row.role==12
      for j,s in ipairs(sections) do
        local prefix=row.key..":"..s.key
        row.cells[j]={}
        for b=1,#s.bars do row.cells[j][b]=clamp(num("cell:"..prefix..":"..b,4),1,9) end
        local cached=tonumber(get("base:"..prefix,""))
        if cached and fx_index(row) then row.base[j]=cached end
      end
      rows[#rows+1]=row; byptr[t]=row
    end
  end
  -- Dependency graph: audio receives and folder routing. Hidden tracks are never instrumented.
  for _,row in ipairs(rows) do
    local t=row.track
    for i=0,r.GetTrackNumSends(t,0)-1 do
      local dest=r.GetTrackSendInfo_Value(t,0,i,"P_DESTTRACK")
      if r.GetTrackSendInfo_Value(t,0,i,"I_SRCCHAN")>=0 and r.GetTrackSendInfo_Value(t,0,i,"B_MUTE")==0 and byptr[dest] then
        byptr[dest].deps[row]=true
      end
    end
    local parent=r.GetParentTrack(t)
    if parent and byptr[parent] and r.GetMediaTrackInfo_Value(t,"B_MAINSEND")>0 then byptr[parent].deps[row]=true end
  end
  local visiting={}
  local function depth(row)
    if row.depth_done then return row.depth end
    if visiting[row] then error("Audio routing cycle among visible tracks.") end
    visiting[row]=true
    local d=row.bus and 1 or 0
    for dep in pairs(row.deps) do d=math.max(d,depth(dep)+1) end
    row.depth=d;row.depth_done=true;visiting[row]=nil
    return d
  end
  local ok,e=pcall(function()
    for _,row in ipairs(rows) do
      local d=depth(row)
      groups[d]=groups[d] or {};groups[d][#groups[d]+1]=row
    end
  end)
  if not ok then status=tostring(e);return false end
  local t=r.GetMasterTrack(proj)
  master={track=t,key=track_key(t),name="Master",fxguid=get_owned(t),reports={}}
  if #rows==0 or #rows>MAX then status="Need 1–256 MCP-visible tracks.";return false end
  return true
end
local function active_env(env)
  if not env then return false end
  local ok,c=r.GetEnvelopeStateChunk(env,"",false)
  return not ok or c:match("[\r\n]ACT%s+1")~=nil
end
local function safe_row(t)
  if not valid(t.track) then return false,"Track no longer exists: "..t.name end
  local mode=r.GetMediaTrackInfo_Value(t.track,"I_AUTOMODE")
  if mode>1 then return false,"Change automation mode to Trim/Read or Read: "..t.name end
  local e=r.GetTrackEnvelopeByChunkName(t.track,"<VOLENV2")
  if active_env(e) or active_env(r.GetTrackEnvelopeByName(t.track,"Volume")) then
    return false,"Active conventional volume envelope: "..t.name..". Disable it first; it will not be overwritten."
  end
  local i=fx_index(t)
  if i and i~=r.TrackFX_GetCount(t.track)-1 then return false,"Move owned N2N meter to end of FX chain: "..t.name end
  if i then
    if not r.TrackFX_GetEnabled(t.track,i) or r.TrackFX_GetOffline(t.track,i) then return false,"Enable N2N meter: "..t.name end
    local env=r.GetFXEnvelope(t.track,i,0,false)
    if env and r.CountAutomationItems(env)>0 then return false,"N2N gain envelope has automation items: "..t.name end
  else
    for f=0,r.TrackFX_GetCount(t.track)-1 do
      local _,n=r.TrackFX_GetFXName(t.track,f,"")
      if n:find(FXNAME,1,true) then return false,"Unowned N2N meter already on "..t.name.."; remove it before mixing." end
    end
  end
  return true
end
local function ensure_fx(t)
  local f=fx_index(t)
  if f then return f end
  local at=-1000-r.TrackFX_GetCount(t.track)
  f=r.TrackFX_AddByName(t.track,"JS: N2N Mix Meter.jsfx",false,at)
  if f<0 then f=r.TrackFX_AddByName(t.track,"JS: N2N Mix Meter (diagnostic)",false,at) end
  if f<0 then error("Install N2N Mix Meter.jsfx first.") end
  t.fxguid=r.TrackFX_GetFXGUID(t.track,f)
  r.GetSetMediaTrackInfo_String(t.track,"P_EXT:N2N_MIX_FX",t.fxguid,true)
  return f
end
local function envelope(t)
  local f=ensure_fx(t)
  local env=r.GetFXEnvelope(t.track,f,0,true)
  if not env then error("Cannot create gain envelope: "..t.name) end
  local ok,c=r.GetEnvelopeStateChunk(env,"",false)
  if not ok then error("Cannot read gain envelope: "..t.name) end
  -- Raw PARMENV range may be native slider units or normalized, depending on FX.
  local lo,hi=c:match("<PARMENV%s+%S+%s+([%+%-%.%deE]+)%s+([%+%-%.%deE]+)")
  lo,hi=tonumber(lo),tonumber(hi)
  if not lo or not hi or hi<=lo then error("Unrecognized PARMENV range: "..t.name) end
  c=c:gsub("([\r\n]ACT%s+)%d+", function(p) return p.."1" end,1)
  c=c:gsub("([\r\n]VIS%s+)%d+", function(p) return p.."0" end,1)
  c=c:gsub("([\r\n]ARM%s+)%d+", function(p) return p.."0" end,1)
  if not r.SetEnvelopeStateChunk(env,c,false) then error("Cannot configure gain envelope: "..t.name) end
  env=r.GetFXEnvelope(t.track,f,0,false)
  if r.CountAutomationItems(env)>0 then error("Unexpected automation items: "..t.name) end
  r.DeleteEnvelopePointRangeEx(env,-1,-1e9,1e9)
  return env,lo,hi
end
local function write_points(t,pts)
  local env,lo,hi=envelope(t)
  for _,p in ipairs(pts) do
    local db=clamp(p[2],-60,30)
    local raw=lo+(db+60)/90*(hi-lo)
    if not r.InsertEnvelopePointEx(env,-1,p[1],raw,p[3] or 0,0,false,true) then error("Cannot insert gain point: "..t.name) end
  end
  r.Envelope_SortPointsEx(env,-1)
end
local function flat(t,db) write_points(t,{{0,db,0}}) end
local function calc_base(t,j,v)
  if sections[j].countin or not v or v.state~=1 or math.abs(v.coverage-1)>0.02 then return nil end
  return clamp(t.target-v.lufs,-30,24)
end
local function offset(v) return levels[v] or 0 end
local function apply_row(t)
  local bars={}
  for j,s in ipairs(sections) do
    for b,span in ipairs(s.bars) do
      local v=t.cells[j][b]
      bars[#bars+1]={a=span.a,b=span.b,j=j,v=v,ignore=s.countin}
    end
  end
  local function db_at(x,off)
    local s=sections[x.j]
    if x.ignore then return 0 end
    if off<=-59.9 then return -60 end
    -- Section intensity is applied at source only, not again to downstream busses.
    return clamp((t.base[x.j] or 0)+off+(t.depth==0 and intensity[s.int] or 0),-60,30)
  end
  local i=1
  while i<=#bars do
    local x=bars[i]
    if x.v~=9 or x.ignore then
      x.g0=db_at(x,offset(x.v));x.g1=x.g0;i=i+1
    else
      local first=i
      while i<=#bars and bars[i].v==9 and not bars[i].ignore and (i==first or math.abs(bars[i].a-bars[i-1].b)<0.001) do i=i+1 end
      local last=i-1
      local p,n=bars[first-1],bars[i]
      local a=p and not p.ignore and math.abs(p.b-bars[first].a)<0.001 and db_at(p,offset(p.v)) or -60
      local z=n and not n.ignore and math.abs(n.a-bars[last].b)<0.001 and db_at(n,offset(n.v)) or -60
      local t0,t1=bars[first].a,bars[last].b
      for k=first,last do local b=bars[k];b.g0=a+(z-a)*(b.a-t0)/(t1-t0);b.g1=a+(z-a)*(b.b-t0)/(t1-t0) end
    end
  end
  local pts={}
  local function add(t,v,shape) 
    if #pts>0 and math.abs(pts[#pts][1]-t)<0.0000001 then pts[#pts]={t,v,shape} else pts[#pts+1]={t,v,shape} end
  end
  add(0,0,1)
  for k,b in ipairs(bars) do
    local prev=bars[k-1]
    if not prev or b.a>prev.b+0.00001 then
      if b.a>0 then add(math.max(0,b.a-0.005),0,0) end
      add(b.a,b.g0,0)
    else add(b.a,b.g0,0) end
    local nextb=bars[k+1]
    local e=b.b
    if nextb and math.abs(nextb.a-e)<0.00001 then
      -- 5 ms ramp at hard boundaries; continuous transition endpoints already match.
      if math.abs(b.g1-nextb.g0)>0.0001 then add(math.max(b.a,e-0.005),b.g1,0) end
    else
      add(math.max(b.a,e-0.005),b.g1,0)
      add(e,0,1)
    end
  end
  write_points(t,pts)
end
local function save_cells(t,j)
  local s=sections[j]
  for b,v in ipairs(t.cells[j]) do put("cell:"..t.key..":"..s.key..":"..b,v) end
end
local function action_id()
  local sec=r.SectionFromUniqueID(0)
  for i=0,100000 do
    local cmd,n=r.kbd_enumerateActions(sec,i)
    if not cmd or cmd<=0 then break end
    if n=="Calculate loudness of master mix within time selection via dry run render" then return cmd end
  end
end
local function poll()
  if not pass then return 0,0 end
  attach()
  local done,total=0,#pass.rows*#sections
  for i,t in ipairs(pass.rows) do
    for j,s in ipairs(sections) do
      local addr=4096+((i-1)*256+j-1)*8
      if r.gmem_read(addr)==pass.token then
        local n,rate=r.gmem_read(addr+4),r.gmem_read(addr+5)
        t.reports[j]={state=r.gmem_read(addr+1),lufs=r.gmem_read(addr+2),peak=r.gmem_read(addr+3),coverage=rate>0 and n/rate/(s.b-s.a) or 0}
      end
      if t.reports[j] then done=done+1 end
    end
  end
  return done,total
end
local function cleanup()
  attach();r.gmem_write(0,0)
  if job then
    if job.mode=="Real time" then r.OnStopButtonEx(proj) end
    r.GetSet_LoopTimeRange2(proj,true,false,job.a,job.b,false)
    r.GetSetRepeatEx(proj,job.repeat_state)
    r.SetEditCurPos2(proj,job.cursor,false,false)
  end
end
local function finish(msg)
  if not job then return end
  cleanup()
  note(msg)
  r.Undo_EndBlock2(proj,"N2N Mix: "..job.kind,-1)
  job=nil;pass=nil
  r.UpdateArrange()
end
local function fail(e) finish("Stopped: "..tostring(e)..". Undo N2N Mix to revert partial changes.") end
local function stats_value(s,k) return tonumber((s or ""):match(k..":([%+%-%.%d]+)")) end
local function master_target()
  return preset==#presets and custom or presets[preset][2]
end
local function complete_pass(stats)
  if not job or not pass then return end
  local done,total=poll()
  attach();r.gmem_write(0,0)
  local p=pass
  pass=nil
  local invalid=0
  for _,t in ipairs(p.rows) do
    for j=1,#sections do
      local v=t.reports[j]
      if not v or v.state>=3 or math.abs(v.coverage-1)>0.02 then invalid=invalid+1 end
    end
  end
  note(string.format("%s: %d/%d reports, %d invalid or incomplete.",p.name,done,total,invalid))
  if invalid>0 then error("Incomplete analysis; no gain applied for this pass") end
  if p.kind=="track" then
    for _,t in ipairs(p.rows) do
      for j,v in pairs(t.reports) do
        t.base[j]=calc_base(t,j,v)
        put("base:"..t.key..":"..sections[j].key,t.base[j] or "")
      end
      apply_row(t)
    end
  elseif p.kind=="master" then
    local lufs,peak=stats_value(stats,"LUFSI"),stats_value(stats,"PEAK")
    if not lufs or not peak or lufs<=-70 then error("No valid native master loudness/peak result") end
    local requested=master_target()-lufs
    local gain=clamp(math.min(requested,peak_ceiling-peak),-60,30)
    flat(master,gain)
    put("mastergain",gain)
    last_stats=string.format("Master before %.2f LUFS / %.2f dBFS; gain %+.2f dB; estimated %.2f LUFS.",lufs,peak,gain,lufs+gain)
    if gain<requested-0.1 then last_stats=last_stats.." Peak constrained (gain only; no limiter)." end
    note(last_stats)
  elseif p.kind=="verify" then
    local lufs,peak=stats_value(stats,"LUFSI"),stats_value(stats,"PEAK")
    if not lufs or not peak then error("No native verification result") end
    last_verified=string.format("Verified master: %.2f LUFS-I, %.2f dBFS sample peak (target %.1f LUFS).",lufs,peak,master_target())
    if peak>peak_ceiling+0.1 then
      local g=num("mastergain",0)-(peak-peak_ceiling)
      flat(master,g);put("mastergain",g)
      last_verified=last_verified.." Additional peak correction applied; rerun Master to verify."
    end
    note(last_verified)
  end
  job.index=job.index+1
end
local function arm(p)
  attach()
  local tok=(math.floor(r.time_precise()*1000)%800000)+1
  if tok==r.gmem_read(1) then tok=tok+1 end
  r.gmem_write(0,0);r.gmem_write(1,tok);r.gmem_write(2,#sections)
  for j,s in ipairs(sections) do r.gmem_write(16+2*(j-1),s.a);r.gmem_write(17+2*(j-1),s.b) end
  for i,t in ipairs(p.rows) do
    t.reports={}
    local f=ensure_fx(t)
    r.TrackFX_SetParam(t.track,f,1,i);r.TrackFX_SetParam(t.track,f,2,tok)
    for j=1,#sections do r.gmem_write(4096+((i-1)*256+j-1)*8,0) end
  end
  p.token=tok; p.phase="armed";pass=p
  r.gmem_write(0,1)
  r.GetSet_LoopTimeRange2(proj,true,false,sections[1].a,sections[#sections].b+0.1,false)
  note(p.name.." — listening ("..job.mode..")")
end
local function step()
  if not job then return end
  if not pass then
    local p=job.queue[job.index]
    if not p then finish("Fine tune complete. "..last_verified);return end
    arm(p);return -- draw armed state before render
  end
  if pass.phase=="armed" then
    if job.mode=="Real time" and pass.kind=="track" then
      r.GetSetRepeatEx(proj,0);r.SetEditCurPos2(proj,sections[1].a,false,false);r.OnPlayButtonEx(proj)
      pass.phase="playing";pass.started=r.time_precise()
    else
      -- Native render stats are required for integrated whole-master loudness.
      local _,stats=r.GetSetProjectInfo_String(proj,"RENDER_STATS",tostring(job.cmd),false)
      complete_pass(stats)
    end
  elseif pass.phase=="playing" then
    poll()
    if r.GetPlayPositionEx(proj)>=sections[#sections].b+0.05 then
      r.OnStopButtonEx(proj);complete_pass("")
    elseif r.GetPlayStateEx(proj)&1==0 and r.time_precise()-pass.started>0.5 then
      error("Playback stopped before end")
    end
  end
end
local function start(kind)
  if next(dirty) then status="Finish current grid edit first.";return end
  if not stopped() then status="Stop transport first.";return end
  if not refresh() then return end
  if math.abs(r.Master_GetPlayRate(proj)-1)>0.0001 then status="Set project play rate to 1.0.";return end
  local override=r.GetGlobalAutomationOverride()
  if override>1 then status="Disable global automation write/bypass override.";return end
  attach()
  if r.gmem_read(0)==1 then status="Another analysis is armed.";return end
  local cmd=action_id()
  if not cmd then status="Native dry-run action not found.";return end
  local q,selected={},{}
  if kind=="All" or kind=="Instruments" then
    if groups[0] then q[#q+1]={kind="track",name="1. Instruments",rows=groups[0]} end
  end
  if kind=="All" or kind=="Busses & FX" then
    for d=1,#rows do if groups[d] then q[#q+1]={kind="track",name="2. Busses / FX layer "..d,rows=groups[d]} end end
  end
  if kind=="All" or kind=="Master" then
    q[#q+1]={kind="master",name="3. Master",rows={master}}
    q[#q+1]={kind="verify",name="Verify master",rows={master}}
  end
  if #q==0 then status="No eligible tracks for this stage.";return end
  for _,p in ipairs(q) do for _,t in ipairs(p.rows) do selected[t]=true end end
  for t in pairs(selected) do local ok,e=safe_row(t);if not ok then status=e;return end end
  local a,b=r.GetSet_LoopTimeRange2(proj,false,false,0,0,false)
  r.Undo_BeginBlock2(proj)
  job={queue=q,index=1,kind=kind,mode=selected_mode,cmd=cmd,a=a,b=b,cursor=r.GetCursorPositionEx(proj),repeat_state=r.GetSetRepeatEx(proj,-1)}
  last_verified="";last_stats=""
  local ok,e=pcall(function()
    for t in pairs(selected) do
      ensure_fx(t)
      r.SetMediaTrackInfo_Value(t.track,"D_VOL",1)
      flat(t,0)
    end
    -- A previous master gain must not influence a new master pass; it was reset above.
    note("Fine tune "..kind.." prepared. Faders at unity for participating stages.")
  end)
  if not ok then fail(e) end
end
local function edit_cell(t,j,b)
  if sections[j].countin then return end
  if tool==9 then
    if not transition_start or transition_start.t~=t then transition_start={t=t,j=j,b=b};status="Select transition end on the same track.";return end
    local s0=transition_start;transition_start=nil
    local start_j,end_j=math.min(s0.j,j),math.max(s0.j,j)
    local start_b,end_b=s0.b,b
    if s0.j>j then start_b,end_b=b,s0.b end
    if start_j==end_j and start_b and end_b then start_b,end_b=math.min(start_b,end_b),math.max(start_b,end_b) end
    for k=start_j,end_j do
      if not sections[k].countin then
        local x=k==start_j and start_b or 1
        local y=k==end_j and end_b or #sections[k].bars
        for n=x or 1,y or #sections[k].bars do t.cells[k][n]=9 end
        save_cells(t,k)
      end
    end
  else
    if b then t.cells[j][b]=tool else for k=1,#t.cells[j] do t.cells[j][k]=tool end end
    save_cells(t,j)
  end
  dirty[t]=true
end
local function rgba(rr,gg,bb,aa) return (rr<<24)|(gg<<16)|(bb<<8)|aa end
local function cell(t,j,b,w)
  local s=sections[j]
  local v=b and t.cells[j][b] or t.cells[j][1]
  if not b then for _,x in ipairs(t.cells[j]) do if x~=v then v=0;break end end end
  local label=v==9 and "~" or v==0 and "..." or (traditional and trad or simple)[v]
  local dl=r.ImGui_GetWindowDrawList(ctx)
  local x,y=r.ImGui_GetCursorScreenPos(ctx)
  local h=24
  local id="##"..t.key..":"..j..":"..(b or 0)
  local clicked=r.ImGui_InvisibleButton(ctx,id,w,h)
  local hovered=r.ImGui_IsItemHovered(ctx)
  local raw=r.GetTrackColor(t.track)
  local rr,gg,bb=90,120,145
  if raw~=0 then rr,gg,bb=r.ColorFromNative(raw) end
  local light=rgba(math.floor(rr*.45+140),math.floor(gg*.45+140),math.floor(bb*.45+140),255)
  local dark=rgba(math.floor(rr*.65),math.floor(gg*.65),math.floor(bb*.65),255)
  r.ImGui_DrawList_AddRectFilled(dl,x,y,x+w,y+h,light,2)
  local f=v==9 and 0.5 or v==0 and 0.43 or (v-1)/7
  if f>0 then r.ImGui_DrawList_AddRectFilled(dl,x,y+h*(1-f),x+w,y+h,dark,2) end
  if v==9 then r.ImGui_DrawList_AddLine(dl,x+2,y+h-3,x+w-2,y+3,0xFFFFFFFF,2) end
  local report=t.reports[j]
  if job then label=report and (report.state==1 and ("✓ "..string.format("%.1f",report.lufs)) or "✓") or "·" end
  if s.countin and not job then label="—" end
  local tw,th=r.ImGui_CalcTextSize(ctx,label)
  r.ImGui_DrawList_AddText(dl,x+(w-tw)/2,y+(h-th)/2,0xFFFFFFFF,label)
  if hovered and not job then
    local k=id
    if clicked or (tool~=9 and r.ImGui_IsMouseDown(ctx,0) and last_paint~=k) then edit_cell(t,j,b);last_paint=k end
  end
  if hovered then
    local b0=t.base[j]
    r.ImGui_SetTooltip(ctx,string.format("%s | %s\nTarget %.1f LUFS | calibration %s%s",t.name,s.name,t.target,b0 and string.format("%+.2f dB",b0) or "unmeasured",report and string.format("\nReport %.2f LUFS / %.0f%% coverage",report.lufs,report.coverage*100) or ""))
  end
end
local function apply_dirty()
  if not next(dirty) or job or not stopped() then return end
  if r.GetGlobalAutomationOverride()>1 then status="Disable global automation write/bypass before editing.";return end
  r.Undo_BeginBlock2(proj)
  local ok,e=pcall(function()
    for t in pairs(dirty) do
      if fx_index(t) then
        local safe,msg=safe_row(t);if not safe then error(msg) end
        apply_row(t)
      end
    end
  end)
  r.Undo_EndBlock2(proj,"N2N Mix grid edit",-1)
  dirty={}
  if not ok then note("Grid update stopped: "..tostring(e)) end
end
local function same() r.ImGui_SameLine(ctx) end
local function button(s,fn)
  if r.ImGui_Button(ctx,s) then fn() end
end
local function draw()
  r.ImGui_SetNextWindowSize(ctx,1200,600,r.ImGui_Cond_FirstUseEver())
  local visible,open=r.ImGui_Begin(ctx,"N2N Mix",true)
  if visible then
    if not job then
      button("Fine Tune All",function() start("All") end);same()
      button("Instruments",function() start("Instruments") end);same()
      button("Busses & FX",function() start("Busses & FX") end);same()
      button("Master",function() start("Master") end);same()
      button(selected_mode,function() selected_mode=selected_mode=="Offline" and "Real time" or "Offline" end);same()
      button("Refresh",refresh)
    else
      button("Cancel",function() finish("Cancelled. Undo to revert partial changes.") end)
    end
    same();button("Report",function() r.ShowConsoleMsg(table.concat(log,"\n").."\n") end)
    r.ImGui_TextWrapped(ctx,status)
    if last_stats~="" then r.ImGui_TextWrapped(ctx,last_stats) end
    if last_verified~="" then r.ImGui_TextWrapped(ctx,last_verified) end
    if job then
      local d,n=poll()
      r.ImGui_ProgressBar(ctx,n>0 and d/n or 0,-1,0,string.format("Stage %d/%d | %d/%d reports",job.index,#job.queue,d,n))
    else
      r.ImGui_SetNextItemWidth(ctx,160)
      if r.ImGui_BeginCombo(ctx,"Master target",presets[preset][1]) then
        for i,p in ipairs(presets) do if r.ImGui_Selectable(ctx,p[1],i==preset) then preset=i;put("preset",i) end end
        r.ImGui_EndCombo(ctx)
      end
      same()
      if preset==#presets then
        r.ImGui_SetNextItemWidth(ctx,90)
        local ch,v=r.ImGui_InputDouble(ctx,"LUFS",custom,1,1,"%.1f")
        if ch then custom=clamp(v,-35,-8);put("custom",custom) end
        same()
      end
      r.ImGui_Text(ctx,string.format("Target %.1f LUFS | sample peak guard %.1f dBFS",master_target(),peak_ceiling))
      local ch,v=r.ImGui_Checkbox(ctx,"Traditional",traditional)
      if ch then traditional=v;put("traditional",v and 1 or 0) end
      for i=1,9 do
        same()
        local lbl=i==9 and "Transition" or (traditional and trad or simple)[i]
        if r.ImGui_Button(ctx,(tool==i and "["..lbl.."]" or lbl).."##tool"..i) then tool=i;transition_start=nil end
      end
      r.ImGui_TextWrapped(ctx,"Paint levels by dragging. Transition: click start and end on one track. Click a section heading to expand bars.")
    end
    if #sections>0 and r.ImGui_BeginChild(ctx,"##grid",0,0,0,r.ImGui_WindowFlags_HorizontalScrollbar()) then
      local cols={}
      for j,s in ipairs(sections) do
        if expanded[s.key] then for b=1,#s.bars do cols[#cols+1]={j=j,b=b,w=55} end
        else cols[#cols+1]={j=j,w=98} end
      end
      local colx=355
      r.ImGui_Text(ctx,"Track / Role / Target")
      for _,c in ipairs(cols) do
        r.ImGui_SameLine(ctx,colx);colx=colx+c.w+4
        local s=sections[c.j]
        local lbl=c.b and (c.b==1 and s.name.." [-]" or tostring(c.b)) or s.name.." [+]"
        if r.ImGui_Button(ctx,lbl.."##sec"..c.j..":"..(c.b or 0),c.w,24) and not job then expanded[s.key]=not expanded[s.key] end
      end
      r.ImGui_Text(ctx,"Section intensity")
      colx=355
      for _,c in ipairs(cols) do
        r.ImGui_SameLine(ctx,colx);colx=colx+c.w+4
        local s=sections[c.j]
        if r.ImGui_Button(ctx,(s.countin and "—" or intens_names[s.int]).."##int"..c.j..":"..(c.b or 0),c.w,24) and not job and not s.countin then
          s.int=s.int%4+1;put("int:"..s.key,s.int)
          for _,t in ipairs(rows) do if t.depth==0 then dirty[t]=true end end
        end
      end
      for _,t in ipairs(rows) do
        r.ImGui_Text(ctx,t.name)
        r.ImGui_SameLine(ctx,165)
        r.ImGui_SetNextItemWidth(ctx,118)
        if r.ImGui_BeginCombo(ctx,"##role"..t.key,roles[t.role]) then
          for i,name in ipairs(roles) do
            if r.ImGui_Selectable(ctx,name,i==t.role) and not job then
              local old=t.target;t.role=i;t.target=defaults[i];put("role:"..t.key,i);put("target:"..t.key,t.target)
              for j,base in pairs(t.base) do t.base[j]=clamp(base+t.target-old,-30,24);put("base:"..t.key..":"..sections[j].key,t.base[j]) end
              dirty[t]=true
            end
          end
          r.ImGui_EndCombo(ctx)
        end
        r.ImGui_SameLine(ctx,287);r.ImGui_SetNextItemWidth(ctx,64)
        local ch,v=r.ImGui_InputDouble(ctx,"##target"..t.key,t.target,0,0,"%.1f")
        if ch and not job then
          local old=t.target;t.target=clamp(v,-60,-8);put("target:"..t.key,t.target)
          for j,base in pairs(t.base) do t.base[j]=clamp(base+t.target-old,-30,24);put("base:"..t.key..":"..sections[j].key,t.base[j]) end
          dirty[t]=true
        end
        colx=355
        for _,c in ipairs(cols) do r.ImGui_SameLine(ctx,colx);colx=colx+c.w+4;cell(t,c.j,c.b,c.w) end
      end
      r.ImGui_EndChild(ctx)
    end
    r.ImGui_End(ctx)
  end
  if not r.ImGui_IsMouseDown(ctx,0) then last_paint=nil;apply_dirty() end
  return open
end
if not r.ImGui_CreateContext then r.MB("ReaImGui is required.","N2N Mix",0);return end
ctx=r.ImGui_CreateContext("N2N Mix")
preset=clamp(num("preset",1),1,#presets)
custom=num("custom",-16)
traditional=num("traditional",0)==1
refresh()
local function loop()
  if r.EnumProjects(-1,"")~=proj then if job then fail("Project changed") end;return end
  if job then
    local ok,e=pcall(step)
    if not ok then fail(e) end
  end
  local ok,open=pcall(draw)
  if not ok then if job then fail(open) end;r.ShowConsoleMsg("N2N Mix GUI error: "..tostring(open).."\n");return end
  if open then r.defer(loop) elseif job then finish("Closed. Undo to revert partial changes.") end
end
r.atexit(function() if job then finish("Closed. Undo to revert partial changes.") end end)
loop()
