local Compiler=require('__computer_core_2__.scripts.native.compiler')
local Execution=require('__computer_core_2__.scripts.native.execution')
local Helpers=require('__computer_core_2__.scripts.native.helpers')
local Scheduler=require('__computer_core_2__.scripts.native.scheduler')
local Collector=require('__computer_core_2__.scripts.native.collector')
local Events=require('__computer_core_2__.scripts.native.events')
local FS=require('__computer_core_2__.scripts.native.filesystem')
local Files=require('__computer_core_2__.scripts.guest.files')
local Model=require('__computer_core_2__.scripts.filesystem')
local Limits=require('__computer_core_2__.scripts.guest.limits')
local function disk()
 return {fs={['/']={type='dir'},['/seed']={type='dir'},['/seed/a']={type='file',text='leaf'},['/seed/b']={type='file',text='root'}}}
end
local function create(source,input)
 local m=Execution.new(assert(Compiler.compile(source,'=native-filesystem')))
 Execution.install_core(m); Helpers.install(m); Events.install_services(m); FS.install(m,input or disk())
 local s=Scheduler.new(); Scheduler.add(s,1,m); return s,m
end
local function finish(s,tick,terminal)
 local m=s.machines[1]
 for i=0,100 do
  Scheduler.tick(s,tick+i)
  if m.status=='return' or m.status=='error' or (m.status=='yield' and not terminal) then return m end
 end
 error('native filesystem fixture deadline exceeded')
end
local function snapshot(m) return serpent.line(FS.files(m),{sortkeys=true}) end
return {
 run=function(check)
  local s,m=create([[
fs.makeDir('/work/nested')
fs.copy('/seed','/work/copied')
fs.move('/work/copied','/moved')
local names=fs.list('/moved')
local exists,size=fs.exists('/moved/a'),fs.getSize('/moved/a')
fs.delete('/seed')
return names[1],names[2],#names,exists,size,fs.isDir('/work/nested'),fs.exists('/seed'),
 fs.combine('work','.','nested','..','leaf'),fs.getName(''),fs.getDir(''),fs.getName('/moved/a'),fs.getDir('/moved/a'),
 fs.isReadOnly('/rc'),fs.isReadOnly('/moved'),fs.getFreeSpace(),nil
]])
  finish(s,10)
  check('native compiled filesystem directory copy move list metadata and return arity',m.status=='return'
   and m.result.n==16 and m.result[1]=='a' and m.result[2]=='b' and m.result[3]==2 and m.result[4]
   and m.result[5]==4 and m.result[6] and not m.result[7] and m.result[8]=='work/leaf'
   and m.result[9]=='' and m.result[10]=='' and m.result[11]=='a' and m.result[12]=='moved'
   and m.result[13] and not m.result[14] and m.result[15]==Model.max_bytes-8)
  check('native authoritative tree follows replacements without boot alias',FS.files(m)==m.disk.fs
   and FS.files(m)['/moved/a'].text=='leaf' and FS.files(m)['/seed']==nil)
  local input=disk(); s,m=create('return fs.getSize("/seed/a")',input)
  input.fs['/seed/a'].text='edited'; finish(s,100)
  check('native disk import clones content without exposing host snapshot alias',m.result[1]==4 and FS.files(m)~=input.fs)
  local alias=m.disk; local count=m.objects; FS.install(m,disk())
  check('native filesystem install preserves authoritative disk and identities',m.disk==alias and m.objects==count)
  local cases={
   {'fs.makeDir',table.pack('/new/deep')},{'fs.delete',table.pack('/seed')},
   {'fs.copy',table.pack('/seed','/copy')},{'fs.move',table.pack('/seed','/move')},
  }
  for _,case in ipairs(cases) do
   s,m=create('return 1'); local before=snapshot(m)
   local services=FS.services(function() return false end)
   local ok=pcall(services[case[1]],m,case[2])
   check('native filesystem zero-credit mutation is atomic '..case[1],not ok and snapshot(m)==before)
   local _,reference=create('return 1')
   local needed=0
   local measuring=FS.services(function(amount) needed=needed+amount; return true end)
   measuring[case[1]](reference,case[2])
   local used=0; services=FS.services(function(amount) used=used+amount; return used<needed end)
   ok=pcall(services[case[1]],m,case[2])
   check('native filesystem partial admission preserves original tree '..case[1],not ok and snapshot(m)==before)
  end
  local malformed={
   {fs={['/']={type='file',text='bad'}}},
   {fs={['/']={type='dir'},['/bad/../token']={type='file',text='bad'}}},
   {fs={['/']={type='dir'},['/orphan/file']={type='file',text='bad'}}},
   {fs={['/']={type='dir'},['/bad']={type='file',text=function() end}}},
   {fs={['/']={type='dir'},['/nul\0']={type='dir'}}},
   {fs={['/']={type='dir'},['/large']={type='file',text=string.rep('x',Model.max_bytes+1)}}},
  }
  for i,input in ipairs(malformed) do
   local value=Execution.new(assert(Compiler.compile('return 1'))); local before=value.objects
   local ok=pcall(FS.install,value,input)
   check('native malformed snapshot refuses before filesystem publication '..i,not ok and value.disk==nil
    and not value.filesystem_installed and value.objects==before)
  end
  s,m=create([[
local root=pcall(fs.delete,'/')
local readonly=pcall(fs.makeDir,'/rc/new')
local nul=pcall(fs.exists,'bad\0path')
local escape=pcall(fs.copy,'/seed','/seed/inside')
return root,readonly,nul,escape,fs.exists('/mnt/peer'),fs.isDir('/rc'),fs.open==nil
]])
  finish(s,200)
  check('native filesystem protects root ROM NUL and recursive destination without peer mounts',m.status=='return'
   and not m.result[1] and not m.result[2] and not m.result[3] and not m.result[4] and not m.result[5]
   and m.result[6] and not m.result[7])
  local text=Files.read_source(m,'/rc/programs/shell.lua',function() end)
  check('native local ROM reader selects real shipped shell source without execution',type(text)=='string' and #text>0)
  s,m=create([[
local names=fs.list('/seed')
names[1]='changed'
local next_names=fs.list('/seed')
return next_names[1],fs.getSize('/seed/a'),fs.getName('/seed/a'),select('#',fs.getDir('/seed/a'))
]])
  finish(s,250)
  check('native directory result is defensive guest data and metadata keeps scalar arity',m.status=='return'
   and m.result[1]=='a' and m.result[2]==4 and m.result[3]=='a' and m.result[4]==1)
  local maximum={fs={['/']={type='dir'}}}
  for i=1,Model.max_nodes-1 do maximum.fs[string.format('/f%04d',i)]={type='file',text=''} end
  s,m=create("local names=fs.list('/'); return #names,names[1],names[#names]",maximum)
  finish(s,270)
  check('native maximum local node inventory lists deterministically inside unchanged credits',m.status=='return'
   and m.result[1]==Model.max_nodes and m.result[2]=='f0001' and m.result[3]=='rc'
   and s.budget.used.filesystem<=Limits.filesystem_work_per_computer)
  s,m=create("local ok=pcall(fs.makeDir,'/overflow'); return ok",maximum)
  local before=snapshot(m); finish(s,280)
  check('native full node quota refuses directory publication',m.status=='return' and m.result[1]==false and snapshot(m)==before)
  s,m=create("local ok=pcall(fs.makeDir,'/later'); return ok")
  Scheduler.begin_tick(s,300); assert(Scheduler.consume(s,1,'filesystem',Limits.filesystem_work_per_computer))
  before=snapshot(m); finish(s,300)
  check('native compiled filesystem refusal retains tick ledger and disk',m.status=='return' and m.result[1]==false
   and s.budget.used.filesystem==Limits.filesystem_work_per_computer and snapshot(m)==before)
  local _,neighbor=create('return 1'); Scheduler.add(s,2,neighbor)
  assert(Scheduler.consume(s,2,'filesystem',Limits.filesystem_work_per_computer))
  check('native filesystem aggregate ceiling shares original unchanged limits',s.budget.used.filesystem==Limits.filesystem_work_per_tick
   and not Scheduler.consume(s,2,'filesystem',1))
 end,
 suspend=function(check)
  local s,m=create([[
boot=(boot or 0)+1
fs.copy('/seed','/saved')
local move=fs.move
fs=nil
coroutine.yield('disk-ready')
move('/saved','/resumed')
return boot,nil
]])
  finish(s,game.tick); assert(m.status=='yield')
  assert(Scheduler.consume(s,1,'filesystem',Scheduler.remaining(s,1,'filesystem')))
  Collector.start(m)
  check('native filesystem save retains replaced disk tree with exhausted credits',FS.files(m)['/saved/a'].text=='leaf'
   and m.collector~=nil and m.yielded[1]=='disk-ready')
  return {scheduler=s,tick=s.budget.tick,tree=FS.files(m),before=snapshot(m),blocks=m.blocks}
 end,
 reload=function(state,check)
  local s,m=state.scheduler,state.scheduler.machines[1]
  check('native filesystem load preserves authoritative tree aliases and no guest effects',FS.files(m)==state.tree
   and snapshot(m)==state.before and m.blocks==state.blocks and Scheduler.remaining(s,1,'filesystem')==0)
  local services=FS.services(function(amount) return Scheduler.consume(s,1,'filesystem',amount) end)
  local ok=pcall(services['fs.delete'],m,table.pack('/saved'))
  check('native filesystem exhausted same-tick reload cannot change disk',not ok and snapshot(m)==state.before)
  assert(Events.admit(m,table.pack('char','resume')))
  finish(s,state.tick+1,true)
  check('native collected directory move resumes once through captured service after global removal',m.status=='return'
   and m.result.n==2 and m.result[1]==1 and FS.files(m)['/resumed/a'].text=='leaf' and FS.files(m)['/saved']==nil
   and FS.files(m)~=state.tree)
 end,
}
