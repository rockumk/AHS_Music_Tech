-- @description N2N Mix
-- @version 0.2.16
-- @noindex
-- First functional test. Requires the unchanged N2N Mix Meter.jsfx and ReaImGui.
local r=reaper
local proj=r.EnumProjects(-1,"")
local NS="N2N_Mix_Analysis_v1"
local STORE="N2N Mix v1"
local MAX=256
local FXNAME="N2N Mix Meter"
local PERFNAME="Performance Dynamics"
local timbres={"None","Brass / Sax","Drums","Acoustic Guitar","Voice","Piano","Bowed Strings","Electric Bass","Upright Bass","Electric Guitar","Small Plucked","Clarinet","Flute","Double Reeds","Low Brass / Bari Sax"}
local roles={"Lead Vocal","Lead Instrument","Drums","Bass","Primary Accomp.","BG Vocals","Secondary Accomp.","Traditional Arp","Pad / Texture","Effects","Unclassified","Buss"}
local defaults={-22,-24,-25,-25,-27,-28,-30,-32,-35,-40,-30,-27}
-- Preserve stored IDs: 5 is section transition, 6 is Silent; 7 is retired track level.
local intensity={-3,0,2,4,[6]=-60}
local intens_names={"Soft","Normal","Strong","Very Strong",[5]="Transition",[6]="Silent"}
local intensity_ids={6,1,2,3,4,5}
local levels={-60,-10,-5,0,5,10,15,15}
local simple={"Mute","Very Low","Low","Mid","High","Very High","Very High","Star"}
local trad={"0","p","mp","•","mf","f","f","★"}
local tool_ids={1,2,3,4,5,6,8,9}
local presets={{"YouTube",-14},{"Spotify",-14},{"Apple Music",-16},{"General streaming",-14},{"Dynamic master",-18},{"Premaster",-20},{"EBU R128",-23},{"Custom",-16}}
local sections,rows,master,groups={}, {},nil,{}
local job,pass=nil,nil
local status="Ready."
local log={}
local traditional=false
local tool=4
local intensity_tool=2
local mono_push
local expanded={}
local dirty={}
local master_dirty=false
local transition_start=nil
local last_paint=nil
local stroke=nil
local ui_font=nil
local UI_SIZE=13
local CELL_H=26
local LEFT_W=535
local ui={role=true,timbre=true,pan_transition=false,pan_start=nil,pan_stroke=nil}
function ui.header_width()
  return 161+3*(22+3)+6+(ui.role and 153 or 35)+(ui.timbre and 153 or 35)
end
local ALL_W=68
local TARGET_H=CELL_H
local edit_mode="levels"
local show_parameters=false
local pan_dirty={}
local pan_scan_pending=true
local pan_drag=nil
local GAP=3
local display_cols={}
local font_new_api=nil
local preset=1
local custom=-16
local DEFAULT_PRESET=1
local last_preset,last_custom=1,-16
local target_popup=false
local peak_ceiling=-2 -- sample-peak guard; not a true-peak guarantee
local boundary_ramp=0.250 -- seconds; ordinary level changes, not explicit transitions
local alert_text,alert_until="",0
local pending_start=nil
local alert_x,alert_y
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
local function new_ramp()
  local id=num("ramp_serial",0)+1;put("ramp_serial",id);return id
end
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
local function perf_index(t)
  if not valid(t.track) or not t.perfguid then return nil end
  for i=0,r.TrackFX_GetCount(t.track)-1 do
    if r.TrackFX_GetFXGUID(t.track,i)==t.perfguid then return i end
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
    s.int=clamp(num("int:"..s.key,2),1,6)
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
      s.bars[b]={a=start,b=e,int=clamp(num("int:"..s.key..":"..b,s.int),1,6),ramp=num("iramp:"..s.key..":"..b,0)}
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
local function project_layout_signature()
  local parts={}
  local function add(...) local v={...};for i=1,#v do v[i]=tostring(v[i]) end;parts[#parts+1]=table.concat(v,"|") end
  for i=0,r.CountTracks(proj)-1 do
    local t=r.GetTrack(proj,i);local _,name=r.GetTrackName(t)
    add(track_key(t),name,r.GetMediaTrackInfo_Value(t,"B_SHOWINMIXER"),r.GetMediaTrackInfo_Value(t,"B_MAINSEND"),r.GetMediaTrackInfo_Value(t,"I_FOLDERDEPTH"))
    for k=0,r.GetTrackNumSends(t,0)-1 do
      local dest=r.GetTrackSendInfo_Value(t,0,k,"P_DESTTRACK")
      add(dest and track_key(dest) or "",r.GetTrackSendInfo_Value(t,0,k,"I_SRCCHAN"),r.GetTrackSendInfo_Value(t,0,k,"I_SENDMODE"),r.GetTrackSendInfo_Value(t,0,k,"B_MUTE"))
    end
  end
  local i=0
  while true do
    local ok,region,a,b,name,id,col=r.EnumProjectMarkers3(proj,i)
    if ok==0 then break end
    if region then add(id,a,b,name,col,r.TimeMap2_timeToQN(proj,a),r.TimeMap2_timeToQN(proj,b)) end
    i=i+1
  end
  return table.concat(parts,"\n")
end
local function refresh()
  pan_scan_pending=true;pan_dirty={};pan_drag=nil;ui.pan_start=nil;ui.pan_stroke=nil
  layout_sig=project_layout_signature()  local a,err=read_sections()
  if not a then sections={};rows={};groups={};status=err;return false end
  sections=a; rows={}; groups={}; dirty={}; master_dirty=false; transition_start=nil
  local byptr={}
  for i=0,r.CountTracks(proj)-1 do
    local t=r.GetTrack(proj,i)
    if r.GetMediaTrackInfo_Value(t,"B_SHOWINMIXER")>0 then
      local _,name=r.GetTrackName(t)
      local row={track=t,key=track_key(t),name=name,fxguid=get_owned(t),cells={},ramps={},pans={},panramps={},base={},reports={},deps={},depth=0}
      local _,initial=r.GetSetMediaTrackInfo_String(t,"P_EXT:N2N_MIX_INITIAL_DB","",false)
      row.initial=clamp(tonumber(initial) or 0,-60,30)
      row.bus=false
      for k=0,r.GetTrackNumSends(t,-1)-1 do
        if r.GetTrackSendInfo_Value(t,-1,k,"I_SRCCHAN")>=0 and r.GetTrackSendInfo_Value(t,-1,k,"B_MUTE")==0 then row.bus=true;break end
      end
      row.role=clamp(num("role:"..row.key,role_guess(t,name,row.bus)),1,#roles)
      row.target=num("target:"..row.key,defaults[row.role])
      local _,pg=r.GetSetMediaTrackInfo_String(t,"P_EXT:N2N_PERF_FX","",false)
      local _,pm=r.GetSetMediaTrackInfo_String(t,"P_EXT:N2N_PERF_MODEL","",false)
      row.perfguid=pg~="" and pg or nil
      local _,id=r.GetSetMediaTrackInfo_String(t,"P_EXT:N2N:ID","",false)
      local recipe=tonumber(id:match("^(%d+)_"))
      local known=recipe==31 and 1 or recipe==20 and 6 or -1
      row.model=clamp(tonumber(pm) or known,-1,13)
      -- A MIDI receive may still have audio channels configured. Role, not
      -- the mere presence of receives, determines timbre eligibility.
      row.timbre_allowed=row.role~=10 and row.role~=12
      for j,s in ipairs(sections) do
        local prefix=row.key..":"..s.key
        row.cells[j]={};row.ramps[j]={};row.pans[j]={};row.panramps[j]={}
        for b=1,#s.bars do
          local v=clamp(num("cell:"..prefix..":"..b,4),1,9)
          row.cells[j][b]=v==7 and 6 or v
          row.ramps[j][b]=num("ramp:"..prefix..":"..b,0)
          row.pans[j][b]=clamp(num("pan:"..prefix..":"..b,0),-100,100)
          row.panramps[j][b]=num("panramp:"..prefix..":"..b,0)
        end
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
  if not ok then groups={};status=tostring(e);return false end
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
local function is_performance_name(n)
  n=(n or ""):lower()
  return n:find("performance dynamics",1,true) or n:find("tickle whale",1,true)
end
local function has_position(t,f)
  if not f or f<0 or r.TrackFX_GetNumParams(t.track,f)<=10 then return false end
  local ok,name=r.TrackFX_GetParamName(t.track,f,10,"")
  local _,lo,hi=r.TrackFX_GetParam(t.track,f,10)
  return ok and (name:lower():find("position",1,true) or name:lower():find("pan",1,true)) and lo and hi and lo<=-100 and hi>=100
end
function ui.has_volume_envelope(t)
  return active_env(r.GetTrackEnvelopeByChunkName(t.track,"<VOLENV2")) or active_env(r.GetTrackEnvelopeByChunkName(t.track,"<VOLENV")) or active_env(r.GetTrackEnvelopeByName(t.track,"Volume"))
end
function ui.set_unity_unless_automated(t)
  if not ui.has_volume_envelope(t) then r.SetMediaTrackInfo_Value(t.track,"D_VOL",1) end
end
local function safe_row(t)
  if not valid(t.track) then return false,"Track no longer exists: "..t.name end
  if r.GetMediaTrackInfo_Value(t.track,"I_FXEN")==0 then return false,"Track FX chain bypassed: "..t.name end
  local mode=r.GetMediaTrackInfo_Value(t.track,"I_AUTOMODE")
  if mode>1 then return false,"Change automation mode to Trim/Read or Read: "..t.name end
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
  local pf=perf_index(t)
  if pf then
    local _,n=r.TrackFX_GetFXName(t.track,pf,"")
    if not is_performance_name(n) then return false,"Owned Performance Dynamics GUID mismatch: "..t.name end
    if i and pf~=i-1 then return false,"Move Performance Dynamics immediately before N2N Mix Meter: "..t.name end
    local pe=r.GetFXEnvelope(t.track,pf,0,false)
    if pe and r.CountAutomationItems(pe)>0 then return false,"Performance intensity envelope has automation items: "..t.name end
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
local function envelope(t,live,fx,param,force_hidden)
  local f=fx or ensure_fx(t)
  param=param or 0
  local env=r.GetFXEnvelope(t.track,f,param,true)
  if not env then error("Cannot create gain envelope: "..t.name) end
  local ok,c=r.GetEnvelopeStateChunk(env,"",false)
  if not ok then error("Cannot read gain envelope: "..t.name) end
  -- Raw PARMENV range may be native slider units or normalized, depending on FX.
  local lo,hi=c:match("<PARMENV%s+%S+%s+([%+%-%.%deE]+)%s+([%+%-%.%deE]+)")
  lo,hi=tonumber(lo),tonumber(hi)
  if not lo or not hi or hi<=lo then error("Unrecognized PARMENV range: "..t.name) end
  c=c:gsub("([\r\n]ACT%s+)%d+", function(p) return p.."1" end,1)
  c=c:gsub("([\r\n]VIS%s+)%d+", function(p) return p..(show_parameters and not force_hidden and "1" or "0") end,1)
  c=c:gsub("([\r\n]ARM%s+)%d+", function(p) return p.."0" end,1)
  if live then return env,lo,hi,c end
  if not r.SetEnvelopeStateChunk(env,c,false) then error("Cannot configure gain envelope: "..t.name) end
  env=r.GetFXEnvelope(t.track,f,param,false)
  if r.CountAutomationItems(env)>0 then error("Unexpected automation items: "..t.name) end
  r.DeleteEnvelopePointRangeEx(env,-1,-1e9,1e9)
  return env,lo,hi
end
local function write_points(t,pts,fx,minval,maxval,param,force_hidden)
  minval,maxval=minval or -60,maxval or 30
  local live=(r.GetPlayStateEx(proj)&1)~=0
  local env,lo,hi,chunk=envelope(t,live,fx,param,force_hidden)
  if live then
    -- Replace the point list in one host update during playback, rather than
    -- leaving a temporarily empty gain envelope between individual calls.
    if r.CountAutomationItems(env)>0 then error("Unexpected automation items: "..t.name) end
    chunk=chunk:gsub("\r\n","\n"):gsub("\n[ \t]*PT[ \t][^\n]*","")
    local close=chunk:match("()>%s*$")
    if not close then error("Invalid envelope chunk: "..t.name) end
    local lines={}
    for _,p in ipairs(pts) do
      local raw=lo+(clamp(p[2],minval,maxval)-minval)/(maxval-minval)*(hi-lo)
      lines[#lines+1]=string.format("PT %.12f %.12f %d 0 0",p[1],raw,p[3] or 0)
    end
    local replacement=chunk:sub(1,close-1):gsub("%s*$","").."\n"..table.concat(lines,"\n").."\n"..chunk:sub(close)
    if not r.SetEnvelopeStateChunk(env,replacement,false) then error("Cannot update live gain envelope: "..t.name) end
    return
  end
  for _,p in ipairs(pts) do
    local db=clamp(p[2],minval,maxval)
    local raw=lo+(db-minval)/(maxval-minval)*(hi-lo)
    if not r.InsertEnvelopePointEx(env,-1,p[1],raw,p[3] or 0,0,false,true) then error("Cannot insert gain point: "..t.name) end
  end
  r.Envelope_SortPointsEx(env,-1)
end
local function flat(t,db) write_points(t,{{0,db,0}}) end
local section_fill={[6]=0,[1]=0.25,[2]=0.5,[3]=0.75,[4]=1}
-- Fade progress is a linear musical contour, not a linear interpolation of -60 dB.
local function section_db(f)
  f=clamp(f,0,1)
  if f<=0 then return -60 end
  if f<0.25 then return math.max(-60,-3+20*math.log(f/0.25,10)) end
  if f<0.5 then return -3+12*(f-0.25) end
  return 8*(f-0.5)
end
local function ramp_chain(all,first,transition,fill,low,high)
  -- Contiguous transition bars are divided into individual painted spans.
  -- Legacy spans have id 0. Adjacent independently painted spans alternate
  -- peak/valley at their shared boundaries instead of collapsing into one.
  local i=first;local spans={}
  while i<=#all and all[i].v==transition and not all[i].ignore and (i==first or math.abs(all[i].a-all[i-1].b)<0.001) do
    local x=all[i];local span=spans[#spans]
    if not span or span.id~=x.ramp then span={first=i,last=i,id=x.ramp};spans[#spans+1]=span else span.last=i end
    i=i+1
  end
  local p,n=all[first-1],all[i]
  local left=p and not p.ignore and math.abs(p.b-all[first].a)<0.001 and p or nil
  local right=n and not n.ignore and math.abs(n.a-all[i-1].b)<0.001 and n or nil
  local rising=not left or fill(left.v)<=0.5
  for k,span in ipairs(spans) do
    span.left=k==1 and left or nil;span.right=k==#spans and right or nil
    span.lv=k==1 and (left and left.v or low) or ((k%2==0)==rising and high or low)
    span.rv=k==#spans and (right and right.v or low) or ((k%2==1)==rising and high or low)
  end
  return spans,i
end
local function intensity_contour()
  local all,map={},{}
  for j,s in ipairs(sections) do
    map[j]={}
    for b,bar in ipairs(s.bars) do
      local x={a=bar.a,b=bar.b,v=bar.int,ramp=bar.ramp or 0,ignore=s.countin}
      all[#all+1]=x;map[j][b]=x
    end
  end
  local i=1
  while i<=#all do
    local x=all[i]
    if x.v~=5 or x.ignore then
      x.f0=x.ignore and 0.5 or (section_fill[x.v] or 0.5);x.f1=x.f0
      x.d0=section_db(x.f0);x.d1=x.d0;i=i+1
    else
      local spans,next_i=ramp_chain(all,i,5,function(v) return section_fill[v] or 0.5 end,6,4)
      i=next_i
      for _,span in ipairs(spans) do
        local a,z=section_fill[span.lv],section_fill[span.rv]
        local t0,t1=all[span.first].a,all[span.last].b
        for k=span.first,span.last do
          local b=all[k]
          b.f0=a+(z-a)*(b.a-t0)/(t1-t0);b.f1=a+(z-a)*(b.b-t0)/(t1-t0)
          b.d0=section_db(b.f0);b.d1=section_db(b.f1)
        end
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
    local x,y=10^(math.max(-3,b.d0)/10),10^(math.max(-3,b.d1)/10)
    local mean=math.abs(x-y)<1e-8 and x or (y-x)/(math.log(y)-math.log(x))
    energy=energy+d*mean;duration=duration+d
  end
  return duration>0 and 10*math.log(energy/duration,10) or 0
end
local function perf_volume(t,p)
  return p>=0 and p*(t.perfboost or 7)/100 or p*(t.perfcut or 4)/100
end
local function calc_base(t,j,v)
  if sections[j].countin or not v or v.state~=1 or math.abs(v.coverage-1)>0.02 then return nil end
  local adjustment=t.depth>0 and section_intensity(sections[j],j) or 0
  -- Measure the changed timbre and room directly; estimate the nominal volume
  -- component across the section to retain rather than erase the grid contour.
  if t.perfplan and t.perfplan[j] then
    local desired,residual,duration=0,0,0
    for b,span in ipairs(sections[j].bars) do
      local p=t.perfplan[j][b]
      if p and not p.mute then
        for k=1,16 do
          local u=(k-0.5)/16;local d=(span.b-span.a)/16
          local want=p.want(u);local nominal=perf_volume(t,p.value(u))
          desired=desired+d*10^(want/10)
          residual=residual+d*10^((want-nominal)/10)
          duration=duration+d
        end
      end
    end
    if duration>0 and residual>0 then adjustment=10*math.log(desired/residual,10) end
  end
  return clamp(t.target+adjustment-v.lufs,-30,24)
end
local function offset(v) return levels[v] or 0 end
local function contour_points(bars,initial)
  local pts={}
  local function add(t,v,shape) 
    if #pts>0 and math.abs(pts[#pts][1]-t)<0.0000001 then pts[#pts]={t,v,shape} else pts[#pts+1]={t,v,shape} end
  end
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
  return pts
end
local function track_fill(v) return v==0 and 0.5 or v==8 and 1 or (math.min(v,6)-1)/6 end
local perf_levels={[1]=0,[2]=-100,[3]=-50,[4]=0,[5]=33,[6]=67,[8]=100}
local function section_perf(f)
  if f<=0.25 then return -20 end
  if f<0.5 then return -20+80*(f-0.25) end
  return 60*(f-0.5)
end
local function make_perf_plan(t)
  local all,map={},{}
  local section=intensity_contour()
  for j,s in ipairs(sections) do
    map[j]={}
    for b,bar in ipairs(s.bars) do
      local v=t.cells[j][b]
      local x={a=bar.a,b=bar.b,v=v,ramp=t.ramps[j][b] or 0,ignore=s.countin,sec=section[j][b]}
      all[#all+1]=x;map[j][b]=x
    end
  end
  local i=1
  while i<=#all do
    local x=all[i]
    if x.v~=9 or x.ignore then
      x.p0=x.ignore and 0 or (perf_levels[x.v] or 0);x.p1=x.p0
      x.w0=x.ignore and 0 or (levels[x.v] or 0);x.w1=x.w0;i=i+1
    else
      local spans,next_i=ramp_chain(all,i,9,track_fill,1,8)
      i=next_i
      for _,s in ipairs(spans) do
        local p0=s.lv==1 and -100 or perf_levels[s.lv] or 0
        local p1=s.rv==1 and -100 or perf_levels[s.rv] or 0
        local w0,w1=levels[s.lv] or 0,levels[s.rv] or 0
        local a,z=all[s.first].a,all[s.last].b
        for k=s.first,s.last do
          local b=all[k];local u,v=(b.a-a)/(z-a),(b.b-a)/(z-a)
          b.p0=p0+(p1-p0)*u;b.p1=p0+(p1-p0)*v
          b.w0=w0+(w1-w0)*u;b.w1=w0+(w1-w0)*v
        end
      end
    end
  end
  for _,p in ipairs(all) do
    p.mute=p.v==1 or p.ignore
    p.value=function(u)
      if p.mute then return 0 end
      local f=p.sec.f0+(p.sec.f1-p.sec.f0)*u
      return clamp(p.p0+(p.p1-p.p0)*u+(t.depth==0 and section_perf(f) or 0),-100,100)
    end
    p.want=function(u)
      local f=p.sec.f0+(p.sec.f1-p.sec.f0)*u
      return p.w0+(p.w1-p.w0)*u+(t.depth==0 and math.max(-3,section_db(f)) or 0)
    end
  end
  return map
end
-- Install or reuse the processor for position on every visible track.
-- The older ten-slider version is deliberately not treated as a pan FX.
local function ensure_position_fx(t)
  local f=perf_index(t)
  if f then
    local _,name=r.TrackFX_GetFXName(t.track,f,"")
    if not is_performance_name(name) then return nil,"Owned performance FX mismatch: "..t.name end
  else
    local found
    for i=0,r.TrackFX_GetCount(t.track)-1 do
      local _,name=r.TrackFX_GetFXName(t.track,i,"")
      if is_performance_name(name) then
        if found then return nil,"Multiple performance processors: "..t.name end
        found=i
      end
    end
    if found then
      if not has_position(t,found) then return nil,"Update Performance Dynamics: "..t.name.." (no Position slider 11)" end
      for _,p in ipairs({0,10}) do
        local e=r.GetFXEnvelope(t.track,found,p,false)
        if e and active_env(e) then return nil,"Existing unowned performance automation: "..t.name end
      end
      f=found
    else
      if not stopped() then return nil,"Stop transport to install Performance Dynamics." end
      local meter=fx_index(t)
      local at=meter or r.TrackFX_GetCount(t.track)
      f=r.TrackFX_AddByName(t.track,"JS: Performance Dynamics.jsfx",false,-1000-at)
      if f<0 then f=r.TrackFX_AddByName(t.track,"JS: Performance Dynamics",false,-1000-at) end
      if f<0 then return nil,"Install the updated Performance Dynamics JSFX." end
      if not has_position(t,f) then
        r.TrackFX_Delete(t.track,f)
        return nil,"Installed Performance Dynamics has no Position slider 11. Update the JSFX."
      end
    end
    t.perfguid=r.TrackFX_GetFXGUID(t.track,f)
    r.GetSetMediaTrackInfo_String(t.track,"P_EXT:N2N_PERF_FX",t.perfguid,true)
  end
  if not has_position(t,f) then return nil,"Update Performance Dynamics: "..t.name.." (no Position slider 11)" end
  local meter=fx_index(t)
  if meter and f~=meter-1 then return nil,"Move Performance Dynamics immediately before N2N Mix Meter: "..t.name end
  if r.TrackFX_GetOffline(t.track,f) then return nil,"Bring Performance Dynamics online: "..t.name end
  return f
end
-- None means no expressive intensity, not bypass of the entire pan processor.
local function position_only(t,f)
  local _,room=r.GetSetMediaTrackInfo_String(t.track,"P_EXT:N2N_PERF_SAVED_ROOM","",false)
  if room=="" then
    r.GetSetMediaTrackInfo_String(t.track,"P_EXT:N2N_PERF_SAVED_ROOM",tostring(r.TrackFX_GetParam(t.track,f,8)),true)
  end
  r.TrackFX_SetParam(t.track,f,8,0)
  r.TrackFX_SetEnabled(t.track,f,true)
  write_points(t,{{0,0,0}},f,-100,100,0)
  t.perfplan=nil
end
local function restore_performance_room(t,f)
  local _,room=r.GetSetMediaTrackInfo_String(t.track,"P_EXT:N2N_PERF_SAVED_ROOM","",false)
  if tonumber(room) then
    r.TrackFX_SetParam(t.track,f,8,tonumber(room))
    r.GetSetMediaTrackInfo_String(t.track,"P_EXT:N2N_PERF_SAVED_ROOM","",true)
  end
end
-- A transition stores a span ID, leaving the fixed pan values available
-- as fallback endpoints. Neighboring fixed cells determine the audible ramp.
function ui.pan_contour(t)
  local all,map={},{}
  for j,s in ipairs(sections) do
    map[j]={}
    for b,bar in ipairs(s.bars) do
      local x={a=bar.a,b=bar.b,v=t.pans[j][b],ramp=t.panramps[j][b] or 0}
      all[#all+1]=x;map[j][b]=x
    end
  end
  local i=1
  while i<=#all do
    local x=all[i]
    if x.ramp==0 then x.g0=x.v;x.g1=x.v;i=i+1
    else
      local first=i
      while i<#all and all[i+1].ramp==x.ramp and math.abs(all[i].b-all[i+1].a)<0.001 do i=i+1 end
      local last=i
      local prev,nextb=all[first-1],all[last+1]
      local a=prev and math.abs(prev.b-x.a)<0.001 and (prev.g1 or prev.v) or x.v
      local z=nextb and math.abs(all[last].b-nextb.a)<0.001 and nextb.v or all[last].v
      local begin,finish=x.a,all[last].b
      for k=first,last do
        local b=all[k]
        b.g0=a+(z-a)*(b.a-begin)/(finish-begin)
        b.g1=a+(z-a)*(b.b-begin)/(finish-begin)
      end
      i=last+1
    end
  end
  return all,map
end
-- Display mirrors use the identical contour, not the native track fader.
-- Look up by label rather than assuming contiguous JSFX parameter indices:
-- the Drum Arranger leaves slider13/14 unused.
function ui.mirror_mix_points(t,pts,kind)
  if not valid(t.track) then return end
  local label=kind=="level" and "n2n mix level" or "n2n mix position"
  local lo,hi=kind=="level" and -60 or -100,kind=="level" and 30 or 100
  for fx=0,r.TrackFX_GetCount(t.track)-1 do
    local _,name=r.TrackFX_GetFXName(t.track,fx,"")
    local n=(name or ""):lower()
    if n:find("n2n arp",1,true) or n:find("n2n drum arranger",1,true) then
      for p=0,r.TrackFX_GetNumParams(t.track,fx)-1 do
        local ok,pname=r.TrackFX_GetParamName(t.track,fx,p,"")
        if ok and pname:lower():gsub("^%-","")==label then
          local _,a,b=r.TrackFX_GetParam(t.track,fx,p)
          if a and b and math.abs(a-lo)<.001 and math.abs(b-hi)<.001 then
            local env=r.GetFXEnvelope(t.track,fx,p,false)
            if not env or r.CountAutomationItems(env)==0 then
              local success,err=pcall(write_points,t,pts,fx,lo,hi,p,true)
              if not success then r.ShowConsoleMsg("N2N Mix display mirror: "..t.name..": "..tostring(err).."\n") end
            else r.ShowConsoleMsg("N2N Mix display mirror: automation items on "..t.name.."; skipped.\n") end
          end
          break
        end
      end
    end
  end
end
function ui.mirror_existing_gain(t)
  local fx=fx_index(t)
  if not fx then return end
  local env=r.GetFXEnvelope(t.track,fx,0,false)
  if not env or not active_env(env) or r.CountAutomationItems(env)>0 then return end
  local ok,c=r.GetEnvelopeStateChunk(env,"",false)
  if not ok then return end
  local lo,hi=c:match("<PARMENV%s+%S+%s+([%+%-%.%deE]+)%s+([%+%-%.%deE]+)")
  lo,hi=tonumber(lo),tonumber(hi)
  if not lo or not hi or hi<=lo then return end
  local pts={}
  for i=0,r.CountEnvelopePointsEx(env,-1)-1 do
    local got,time,v,shape=r.GetEnvelopePointEx(env,-1,i)
    if got then pts[#pts+1]={time,-60+90*(v-lo)/(hi-lo),shape} end
  end
  if #pts>0 then ui.mirror_mix_points(t,pts,"level") end
end
local function apply_pan(t,f)
  local state=r.GetPlayStateEx(proj)
  if (state&4)~=0 or r.GetGlobalAutomationOverride()>1 or r.GetMediaTrackInfo_Value(t.track,"I_AUTOMODE")>1 then error("Use Read or Trim/Read before editing pan: "..t.name,0) end
  if r.GetMediaTrackInfo_Value(t.track,"I_FXEN")==0 then error("Track FX chain bypassed: "..t.name,0) end
  f=f or perf_index(t)
  if not has_position(t,f) then error("Updated Position slider 11 required: "..t.name,0) end
  local e=r.GetFXEnvelope(t.track,f,10,false)
  if e and r.CountAutomationItems(e)>0 then error("Position envelope contains automation items: "..t.name,0) end
  local bars=ui.pan_contour(t)
  local pts=contour_points(bars,0)
  write_points(t,pts,f,-100,100,10)
  ui.mirror_mix_points(t,pts,"position")
end
local function configure_perf(t)
  local f=perf_index(t)
  if not t.timbre_allowed or t.model<0 then
    if has_position(t,f) then position_only(t,f)
    elseif f then r.TrackFX_SetEnabled(t.track,f,false) end
    t.perfplan=nil;return
  end
  local meter=ensure_fx(t)
  if not f then
    for i=0,r.TrackFX_GetCount(t.track)-1 do
      local _,n=r.TrackFX_GetFXName(t.track,i,"")
      if is_performance_name(n) then error("Unowned Performance Dynamics on "..t.name.."; remove it or use None.",0) end
    end
    if not stopped() then error("Stop playback to install Performance Dynamics: "..t.name,0) end
    f=r.TrackFX_AddByName(t.track,"JS: Performance Dynamics.jsfx",false,-1000-meter)
    if f<0 then f=r.TrackFX_AddByName(t.track,"JS: Performance Dynamics (14-Instrument Clean Headroom Prototype)",false,-1000-meter) end
    if f<0 then error("Install Performance Dynamics.jsfx first.",0) end
    t.perfguid=r.TrackFX_GetFXGUID(t.track,f)
    r.GetSetMediaTrackInfo_String(t.track,"P_EXT:N2N_PERF_FX",t.perfguid,true)
  end
  if f~=fx_index(t)-1 then error("Performance Dynamics must immediately precede the meter: "..t.name,0) end
  if r.TrackFX_GetOffline(t.track,f) then error("Bring Performance Dynamics online: "..t.name,0) end
  r.TrackFX_SetEnabled(t.track,f,true)
  restore_performance_room(t,f)
  r.TrackFX_SetParam(t.track,f,1,t.model)
  -- Preserve user-adjustable timbre, room and timing settings. This initial
  -- integration requires the supplied boost/cut volume mode.
  r.TrackFX_SetParam(t.track,f,6,0)
  t.perfboost=r.TrackFX_GetParam(t.track,f,4)
  t.perfcut=math.abs(r.TrackFX_GetParam(t.track,f,5))
  t.perfplan=make_perf_plan(t)
  local bars={}
  for j,s in ipairs(sections) do
    for b,span in ipairs(s.bars) do
      local p=t.perfplan[j][b]
      local n=(math.abs(p.p1-p.p0)>1e-9 or math.abs(p.sec.f1-p.sec.f0)>1e-9) and 8 or 1
      for k=1,n do
        local u,v=(k-1)/n,k/n
        bars[#bars+1]={a=span.a+(span.b-span.a)*u,b=span.a+(span.b-span.a)*v,g0=p.value(u),g1=p.value(v)}
      end
    end
  end
  write_points(t,contour_points(bars,0),f,-100,100)
end

local function apply_row(t)
  local bars={}
  local contour=intensity_contour()
  for j,s in ipairs(sections) do
    for b,span in ipairs(s.bars) do
      local v=t.cells[j][b]
      local d=contour[j][b]
      bars[#bars+1]={a=span.a,b=span.b,j=j,bar=b,v=v,ramp=t.ramps[j][b] or 0,f0=d.f0,f1=d.f1,ignore=s.countin}
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
      local spans,next_i=ramp_chain(bars,i,9,track_fill,1,8)
      i=next_i
      local previous_end
      for _,span in ipairs(spans) do
        local a=previous_end or (span.left and db_at(span.left,offset(span.lv)) or -60)
        local z=span.right and db_at(span.right,offset(span.rv)) or
          (span.rv==1 and -60 or db_at(bars[span.last],offset(span.rv)))
        local t0,t1=bars[span.first].a,bars[span.last].b
        for k=span.first,span.last do
          local b=bars[k];b.g0=a+(z-a)*(b.a-t0)/(t1-t0);b.g1=a+(z-a)*(b.b-t0)/(t1-t0)
        end
        previous_end=z
      end
    end
  end
  -- Split only at the musical intensity breakpoints; master handles below Soft.
  local result={}
  for _,b in ipairs(bars) do
    local cuts={0,1}
    local pp=t.perfplan and t.perfplan[b.j][b.bar]
    if pp and not pp.mute and (math.abs(pp.p1-pp.p0)>1e-9 or math.abs(pp.sec.f1-pp.sec.f0)>1e-9) then for k=1,7 do cuts[#cuts+1]=k/8 end end
    local add_int=t.depth==0 and not b.ignore and b.v~=1
    if add_int and math.abs(b.f1-b.f0)>1e-9 then
      for _,f in ipairs({0.25,0.5,0.75}) do
        local cross=(f-b.f0)/(b.f1-b.f0)
        if cross>0 and cross<1 then cuts[#cuts+1]=cross end
      end
    end
    table.sort(cuts)
    local function value(u)
      local g=b.g0+(b.g1-b.g0)*u
      if add_int and g>-60 then g=g+math.max(-3,section_db(b.f0+(b.f1-b.f0)*u)) end
      if pp and not pp.mute and g>-60 then g=g-perf_volume(t,pp.value(u)) end
      return clamp(g,-60,30)
    end
    for k=2,#cuts do
      local a,z=cuts[k-1],cuts[k]
      if z-a>1e-9 then result[#result+1]={a=b.a+(b.b-b.a)*a,b=b.a+(b.b-b.a)*z,g0=value(a),g1=value(z)} end
    end
  end
  local pts=contour_points(result,t.initial or 0)
  write_points(t,pts)
  ui.mirror_mix_points(t,pts,"level")
end
-- Global silence is applied at the master, after effects and busses.
-- Normal section intensity stays at the sources; only the portion below Soft
-- is assigned to the master, avoiding duplicate gain changes in routing.
local function apply_master(gain)
  local contour=intensity_contour()
  local bars={}
  local function value(d)
    if d<=-60+1e-8 then return -60 end
    return clamp(gain+math.min(0,d+3),-60,30)
  end
  for j,s in ipairs(sections) do
    for b,span in ipairs(s.bars) do
      local d=contour[j][b]
      -- Approximate the amplitude-linear fade in dB with closely spaced
      -- points, retaining exact endpoints and the Soft crossing.
      local cuts={0,1}
      if math.abs(d.f1-d.f0)>1e-9 then
        for k=1,31 do cuts[#cuts+1]=k/32 end
        local cross=(0.25-d.f0)/(d.f1-d.f0)
        if cross>0 and cross<1 then cuts[#cuts+1]=cross end
        table.sort(cuts)
      end
      for k=2,#cuts do
        local a,b=cuts[k-1],cuts[k]
        if b-a>1e-9 then
          bars[#bars+1]={a=span.a+(span.b-span.a)*a,b=span.a+(span.b-span.a)*b,
            g0=value(section_db(d.f0+(d.f1-d.f0)*a)),g1=value(section_db(d.f0+(d.f1-d.f0)*b))}
        end
      end
    end
  end
  write_points(master,contour_points(bars,gain))
end
local function save_cells(t,j)
  local s=sections[j]
  for b,v in ipairs(t.cells[j]) do
    put("cell:"..t.key..":"..s.key..":"..b,v)
    put("ramp:"..t.key..":"..s.key..":"..b,t.ramps[j][b] or 0)
  end
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
  if not pass or pass.kind~="track" then return 0,0 end
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
    for t,flags in pairs(job.perf or {}) do if valid(t) then r.SetMediaTrackInfo_Value(t,"I_PERFFLAGS",flags) end end
    for t,state in pairs(job.states or {}) do if valid(t) then
      r.SetMediaTrackInfo_Value(t,"B_MUTE",state.mute)
      r.SetMediaTrackInfo_Value(t,"I_SOLO",state.solo)
    end end
    for t,guid in pairs(job.temporary or {}) do
      if valid(t) then
        for i=r.TrackFX_GetCount(t)-1,0,-1 do if r.TrackFX_GetFXGUID(t,i)==guid then r.TrackFX_Delete(t,i);break end end
        r.GetSetMediaTrackInfo_String(t,"P_EXT:N2N_MIX_FX","",true)
      end
    end
    r.TrackList_AdjustWindows(false)
    r.GetSet_LoopTimeRange2(proj,true,false,job.a,job.b,false)
    r.GetSetRepeatEx(proj,job.repeat_state)
    r.SetEditCurPos2(proj,job.cursor,false,false)
  end
end
local function finish(msg)
  if not job then return end
  cleanup()
  note(msg..string.format(" (%d dry runs)",job.renders or 0))
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
local function track_diagnostic(t,i,p)
  local f=fx_index(t)
  local slot=f and r.TrackFX_GetParam(t.track,f,1) or -1
  local tok=f and r.TrackFX_GetParam(t.track,f,2) or -1
  local ab
  if f then local ok,v=r.TrackFX_GetNamedConfigParm(t.track,f,"force_auto_bypass");if ok then ab=v end end
  local addr=1024+(i-1)*8
  local beat=r.gmem_read(addr)==p.token
  return string.format("%s: mute=%d, recarm=%d, chain=%d, main=%d, sends=%d, slot=%.0f/%d, token=%.0f/%d, auto-bypass=%s, meter heartbeat=%s, blocks=%d, active blocks=%d",t.name,r.GetMediaTrackInfo_Value(t.track,"B_MUTE"),r.GetMediaTrackInfo_Value(t.track,"I_RECARM"),r.GetMediaTrackInfo_Value(t.track,"I_FXEN"),r.GetMediaTrackInfo_Value(t.track,"B_MAINSEND"),r.GetTrackNumSends(t.track,0),slot,i,tok,p.token,tostring(ab),beat and "yes" or "no",beat and r.gmem_read(addr+1) or 0,beat and r.gmem_read(addr+2) or 0)
end
local function complete_pass(stats)
  if not job or not pass then return end
  local done,total=poll()
  attach();r.gmem_write(0,0)
  local p=pass
  pass=nil
  -- Track calibration requires per-section reports. Master/verification use
  -- REAPER's native rendered-output statistics, not the meter's pre-gain reports.
  if p.kind=="track" then
    local failures,diagnostics,missing_rows={},{},{}
    for i,t in ipairs(p.rows) do
      local failed=false
      local absent=next(t.reports)==nil
      -- In current-audition mode REAPER may suspend nonsoloed tracks. Do
      -- not alter a track that the host did not process, or treat partial reports as silence.
      if job.keep_solo and absent and r.GetMediaTrackInfo_Value(t.track,"I_SOLO")==0 and r.GetMediaTrackInfo_Value(t.track,"B_SOLO_DEFEAT")==0 then
        t.skip_analysis=true
        note("Excluded from current audition: "..t.name)
      else
      t.skip_analysis=false
      for j,s in ipairs(sections) do
        local v=t.reports[j]
        local reason
        if not v then reason="missing report"
        elseif v.state~=1 and v.state~=2 then reason="meter status "..tostring(v.state)
        elseif math.abs(v.coverage-1)>0.02 then reason=string.format("%.1f%% coverage",v.coverage*100) end
        if reason then failures[#failures+1]=t.name.." / "..s.name..": "..reason;failed=true end
      end
      if failed then missing_rows[#missing_rows+1]=t;diagnostics[#diagnostics+1]=track_diagnostic(t,i,p) end
      end
    end
    if #failures>0 then
      local detail=p.name..": "..done.."/"..total.." reports; "..#failures.." incomplete.\n"..table.concat(failures,"\n")
      r.ShowConsoleMsg("N2N Mix analysis:\n"..detail.."\nTrack state:\n"..table.concat(diagnostics,"\n").."\nNative render stats: "..tostring(stats).."\n")
      if not p.retried then
        p.retried=true
        for _,t in ipairs(missing_rows) do
          local flags=math.floor(r.GetMediaTrackInfo_Value(t.track,"I_PERFFLAGS"))
          if job.perf[t.track]==nil then job.perf[t.track]=flags end
          r.SetMediaTrackInfo_Value(t.track,"I_PERFFLAGS",flags|2)
        end
        note(p.name..": incomplete reports; retrying with anticipative FX disabled on affected tracks.")
        return
      end
      error(p.name..": "..#failures.." incomplete; "..failures[1]..". Full details in REAPER console",0)
    end
    note(string.format("%s: %d/%d reports complete.",p.name,done,total))
  end
  if p.kind=="track" then
    for _,t in ipairs(p.rows) do
      if not t.skip_analysis then
      ui.set_unity_unless_automated(t)
      for j,v in pairs(t.reports) do
        t.base[j]=calc_base(t,j,v)
        put("base:"..t.key..":"..sections[j].key,t.base[j] or "")
      end
      apply_row(t)
      job.temporary[t.track]=nil
      end
    end
  elseif p.kind=="master" then
    local lufs,peak=stats_value(stats,"LUFSI"),stats_value(stats,"PEAK")
    if not lufs or not peak or lufs<=-70 then
      r.ShowConsoleMsg("N2N Mix master render: "..tostring(stats).."\n")
      error("No valid native master loudness/peak result; see REAPER console",0)
    end
    local requested=master_target()-lufs
    local gain=clamp(math.min(requested,peak_ceiling-peak-0.25),-60,30)
    apply_master(gain)
    put("mastergain",gain)
    last_stats=string.format("Master before %.2f LUFS / %.2f dBFS; gain %+.2f dB; estimated %.2f LUFS.",lufs,peak,gain,lufs+gain)
    if gain<requested-0.1 then last_stats=last_stats.." Peak constrained (gain only; no limiter)." end
    note(last_stats)
  elseif p.kind=="verify" then
    local lufs,peak=stats_value(stats,"LUFSI"),stats_value(stats,"PEAK")
    if not lufs or not peak then
      r.ShowConsoleMsg("N2N Mix verification render: "..tostring(stats).."\n")
      error("No native verification result; see REAPER console",0)
    end
    last_verified=string.format("Verified master: %.2f LUFS-I, %.2f dBFS sample peak (target %.1f LUFS).",lufs,peak,master_target())
    if peak>peak_ceiling+0.1 then
      local g=clamp(num("mastergain",0)-(peak-peak_ceiling)-0.35,-60,30)
      apply_master(g);put("mastergain",g)
      job.verify_retries=(job.verify_retries or 0)+1
      if job.verify_retries<=1 then
        job.queue[#job.queue+1]={kind="verify",name="Master peak recheck",rows={master}}
        last_verified=last_verified.." Additional peak correction; verifying again."
      else
        last_verified=last_verified.." Peak correction applied but not reverified; inspect the final master."
      end
    end
    note(last_verified)
  end
  job.index=job.index+1
end
local function arm(p)
  attach()
  local tok=(math.floor(r.gmem_read(1))%2000000000)+1
  r.gmem_write(0,0);r.gmem_write(1,tok);r.gmem_write(2,#sections)
  for j,s in ipairs(sections) do r.gmem_write(16+2*(j-1),s.a);r.gmem_write(17+2*(j-1),s.b) end
  for i,t in ipairs(p.kind=="track" and p.rows or {}) do
    t.reports={}
    local existing=fx_index(t)
    local f=ensure_fx(t)
    if not existing then job.temporary[t.track]=t.fxguid end
    -- The current-audition option can suspend non-soloed tracks. Do not
    -- change their performance FX in advance of a report.
    if not job.keep_solo or r.GetMediaTrackInfo_Value(t.track,"I_SOLO")~=0 or r.GetMediaTrackInfo_Value(t.track,"B_SOLO_DEFEAT")~=0 then
      local pf,msg=ensure_position_fx(t)
      configure_perf(t)
      pf=perf_index(t)
      if has_position(t,pf) then apply_pan(t,pf)
      elseif msg then r.ShowConsoleMsg("N2N Mix Pan: "..t.name..": "..msg.."\n") end
    end
    f=fx_index(t)
    r.TrackFX_SetNamedConfigParm(t.track,f,"force_auto_bypass","0")
    if not r.TrackFX_SetParam(t.track,f,1,i) or not r.TrackFX_SetParam(t.track,f,2,tok) then error("Cannot arm meter: "..t.name,0) end
    local slot_now=r.TrackFX_GetParam(t.track,f,1)
    local token_now=r.TrackFX_GetParam(t.track,f,2)
    if math.abs(slot_now-i)>0.1 or math.abs(token_now-tok)>0.1 then
      error(string.format("Meter parameter mismatch: %s (slot %.2f/%d, token %.2f/%d)",t.name,slot_now,i,token_now,tok),0)
    end
    for k=0,7 do r.gmem_write(1024+(i-1)*8+k,0) end
    for j=1,#sections do r.gmem_write(4096+((i-1)*256+j-1)*8,0) end
  end
  if p.kind=="master" then
    ensure_fx(master);ui.set_unity_unless_automated(master);apply_master(0)
  end
  p.token=tok; p.phase="armed";pass=p
  r.gmem_write(0,p.kind=="track" and 1 or 0)
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
  job.renders=job.renders+1
  r.ShowConsoleMsg(string.format("N2N Mix dry run %d: %s\n",job.renders,pass.name))
  local _,stats=r.GetSetProjectInfo_String(proj,"RENDER_STATS",tostring(job.cmd),false)
  complete_pass(stats)
end
local function start(policy)
  if next(dirty) or master_dirty then status="Finish current grid edit first.";return end
  if not stopped() then status="Stop transport before Auto Mix.";return end
  if not refresh() then return end
  if math.abs(r.Master_GetPlayRate(proj)-1)>0.0001 then status="Set project play rate to 1.0.";return end
  if r.GetGlobalAutomationOverride()>1 then status="Disable global automation write/bypass override.";return end
  attach()
  if r.gmem_read(0)==1 then
    status="An analysis flag is still armed. Close any other N2N Mix instance and reopen REAPER before retrying."
    return
  end
  local cmd=action_id()
  if not cmd then status="Native dry-run action not found.";return end
  local q,selected,skipped={},{},{}
  local function skip_muted(t)
    if r.GetMediaTrackInfo_Value(t.track,"B_MUTE")==0 then return false end
    -- A muted track can still supply pre-fader audio depending on REAPER's
    -- preferences. Never assume that such a send is silent.
    for i=0,r.GetTrackNumSends(t.track,0)-1 do
      if r.GetTrackSendInfo_Value(t.track,0,i,"I_SRCCHAN")>=0 and
         r.GetTrackSendInfo_Value(t.track,0,i,"B_MUTE")==0 and
         r.GetTrackSendInfo_Value(t.track,0,i,"I_SENDMODE")~=0 then return false end
    end
    return true
  end
  for d=0,#rows do
    local eligible={}
    for _,t in ipairs(groups[d] or {}) do
      if policy~="all" and skip_muted(t) then skipped[#skipped+1]=t.name else eligible[#eligible+1]=t end
    end
    if #eligible>0 then
      local label=d==0 and "Source tracks" or ("Downstream audio layer "..d)
      q[#q+1]={kind="track",name=label.." ("..#eligible.." tracks)",rows=eligible}
    end
  end
  if #skipped>0 then r.ShowConsoleMsg("N2N Mix: preserving muted tracks: "..table.concat(skipped,", ").."\n") end
  if #q==0 then status="No unmuted tracks to analyze.";return end
  q[#q+1]={kind="master",name="Master",rows={master}}
  q[#q+1]={kind="verify",name="Master verification",rows={master}}
  for _,p in ipairs(q) do for _,t in ipairs(p.rows) do selected[t]=true end end
  for t in pairs(selected) do
    local ok,e=safe_row(t);if not ok then status=e;return end
    if ui.has_volume_envelope(t) then r.ShowConsoleMsg("N2N Mix: preserving conventional volume automation and fader on "..t.name..". Per-track targets are pre-fader; downstream and master analysis include its effect.\n") end
  end
  local a,b=r.GetSet_LoopTimeRange2(proj,false,false,0,0,false)
  r.Undo_BeginBlock2(proj)
  job={queue=q,index=1,kind="Auto Mix",cmd=cmd,a=a,b=b,cursor=r.GetCursorPositionEx(proj),repeat_state=r.GetSetRepeatEx(proj,-1),ready_at=r.time_precise(),perf={},states={},temporary={},renders=0,keep_solo=policy=="current" and r.AnyTrackSolo(proj)}
  last_verified="";last_stats=""
  -- Persist only an accepted Auto Mix run, not merely opening the dialog.
  last_preset,last_custom=preset,custom
  put("preset",last_preset);put("custom",last_custom)
  local ok,e=pcall(function()
    if policy=="all" then
      for i=-1,r.CountTracks(proj)-1 do
        local t=i<0 and r.GetMasterTrack(proj) or r.GetTrack(proj,i)
        local mute=r.GetMediaTrackInfo_Value(t,"B_MUTE")
        local solo=r.GetMediaTrackInfo_Value(t,"I_SOLO")
        local change_mute=mute~=0 and (i<0 or r.GetMediaTrackInfo_Value(t,"B_SHOWINMIXER")>0)
        if change_mute or solo~=0 then
          job.states[t]={mute=mute,solo=solo}
          if change_mute then r.SetMediaTrackInfo_Value(t,"B_MUTE",0) end
          if solo~=0 then r.SetMediaTrackInfo_Value(t,"I_SOLO",0) end
        end
      end
    end
    note(string.format("Audio routing: %d track layers, master and verification.",#q-2))
    local plan={}
    for _,p in ipairs(q) do
      local names={};for _,t in ipairs(p.rows) do names[#names+1]=t.name end
      plan[#plan+1]=p.name..": "..table.concat(names,", ")
    end
    r.ShowConsoleMsg("N2N Mix planned stages:\n"..table.concat(plan,"\n").."\n")
  end)
  if not ok then fail(e) end
end
local function request_start()
  if pending_start or job then return end
  if not stopped() then status="Stop transport before Auto Mix.";return end
  local restricted=r.AnyTrackSolo(proj) or r.GetMediaTrackInfo_Value(r.GetMasterTrack(proj),"B_MUTE")~=0
  for i=0,r.CountTracks(proj)-1 do
    local t=r.GetTrack(proj,i)
    if r.GetMediaTrackInfo_Value(t,"B_SHOWINMIXER")>0 and r.GetMediaTrackInfo_Value(t,"B_MUTE")~=0 then restricted=true end
  end
  local policy="current"
  if restricted then
    local answer=r.MB("Some tracks are muted or soloed.\n\nYes: Temporarily unmute visible tracks and clear solos for a full mix.\nNo: Mix the current audible arrangement.\nCancel: Do not process.\n\nOriginal mute and solo settings are restored afterward.","N2N Mix",3)
    if answer==2 then return end
    if answer==6 then policy="all" end
  end
  if policy=="current" and r.GetMediaTrackInfo_Value(r.GetMasterTrack(proj),"B_MUTE")~=0 then status="Master is muted. Choose the full-mix option.";return end
  pending_start=policy;status="Preparing Auto Mix...";alert_text="";alert_until=0
end
-- Normalize endpoints as inclusive cell ranges, including folded regions.
function ui.span_bounds(j,b,k,n)
  local aj,ab,zj,zb=j,b,k,n
  if j>k or (j==k and (b or 1)>(n or 1)) then aj,ab,zj,zb=k,n,j,b end
  if j==k and (not b or not n) then return j,1,j,#sections[j].bars end
  return aj,ab or 1,zj,zb or #sections[zj].bars
end
local function edit_cell(t,j,b,chosen)
  if sections[j].countin then return end
  local chosen=chosen or tool
  if chosen==9 then
    if not transition_start or transition_start.t~=t then transition_start={t=t,j=j,b=b};status="Select transition end on the same track.";return end
    local s0=transition_start;transition_start=nil
    local start_j,start_b,end_j,end_b=ui.span_bounds(s0.j,s0.b,j,b)
    local ramp=new_ramp()
    for k=start_j,end_j do
      if not sections[k].countin then
        local x=k==start_j and start_b or 1
        local y=k==end_j and end_b or #sections[k].bars
        for n=x or 1,y or #sections[k].bars do t.cells[k][n]=9;t.ramps[k][n]=ramp end
        save_cells(t,k)
      end
    end
  else
    if b then t.cells[j][b]=chosen;t.ramps[j][b]=0 else for k=1,#t.cells[j] do t.cells[j][k]=chosen;t.ramps[j][k]=0 end end
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
  if v==0 then centered(dl,x,y,w,h,"...",0x101010FF)
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
  elseif traditional then centered(dl,x,y,w,h,trad[v],0x101010FF)
  else
    local n=v==2 and 2 or v==3 and 1 or math.min(v-4,2)
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
local fill_for=track_fill
-- Display musical prominence using the same time interpolation as the audio transition.
local function transition_fills(t)
  local all,map={},{}
  for j,s in ipairs(sections) do
    map[j]={}
    for b,bar in ipairs(s.bars) do
      local v=t.cells[j][b]
      local x={a=bar.a,b=bar.b,v=v,ramp=t.ramps[j][b] or 0,ignore=s.countin}
      all[#all+1]=x;map[j][b]=x
    end
  end
  local i=1
  while i<=#all do
    local x=all[i]
    if x.v~=9 or x.ignore then
      x.f0=fill_for(x.ignore and 1 or x.v);x.f1=x.f0;i=i+1
    else
      local spans,next_i=ramp_chain(all,i,9,fill_for,1,8)
      i=next_i
      for _,span in ipairs(spans) do
        local a,z=fill_for(span.lv),fill_for(span.rv)
        local t0,t1=all[span.first].a,all[span.last].b
        for k=span.first,span.last do
          local b=all[k];b.f0=a+(z-a)*(b.a-t0)/(t1-t0);b.f1=a+(z-a)*(b.b-t0)/(t1-t0)
        end
      end
    end
  end
  return map
end
-- Use the same view-only editor mailbox as the Numbers2Notes Tracks panel.
-- Pattern numbers in the published song form are shared by Arp and Drums.
local function section_pattern_slot(s)
  local n=(s.name or ""):upper():match("^%s*(.-)%s*$"):gsub("^%{(.*)%}$","%1")
  local fixed={["#"]=77,["COUNT IN"]=77,["COUNT-IN"]=77,D=75,DROP=75,X=76,BREAKDOWN=76,F=78,FADEOUT=78,["1"]=27,["USER 1"]=27,["2"]=28,["USER 2"]=28,["3"]=29,["USER 3"]=29}
  if fixed[n] then return fixed[n],false end
  local single={I=1,INTRO=1,B=17,BRIDGE=17,M=17,["MIDDLE 8"]=17,S=44,SOLO=44,O=71,OUTRO=71}
  if single[n] then return single[n],true end
  for _,family in ipairs({{{"V","VERSE"},{5,32,59}},{{"P","PC","PRE","PRE-CHORUS","PRE CHORUS","R","RAMP"},{9,36,63}},{{"C","CHORUS"},{13,40,67}}}) do
    for _,p in ipairs(family[1]) do
      for i=1,3 do
        if n==p..i or n==p.." "..i or (i==1 and n==p) then return family[2][i],true end
      end
    end
  end
  return 26,false
end
local function is_arranger_name(name)
  name=name:lower()
  if name:find("n2n drum arranger",1,true) then return "N2N Drum Arranger" end
  if name:find("n2n arp",1,true) then return "N2N Arp" end
end
local function open_track_plugin(t,fx,j,b,arranger)
  if job or pending_start or not valid(t.track) then return end
  if arranger and j and r.TrackFX_GetEnabled(t.track,fx) and not r.TrackFX_GetOffline(t.track,fx) then
    local s=sections[j]
    local instance=math.floor(r.TrackFX_GetParam(t.track,fx,4)+0.5)
    if s and instance>=1 and instance<=512 then
      -- Never send a view command to an ambiguous instance ID.
      local matches=0
      for i=0,r.CountTracks(proj)-1 do
        local tr=r.GetTrack(proj,i)
        for f=0,r.TrackFX_GetCount(tr)-1 do
          local _,name=r.TrackFX_GetFXName(tr,f,"")
          if is_arranger_name(name or "") and math.floor(r.TrackFX_GetParam(tr,f,4)+0.5)==instance then matches=matches+1 end
        end
      end
      if matches==1 then
        r.gmem_attach("N2N_Ecosystem_RSKennedy")
        local key=r.gmem_read(8000000+instance)
        if key>0 then
          local slot,variants=section_pattern_slot(s)
          local q=r.TimeMap2_timeToQN(proj,b and s.bars[b].a or s.a)
          local base=6000000
          local rev=r.gmem_read(base+1)
          local count=math.floor(r.gmem_read(base+2))
          if r.gmem_read(base)==0x4E324631 and rev>0 and rev%2==0 and count>=0 and count<=4096 and r.gmem_read(base+10+instance)==key then
            for i=0,count-1 do
              local p=base+1024+i*3
              local a,z,candidate=r.gmem_read(p),r.gmem_read(p+1),math.floor(r.gmem_read(p+2))
              if q>=a-1e-7 and q<z-1e-7 then
                -- Accept only a slot from the matching region family.
                if variants and candidate>=slot and candidate<=slot+3 and r.gmem_read(base+1)==rev then slot=candidate end
                break
              end
            end
          end
          local mailbox=8300000+(instance-1)*2
          r.gmem_write(mailbox,key)
          r.gmem_write(mailbox+1,slot+1)
        end
        attach()
      end
    end
  end
  r.TrackFX_Show(t.track,fx,3)
end
function ui.is_topline(t)
  return t.name:lower():find("n2n topline",1,true)~=nil
end
function ui.launch_topline(t,j)
  if job or pending_start or not valid(t.track) then return end
  local sec="N2N_TOPLINE_HUB"
  local owner=r.GetExtState(sec,"owner")
  local hb=tonumber(r.GetExtState(sec,"heartbeat"))
  local running=owner~="" and hb and math.abs(r.time_precise()-hb)<2
  if running and owner:match("^[^\t]+")~=tostring(proj) then
    r.MB("Close Topline in the other project before opening this track.","N2N Topline",0);return
  end
  local path
  if not running then
    if r.JS_Window_Find and r.JS_Window_Find("N2N Topline",true) then
      r.MB("Close the existing Topline window and reopen it to enable navigation.","N2N Topline",0);return
    end
    local source=debug.getinfo(1,"S").source:sub(2)
    local dir=source:match("^(.*[/\\])")
    if dir then
      local candidate=dir.."N2N Topline.lua"
      local file=io.open(candidate,"rb")
      if file then file:close();path=candidate end
    end
    local function search(dir,depth)
      if depth>7 then return end
      local i=0
      while true do
        local file=r.EnumerateFiles(dir,i);if not file then break end
        if file:lower()=="n2n topline.lua" then return dir.."/"..file end
        i=i+1
      end
      i=0
      while true do
        local sub=r.EnumerateSubdirectories(dir,i);if not sub then break end
        local found=search(dir.."/"..sub,depth+1);if found then return found end
        i=i+1
      end
    end
    path=path or search(r.GetResourcePath().."/Scripts",0)
    if not path then r.MB("Install N2N Topline.lua first.","N2N Mix",0);return end
  end
  local region=j and sections[j].id or -1
  r.GetSetMediaTrackInfo_String(t.track,"P_EXT:N2N:TOPLINE","1",true)
  r.SetExtState(sec,"request",table.concat({tostring(proj),t.key,tostring(region),tostring(r.time_precise())},"\t"),false)
  if not running then
    local cmd=r.AddRemoveReaScript(true,0,path,true)
    if cmd and cmd>0 then r.Main_OnCommand(cmd,0)
    else r.DeleteExtState(sec,"request",false);r.MB("Could not launch N2N Topline.","N2N Mix",0) end
  end
end
local function plugin_menu(t,j,b,no_divider)
  local inst=r.TrackFX_GetInstrument(t.track)
  local arrangers={}
  for fx=0,r.TrackFX_GetCount(t.track)-1 do
    local _,name=r.TrackFX_GetFXName(t.track,fx,"")
    local kind=is_arranger_name(name or "")
    if kind then arrangers[#arrangers+1]={fx=fx,label=kind};if inst==fx then inst=-1 end end
  end
  local top=ui.is_topline(t)
  if inst>=0 or #arrangers>0 or top then
    if not no_divider then r.ImGui_Separator(ctx) end
    if top and r.ImGui_Selectable(ctx,"Open N2N Topline",false) then ui.launch_topline(t,j) end
    for _,a in ipairs(arrangers) do
      if r.ImGui_Selectable(ctx,"Open "..a.label.."##"..a.fx,false) then open_track_plugin(t,a.fx,j,b,true) end
    end
    if inst>=0 and r.ImGui_Selectable(ctx,"Open Instrument",false) then open_track_plugin(t,inst,j,b,false) end
  end
end
local function popup_level(t,j,b,v,id)
  local n=mono_push(true)
  if r.ImGui_BeginPopupContextItem(ctx,"##options"..id) then
    for i=#tool_ids-1,1,-1 do
      local k=tool_ids[i]
      if k~=9 then
      local label=traditional and (trad[k].."  "..simple[k]) or simple[k]
      if r.ImGui_Selectable(ctx,label,k==v) then
        transition_start=nil;edit_cell(t,j,b,k)
      end
      end
    end
    if r.ImGui_Selectable(ctx,"Transition",v==9) then
      local ramp=new_ramp()
      if b then t.cells[j][b]=9;t.ramps[j][b]=ramp else for k=1,#t.cells[j] do t.cells[j][k]=9;t.ramps[j][k]=ramp end end
      save_cells(t,j);dirty[t]=true;transition_start=nil
    end
    plugin_menu(t,j,b)
    r.ImGui_EndPopup(ctx)
  end
  r.ImGui_PopStyleColor(ctx,n)
end
-- The whole-row cell is a derived summary, not another independent setting.
-- All edits go through the same stored bar values as the ordinary grid.
local function row_level(t)
  local v
  for j,s in ipairs(sections) do
    if not s.countin then
      for _,level in ipairs(t.cells[j]) do
        if level==9 or (v~=nil and level~=v) then return 0 end
        v=level
      end
    end
  end
  return v
end
local function set_row_level(t,v)
  if job or not v or v==9 or v==0 then return end
  transition_start=nil
  for j,s in ipairs(sections) do
    if not s.countin then edit_cell(t,j,nil,v) end
  end
end
local function row_level_cell(t)
  local v=row_level(t)
  local w,h=ALL_W,CELL_H
  local dl=r.ImGui_GetWindowDrawList(ctx)
  local x,y=r.ImGui_GetCursorScreenPos(ctx)
  local id="##alllevel"..t.key
  local clicked=r.ImGui_InvisibleButton(ctx,id,w,h)
  local hover=r.ImGui_IsItemHovered(ctx)
  local rr,gg,bb=rgb(r.GetTrackColor(t.track))
  local light=rgba(math.floor(rr*.55+110),math.floor(gg*.55+110),math.floor(bb*.55+110),255)
  local dark=rgba(math.floor(rr*.70),math.floor(gg*.70),math.floor(bb*.70),255)
  r.ImGui_DrawList_AddRectFilled(dl,x,y,x+w,y+h,light,0)
  if v and v~=0 then
    local f=fill_for(v)
    if f>0 then r.ImGui_DrawList_AddRectFilled(dl,x,y+h*(1-f),x+w,y+h,dark,0) end
  end
  r.ImGui_DrawList_AddRect(dl,x,y,x+w,y+h,hover and 0xFFFFFFFF or 0x00000080,0,0,hover and 2 or 1)
  if job or v==nil then centered(dl,x,y,w,h,"—",0x101010FF)
  elseif v==0 then centered(dl,x,y,w,h,"Mixed",0x101010FF)
  else symbol(dl,x,y,w,h,v) end
  if not job and v~=nil then
    if clicked then
      if tool~=9 then set_row_level(t,tool) else status="Select a fixed level to paint the whole row." end
    end
    local n=mono_push(true)
    if r.ImGui_BeginPopupContextItem(ctx,"##alloptions"..t.key) then
      for i=#tool_ids-1,1,-1 do
        local k=tool_ids[i]
        if k~=9 then
          local label=traditional and (trad[k].."  "..simple[k]) or simple[k]
          if r.ImGui_Selectable(ctx,label,v==k) then set_row_level(t,k) end
        end
      end
      plugin_menu(t,nil,nil)
      r.ImGui_EndPopup(ctx)
    end
    r.ImGui_PopStyleColor(ctx,n)
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
      local first,last=b or 1,b or #s.bars
      local ta,tz=s.bars[first].a,s.bars[last].b
      for k=first,last do
        local f0,f1=fills[j][k].f0,fills[j][k].f1
        local xa=x+w*(s.bars[k].a-ta)/(tz-ta)
        local xb=x+w*(s.bars[k].b-ta)/(tz-ta)
        if f0>0 or f1>0 then
          if f0==0 then r.ImGui_DrawList_AddTriangleFilled(dl,xa,y+h,xb,y+h*(1-f1),xb,y+h,dark)
          elseif f1==0 then r.ImGui_DrawList_AddTriangleFilled(dl,xa,y+h*(1-f0),xb,y+h,xa,y+h,dark)
          else r.ImGui_DrawList_AddQuadFilled(dl,xa,y+h*(1-f0),xb,y+h*(1-f1),xb,y+h,xa,y+h,dark) end
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
    centered(dl,x,y,w,h,report and (report.state==1 and string.format("%.1f",report.lufs) or "OK") or "·",0x101010FF)
  elseif s.countin then centered(dl,x,y,w,h,"—",0x101010FF)
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
end
local function set_intensity(j,b,v,ramp)
  ramp=v==5 and (ramp or new_ramp()) or 0
  local s=sections[j]
  if s.countin then return end
  if b then
    s.bars[b].int=v;s.bars[b].ramp=ramp;put("int:"..s.key..":"..b,v);put("iramp:"..s.key..":"..b,ramp)
  else
    s.int=v;put("int:"..s.key,v)
    for k,bar in ipairs(s.bars) do bar.int=v;bar.ramp=ramp;put("int:"..s.key..":"..k,v);put("iramp:"..s.key..":"..k,ramp) end
  end
  for _,t in ipairs(rows) do if t.depth==0 then dirty[t]=true end end
  master_dirty=true
end
local function draw_section_tile(dl,x,y,w,h,f0,f1,label,selected,hover,segments)
  local light=selected and 0xE5D6A3FF or 0xDADADAFF
  local dark=selected and 0xB89B4EFF or 0x858585FF
  local rim=selected and 0xD3B86DFF or hover and 0xEEEEEEFF or 0x303030FF
  local rad=4
  r.ImGui_DrawList_AddRectFilled(dl,x,y,x+w,y+h,light,rad)
  -- Keep the sloped interior inside the rounded silhouette. Fill the central
  -- polygon, then cover the lower corners using a rounded base where needed.
  if segments then
    local inset=2;local bot=y+h-inset
    for _,seg in ipairs(segments) do
      local a=x+inset+(w-2*inset)*seg.a
      local b=x+inset+(w-2*inset)*seg.b
      local ya=y+inset+(h-2*inset)*(1-seg.f0)
      local yb=y+inset+(h-2*inset)*(1-seg.f1)
      if seg.f0>0 or seg.f1>0 then r.ImGui_DrawList_AddQuadFilled(dl,a,ya,b,yb,b,bot,a,bot,dark) end
    end
  elseif f0>0 or f1>0 then
    if f0==f1 then
      local top=y+h*(1-f0)
      r.ImGui_DrawList_AddRectFilled(dl,x,top,x+w,y+h,dark,math.min(rad,(y+h-top)*0.5),f0==1 and 0 or r.ImGui_DrawFlags_RoundCornersBottom())
    else
      local inset=2
      local a,b=x+inset,x+w-inset
      local bot=y+h-inset
      local top0=y+inset+(h-2*inset)*(1-f0)
      local top1=y+inset+(h-2*inset)*(1-f1)
      r.ImGui_DrawList_AddQuadFilled(dl,a,top0,b,top1,b,bot,a,bot,dark)
    end
  end
  r.ImGui_DrawList_AddRect(dl,x,y,x+w,y+h,rim,rad,0,selected and 2 or 1)
  if label~="" then centered(dl,x,y,w,h,label,0x101010FF) end
end
local function all_intensity_cell()
  local v
  for _,s in ipairs(sections) do
    if not s.countin then
      for _,b in ipairs(s.bars) do
        if v==nil then v=b.int elseif v~=b.int then v=0 end
        if v==5 then v=0 end
      end
    end
  end
  local dl=r.ImGui_GetWindowDrawList(ctx)
  local x,y=r.ImGui_GetCursorScreenPos(ctx)
  local clicked=r.ImGui_InvisibleButton(ctx,"##allintensity",ALL_W,CELL_H)
  local hover=r.ImGui_IsItemHovered(ctx)
  local f=section_fill[v] or (v==0 and 0.5 or 0)
  local label=job or v==nil
  label=label and "—" or v==0 and "Mixed" or v==4 and "V.Strong" or intens_names[v]
  draw_section_tile(dl,x,y,ALL_W,CELL_H,f,f,label,false,hover)
  local function set_all(k)
    if k==5 then status="Select a fixed section level to paint the whole row.";return end
    for j,s in ipairs(sections) do if not s.countin then set_intensity(j,nil,k) end end
  end
  if not job and v~=nil then
    if clicked then set_all(intensity_tool) end
    local n=mono_push(true)
    if r.ImGui_BeginPopupContextItem(ctx,"##allintensityoptions") then
      for i=#intensity_ids-1,1,-1 do
        local k=intensity_ids[i]
        if k~=5 and r.ImGui_Selectable(ctx,intens_names[k],v==k) then intensity_tool=k;set_all(k) end
      end
      r.ImGui_EndPopup(ctx)
    end
    r.ImGui_PopStyleColor(ctx,n)
  end
end
local function intensity_cell(c,contour,ci)
  local s=sections[c.j]
  local v=c.b and s.bars[c.b].int or s.bars[1].int
  if not c.b then for _,bar in ipairs(s.bars) do if bar.int~=v then v=0;break end end end
  local label=s.countin and "—" or v==0 and "Mixed" or v==5 and "" or (c.b and v==4 and "V.Strong" or intens_names[v])
  local id="##int"..c.j..":"..(c.b or 0)
  local dl=r.ImGui_GetWindowDrawList(ctx)
  local x,y=r.ImGui_GetCursorScreenPos(ctx)
  local clicked=r.ImGui_InvisibleButton(ctx,id,c.w,CELL_H)
  local hover=r.ImGui_IsItemHovered(ctx,r.ImGui_HoveredFlags_AllowWhenBlockedByActiveItem())
  local f0,f1
  if v==5 then
    local a=contour[c.j][c.b or 1]
    local b=contour[c.j][c.b or #s.bars]
    f0,f1=a.f0,b.f1
  elseif v==0 then f0,f1=0.5,0.5
  elseif not s.countin then f0,f1=section_fill[v],section_fill[v]
  else f0,f1=0,0 end
  local segments
  if v==5 and not c.b then
    segments={}
    for k,bar in ipairs(s.bars) do
      local d=contour[c.j][k]
      segments[#segments+1]={a=(bar.a-s.a)/(s.b-s.a),b=(bar.b-s.a)/(s.b-s.a),f0=d.f0,f1=d.f1}
    end
  end
  draw_section_tile(dl,x,y,c.w,CELL_H,f0,f1,label,false,hover,segments)
  if not job and not s.countin then
    if hover and r.ImGui_IsMouseClicked(ctx,0) then
      local chosen=intensity_tool
      stroke={kind="intensity",ci=ci,value=chosen,ramp=chosen==5 and new_ramp() or 0};set_intensity(c.j,c.b,chosen,stroke.ramp)
    elseif hover and stroke and stroke.kind=="intensity" and r.ImGui_IsMouseDown(ctx,0) and stroke.ci~=ci then
      for k=math.min(ci,stroke.ci),math.max(ci,stroke.ci) do
        local col=display_cols[k];if col then set_intensity(col.j,col.b,stroke.value,stroke.ramp) end
      end
      stroke.ci=ci
    end
  end
  local n=mono_push(true)
  if not job and not s.countin and r.ImGui_BeginPopupContextItem(ctx,"##opts"..id) then
    for i=#intensity_ids-1,1,-1 do local k=intensity_ids[i];if r.ImGui_Selectable(ctx,intens_names[k],v==k) then intensity_tool=k;set_intensity(c.j,c.b,k) end end
    if r.ImGui_Selectable(ctx,"Transition",v==5) then intensity_tool=5;set_intensity(c.j,c.b,5) end
    r.ImGui_EndPopup(ctx)
  end
  r.ImGui_PopStyleColor(ctx,n)
end
local function play_section(s,bars_early,go_only)
  if job or pending_start or r.EnumProjects(-1,"")~=proj then return end
  local state=r.GetPlayStateEx(proj)
  if (state&4)~=0 then status="Stop recording before jumping to a section.";return end
  -- Stop first so REAPER cannot restore its previous edit cursor over our cue.
  if state~=0 then r.Main_OnCommand(1016,0) end
  local q=r.TimeMap2_timeToQN(proj,s.a)
  local pos=math.max(0,r.TimeMap2_QNToTime(proj,q-4*bars_early))
  r.SetEditCurPos2(proj,pos,true,false)
  if not go_only then r.Main_OnCommand(1007,0) end
end
local function color_header(c)
  local s=sections[c.j]
  local id="##sec"..c.j..":"..(c.b or 0)
  local dl=r.ImGui_GetWindowDrawList(ctx)
  local x,y=r.ImGui_GetCursorScreenPos(ctx)
  local rr,gg,bb=rgb(s.color)
  local col=contrast(rr,gg,bb)
  local foldable=not c.b or c.b==1
  local fold_w=foldable and 18 or 0
  local main_w=c.w-fold_w
  local clicked=r.ImGui_InvisibleButton(ctx,id,main_w,CELL_H)
  local hover=r.ImGui_IsItemHovered(ctx)
  r.ImGui_DrawList_AddRectFilled(dl,x,y,x+c.w,y+CELL_H,rgba(rr,gg,bb,255),3)
  local label=c.b and (c.b==1 and s.name or tostring(c.b)) or s.name
  r.ImGui_DrawList_PushClipRect(dl,x+2,y,x+main_w-2,y+CELL_H,true)
  centered(dl,x,y,main_w,CELL_H,label,col)
  r.ImGui_DrawList_PopClipRect(dl)
  if not job and not pending_start then
    if clicked and r.ImGui_IsKeyDown(ctx,r.ImGui_Mod_Shift()) then
      ui.section_hover=nil;play_section(s,1)
    elseif hover and not r.ImGui_IsMouseDown(ctx,0) then
      ui.section_hover={s=s,x=x,y=y,until_time=r.time_precise()+0.45}
    end
    local n=mono_push(true)
    if r.ImGui_BeginPopupContextItem(ctx,"##secplay"..c.j..":"..(c.b or 0)) then
      ui.section_hover=nil
      if r.ImGui_Selectable(ctx,"Go to Section") then play_section(s,0,true) end
      r.ImGui_EndPopup(ctx)
    end
    r.ImGui_PopStyleColor(ctx,n)
  end
  if foldable then
    -- Dedicated right-hand hit region; title clicks never expand the grid.
    r.ImGui_SameLine(ctx,0,0)
    local fold_clicked=r.ImGui_InvisibleButton(ctx,id.."fold",fold_w,CELL_H)
    local fold_hover=r.ImGui_IsItemHovered(ctx)
    if fold_hover then ui.section_hover=nil end
    if fold_hover then r.ImGui_DrawList_AddRectFilled(dl,x+main_w,y,x+c.w,y+CELL_H,0xFFFFFF20,3) end
    local tx,ty=x+c.w-5,y+CELL_H-5
    if expanded[s.key] then
      r.ImGui_DrawList_AddTriangleFilled(dl,tx-10,ty-1,tx,ty-1,tx-5,ty-8,col)
    else
      r.ImGui_DrawList_AddTriangleFilled(dl,tx-9,ty-9,tx-9,ty,tx,ty,col)
    end
    if fold_clicked and not job and not pending_start then expanded[s.key]=not expanded[s.key] end
  end
end
-- A small input-capable floating strip, rather than a non-clickable tooltip.
-- The brief grace interval lets the pointer cross from title to controls.
function ui.section_play_strip()
  local h=ui.section_hover
  if not h or job or pending_start or r.time_precise()>h.until_time then ui.section_hover=nil;return end
  local flags=r.ImGui_WindowFlags_NoTitleBar() | r.ImGui_WindowFlags_AlwaysAutoResize() |
    r.ImGui_WindowFlags_NoSavedSettings() | r.ImGui_WindowFlags_NoFocusOnAppearing() |
    r.ImGui_WindowFlags_NoMove() | r.ImGui_WindowFlags_NoResize() | r.ImGui_WindowFlags_NoDocking()
  r.ImGui_SetNextWindowPos(ctx,h.x-6,h.y-2,r.ImGui_Cond_Always(),0,1)
  r.ImGui_SetNextWindowBgAlpha(ctx,1)
  local visible=r.ImGui_Begin(ctx,"##sectionPlaybackStrip",nil,flags)
  if visible then
    if r.ImGui_IsWindowHovered(ctx) then h.until_time=r.time_precise()+0.45 end
    local n=mono_push(true)
    r.ImGui_PushStyleVar(ctx,r.ImGui_StyleVar_FrameRounding(),3)
    local choice
    if r.ImGui_Button(ctx,"-2",29,22) then choice=2 end
    r.ImGui_SameLine(ctx,0,3)
    if r.ImGui_Button(ctx,"-1",29,22) then choice=1 end
    r.ImGui_SameLine(ctx,0,3)
    if r.ImGui_Button(ctx,"►",29,22) then choice=0 end
    r.ImGui_PopStyleVar(ctx)
    r.ImGui_PopStyleColor(ctx,n)
    if choice~=nil then ui.section_hover=nil;play_section(h.s,choice) end
    r.ImGui_End(ctx)
  end
end
local function track_header(t)
  local dl=r.ImGui_GetWindowDrawList(ctx)
  local x,y=r.ImGui_GetCursorScreenPos(ctx)
  local w=161
  local clicked=r.ImGui_InvisibleButton(ctx,"##track"..t.key,w,CELL_H)
  local rr,gg,bb=rgb(r.GetTrackColor(t.track))
  r.ImGui_DrawList_AddRectFilled(dl,x,y,x+w,y+CELL_H,rgba(rr,gg,bb,255),3)
  local _,th=r.ImGui_CalcTextSize(ctx,t.name)
  r.ImGui_DrawList_PushClipRect(dl,x+5,y,x+w-5,y+CELL_H,true)
  r.ImGui_DrawList_AddText(dl,x+6,y+(CELL_H-th)/2,contrast(rr,gg,bb),t.name)
  r.ImGui_DrawList_PopClipRect(dl)
  if not job then
    local n=mono_push(true)
    if clicked then r.ImGui_OpenPopup(ctx,"##trackmenu"..t.key) end
    if r.ImGui_BeginPopupContextItem(ctx,"##trackmenu"..t.key) then
      plugin_menu(t,nil,nil,true)
      r.ImGui_EndPopup(ctx)
    end
    r.ImGui_PopStyleColor(ctx,n)
  end
end
function ui.track_switch(t,label,param)
  local value=r.GetMediaTrackInfo_Value(t.track,param)
  local active=value~=0
  r.ImGui_SameLine(ctx,0,3)
  r.ImGui_PushStyleColor(ctx,r.ImGui_Col_Button(),active and 0x8A8A8AFF or 0x303030FF)
  r.ImGui_PushStyleColor(ctx,r.ImGui_Col_ButtonHovered(),0x555555FF)
  r.ImGui_PushStyleColor(ctx,r.ImGui_Col_ButtonActive(),0x707070FF)
  r.ImGui_PushStyleColor(ctx,r.ImGui_Col_Text(),active and 0x151515FF or 0xD0D0D0FF)
  if r.ImGui_Button(ctx,label.."##"..param..t.key,22,CELL_H) and not job and not pending_start then
    if param=="I_SOLO" then r.SetMediaTrackInfo_Value(t.track,param,active and 0 or 2)
    else r.SetMediaTrackInfo_Value(t.track,param,active and 0 or 1) end
    r.TrackList_AdjustWindows(false);r.UpdateArrange()
  end
  r.ImGui_PopStyleColor(ctx,4)
end
local function tool_button(i)
  local dl=r.ImGui_GetWindowDrawList(ctx)
  local x,y=r.ImGui_GetCursorScreenPos(ctx)
  local w=i==9 and 82 or 32
  local clicked=r.ImGui_InvisibleButton(ctx,"##tool"..i,w,CELL_H)
  local hover=r.ImGui_IsItemHovered(ctx)
  r.ImGui_DrawList_AddRectFilled(dl,x,y,x+w,y+CELL_H,tool==i and 0xD3B86DFF or hover and 0xB5BEC8FF or 0x8F9BA7FF,0)
  r.ImGui_DrawList_AddRect(dl,x,y,x+w,y+CELL_H,tool==i and 0xFFFFFFFF or 0x11111180,0,0,tool==i and 2.5 or 1)
  if i==9 then centered(dl,x,y,w,CELL_H,"Transition",0x101010FF,0xFFFFFFFF)
  else symbol(dl,x,y,w,CELL_H,i) end
  if hover then r.ImGui_SetTooltip(ctx,i==9 and "Transition" or simple[i]) end
  if clicked then tool=i;transition_start=nil end
end
local function set_pan(t,j,b,v)
  v=clamp(math.floor(v+0.5),-100,100)
  local first,last=j or 1,j or #sections
  for k=first,last do
    local s=sections[k]
    for n=(j and b or 1),(j and b or #s.bars) do
      t.pans[k][n]=v;t.panramps[k][n]=0
      put("pan:"..t.key..":"..s.key..":"..n,v);put("panramp:"..t.key..":"..s.key..":"..n,0)
    end
  end
  pan_dirty[t]=true
end
function ui.paint_pan_transition(t,j,b,k,n)
  local aj,ab,zj,zb=ui.span_bounds(j,b,k,n)
  local id=new_ramp()
  for s=aj,zj do
    for p=(s==aj and ab or 1),(s==zj and zb or #sections[s].bars) do
      t.panramps[s][p]=id
      put("panramp:"..t.key..":"..sections[s].key..":"..p,id)
    end
  end
  pan_dirty[t]=true;ui.pan_start=nil
end
function ui.pan_transition_cell(t,j,b)
  if not j then return false end
  for n=b or 1,b or #sections[j].bars do
    if t.panramps[j][n]~=0 then return true end
  end
  return false
end
function ui.pan_label(v)
  return v==0 and "C" or (v<0 and "L" or "R")..math.floor(math.abs(v)+0.5)
end
local function pan_summary(t,j,b)
  local value
  for k=j or 1,j or #sections do
    for n=(j and b or 1),(j and b or #sections[k].bars) do
      local p=t.pans[k][n]
      if t.panramps[k][n]~=0 then return nil end
      if value~=nil and value~=p then return nil end
      value=p
    end
  end
  return value
end
local function pan_cell(t,j,b,w,map)
  local dl=r.ImGui_GetWindowDrawList(ctx)
  local x,y=r.ImGui_GetCursorScreenPos(ctx)
  local id="##pan"..t.key..":"..(j or 0)..":"..(b or 0)
  local v=pan_summary(t,j,b)
  local available=has_position(t,perf_index(t)) and t.position_ready~=false
  r.ImGui_InvisibleButton(ctx,id,w,CELL_H)
  local hover=r.ImGui_IsItemHovered(ctx,r.ImGui_HoveredFlags_AllowWhenBlockedByActiveItem())
  local rr,gg,bb=rgb(r.GetTrackColor(t.track))
  local light=rgba(math.floor(rr*.55+110),math.floor(gg*.55+110),math.floor(bb*.55+110),255)
  local dark=rgba(math.floor(rr*.70),math.floor(gg*.70),math.floor(bb*.70),255)
  local transition=ui.pan_transition_cell(t,j,b)
  local split=x+w*((v or 0)+100)/200
  r.ImGui_DrawList_AddRectFilled(dl,x,y,x+w,y+CELL_H,light)
  if transition and map then
    local first,last=b or 1,b or #sections[j].bars
    local ta,tz=map[j][first].a,map[j][last].b
    for k=first,last do
      local p=map[j][k]
      local xa,xb=x+w*(p.a-ta)/(tz-ta),x+w*(p.b-ta)/(tz-ta)
      local ya=y+CELL_H*(1-(p.g0+100)/200)
      local yb=y+CELL_H*(1-(p.g1+100)/200)
      r.ImGui_DrawList_AddQuadFilled(dl,xa,ya,xb,yb,xb,y+CELL_H,xa,y+CELL_H,dark)
      r.ImGui_DrawList_AddLine(dl,xa,ya,xb,yb,0x111111FF,2)
    end
  else
    r.ImGui_DrawList_AddRectFilled(dl,x,y,split,y+CELL_H,dark)
    r.ImGui_DrawList_AddLine(dl,x+w/2,y+2,x+w/2,y+CELL_H-2,0xFFFFFFA0,1)
    if v~=nil then r.ImGui_DrawList_AddLine(dl,split,y,split,y+CELL_H,0x111111FF,2) end
  end
  r.ImGui_DrawList_AddRect(dl,x,y,x+w,y+CELL_H,hover and 0xFFFFFFFF or 0x00000060,0,0,hover and 2 or 1)
  local label=not available and "No Pan FX" or v==nil and "Mixed" or v==0 and "C" or (v<0 and "L" or "R")..math.abs(v)
  if transition and available and map then
    local a=map[j][b or 1].g0;local z=map[j][b or #sections[j].bars].g1
    centered(dl,x,y,w,CELL_H,ui.pan_label(a).." > "..ui.pan_label(z),0x101010FF)
  else centered(dl,x,y,w,CELL_H,label,0x101010FF) end
  if not job and not pending_start then
    if available and hover and r.ImGui_IsMouseClicked(ctx,0) then
      if ui.pan_transition then
        if j then ui.pan_stroke={t=t,j=j,b=b} else status="Select a section or bar for a pan transition." end
      else pan_drag={id=id} end
    end
    if available and hover and ui.pan_stroke and ui.pan_stroke.t==t and j and r.ImGui_IsMouseDown(ctx,0) then
      ui.pan_stroke.endj=j;ui.pan_stroke.endb=b
    end
    if available and pan_drag and pan_drag.id==id and r.ImGui_IsMouseDown(ctx,0) then
      local mx=r.ImGui_GetMousePos(ctx)
      local p=clamp(math.floor(((mx-x)/w*200-100)+0.5),-100,100)
      if v~=p then set_pan(t,j,b,p) end
    end
    local n=mono_push(true)
    if r.ImGui_BeginPopupContextItem(ctx,id.."menu") then
      if available then
        if r.ImGui_Selectable(ctx,"Center",v==0) then set_pan(t,j,b,0) end
        if r.ImGui_Selectable(ctx,"Hard Left",v==-100) then set_pan(t,j,b,-100) end
        if r.ImGui_Selectable(ctx,"Hard Right",v==100) then set_pan(t,j,b,100) end
        if j and r.ImGui_Selectable(ctx,"Transition",transition) then ui.paint_pan_transition(t,j,b,j,b) end
      else r.ImGui_Text(ctx,"Position slider 11 unavailable") end
      plugin_menu(t,j,b)
      r.ImGui_EndPopup(ctx)
    end
    r.ImGui_PopStyleColor(ctx,n)
  end
end
local function set_parameters_visible()
  show_parameters=not show_parameters
  put("show_parameters",show_parameters and 1 or 0)
  for _,t in ipairs(rows) do
    local f,p=fx_index(t),perf_index(t)
    local list={}
    if f then list[#list+1]={f,0} end
    if p then
      list[#list+1]={p,0}
      if has_position(t,p) then list[#list+1]={p,10} end
    end
    for _,v in ipairs(list) do
      local e=r.GetFXEnvelope(t.track,v[1],v[2],false)
      if e then
        local ok,chunk=r.GetEnvelopeStateChunk(e,"",false)
        if ok then
          chunk=chunk:gsub("([\r\n]VIS%s+)%d+",function(prefix) return prefix..(show_parameters and "1" or "0") end,1)
          r.SetEnvelopeStateChunk(e,chunk,false)
        end
      end
    end
  end
  r.TrackList_AdjustWindows(false);r.UpdateArrange()
end
local function install_visible_position()
  if not pan_scan_pending or not stopped() or job or pending_start then return end
  pan_scan_pending=false
  local missing,ready=0,0
  r.Undo_BeginBlock2(proj)
  for _,t in ipairs(rows) do
    local ok,err=pcall(function()
      if r.GetMediaTrackInfo_Value(t.track,"I_FXEN")==0 or r.GetMediaTrackInfo_Value(t.track,"I_AUTOMODE")>1 or r.GetGlobalAutomationOverride()>1 then error("Enable FX and use Read or Trim/Read first.",0) end
      local f,msg=ensure_position_fx(t)
      if not f then error(msg,0) end
      if t.model<0 or not t.timbre_allowed then position_only(t,f)
      else r.TrackFX_SetEnabled(t.track,f,true) end
      apply_pan(t,f)
      ui.mirror_existing_gain(t)
    end)
    t.position_ready=ok
    if ok then ready=ready+1 else missing=missing+1;r.ShowConsoleMsg("N2N Mix Pan: "..t.name..": "..tostring(err).."\n") end
  end
  r.Undo_EndBlock2(proj,"N2N Mix: initialize track position",-1)
  if missing>0 then
    local msg=string.format("Position ready on %d/%d tracks. Update Performance Dynamics with slider 11; see console.",ready,#rows)
    r.ShowConsoleMsg("N2N Mix: "..msg.."\n")
    if not ui.start_rejected then status=msg end
  end
end
local function apply_dirty()
  if (not next(dirty) and not next(pan_dirty) and not master_dirty) or job or r.EnumProjects(-1,"")~=proj or (r.GetPlayStateEx(proj)&4)~=0 then return end
  if r.GetGlobalAutomationOverride()>1 then status="Disable global automation write/bypass before editing.";return end
  r.Undo_BeginBlock2(proj)
  local ok,e=pcall(function()
    if master_dirty and master then
      local needed=fx_index(master)~=nil
      for _,s in ipairs(sections) do for _,b in ipairs(s.bars) do if b.int==6 then needed=true end end end
      if needed then
        local safe,msg=safe_row(master);if not safe then error(msg) end
        ensure_fx(master);apply_master(num("mastergain",0))
      end
    end
    for t in pairs(pan_dirty) do
      if valid(t.track) and r.GetMediaTrackInfo_Value(t.track,"B_SHOWINMIXER")>0 then
        local f,msg=ensure_position_fx(t)
        if not f then error(msg,0) end
        if t.model<0 or not t.timbre_allowed then position_only(t,f) end
        apply_pan(t,f)
      end
    end
    for t in pairs(dirty) do
      if valid(t.track) and r.GetMediaTrackInfo_Value(t.track,"B_SHOWINMIXER")>0 and (fx_index(t) or perf_index(t) or t.model>=0) then
        local safe,msg=safe_row(t);if not safe then error(msg) end
        configure_perf(t)
        apply_row(t)
      end
    end
  end)
  r.Undo_EndBlock2(proj,"N2N Mix grid edit",-1)
  dirty={};pan_dirty={};master_dirty=false
  if not ok then note("Grid update stopped: "..tostring(e)) end
end
local function same() r.ImGui_SameLine(ctx) end
local function button(s,fn)
  if r.ImGui_Button(ctx,s) then fn() end
end
mono_push=function(gray)
  local base=gray and 0xC4C4C4FF or 0xEAEAEAFF
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
  r.ImGui_DrawList_AddCircleFilled(dl,x+8,cy,7,0xEAEAEAFF)
  r.ImGui_DrawList_AddCircle(dl,x+8,cy,7,0x111111FF,0,1.5)
  if traditional==value then r.ImGui_DrawList_AddCircleFilled(dl,x+8,cy,3.8,0x111111FF) end
  local text_color=r.ImGui_GetStyleColor(ctx,r.ImGui_Col_Text())
  r.ImGui_DrawList_AddText(dl,x+19,y+(CELL_H-th)/2,text_color,label)
  if clicked then traditional=value;put("traditional",value and 1 or 0) end
end
-- The song grid has a frozen track header. Tool palettes are anchored to
-- the visible editing area, not to the full window or the scrolled song.
local function song_palette_x(x,avail,w)
  local left=x+LEFT_W+ALL_W+12
  return left+math.max(0,(x+avail-left-w)/2)
end
local function section_tool_width()
  local w=0
  for _,k in ipairs(intensity_ids) do w=math.max(w,r.ImGui_CalcTextSize(ctx,intens_names[k])+18) end
  return w,w*#intensity_ids+4*(#intensity_ids-1)
end
-- Keep the current volume palette separate from the transport and notation
-- layout, so other editing contexts can provide their own tools later.
local function cell_palette_width()
  local w=0
  for _,i in ipairs(tool_ids) do w=w+(i==9 and 82 or 32) end
  return w+4*(#tool_ids-1)
end
local function draw_cell_palette()
  for k,i in ipairs(tool_ids) do if k>1 then same() end;tool_button(i) end
end
local function notation_width()
  return r.ImGui_CalcTextSize(ctx,"Simple")+r.ImGui_CalcTextSize(ctx,"Traditional")+48
end
-- Transport symbols are drawn with geometry rather than font glyphs so the
-- appearance is consistent on macOS and Windows, even at small font sizes.
function ui.transport_icon(dl,i,x,y,color)
  local function ln(a,b,c,d,w)
    r.ImGui_DrawList_AddLine(dl,x+a,y+b,x+c,y+d,color,w or 1.6)
  end
  local function rect(a,b,c,d)
    r.ImGui_DrawList_AddRectFilled(dl,x+a,y+b,x+c,y+d,color,0.7)
  end
  local function tri(a,b,c,d,e,f)
    r.ImGui_DrawList_AddTriangleFilled(dl,x+a,y+b,x+c,y+d,x+e,y+f,color)
  end
  if i==1 then
    -- Panic / all notes off.
    ln(0,-6,0,1,2);r.ImGui_DrawList_AddCircleFilled(dl,x,y+5,1.3,color)
  elseif i==2 then
    r.ImGui_DrawList_AddCircleFilled(dl,x,y,5.5,color)
  elseif i==3 then
    tri(-4,-6,-4,6,6,0)
  elseif i==4 then
    rect(-5,-5,5,5)
  elseif i==5 then
    rect(-5,-6,-1,6);rect(1,-6,5,6)
  elseif i==6 then
    -- Two arrows in a compact repeat loop.
    ln(-6,0,-6,-4);ln(-6,-4,4,-4)
    ln(1,-7,4,-4);ln(1,-1,4,-4)
    ln(6,0,6,4);ln(6,4,-4,4)
    ln(-1,1,-4,4);ln(-1,7,-4,4)
  elseif i==7 then
    rect(-7,-6,-5,6);tri(4,-6,4,6,-4,0)
  elseif i==8 then
    ln(5,0,-5,0);ln(-5,0,0,-5);ln(-5,0,0,5)
  elseif i==9 then
    ln(-5,0,5,0);ln(5,0,0,-5);ln(5,0,0,5)
  elseif i==10 then
    rect(5,-6,7,6);tri(-4,-6,-4,6,4,0)
  end
end
-- Canonicalize script paths before registering actions or loading modules.
-- Preserve Windows drive/UNC roots and Unix roots; do not treat "." as a module.
function ui.canonical_script_path(path)
    path=path:gsub("\\","/")
    local root,rest=path:match("^(//[^/]+/[^/]+/?)/*(.*)$")
    if not root then root,rest=path:match("^(%a:/)/*(.*)$") end
    if not root then root,rest=path:match("^(/)/*(.*)$") end
    root,rest=root or "",rest or path
    if root~="" and root:sub(-1)~="/" then root=root.."/" end
    local parts={}
    for part in rest:gmatch("[^/]+") do
        if part==".." then
            if #parts>0 and parts[#parts]~=".." then parts[#parts]=nil
            elseif root=="" then parts[#parts+1]=part end
        elseif part~="." then parts[#parts+1]=part end
    end
    return root..table.concat(parts,"/")
end
function ui.raise_window(title)
    local r=reaper
    local hwnd=r.JS_Window_Find and r.JS_Window_Find(title,true)
    if not hwnd and r.JS_Window_FindTop then hwnd=r.JS_Window_FindTop(title,true) end
    if not hwnd then return false end
    if r.JS_Window_IsVisible and not r.JS_Window_IsVisible(hwnd) and r.JS_Window_Show then r.JS_Window_Show(hwnd,"SHOW") end
    if r.JS_Window_SetZOrder then r.JS_Window_SetZOrder(hwnd,"TOP") end
    if r.JS_Window_SetForeground then r.JS_Window_SetForeground(hwnd) end
    if r.JS_Window_SetFocus then r.JS_Window_SetFocus(hwnd) end
    return true
end
function ui.open_numbers2notes()
  local sec="N2N_EDITOR_WINDOWS"
  local hb=tonumber(r.GetExtState(sec,"numbers2notes:heartbeat"))
  if hb and math.abs(r.time_precise()-hb)<3 then
    r.SetExtState(sec,"numbers2notes:focus",tostring(r.time_precise()),false)
    ui.raise_window("Numbers2Notes - Nashville Number Charts for Reaper")
    return
  end
  if ui.raise_window("Numbers2Notes - Nashville Number Charts for Reaper") then return end
  local function search(dir,depth)
    if depth>7 then return end
    local i=0
    while true do
      local name=r.EnumerateFiles(dir,i)
      if not name then break end
      if name:lower()=="numbers2notes.lua" then return dir.."/"..name end
      i=i+1
    end
    i=0
    while true do
      local sub=r.EnumerateSubdirectories(dir,i)
      if not sub then break end
      local path=search(dir.."/"..sub,depth+1)
      if path then return path end
      i=i+1
    end
  end
  local source=ui.canonical_script_path(debug.getinfo(1,"S").source:gsub("^@",""))
  local dir=source:match("^(.*[/])")
  local path
  if dir then
    local candidate=dir.."Notes2Numbers/Numbers2Notes.lua"
    local f=io.open(candidate,"rb")
    if f then f:close();path=candidate end
  end
  path=path or search(r.GetResourcePath().."/Scripts",0)
  if not path then r.MB("Install Numbers2Notes.lua first.","N2N Mix",0);return end
  path=ui.canonical_script_path(path)
  local cmd=r.AddRemoveReaScript(true,0,path,true)
  if cmd and cmd>0 then r.Main_OnCommand(cmd,0)
  else r.MB("Could not launch Numbers2Notes.","N2N Mix",0) end
end
local function transport()
  local repeat_on=r.GetSetRepeat(-1)==1
  local state=r.GetPlayStateEx(proj)
  local recording=(state&4)~=0
  local paused=(state&2)~=0
  local playing=(state&1)~=0 and not paused
  local items={
    {"!",40349},
    {"F9",1013,r.ImGui_Key_F9()},
    {"F10",1007,r.ImGui_Key_F10()},
    {"F11",1016,r.ImGui_Key_F11()},
    {"F12",1008,r.ImGui_Key_F12()},
    {"",nil},
    {"Home",40042,r.ImGui_Key_Home()},
    {"Pg ↓",40172,r.ImGui_Key_PageDown()},
    {"Pg ↑",40173,r.ImGui_Key_PageUp()},
    {"End",40043,r.ImGui_Key_End()},
  }
  local keys_allowed=r.ImGui_IsWindowFocused(ctx) and not r.ImGui_IsAnyItemActive(ctx)
  local dl=r.ImGui_GetWindowDrawList(ctx)
  local w,h=26,22
  r.ImGui_BeginGroup(ctx)
  for i,v in ipairs(items) do
    if i>1 then r.ImGui_SameLine(ctx,0,(i==2 or i==7) and 6 or 3) end
    local x,y=r.ImGui_GetCursorScreenPos(ctx)
    local active=(i==2 and recording) or (i==3 and playing) or (i==5 and paused) or (i==6 and repeat_on)
    local accent=i==2 and 0xCF7777FF or i==3 and 0x9DC6A7FF or 0xD3B86DFF
    local icon=active and accent or (i==2 and 0xBA8585FF or 0xCCCCCCFF)
    if v[1]~="" then
      local tw,th=r.ImGui_CalcTextSize(ctx,v[1])
      r.ImGui_DrawList_AddText(dl,x+(w-tw)/2,y-th-1,0xE0E0E0FF,v[1])
    end
    local click=r.ImGui_InvisibleButton(ctx,"##mixtransport"..i,w,h)
    local hover=r.ImGui_IsItemHovered(ctx)
    local pressed=r.ImGui_IsItemActive(ctx)
    local bg=pressed and 0x4A4A4AFF or hover and 0x393939FF or active and 0x333333FF or 0x252525FF
    r.ImGui_DrawList_AddRectFilled(dl,x,y,x+w,y+h,bg,4)
    r.ImGui_DrawList_AddRect(dl,x,y,x+w,y+h,active and accent or 0x515151FF,4,0,1)
    ui.transport_icon(dl,i,x+w/2,y+h/2,icon)
    local key=keys_allowed and v[3] and r.ImGui_IsKeyPressed(ctx,v[3],false)
    if i==1 and keys_allowed then
      key=r.ImGui_IsKeyDown(ctx,r.ImGui_Mod_Shift()) and r.ImGui_IsKeyPressed(ctx,r.ImGui_Key_1(),false)
    end
    if (click or key) and not pending_start then
      if i==6 then r.GetSetRepeat(repeat_on and 0 or 1)
      else
        r.Main_OnCommand(v[2],0)
        if i==4 then r.Main_OnCommand(40349,0) end
      end
    end
  end
  r.ImGui_SameLine(ctx,0,12)
  local x,y=r.ImGui_GetCursorScreenPos(ctx)
  local label="Open Numbers2Notes"
  local bw=r.ImGui_CalcTextSize(ctx,label)+18
  local click=r.ImGui_InvisibleButton(ctx,"##openNumbers2Notes",bw,h)
  local hover=r.ImGui_IsItemHovered(ctx)
  local pressed=r.ImGui_IsItemActive(ctx)
  r.ImGui_DrawList_AddRectFilled(dl,x,y,x+bw,y+h,pressed and 0x4A4A4AFF or hover and 0x393939FF or 0x252525FF,4)
  r.ImGui_DrawList_AddRect(dl,x,y,x+bw,y+h,0x515151FF,4,0,1)
  centered(dl,x,y,bw,h,label,0xCCCCCCFF)
  if click and not pending_start then ui.open_numbers2notes() end
  r.ImGui_EndGroup(ctx)
end

local function show_target_popup()
  if job or pending_start then return end
  if not stopped() then status="Stop transport before Auto Mix.";return end
  ui.section_hover=nil
  target_popup=not target_popup
end
local function master_options()
  if not target_popup then return end
  r.ImGui_SetNextWindowPos(ctx,ui.target_x+10,ui.target_y+10,r.ImGui_Cond_Always(),0,0)
  r.ImGui_SetNextWindowBgAlpha(ctx,1)
  local chosen,custom_requested
  r.ImGui_PushStyleColor(ctx,r.ImGui_Col_WindowBg(),0x000000FF)
  r.ImGui_PushStyleColor(ctx,r.ImGui_Col_Text(),0xFFFFFFFF)
  r.ImGui_PushStyleColor(ctx,r.ImGui_Col_Border(),0x515151FF)
  local flags=r.ImGui_WindowFlags_AlwaysAutoResize()|r.ImGui_WindowFlags_NoTitleBar()|r.ImGui_WindowFlags_NoSavedSettings()|r.ImGui_WindowFlags_NoMove()|r.ImGui_WindowFlags_NoResize()|r.ImGui_WindowFlags_NoDocking()
  if r.ImGui_Begin(ctx,"Auto Mix Settings##target",nil,flags) then
    r.ImGui_Text(ctx,"Choose master loudness")
    local n=mono_push(true)
    r.ImGui_PushStyleVar(ctx,r.ImGui_StyleVar_FrameRounding(),4)
    if r.ImGui_Button(ctx,"Use Default",320,30) then chosen={DEFAULT_PRESET,last_custom} end
    r.ImGui_Text(ctx,"YouTube / general listening  |  -14 LUFS")
    if r.ImGui_Button(ctx,"Use Last Used Settings",320,30) then chosen={last_preset,last_custom} end
    local previous=last_preset==#presets and last_custom or presets[last_preset][2]
    r.ImGui_Text(ctx,string.format("%s  |  %.1f LUFS",presets[last_preset][1],previous))
    r.ImGui_PopStyleVar(ctx)
    r.ImGui_PopStyleColor(ctx,n)
    r.ImGui_Separator(ctx)
    r.ImGui_Text(ctx,"Other master targets")
    -- Draw text after hit testing so normal and hovered text can differ.
    for i,p in ipairs(presets) do
      local label=i<#presets and string.format("%s  |  %.0f LUFS",p[1],p[2]) or "Custom..."
      local x,y=r.ImGui_GetCursorScreenPos(ctx)
      local w,h=340,22
      local clicked=r.ImGui_InvisibleButton(ctx,"##master_target"..i,w,h)
      local hovered=r.ImGui_IsItemHovered(ctx)
      local dl=r.ImGui_GetWindowDrawList(ctx)
      if hovered then r.ImGui_DrawList_AddRectFilled(dl,x,y,x+w,y+h,0xD4D4D4FF,3) end
      local _,th=r.ImGui_CalcTextSize(ctx,label)
      r.ImGui_DrawList_AddText(dl,x+6,y+(h-th)/2,hovered and 0x111111FF or 0xFFFFFFFF,label)
      if clicked then
        if i<#presets then chosen={i,last_custom} else custom_requested=true end
      end
    end
    r.ImGui_Separator(ctx)
    r.ImGui_Text(ctx,"Integrated LUFS (LUFS-I)")
    r.ImGui_PushTextWrapPos(ctx,r.ImGui_GetCursorPosX(ctx)+340)
    r.ImGui_TextWrapped(ctx,string.format("Gain-only normalization with a %.1f dBFS sample-peak ceiling. The result may be quieter than the target to avoid clipping. This is not a true-peak limiter or a guarantee of streaming compliance.",peak_ceiling))
    r.ImGui_PopTextWrapPos(ctx)
    n=mono_push(true)
    local avail=r.ImGui_GetContentRegionAvail(ctx)
    r.ImGui_SetCursorPosX(ctx,r.ImGui_GetCursorPosX(ctx)+math.max(0,(avail-100)/2))
    local cancel=r.ImGui_Button(ctx,"Cancel",100,26)
    r.ImGui_PopStyleColor(ctx,n)
    if chosen or custom_requested or cancel then target_popup=false end
    r.ImGui_End(ctx)
  end
  r.ImGui_PopStyleColor(ctx,3)
  if custom_requested then
    local ok,s=r.GetUserInputs("Custom Master Loudness",1,"Target LUFS-I (-35 to -8):",tostring(last_custom))
    if ok then
      local v=tonumber(s)
      if v and v>=-35 and v<=-8 then chosen={#presets,v}
      else r.MB("Enter a numeric LUFS target between -35 and -8.","Custom Master Loudness",0);target_popup=true end
    else target_popup=true end
  end
  if chosen then
    preset,custom=chosen[1],chosen[2]
    request_start()
  end
end
-- Read-only nominal target display. Measurements and base corrections are
-- section-level, not per-bar measurements, and are labelled accordingly.
local function target_cell(t,j,b,w,plan,bus_offset)
  local s=sections[j]
  local dl=r.ImGui_GetWindowDrawList(ctx)
  local x,y=r.ImGui_GetCursorScreenPos(ctx)
  r.ImGui_Dummy(ctx,w,TARGET_H)
  local rr,gg,bb=rgb(r.GetTrackColor(t.track))
  local color=rgba(math.floor(rr*.55+110),math.floor(gg*.55+110),math.floor(bb*.55+110),255)
  r.ImGui_DrawList_AddRectFilled(dl,x,y,x+w,y+TARGET_H,color,0)
  r.ImGui_DrawList_AddRect(dl,x,y,x+w,y+TARGET_H,0x00000050)
  if s.countin then centered(dl,x,y,w,TARGET_H,"—",0x101010FF);return end
  local energy,duration=0,0
  for k=b or 1,b or #s.bars do
    local p=plan[j][k]
    local dt=(s.bars[k].b-s.bars[k].a)/16
    for i=1,16 do
      local u=(i-0.5)/16
      if not p.mute then energy=energy+dt*10^((p.want(u)+bus_offset)/10) end
      duration=duration+dt
    end
  end
  local label=energy>0 and duration>0 and string.format("%.1f",t.target+10*math.log(energy/duration,10)) or "Mute"
  local base=t.base[j]
  local gain=base and string.format("G%+.1f",base) or "G—"
  local line=label.." / "..gain
  local tw,th=r.ImGui_CalcTextSize(ctx,line)
  local native_size=r.ImGui_GetFontSize(ctx)
  local size=math.min(10,native_size*math.max(1,w-4)/math.max(1,tw))
  if r.ImGui_DrawList_AddTextEx and r.ImGui_GetFont then
    local scale=size/native_size
    r.ImGui_DrawList_AddTextEx(dl,r.ImGui_GetFont(ctx),size,x+(w-tw*scale)/2,y+(TARGET_H-th*scale)/2,0x101010FF,line)
  else centered(dl,x,y,w,TARGET_H,line,0x101010FF) end
end
local function target_section_cell(c,contour)
  local s=sections[c.j]
  local dl=r.ImGui_GetWindowDrawList(ctx)
  local x,y=r.ImGui_GetCursorScreenPos(ctx)
  r.ImGui_Dummy(ctx,c.w,CELL_H)
  local energy,duration=0,0
  for k=c.b or 1,c.b or #s.bars do
    local d=contour[c.j][k]
    local dt=(d.b-d.a)/16
    for i=1,16 do
      local f=d.f0+(d.f1-d.f0)*(i-0.5)/16
      if f>0 then energy=energy+dt*10^(section_db(f)/10) end
      duration=duration+dt
    end
  end
  local label=s.countin and "—" or energy>0 and duration>0 and string.format("%+.1f dB",10*math.log(energy/duration,10)) or "Silent"
  draw_section_tile(dl,x,y,c.w,CELL_H,0,0,label,false,false)
end
local function alert_window()
  if alert_text=="" or r.time_precise()>=alert_until then return end
  local flags=r.ImGui_WindowFlags_NoTitleBar() | r.ImGui_WindowFlags_NoResize() |
    r.ImGui_WindowFlags_NoCollapse() | r.ImGui_WindowFlags_NoSavedSettings() |
    r.ImGui_WindowFlags_NoDocking()
  r.ImGui_SetNextWindowPos(ctx,alert_x or 300,alert_y or 200,r.ImGui_Cond_Always(),0.5,0.5)
  r.ImGui_SetNextWindowSize(ctx,280,68,r.ImGui_Cond_Always())
  r.ImGui_SetNextWindowBgAlpha(ctx,1)
  r.ImGui_SetNextWindowFocus(ctx)
  local visible=r.ImGui_Begin(ctx,"N2N Mix Processing##notice",nil,flags)
  if visible then
    local dl=r.ImGui_GetWindowDrawList(ctx)
    local x,y=r.ImGui_GetCursorScreenPos(ctx)
    local w,h=r.ImGui_GetContentRegionAvail(ctx)
    centered(dl,x,y,w,h,alert_text,r.ImGui_GetStyleColor(ctx,r.ImGui_Col_Text()))
    r.ImGui_End(ctx)
  end
end
local function draw()
  r.ImGui_PushStyleVar(ctx,r.ImGui_StyleVar_Alpha(),1)
  r.ImGui_PushStyleVar(ctx,r.ImGui_StyleVar_FramePadding(),4,3)
  r.ImGui_PushStyleVar(ctx,r.ImGui_StyleVar_ItemSpacing(),4,3)
  r.ImGui_PushStyleVar(ctx,r.ImGui_StyleVar_CellPadding(),3,2)
  local bg=r.ImGui_GetStyleColor(ctx,r.ImGui_Col_WindowBg()) | 0xff
  r.ImGui_PushStyleColor(ctx,r.ImGui_Col_WindowBg(),bg)
  r.ImGui_PushStyleColor(ctx,r.ImGui_Col_ChildBg(),bg)
  r.ImGui_PushStyleColor(ctx,r.ImGui_Col_TitleBg(),0x080808FF)
  r.ImGui_PushStyleColor(ctx,r.ImGui_Col_TitleBgActive(),0x666666FF)
  r.ImGui_PushStyleColor(ctx,r.ImGui_Col_TitleBgCollapsed(),0x080808FF)
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
  -- Reserve enough width for both centered palettes and the far-right
  -- notation selector, even if a previously saved window was narrower.
  LEFT_W=ui.header_width()
  local _,section_w=section_tool_width()
  local transport_w=10*26+7*3+2*6+12+r.ImGui_CalcTextSize(ctx,"Open Numbers2Notes")+18
  local min_w=math.max(LEFT_W,300)+ALL_W+12+math.max(section_w,cell_palette_width()+2*(notation_width()+8))+28
  -- Keep the added launcher clear of the centered tool palette even when
  -- the Role and Timbre columns are collapsed.
  min_w=math.max(min_w,2*transport_w+cell_palette_width()-LEFT_W-ALL_W+52)
  r.ImGui_SetNextWindowSizeConstraints(ctx,min_w,300,100000,100000)
  r.ImGui_SetNextWindowSize(ctx,math.max(1300,min_w),480,r.ImGui_Cond_FirstUseEver())
  r.ImGui_SetNextWindowBgAlpha(ctx,1)
  local focus=r.GetExtState("N2N_EDITOR_WINDOWS","n2nmix:focus")
  if focus~="" then
    r.DeleteExtState("N2N_EDITOR_WINDOWS","n2nmix:focus",false)
    r.ImGui_SetNextWindowFocus(ctx)
    ui.raise_window("N2N Mix")
  end
  local visible,open=r.ImGui_Begin(ctx,"N2N Mix",true)
  if visible then
    local wx,wy=r.ImGui_GetWindowPos(ctx)
    local ww,wh=r.ImGui_GetWindowSize(ctx)
    alert_x,alert_y=wx+ww/2,wy+wh/2
    local nmono=mono_push(true)
    r.ImGui_PushStyleVar(ctx,r.ImGui_StyleVar_FrameRounding(),5)
    r.ImGui_PushStyleColor(ctx,r.ImGui_Col_Button(),0xDADADAFF)
    if not job then
      if pending_start then r.ImGui_Button(ctx,"Preparing...") else
        ui.target_x,ui.target_y=r.ImGui_GetCursorScreenPos(ctx)
        button("Auto Mix",show_target_popup)
      end
    else button("Cancel",function() finish("Cancelled. Undo to revert partial changes.") end) end
    r.ImGui_PopStyleVar(ctx)
    r.ImGui_PopStyleColor(ctx,nmono+1)
    if not job then
      same()
      local n=mono_push(true)
      r.ImGui_PushStyleVar(ctx,r.ImGui_StyleVar_FrameRounding(),5)
      if r.ImGui_Button(ctx,show_parameters and "Hide Envelope Lanes" or "Show Envelope Lanes",155,0) then set_parameters_visible() end
      r.ImGui_PopStyleVar(ctx)
      r.ImGui_PopStyleColor(ctx,n)
    end
    same();r.ImGui_TextWrapped(ctx,status)
    if job then
      local d,n=poll()
      r.ImGui_ProgressBar(ctx,n>0 and d/n or 0,-1,0,n>0 and string.format("Stage %d/%d | %d/%d reports",job.index,#job.queue,d,n) or string.format("Stage %d/%d | Native render statistics",job.index,#job.queue))
    else
      local section_w,palette_w=section_tool_width()
      local start_x=r.ImGui_GetCursorPosX(ctx)
      local avail=r.ImGui_GetContentRegionAvail(ctx)
      -- Mode buttons occupy the fixed left portion; future modes can sit beside Levels.
      local mc=mono_push(true)
      r.ImGui_PushStyleVar(ctx,r.ImGui_StyleVar_FrameRounding(),4)
      local function mode_button(label,mode,w)
        local selected=edit_mode==mode
        if selected then r.ImGui_PushStyleColor(ctx,r.ImGui_Col_Button(),0xD3B86DFF) end
        if r.ImGui_Button(ctx,label.."##editmode",w,CELL_H) then edit_mode=mode;transition_start=nil;ui.pan_start=nil end
        if selected then r.ImGui_PopStyleColor(ctx) end
      end
      mode_button("Levels","levels",84)
      same();mode_button("Pan","pan",84)
      same();mode_button("Target Luffs","targets",104)

      r.ImGui_PopStyleVar(ctx)
      r.ImGui_PopStyleColor(ctx,mc)
      if edit_mode=="pan" then
        local legend="Position (%)   |   L100           C           R100"
        r.ImGui_SameLine(ctx,song_palette_x(start_x,avail,r.ImGui_CalcTextSize(ctx,legend)))
        r.ImGui_AlignTextToFramePadding(ctx);r.ImGui_Text(ctx,legend)
      elseif edit_mode=="targets" then
        local legend="Target LUFS  |  M: measured section LUFS  |  G: base gain correction (dB)"
        r.ImGui_SameLine(ctx,song_palette_x(start_x,avail,r.ImGui_CalcTextSize(ctx,legend)))
        r.ImGui_AlignTextToFramePadding(ctx);r.ImGui_Text(ctx,legend)
      else
      r.ImGui_SameLine(ctx,song_palette_x(start_x,avail,palette_w))
      for i,k in ipairs(intensity_ids) do
        if i>1 then same() end
        local dl=r.ImGui_GetWindowDrawList(ctx)
        local x,y=r.ImGui_GetCursorScreenPos(ctx)
        local clicked=r.ImGui_InvisibleButton(ctx,"##paintint"..k,section_w,CELL_H)
        local hover=r.ImGui_IsItemHovered(ctx)
        local f0=k==5 and 0 or section_fill[k]
        local f1=k==5 and 1 or f0
        draw_section_tile(dl,x,y,section_w,CELL_H,f0,f1,intens_names[k],k==intensity_tool,hover)
        if clicked then intensity_tool=k end
      end
      end
    end
    r.ImGui_Separator(ctx)
    if #sections>0 then
      local cols,total={},0
      for j,s in ipairs(sections) do
        if expanded[s.key] then
          for b=1,#s.bars do
            local w=b==1 and math.max(92,r.ImGui_CalcTextSize(ctx,s.name)+24) or 70
            cols[#cols+1]={j=j,b=b,w=w};total=total+w+GAP
          end
        else
          local w=math.max(94,r.ImGui_CalcTextSize(ctx,s.name)+24)
          cols[#cols+1]={j=j,w=w};total=total+w+GAP
        end
      end
      display_cols=cols
      local flags=r.ImGui_TableFlags_ScrollX() | r.ImGui_TableFlags_ScrollY() | r.ImGui_TableFlags_SizingFixedFit()
      -- Freeze both the track information and whole-row control. The song
      -- strip remains one scrollable column to avoid ImGui's column limit.
      local role_open,timbre_open=ui.role,ui.timbre
      if r.ImGui_BeginTable(ctx,"##mixgrid_v2",3,flags,0,job and 0 or -(CELL_H+29),LEFT_W+ALL_W+total+38) then
        r.ImGui_TableSetupColumn(ctx,"Track",r.ImGui_TableColumnFlags_WidthFixed(),LEFT_W)
        r.ImGui_TableSetupColumn(ctx,"All",r.ImGui_TableColumnFlags_WidthFixed(),ALL_W)
        r.ImGui_TableSetupColumn(ctx,"Song",r.ImGui_TableColumnFlags_WidthFixed(),total+8)
        r.ImGui_TableSetupScrollFreeze(ctx,2,2)
        local function across(fn)
          for i,c in ipairs(cols) do
            if i>1 then r.ImGui_SameLine(ctx,0,GAP) end
            fn(c,i)
          end
        end
        r.ImGui_TableNextRow(ctx,0,CELL_H)
        r.ImGui_TableSetColumnIndex(ctx,0)
        local dl=r.ImGui_GetWindowDrawList(ctx)
        local hx,hy=r.ImGui_GetCursorScreenPos(ctx)
        r.ImGui_Dummy(ctx,236,CELL_H)
        r.ImGui_DrawList_AddText(dl,hx+5,hy+(CELL_H-UI_SIZE)/2,r.ImGui_GetStyleColor(ctx,r.ImGui_Col_Text()),"Track")
        r.ImGui_PushStyleColor(ctx,r.ImGui_Col_Button(),0x303030FF)
        r.ImGui_PushStyleColor(ctx,r.ImGui_Col_ButtonHovered(),0x505050FF)
        r.ImGui_PushStyleColor(ctx,r.ImGui_Col_ButtonActive(),0x707070FF)
        r.ImGui_PushStyleColor(ctx,r.ImGui_Col_Text(),0xD0D0D0FF)
        r.ImGui_SameLine(ctx,0,GAP)
        if r.ImGui_Button(ctx,role_open and "Role −" or "R+##role",role_open and 150 or 32,CELL_H) then ui.role=not role_open;put("show_role",ui.role and 1 or 0) end
        r.ImGui_SameLine(ctx,0,GAP)
        if r.ImGui_Button(ctx,timbre_open and "Timbre −" or "T+##timbre",timbre_open and 150 or 32,CELL_H) then ui.timbre=not timbre_open;put("show_timbre",ui.timbre and 1 or 0) end
        r.ImGui_PopStyleColor(ctx,4)
        r.ImGui_TableSetColumnIndex(ctx,1)
        do
          local dl=r.ImGui_GetWindowDrawList(ctx)
          local x,y=r.ImGui_GetCursorScreenPos(ctx)
          r.ImGui_Dummy(ctx,ALL_W,CELL_H)
          centered(dl,x,y,ALL_W,CELL_H,edit_mode=="targets" and not job and "Base LUFS" or "All",r.ImGui_GetStyleColor(ctx,r.ImGui_Col_Text()))
        end
        r.ImGui_TableSetColumnIndex(ctx,2);across(color_header)
        r.ImGui_TableNextRow(ctx,0,CELL_H)
        local targets=edit_mode=="targets" and not job
        local pan_mode=edit_mode=="pan" and not job
        r.ImGui_TableSetColumnIndex(ctx,0);r.ImGui_AlignTextToFramePadding(ctx);r.ImGui_Text(ctx,targets and "Section offset (dB)" or pan_mode and "Position (L / R)" or "Section intensity")
        local contour=intensity_contour()
        local bus_offsets={}
        if targets then for j,s in ipairs(sections) do bus_offsets[j]=section_intensity(s,j) end end
        r.ImGui_TableSetColumnIndex(ctx,1)
        if targets or pan_mode then r.ImGui_Dummy(ctx,ALL_W,CELL_H) else all_intensity_cell() end
        r.ImGui_TableSetColumnIndex(ctx,2)
        if targets then across(function(c) target_section_cell(c,contour) end)
        elseif pan_mode then across(function(c) r.ImGui_Dummy(ctx,c.w,CELL_H) end)
        else across(function(c,ci) intensity_cell(c,contour,ci) end) end
        for ri,t in ipairs(rows) do
          r.ImGui_TableNextRow(ctx,0,targets and TARGET_H or CELL_H)
          r.ImGui_TableSetColumnIndex(ctx,0)
          track_header(t)
          ui.track_switch(t,"S","I_SOLO");ui.track_switch(t,"A","I_RECARM");ui.track_switch(t,"M","B_MUTE")
          r.ImGui_SameLine(ctx,0,GAP)
          if role_open then
          local role_colors=mono_push(true)
          r.ImGui_SetNextItemWidth(ctx,150)
          if r.ImGui_BeginCombo(ctx,"##role"..t.key,roles[t.role]) then
            for i,name in ipairs(roles) do
              if r.ImGui_Selectable(ctx,name,i==t.role) and not job then
                local old=t.target;t.role=i;t.target=defaults[i];put("role:"..t.key,i);put("target:"..t.key,t.target)
                t.timbre_allowed=i~=10 and i~=12
                for j,base in pairs(t.base) do t.base[j]=clamp(base+t.target-old,-30,24);put("base:"..t.key..":"..sections[j].key,t.base[j]) end
                dirty[t]=true
              end
            end
            r.ImGui_EndCombo(ctx)
          end
          r.ImGui_PopStyleColor(ctx,role_colors)
          else r.ImGui_Dummy(ctx,32,CELL_H) end
          r.ImGui_SameLine(ctx,0,GAP)
          if timbre_open then
          local tint=mono_push(true)
          r.ImGui_SetNextItemWidth(ctx,150)
          if r.ImGui_BeginCombo(ctx,"##timbre"..t.key,timbres[t.model+2] or "None") then
            for k,name in ipairs(timbres) do
              if r.ImGui_Selectable(ctx,name,t.model==k-2) and not job then
                if not stopped() then status="Stop playback before changing timbre."
                elseif k>1 and not t.timbre_allowed then status="Timbre processing is for source tracks, not busses or effects."
                else
                  t.model=k-2
                  local saved=r.GetSetMediaTrackInfo_String(t.track,"P_EXT:N2N_PERF_MODEL",tostring(t.model),true)
                  if saved then
                    dirty[t]=true;status=t.name..": "..name..". Run Auto Mix to recalibrate loudness."
                  else
                    status="Could not save timbre for "..t.name
                  end
                end
              end
            end
            r.ImGui_EndCombo(ctx)
          end
          r.ImGui_PopStyleColor(ctx,tint)
          else r.ImGui_Dummy(ctx,32,CELL_H) end
          r.ImGui_TableSetColumnIndex(ctx,1)
          if targets then
            r.ImGui_SetNextItemWidth(ctx,ALL_W)
            local tc=mono_push(false)
            local ch,v=r.ImGui_InputDouble(ctx,"##target"..t.key,t.target,0,0,"%.1f")
            r.ImGui_PopStyleColor(ctx,tc)
            if ch then
              local old=t.target;t.target=clamp(v,-60,-8);put("target:"..t.key,t.target)
              for j,base in pairs(t.base) do t.base[j]=clamp(base+t.target-old,-30,24);put("base:"..t.key..":"..sections[j].key,t.base[j]) end
              dirty[t]=true
            end
            r.ImGui_TableSetColumnIndex(ctx,2)
            local plan=make_perf_plan(t)
            across(function(c) target_cell(t,c.j,c.b,c.w,plan,t.depth>0 and bus_offsets[c.j] or 0) end)
          elseif pan_mode then
            local _,map=ui.pan_contour(t)
            pan_cell(t,nil,nil,ALL_W,map)
            r.ImGui_TableSetColumnIndex(ctx,2)
            across(function(c) pan_cell(t,c.j,c.b,c.w,map) end)
          else
            row_level_cell(t)
            r.ImGui_TableSetColumnIndex(ctx,2)
            local fills=transition_fills(t)
            across(function(c,ci) cell(t,c.j,c.b,c.w,fills,ri,ci) end)
          end
        end
        r.ImGui_EndTable(ctx)
      end
    end
    if not job then
      r.ImGui_Separator(ctx)
      -- Space above the transport for the same floating shortcut labels
      -- as Numbers2Notes. All three footer groups share one horizontal row.
      r.ImGui_Dummy(ctx,0,13)
      local x=r.ImGui_GetCursorPosX(ctx);local avail=r.ImGui_GetContentRegionAvail(ctx)
      transport()
      if edit_mode=="levels" then
        r.ImGui_SameLine(ctx,song_palette_x(x,avail,cell_palette_width()))
        draw_cell_palette()
        r.ImGui_SameLine(ctx,x+avail-notation_width())
        radio("Simple",false);same();radio("Traditional",true)
      elseif edit_mode=="pan" then
        r.ImGui_SameLine(ctx,song_palette_x(x,avail,180))
        local n=mono_push(true)
        r.ImGui_PushStyleColor(ctx,r.ImGui_Col_Button(),not ui.pan_transition and 0xD3B86DFF or 0xC4C4C4FF)
        if r.ImGui_Button(ctx,"Position",86,CELL_H) then ui.pan_transition=false;ui.pan_start=nil end
        r.ImGui_PopStyleColor(ctx);same()
        r.ImGui_PushStyleColor(ctx,r.ImGui_Col_Button(),ui.pan_transition and 0xD3B86DFF or 0xC4C4C4FF)
        if r.ImGui_Button(ctx,"Transition",90,CELL_H) then ui.pan_transition=true;ui.pan_start=nil end
        r.ImGui_PopStyleColor(ctx);r.ImGui_PopStyleColor(ctx,n)
      end
    end
    r.ImGui_End(ctx)
  end
  if target_popup then ui.section_hover=nil;master_options() else ui.section_play_strip() end
  alert_window()
  if ui_font then r.ImGui_PopFont(ctx) end
  r.ImGui_PopStyleColor(ctx,5);r.ImGui_PopStyleVar(ctx,4)
  if not r.ImGui_IsMouseDown(ctx,0) then
    if stroke and stroke.kind=="level" and stroke.tool==9 and not job then
      local s=stroke
      if s.endj and (s.j~=s.endj or s.b~=s.endb) then
        transition_start={t=s.t,j=s.j,b=s.b};edit_cell(s.t,s.endj,s.endb,9)
      else edit_cell(s.t,s.j,s.b,9) end
    end
    if ui.pan_stroke and not job then
      local s=ui.pan_stroke
      if s.endj and (s.j~=s.endj or s.b~=s.endb) then
        ui.paint_pan_transition(s.t,s.j,s.b,s.endj,s.endb)
      elseif ui.pan_start and ui.pan_start.t==s.t then
        ui.paint_pan_transition(s.t,ui.pan_start.j,ui.pan_start.b,s.j,s.b)
      else
        ui.pan_start={t=s.t,j=s.j,b=s.b};status="Select pan transition end on the same track."
      end
    end
    ui.pan_stroke=nil;stroke=nil;pan_drag=nil;last_paint=nil;apply_dirty()
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
last_preset=clamp(math.floor(num("preset",DEFAULT_PRESET)),1,#presets)
last_custom=clamp(num("custom",-16),-35,-8)
preset,custom=last_preset,last_custom
show_parameters=num("show_parameters",0)==1
ui.role=num("show_role",1)==1;ui.timbre=num("show_timbre",1)==1
traditional=num("traditional",0)==1
refresh()
local function loop()
  if r.EnumProjects(-1,"")~=proj then if job then fail("Project changed") end;return end
  r.SetExtState("N2N_EDITOR_WINDOWS","n2nmix:heartbeat",tostring(r.time_precise()),false)
  if not job and not stroke and not transition_start and not ui.pan_start and not ui.pan_stroke and not next(dirty) and not next(pan_dirty) and not master_dirty and r.time_precise()>=refresh_at and stopped() then
    refresh_at=r.time_precise()+0.75
    if project_layout_signature()~=layout_sig then refresh() end
  end
  if pending_start then
    local policy=pending_start;pending_start=nil;alert_text="";alert_until=0
    ui.start_rejected=false
    local ok,e=pcall(start,policy)
    if not ok then if job then fail(e) else status=tostring(e) end end
    if job then
      alert_text="Processing please wait.";alert_until=r.time_precise()+1.2
      job.ready_at=alert_until
      ui.start_rejected=false
    else
      ui.start_rejected=true
      pan_scan_pending=false -- do not overwrite a preflight failure
      local msg=status
      r.ShowConsoleMsg("N2N Mix Auto Mix start blocked: "..msg.."\n")
      r.MB(msg,"Auto Mix could not start",0)
    end
  end
  if job then
    local ok,e=pcall(step)
    if not ok then
      local msg=tostring(e)
      fail(e)
      ui.start_rejected=true;pan_scan_pending=false
      r.ShowConsoleMsg("N2N Mix Auto Mix failed: "..msg.."\n")
      r.MB(msg,"Auto Mix stopped",0)
    end
  else install_visible_position() end
  local ok,open=pcall(draw)
  if not ok then if job then fail(open) end;r.ShowConsoleMsg("N2N Mix GUI error: "..tostring(open).."\n");return end
  if open then r.defer(loop) elseif job then finish("Closed. Undo to revert partial changes.") end
end
r.atexit(function()
  r.DeleteExtState("N2N_EDITOR_WINDOWS","n2nmix:heartbeat",false)
  r.DeleteExtState("N2N_EDITOR_WINDOWS","n2nmix:focus",false)
  if job then finish("Closed. Undo to revert partial changes.") end
end)
loop()
