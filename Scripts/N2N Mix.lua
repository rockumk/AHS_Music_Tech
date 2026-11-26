-- @description N2N Mix
-- @version 0.1.4
-- @noindex
-- First functional test. Requires the unchanged N2N Mix Meter.jsfx and ReaImGui.
local r=reaper
local proj=r.EnumProjects(-1,"")
local NS="N2N_Mix_Analysis_v1"
local STORE="N2N Mix v1"
local MAX=256
local FXNAME="N2N Mix Meter"
local roles={"Lead Vocal","Lead Instrument","Drums","Bass","Primary Accomp.","BG Vocals","Secondary Accomp.","Traditional Arp","Pad / Texture","Effects","Unclassified","Buss"}
local defaults={-22,-24,-25,-25,-27,-28,-30,-32,-35,-40,-30,-27}
local intensity={-3,0,2,4}
local intens_names={"Soft","Normal","Strong","Very Strong"}
local levels={-60,-10,-5,0,5,10,15,20}
local simple={"Mute","Down twice","Down","Normal","Up","Up twice","Up three times","Featured"}
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
local stroke=nil
local ui_font=nil
local UI_SIZE=13
local CELL_H=26
local LEFT_W=380
local GAP=3
local display_cols={}
local font_new_api=nil
local preset=1
local custom=-16
local peak_ceiling=-2 -- sample-peak guard; not a true-peak guarantee
local boundary_ramp=0.250 -- seconds; ordinary level changes, not explicit transitions
local alert_text,alert_until="",0
local refresh_at=0
local layout_sig=""
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
    s.int=clamp(num("int:"..s.key,2),1,5)
    s.bars={}
    local q=r.TimeMap2_timeToQN(proj,s.a)
    local qend=r.TimeMap2_timeToQN(proj,s.b)
    local start=s.a
    -- N2N generates 4/4; subdivide each generated region in four quarter notes.
    while start<s.b-0.00001 do
      q=math.min(q+4,qend)
      local e=math.min(s.b,r.TimeMap2_QNToTime(proj,q))
      if e<=start+0.000001 then e=s.b end
      local b=#s.bars+1
      s.bars[b]={a=start,b=e,int=clamp(num("int:"..s.key..":"..b,s.int),1,5)}
      start=e
      if #s.bars>4096 then return nil,"Section too long for grid." end
    end
  end
  return a
end
local function role_guess(t,name,bus)
  local n=name:lower()
  if n:find("lexikan",1,true) or n:find("reverb",1,true) or n:find("delay return",1,true) or n:find("fx return",1,true) or n:find("effects",1,true) then return 10 end
  if n:find("topline",1,true) or n:find("black key live",1,true) or n:find("white key live",1,true) or n:match("^audio%s*%d*$") then return 2 end
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
      local _,initial=r.GetSetMediaTrackInfo_String(t,"P_EXT:N2N_MIX_INITIAL_DB","",false)
      row.initial=clamp(tonumber(initial) or 0,-60,30)
      row.bus=false
      for k=0,r.GetTrackNumSends(t,-1)-1 do
        if r.GetTrackSendInfo_Value(t,-1,k,"I_SRCCHAN")>=0 and r.GetTrackSendInfo_Value(t,-1,k,"B_MUTE")==0 then row.bus=true;break end
      end
      row.role=clamp(num("role:"..row.key,role_guess(t,name,row.bus)),1,#roles)
      row.target=num("target:"..row.key,defaults[row.role])
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
  -- Plan from audio edges, not track labels or folder status. Hidden tracks
  -- may carry audio, but are traversed read-only and never receive a meter.
  local nodes={}
  for i=0,r.CountTracks(proj)-1 do
    local t=r.GetTrack(proj,i)
    nodes[t]={track=t,row=byptr[t],incoming={}}
  end
  local function is_n2n_midi_only(t)
    local _,id=r.GetSetMediaTrackInfo_String(t,"P_EXT:N2N:ID","",false)
    local _,cue=r.GetSetMediaTrackInfo_String(t,"P_EXT:N2N:IS_CUECHILD","",false)
    if cue=="1" then return true end
    return not byptr[t] and (id:match("^%d+_0$")~=nil or id:match("^[1567]_1$")~=nil or id=="15_1" or id=="4_1")
  end
  local function edge(src,dst)
    if nodes[src] and nodes[dst] then nodes[dst].incoming[src]=true end
  end
  for t in pairs(nodes) do
    if not is_n2n_midi_only(t) then
      for i=0,r.GetTrackNumSends(t,0)-1 do
        local dest=r.GetTrackSendInfo_Value(t,0,i,"P_DESTTRACK")
        local chan=r.GetTrackSendInfo_Value(t,0,i,"I_SRCCHAN")
        local muted=r.GetTrackSendInfo_Value(t,0,i,"B_MUTE")
        local mode=r.GetTrackSendInfo_Value(t,0,i,"I_SENDMODE")
        -- Pre-FX sends are independent of our end-of-chain gain.
        if chan>=0 and muted==0 and mode~=1 then edge(t,dest) end
      end
      local parent=r.GetParentTrack(t)
      if parent and r.GetMediaTrackInfo_Value(t,"B_MAINSEND")>0 then edge(t,parent) end
    end
  end
  local visiting={}
  local function depth(node)
    if node.done then return node.depth end
    if visiting[node] then error("Audio routing feedback detected. Auto Mix cannot safely order a feedback loop.") end
    visiting[node]=true
    local d=0
    for src in pairs(node.incoming) do
      local upstream=nodes[src]
      d=math.max(d,depth(upstream)+(upstream.row and 1 or 0))
    end
    node.depth=d;node.done=true;visiting[node]=nil
    return d
  end
  local ok,e=pcall(function()
    for _,row in ipairs(rows) do
      local d=depth(nodes[row.track])
      row.depth=d
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
    local _,owned_name=r.TrackFX_GetFXName(t.track,i,"")
    if not owned_name:find(FXNAME,1,true) then return false,"Owned FX GUID no longer identifies N2N meter: "..t.name end
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
local function intensity_contour()
  local all,map={},{}
  for j,s in ipairs(sections) do
    map[j]={}
    for b,bar in ipairs(s.bars) do
      local x={a=bar.a,b=bar.b,v=bar.int,ignore=s.countin}
      all[#all+1]=x;map[j][b]=x
    end
  end
  local i=1
  while i<=#all do
    local x=all[i]
    if x.v~=5 or x.ignore then
      x.d0=x.ignore and 0 or (intensity[x.v] or 0);x.d1=x.d0;i=i+1
    else
      local first=i
      while i<=#all and all[i].v==5 and not all[i].ignore and (i==first or math.abs(all[i].a-all[i-1].b)<0.001) do i=i+1 end
      local last=i-1
      local p,n=all[first-1],all[i]
      local a=p and not p.ignore and math.abs(p.b-all[first].a)<0.001 and (intensity[p.v] or 0) or intensity[1]
      local z=n and not n.ignore and math.abs(n.a-all[last].b)<0.001 and (intensity[n.v] or 0) or intensity[1]
      local t0,t1=all[first].a,all[last].b
      for k=first,last do
        local b=all[k];b.d0=a+(z-a)*(b.a-t0)/(t1-t0);b.d1=a+(z-a)*(b.b-t0)/(t1-t0)
      end
    end
  end
  return map
end
local function section_intensity(s,j)
  local contour=intensity_contour()[j]
  local energy,duration=0,0
  for _,b in ipairs(contour) do
    local d=b.b-b.a
    local x,y=10^(b.d0/10),10^(b.d1/10)
    local mean=math.abs(b.d1-b.d0)<1e-8 and x or (y-x)/(math.log(y)-math.log(x))
    energy=energy+d*mean;duration=duration+d
  end
  return duration>0 and 10*math.log(energy/duration,10) or 0
end
local function calc_base(t,j,v)
  if sections[j].countin or not v or v.state~=1 or math.abs(v.coverage-1)>0.02 then return nil end
  return clamp(t.target+(t.depth>0 and section_intensity(sections[j],j) or 0)-v.lufs,-30,24)
end
local function offset(v) return levels[v] or 0 end
local function apply_row(t)
  local bars={}
  local contour=intensity_contour()
  for j,s in ipairs(sections) do
    for b,span in ipairs(s.bars) do
      local v=t.cells[j][b]
      local d=contour[j][b]
      bars[#bars+1]={a=span.a,b=span.b,j=j,v=v,d0=d.d0,d1=d.d1,ignore=s.countin}
    end
  end
  local function db_at(x,off)
    local s=sections[x.j]
    if x.ignore then return t.initial or 0 end
    if off<=-59.9 then return -60 end
    -- Section intensity is applied at source only, not again to downstream busses.
    return (t.base[x.j] or t.initial or 0)+off
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
  -- Add the independent intensity contour after calculating the track transition.
  -- Downstream tracks already receive the source intensity through the routing.
  for _,b in ipairs(bars) do
    if t.depth==0 and not b.ignore and b.v~=1 then
      if b.g0>-60 then b.g0=b.g0+b.d0 end
      if b.g1>-60 then b.g1=b.g1+b.d1 end
    end
    b.g0=clamp(b.g0,-60,30);b.g1=clamp(b.g1,-60,30)
  end
  local pts={}
  local function add(t,v,shape) 
    if #pts>0 and math.abs(pts[#pts][1]-t)<0.0000001 then pts[#pts]={t,v,shape} else pts[#pts+1]={t,v,shape} end
  end
  local initial=t.initial or 0
  add(0,initial,1)
  for k,b in ipairs(bars) do
    local prev=bars[k-1]
    if not prev or b.a>prev.b+0.00001 then
      if b.a>0 then
        local gap=prev and b.a-prev.b or b.a
        add(b.a-math.min(boundary_ramp,gap*0.5),initial,0)
      end
      add(b.a,b.g0,0)
    else add(b.a,b.g0,0) end
    local nextb=bars[k+1]
    local e=b.b
    if nextb and math.abs(nextb.a-e)<0.00001 then
      -- Ease ordinary steps over the last 250 ms, capped at a quarter of the bar.
      -- Explicit transition spans already meet their neighbors and remain untouched.
      if math.abs(b.g1-nextb.g0)>0.0001 then
        local ramp=math.min(boundary_ramp,(e-b.a)*0.25)
        local before=b.g0+(b.g1-b.g0)*(1-ramp/(e-b.a))
        add(e-ramp,before,0)
      end
    elseif nextb then
      add(e-math.min(boundary_ramp,(e-b.a)*0.25),b.g1,0)
      add(e,initial,1)
    else
      add(e,b.g1,1) -- preserve final gain through instrument / reverb tails
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
  if msg:match("^Auto Mix complete") then alert_text="Processing done.";alert_until=r.time_precise()+1.8 else alert_text="";alert_until=0 end
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
      last_verified=last_verified.." Additional peak correction applied; run Auto Mix again to verify."
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
  note(p.name.." — offline analysis")
end
local function step()
  if not job or r.time_precise()<job.ready_at then return end
  if not pass then
    local p=job.queue[job.index]
    if not p then finish("Auto Mix complete. "..last_verified);return end
    arm(p);return
  end
  local _,stats=r.GetSetProjectInfo_String(proj,"RENDER_STATS",tostring(job.cmd),false)
  complete_pass(stats)
end
local function start()
  if next(dirty) then status="Finish current grid edit first.";return end
  if not stopped() then status="Stop transport before Auto Mix.";return end
  if not refresh() then return end
  if math.abs(r.Master_GetPlayRate(proj)-1)>0.0001 then status="Set project play rate to 1.0.";return end
  if r.GetGlobalAutomationOverride()>1 then status="Disable global automation write/bypass override.";return end
  attach()
  if r.gmem_read(0)==1 then status="Another analysis is armed.";return end
  local cmd=action_id()
  if not cmd then status="Native dry-run action not found.";return end
  local q,selected={},{}
  for d=0,#rows do
    if groups[d] and #groups[d]>0 then
      local label=d==0 and "Source tracks" or ("Downstream audio layer "..d)
      q[#q+1]={kind="track",name=label.." ("..#groups[d].." tracks)",rows=groups[d]}
    end
  end
  q[#q+1]={kind="master",name="Master",rows={master}}
  q[#q+1]={kind="verify",name="Master verification",rows={master}}
  for _,p in ipairs(q) do for _,t in ipairs(p.rows) do selected[t]=true end end
  for t in pairs(selected) do local ok,e=safe_row(t);if not ok then status=e;return end end
  local a,b=r.GetSet_LoopTimeRange2(proj,false,false,0,0,false)
  r.Undo_BeginBlock2(proj)
  job={queue=q,index=1,kind="Auto Mix",cmd=cmd,a=a,b=b,cursor=r.GetCursorPositionEx(proj),repeat_state=r.GetSetRepeatEx(proj,-1),ready_at=r.time_precise()+1.4}
  last_verified="";last_stats=""
  alert_text="Processing please wait.";alert_until=job.ready_at
  local ok,e=pcall(function()
    for t in pairs(selected) do
      ensure_fx(t)
      r.SetMediaTrackInfo_Value(t.track,"D_VOL",1)
      flat(t,0)
    end
    note(string.format("Audio routing: %d track layers, master and verification.",#q-2))
  end)
  if not ok then fail(e) end
end
local function edit_cell(t,j,b,chosen)
  if sections[j].countin then return end
  local chosen=chosen or tool
  if chosen==9 then
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
    if b then t.cells[j][b]=chosen else for k=1,#t.cells[j] do t.cells[j][k]=chosen end end
    save_cells(t,j)
  end
  dirty[t]=true
end
local function rgba(rr,gg,bb,aa) return (rr<<24)|(gg<<16)|(bb<<8)|aa end
local function rgb(native)
  if native==0 then return 100,112,125 end
  return r.ColorFromNative(native & 0xffffff)
end
local function contrast(rr,gg,bb)
  return (rr*0.299+gg*0.587+bb*0.114)>145 and 0x101010FF or 0xFFFFFFFF
end
local function centered(dl,x,y,w,h,label,col,outline)
  local tw,th=r.ImGui_CalcTextSize(ctx,label)
  local tx,ty=x+(w-tw)/2,y+(h-th)/2
  if outline then
    for dx=-1,1 do for dy=-1,1 do
      if dx~=0 or dy~=0 then r.ImGui_DrawList_AddText(dl,tx+dx,ty+dy,outline,label) end
    end end
  end
  r.ImGui_DrawList_AddText(dl,tx,ty,col,label)
end
local function line(dl,x1,y1,x2,y2)
  r.ImGui_DrawList_AddLine(dl,x1,y1,x2,y2,0xFFFFFFD0,4)
  r.ImGui_DrawList_AddLine(dl,x1,y1,x2,y2,0x151515FF,2.2)
end
local function symbol(dl,x,y,w,h,v)
  local cx,cy=x+w/2,y+h/2
  if v==0 then centered(dl,x,y,w,h,"...",0x101010FF,0xFFFFFFFF)
  elseif v==1 then
    r.ImGui_DrawList_AddCircle(dl,cx,cy,6,0xFFFFFFFF,0,3.5)
    r.ImGui_DrawList_AddCircle(dl,cx,cy,6,0x151515FF,0,1.8)
    line(dl,cx-4,cy+4,cx+4,cy-4)
  elseif v==4 then
    r.ImGui_DrawList_AddCircleFilled(dl,cx,cy,4,0xFFFFFFFF)
    r.ImGui_DrawList_AddCircleFilled(dl,cx,cy,2.5,0x151515FF)
  elseif v==8 then
    local pts={}
    for i=0,9 do
      local ang=-math.pi/2+i*math.pi/5
      local rad=i%2==0 and 9 or 3.8
      pts[i+1]={cx+math.cos(ang)*rad,cy+math.sin(ang)*rad}
    end
    for i=1,10 do
      local p,q=pts[i],pts[i%10+1]
      r.ImGui_DrawList_AddLine(dl,p[1],p[2],q[1],q[2],0xFFFFFFFF,2.4)
    end
    for i=1,10 do
      local p,q=pts[i],pts[i%10+1]
      r.ImGui_DrawList_AddTriangleFilled(dl,cx,cy,p[1],p[2],q[1],q[2],0x151515FF)
    end
  elseif v==9 then
    line(dl,cx-10,cy+6,cx+10,cy-6)
    line(dl,cx+4,cy-6,cx+10,cy-6)
    line(dl,cx+10,cy-6,cx+10,cy)
  elseif traditional then centered(dl,x,y,w,h,trad[v],0x101010FF,0xFFFFFFFF)
  else
    local n=v==2 and 2 or v==3 and 1 or v-4
    local up=v>4
    for i=1,n do
      local xx=cx+(i-(n+1)/2)*9
      local tip=cy+(up and -7 or 7)
      local tail=cy+(up and 6 or -6)
      local wing=tip+(up and 4.5 or -4.5)
      line(dl,xx,tail,xx,tip)
      line(dl,xx-3.5,wing,xx,tip);line(dl,xx+3.5,wing,xx,tip)
    end
  end
end
local function fill_for(v) return v==0 and 3/7 or (v-1)/7 end
-- Display musical prominence using the same time interpolation as the audio transition.
local function transition_fills(t)
  local all,map={},{}
  for j,s in ipairs(sections) do
    map[j]={}
    for b,bar in ipairs(s.bars) do
      local v=t.cells[j][b]
      local x={a=bar.a,b=bar.b,v=v,ignore=s.countin}
      all[#all+1]=x;map[j][b]=x
    end
  end
  local i=1
  while i<=#all do
    local x=all[i]
    if x.v~=9 or x.ignore then
      x.f0=fill_for(x.ignore and 1 or x.v);x.f1=x.f0;i=i+1
    else
      local first=i
      while i<=#all and all[i].v==9 and not all[i].ignore and
        (i==first or math.abs(all[i].a-all[i-1].b)<0.001) do i=i+1 end
      local last=i-1
      local p,n=all[first-1],all[i]
      local a=p and not p.ignore and math.abs(p.b-all[first].a)<0.001 and fill_for(p.v) or 0
      local z=n and not n.ignore and math.abs(n.a-all[last].b)<0.001 and fill_for(n.v) or 0
      local t0,t1=all[first].a,all[last].b
      for k=first,last do
        local b=all[k];b.f0=a+(z-a)*(b.a-t0)/(t1-t0);b.f1=a+(z-a)*(b.b-t0)/(t1-t0)
      end
    end
  end
  return map
end
local function popup_level(t,j,b,v,id)
  if r.ImGui_BeginPopupContextItem(ctx,"##options"..id) then
    for k=1,8 do
      local label=(traditional and trad[k] or simple[k])
      if r.ImGui_Selectable(ctx,label,k==v) then
        transition_start=nil;edit_cell(t,j,b,k)
      end
    end
    if r.ImGui_Selectable(ctx,"Transition",v==9) then
      if b then t.cells[j][b]=9 else for k=1,#t.cells[j] do t.cells[j][k]=9 end end
      save_cells(t,j);dirty[t]=true;transition_start=nil
    end
    r.ImGui_EndPopup(ctx)
  end
end
local function cell(t,j,b,w,fills,ri,ci)
  local s=sections[j]
  local v=b and t.cells[j][b] or t.cells[j][1]
  if not b then for _,x in ipairs(t.cells[j]) do if x~=v then v=0;break end end end
  local dl=r.ImGui_GetWindowDrawList(ctx)
  local x,y=r.ImGui_GetCursorScreenPos(ctx)
  local h=CELL_H
  local id="##"..t.key..":"..j..":"..(b or 0)
  r.ImGui_InvisibleButton(ctx,id,w,h)
  local hovered=r.ImGui_IsItemHovered(ctx,r.ImGui_HoveredFlags_AllowWhenBlockedByActiveItem())
  local rr,gg,bb=rgb(r.GetTrackColor(t.track))
  local light=rgba(math.floor(rr*.55+110),math.floor(gg*.55+110),math.floor(bb*.55+110),255)
  local dark=rgba(math.floor(rr*.70),math.floor(gg*.70),math.floor(bb*.70),255)
  r.ImGui_DrawList_AddRectFilled(dl,x,y,x+w,y+h,light,0)
  if not s.countin then
    if v==9 then
      local f0=b and fills[j][b].f0 or fills[j][1].f0
      local f1=b and fills[j][b].f1 or fills[j][#s.bars].f1
      if f0>0 or f1>0 then
        if f0==0 then
          r.ImGui_DrawList_AddTriangleFilled(dl,x,y+h,x+w,y+h*(1-f1),x+w,y+h,dark)
        elseif f1==0 then
          r.ImGui_DrawList_AddTriangleFilled(dl,x,y+h*(1-f0),x+w,y+h,x,y+h,dark)
        else
          r.ImGui_DrawList_AddQuadFilled(dl,x,y+h*(1-f0),x+w,y+h*(1-f1),x+w,y+h,x,y+h,dark)
        end
      end
    else
      local f=fill_for(v)
      if f>0 then r.ImGui_DrawList_AddRectFilled(dl,x,y+h*(1-f),x+w,y+h,dark,0) end
    end
  end
  r.ImGui_DrawList_AddRect(dl,x,y,x+w,y+h,hovered and 0xFFFFFFFF or 0x00000050,0,0,hovered and 2 or 1)
  local report=t.reports[j]
  if job then
    centered(dl,x,y,w,h,report and (report.state==1 and string.format("%.1f",report.lufs) or "OK") or "·",0x101010FF,0xFFFFFFFF)
  elseif s.countin then centered(dl,x,y,w,h,"—",0x101010FF,0xFFFFFFFF)
  elseif v~=9 then symbol(dl,x,y,w,h,v) end
  if not job and not s.countin then
    if hovered and r.ImGui_IsMouseClicked(ctx,0) then
      stroke={kind="level",t=t,j=j,b=b,tool=tool,ri=ri,ci=ci}
      if tool~=9 then edit_cell(t,j,b,tool);last_paint=id end
    elseif hovered and stroke and stroke.kind=="level" and r.ImGui_IsMouseDown(ctx,0) then
      if stroke.tool~=9 and last_paint~=id then
        -- Interpolate between sampled mouse positions so fast dragging does not skip cells.
        local dr,dc=ri-stroke.ri,ci-stroke.ci
        local steps=math.max(math.abs(dr),math.abs(dc),1)
        for k=1,steps do
          local rr=math.floor(stroke.ri+dr*k/steps+0.5)
          local cc=math.floor(stroke.ci+dc*k/steps+0.5)
          local col=display_cols[cc]
          if rows[rr] and col then edit_cell(rows[rr],col.j,col.b,stroke.tool) end
        end
        stroke.ri,stroke.ci=ri,ci;last_paint=id
      elseif stroke.tool==9 and stroke.t==t then stroke.endj=j;stroke.endb=b end
    end
    popup_level(t,j,b,v,id)
  end
  if hovered and not stroke then
    local b0=t.base[j]
    r.ImGui_SetTooltip(ctx,string.format("%s | %s%s\nTarget %.1f LUFS | calibration %s%s",t.name,s.name,b and (" | Bar "..b) or "",t.target,b0 and string.format("%+.2f dB",b0) or "unmeasured",report and string.format("\nReport %.2f LUFS / %.0f%% coverage",report.lufs,report.coverage*100) or ""))
  end
end
local function set_intensity(j,b,v)
  local s=sections[j]
  if s.countin then return end
  if b then
    s.bars[b].int=v;put("int:"..s.key..":"..b,v)
  else
    s.int=v;put("int:"..s.key,v)
    for k,bar in ipairs(s.bars) do bar.int=v;put("int:"..s.key..":"..k,v) end
  end
  for _,t in ipairs(rows) do if t.depth==0 then dirty[t]=true end end
end
local function intensity_cell(c,contour)
  local s=sections[c.j]
  local v=c.b and s.bars[c.b].int or s.bars[1].int
  if not c.b then for _,bar in ipairs(s.bars) do if bar.int~=v then v=0;break end end end
  local label=s.countin and "—" or v==0 and "Mixed" or v==5 and "" or (c.b and ({"Soft","Normal","Strong","V.Strong"})[v] or intens_names[v])
  local id="##int"..c.j..":"..(c.b or 0)
  local dl=r.ImGui_GetWindowDrawList(ctx)
  local x,y=r.ImGui_GetCursorScreenPos(ctx)
  local clicked=r.ImGui_InvisibleButton(ctx,id,c.w,CELL_H)
  local hover=r.ImGui_IsItemHovered(ctx)
  local light,dark=0xDADADAFF,0x858585FF
  r.ImGui_DrawList_AddRectFilled(dl,x,y,x+c.w,y+CELL_H,light,0)
  local function f(d) return clamp(0.25+0.75*(d+3)/7,0,1) end
  local f0,f1
  if v==5 then
    local a=contour[c.j][c.b or 1]
    local b=contour[c.j][c.b or #s.bars]
    f0,f1=f(a.d0),f(b.d1)
  elseif v==0 then f0,f1=0.5,0.5
  elseif not s.countin then f0,f1=f(intensity[v]),f(intensity[v])
  else f0,f1=0,0 end
  if f0>0 or f1>0 then
    r.ImGui_DrawList_AddQuadFilled(dl,x,y+CELL_H*(1-f0),x+c.w,y+CELL_H*(1-f1),x+c.w,y+CELL_H,x,y+CELL_H,dark)
  end
  r.ImGui_DrawList_AddRect(dl,x,y,x+c.w,y+CELL_H,hover and 0xFFFFFFFF or 0x303030FF,0,0,1)
  if label~="" then centered(dl,x,y,c.w,CELL_H,label,0x101010FF,0xFFFFFFFF) end
  if clicked and not job and not s.countin then
    if tool==9 then set_intensity(c.j,c.b,5)
    else set_intensity(c.j,c.b,v>=1 and v<=4 and v%4+1 or 2) end
  end
  if not job and not s.countin and r.ImGui_BeginPopupContextItem(ctx,"##opts"..id) then
    for k,name in ipairs(intens_names) do if r.ImGui_Selectable(ctx,name,v==k) then set_intensity(c.j,c.b,k) end end
    if r.ImGui_Selectable(ctx,"Transition",v==5) then set_intensity(c.j,c.b,5) end
    r.ImGui_EndPopup(ctx)
  end
  if hover then r.ImGui_SetTooltip(ctx,"Click to cycle intensity; right-click for choices. Select Transition to paint a ramp.") end
end
local function color_header(c)
  local s=sections[c.j]
  local id="##sec"..c.j..":"..(c.b or 0)
  local dl=r.ImGui_GetWindowDrawList(ctx)
  local x,y=r.ImGui_GetCursorScreenPos(ctx)
  local rr,gg,bb=rgb(s.color)
  local clicked=r.ImGui_InvisibleButton(ctx,id,c.w,CELL_H)
  r.ImGui_DrawList_AddRectFilled(dl,x,y,x+c.w,y+CELL_H,rgba(rr,gg,bb,255),3)
  local label=c.b and (c.b==1 and s.name.." −" or tostring(c.b)) or s.name.." +"
  r.ImGui_DrawList_PushClipRect(dl,x+2,y,x+c.w-2,y+CELL_H,true)
  centered(dl,x,y,c.w,CELL_H,label,contrast(rr,gg,bb))
  r.ImGui_DrawList_PopClipRect(dl)
  if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx,s.name..(c.b and " | Bar "..c.b or "").." — click to fold / unfold") end
  if clicked and not job then expanded[s.key]=not expanded[s.key] end
end
local function track_header(t)
  local dl=r.ImGui_GetWindowDrawList(ctx)
  local x,y=r.ImGui_GetCursorScreenPos(ctx)
  local w=161
  r.ImGui_InvisibleButton(ctx,"##track"..t.key,w,CELL_H)
  local rr,gg,bb=rgb(r.GetTrackColor(t.track))
  r.ImGui_DrawList_AddRectFilled(dl,x,y,x+w,y+CELL_H,rgba(rr,gg,bb,255),3)
  local _,th=r.ImGui_CalcTextSize(ctx,t.name)
  r.ImGui_DrawList_PushClipRect(dl,x+5,y,x+w-5,y+CELL_H,true)
  r.ImGui_DrawList_AddText(dl,x+6,y+(CELL_H-th)/2,contrast(rr,gg,bb),t.name)
  r.ImGui_DrawList_PopClipRect(dl)
  if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx,t.name) end
end
local function tool_button(i)
  local dl=r.ImGui_GetWindowDrawList(ctx)
  local x,y=r.ImGui_GetCursorScreenPos(ctx)
  local w=i==9 and 82 or 32
  local clicked=r.ImGui_InvisibleButton(ctx,"##tool"..i,w,CELL_H)
  local hover=r.ImGui_IsItemHovered(ctx)
  r.ImGui_DrawList_AddRectFilled(dl,x,y,x+w,y+CELL_H,tool==i and 0xBDBDBDFF or hover and 0xE5E5E5FF or 0xFFFFFFFF,4)
  r.ImGui_DrawList_AddRect(dl,x,y,x+w,y+CELL_H,0x111111FF,3,0,tool==i and 2.5 or 1)
  if i==9 then centered(dl,x,y,w,CELL_H,"Transition",0x101010FF,0xFFFFFFFF)
  else symbol(dl,x,y,w,CELL_H,i) end
  if hover then r.ImGui_SetTooltip(ctx,i==9 and "Transition" or simple[i]) end
  if clicked then tool=i;transition_start=nil end
end
local function apply_dirty()
  if not next(dirty) or job or r.EnumProjects(-1,"")~=proj or (r.GetPlayStateEx(proj)&4)~=0 then return end
  if r.GetGlobalAutomationOverride()>1 then status="Disable global automation write/bypass before editing.";return end
  r.Undo_BeginBlock2(proj)
  local ok,e=pcall(function()
    for t in pairs(dirty) do
      if valid(t.track) and r.GetMediaTrackInfo_Value(t.track,"B_SHOWINMIXER")>0 and fx_index(t) then
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
local function mono_push(gray)
  local base=gray and 0xC4C4C4FF or 0xFFFFFFFF
  local colors={
    {r.ImGui_Col_Text(),0x111111FF},
    {r.ImGui_Col_Button(),base},
    {r.ImGui_Col_ButtonHovered(),0xE0E0E0FF},
    {r.ImGui_Col_ButtonActive(),0xABABABFF},
    {r.ImGui_Col_FrameBg(),base},
    {r.ImGui_Col_FrameBgHovered(),0xE5E5E5FF},
    {r.ImGui_Col_FrameBgActive(),0xD4D4D4FF},
    {r.ImGui_Col_PopupBg(),base},
    {r.ImGui_Col_Header(),0xB8B8B8FF},
    {r.ImGui_Col_HeaderHovered(),0xD4D4D4FF},
    {r.ImGui_Col_HeaderActive(),0xA0A0A0FF},
    {r.ImGui_Col_Border(),0x202020FF},
    {r.ImGui_Col_TextSelectedBg(),0xAAAAAAFF},
  }
  for _,x in ipairs(colors) do r.ImGui_PushStyleColor(ctx,x[1],x[2]) end
  return #colors
end
local function radio(label,value)
  local dl=r.ImGui_GetWindowDrawList(ctx)
  local x,y=r.ImGui_GetCursorScreenPos(ctx)
  local tw,th=r.ImGui_CalcTextSize(ctx,label)
  local clicked=r.ImGui_InvisibleButton(ctx,"##notation"..label,tw+22,CELL_H)
  local cy=y+CELL_H/2
  r.ImGui_DrawList_AddCircleFilled(dl,x+8,cy,7,0xFFFFFFFF)
  r.ImGui_DrawList_AddCircle(dl,x+8,cy,7,0x111111FF,0,1.5)
  if traditional==value then r.ImGui_DrawList_AddCircleFilled(dl,x+8,cy,3.8,0x111111FF) end
  local text_color=r.ImGui_GetStyleColor(ctx,r.ImGui_Col_Text())
  r.ImGui_DrawList_AddText(dl,x+19,y+(CELL_H-th)/2,text_color,label)
  if clicked then traditional=value;put("traditional",value and 1 or 0) end
end
local function alert_banner()
  if alert_text=="" or r.time_precise()>=alert_until then return end
  local dl=r.ImGui_GetWindowDrawList(ctx)
  local x,y=r.ImGui_GetCursorScreenPos(ctx)
  local w=r.ImGui_GetContentRegionAvail(ctx)
  r.ImGui_Dummy(ctx,w,30)
  r.ImGui_DrawList_AddRectFilled(dl,x,y,x+w,y+30,0xF5F5F5FF,3)
  r.ImGui_DrawList_AddRect(dl,x,y,x+w,y+30,0x111111FF,3,0,1.5)
  centered(dl,x,y,w,30,alert_text,0x111111FF)
end
local function draw()
  r.ImGui_PushStyleVar(ctx,r.ImGui_StyleVar_Alpha(),1)
  r.ImGui_PushStyleVar(ctx,r.ImGui_StyleVar_FramePadding(),4,3)
  r.ImGui_PushStyleVar(ctx,r.ImGui_StyleVar_ItemSpacing(),4,3)
  r.ImGui_PushStyleVar(ctx,r.ImGui_StyleVar_CellPadding(),3,2)
  local bg=r.ImGui_GetStyleColor(ctx,r.ImGui_Col_WindowBg()) | 0xff
  r.ImGui_PushStyleColor(ctx,r.ImGui_Col_WindowBg(),bg)
  r.ImGui_PushStyleColor(ctx,r.ImGui_Col_ChildBg(),bg)
  if ui_font then
    -- Probe PushFont itself: CreateFont can accept a numeric flags argument
    -- in 0.10, so successful font creation does not identify the API version.
    if font_new_api==nil then
      local ok=pcall(r.ImGui_PushFont,ctx,ui_font,UI_SIZE)
      font_new_api=ok
      if not ok then r.ImGui_PushFont(ctx,ui_font) end
    elseif font_new_api then
      r.ImGui_PushFont(ctx,ui_font,UI_SIZE)
    else
      r.ImGui_PushFont(ctx,ui_font)
    end
  end
  r.ImGui_SetNextWindowSize(ctx,1000,480,r.ImGui_Cond_FirstUseEver())
  r.ImGui_SetNextWindowBgAlpha(ctx,1)
  local visible,open=r.ImGui_Begin(ctx,"N2N Mix",true)
  if visible then
    local nmono=mono_push(false)
    if not job then button("Auto Mix",start)
    else button("Cancel",function() finish("Cancelled. Undo to revert partial changes.") end) end
    r.ImGui_PopStyleColor(ctx,nmono)
    same();r.ImGui_Text(ctx,status)
    if job then
      local d,n=poll()
      r.ImGui_ProgressBar(ctx,n>0 and d/n or 0,-1,0,string.format("Stage %d/%d | %d/%d reports",job.index,#job.queue,d,n))
    else
      r.ImGui_Text(ctx,"Master Target");same()
      nmono=mono_push(false)
      r.ImGui_SetNextItemWidth(ctx,205)
      if r.ImGui_BeginCombo(ctx,"##mastertarget",presets[preset][1]) then
        for i,p in ipairs(presets) do if r.ImGui_Selectable(ctx,p[1],i==preset) then preset=i;put("preset",i) end end
        r.ImGui_EndCombo(ctx)
      end
      if preset==#presets then
        same();r.ImGui_SetNextItemWidth(ctx,145)
        local ch,v=r.ImGui_InputDouble(ctx,"##customlufs",custom,1,1,"%.1f")
        if ch then custom=clamp(v,-35,-8);put("custom",custom) end
      end
      r.ImGui_PopStyleColor(ctx,nmono)
      same();r.ImGui_Text(ctx,string.format("%.1f LUFS | sample peak %.1f dBFS",master_target(),peak_ceiling))
      radio("Simple",false);same();radio("Traditional",true)
      for i=1,9 do same();tool_button(i) end
    end
    alert_banner()
    r.ImGui_Separator(ctx)
    if #sections>0 then
      local cols,total={},0
      for j,s in ipairs(sections) do
        if expanded[s.key] then
          for b=1,#s.bars do
            local w=b==1 and math.max(92,r.ImGui_CalcTextSize(ctx,s.name.." −")+14) or 70
            cols[#cols+1]={j=j,b=b,w=w};total=total+w+GAP
          end
        else
          local w=math.max(94,r.ImGui_CalcTextSize(ctx,s.name.." +")+14)
          cols[#cols+1]={j=j,w=w};total=total+w+GAP
        end
      end
      display_cols=cols
      local flags=r.ImGui_TableFlags_ScrollX() | r.ImGui_TableFlags_ScrollY() | r.ImGui_TableFlags_SizingFixedFit()
      -- Only two actual table columns: the entire song strip can exceed the native
      -- ImGui column limit without losing the frozen track header.
      if r.ImGui_BeginTable(ctx,"##mixgrid",2,flags,0,0,LEFT_W+total+32) then
        r.ImGui_TableSetupColumn(ctx,"Track",r.ImGui_TableColumnFlags_WidthFixed(),LEFT_W)
        r.ImGui_TableSetupColumn(ctx,"Song",r.ImGui_TableColumnFlags_WidthFixed(),total+8)
        r.ImGui_TableSetupScrollFreeze(ctx,1,2)
        local function across(fn)
          for i,c in ipairs(cols) do
            if i>1 then r.ImGui_SameLine(ctx,0,GAP) end
            fn(c,i)
          end
        end
        r.ImGui_TableNextRow(ctx,0,CELL_H)
        r.ImGui_TableSetColumnIndex(ctx,0);r.ImGui_AlignTextToFramePadding(ctx);r.ImGui_Text(ctx,"Track / Role / Target")
        r.ImGui_TableSetColumnIndex(ctx,1);across(color_header)
        r.ImGui_TableNextRow(ctx,0,CELL_H)
        r.ImGui_TableSetColumnIndex(ctx,0);r.ImGui_AlignTextToFramePadding(ctx);r.ImGui_Text(ctx,"Section intensity")
        local contour=intensity_contour()
        r.ImGui_TableSetColumnIndex(ctx,1);across(function(c) intensity_cell(c,contour) end)
        for ri,t in ipairs(rows) do
          r.ImGui_TableNextRow(ctx,0,CELL_H)
          r.ImGui_TableSetColumnIndex(ctx,0)
          track_header(t)
          r.ImGui_SameLine(ctx,0,GAP)
          local role_colors=mono_push(true)
          r.ImGui_SetNextItemWidth(ctx,150)
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
          r.ImGui_PopStyleColor(ctx,role_colors)
          r.ImGui_SameLine(ctx,0,GAP);r.ImGui_SetNextItemWidth(ctx,57)
          local ch,v=r.ImGui_InputDouble(ctx,"##target"..t.key,t.target,0,0,"%.1f")
          if ch and not job then
            local old=t.target;t.target=clamp(v,-60,-8);put("target:"..t.key,t.target)
            for j,base in pairs(t.base) do t.base[j]=clamp(base+t.target-old,-30,24);put("base:"..t.key..":"..sections[j].key,t.base[j]) end
            dirty[t]=true
          end
          r.ImGui_TableSetColumnIndex(ctx,1)
          local fills=transition_fills(t)
          across(function(c,ci) cell(t,c.j,c.b,c.w,fills,ri,ci) end)
        end
        r.ImGui_EndTable(ctx)
      end
    end
    r.ImGui_End(ctx)
  end
  if ui_font then r.ImGui_PopFont(ctx) end
  r.ImGui_PopStyleColor(ctx,2);r.ImGui_PopStyleVar(ctx,4)
  if not r.ImGui_IsMouseDown(ctx,0) then
    if stroke and stroke.tool==9 and not job then
      local s=stroke
      if s.endj and (s.j~=s.endj or s.b~=s.endb) then
        transition_start={t=s.t,j=s.j,b=s.b};edit_cell(s.t,s.endj,s.endb,9)
      else edit_cell(s.t,s.j,s.b,9) end
    end
    stroke=nil;last_paint=nil;apply_dirty()
  end
  return open
end
if not r.ImGui_CreateContext then r.MB("ReaImGui is required.","N2N Mix",0);return end
ctx=r.ImGui_CreateContext("N2N Mix")
-- ReaImGui 0.10: CreateFont(family[, flags]), PushFont(ctx,font,size).
-- ReaImGui 0.9: CreateFont(family,size[, flags]), PushFont(ctx,font).
local ok_font,font=pcall(r.ImGui_CreateFont,"sans-serif")
if ok_font and font then
  ui_font=font
else
  ui_font=r.ImGui_CreateFont("sans-serif",UI_SIZE)
end
r.ImGui_Attach(ctx,ui_font)
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
