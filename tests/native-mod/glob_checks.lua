local Compiler=require('__computer_core_2__.scripts.native.compiler')
local Execution=require('__computer_core_2__.scripts.native.execution')
local Helpers=require('__computer_core_2__.scripts.native.helpers')
local Events=require('__computer_core_2__.scripts.native.events')
local Scheduler=require('__computer_core_2__.scripts.native.scheduler')
local Collector=require('__computer_core_2__.scripts.native.collector')
local FS=require('__computer_core_2__.scripts.native.filesystem')
local Glob=require('__computer_core_2__.scripts.native.glob')
local Model=require('__computer_core_2__.scripts.filesystem')
local Limits=require('__computer_core_2__.scripts.guest.limits')
local function disk()
 return {fs={['/']={type='dir'},['/tree']={type='dir'},['/tree/ab.lua']={type='file',text='b'},
  ['/tree/abc.lua']={type='file',text='c'},['/tree/axxb.lua']={type='file',text='x'},
  ['/tree/file[1].txt']={type='file',text='literal'},['/tree/deep']={type='dir'},
  ['/tree/deep/ab.lua']={type='file',text='nested'}}}
end
local function create(source,input)
 local m=Execution.new(assert(Compiler.compile(source,'=native-glob')))
 Execution.install_core(m); Helpers.install(m); Events.install_services(m); FS.install(m,input or disk())
 local s=Scheduler.new(); Scheduler.add(s,1,m); return s,m
end
local function finish(s,tick)
 local m=s.machines[1]
 for offset=0,100 do
  Scheduler.tick(s,tick+offset)
  if m.status=='return' or m.status=='error' or m.status=='yield' then return m end
 end
 error('native glob fixture deadline')
end
local function snapshot(m) return serpent.line(m.disk.fs,{sortkeys=true}) end
-- Independent DP oracle, used only by a labelled host-side finite property test.
local function reference(pattern,name)
 local previous={[0]=true}
 for i=1,#pattern do
  local token=pattern:sub(i,i); local row={[0]=token=='*' and previous[0] or false}
  for j=1,#name do
   if token=='*' then row[j]=previous[j] or row[j-1]
   else row[j]=previous[j-1] and (token=='?' or token==name:sub(j,j)) end
  end
  previous=row
 end
 return previous[#name] or false
end
local function words(alphabet,depth)
 local all,current={}, {''}
 for _=1,depth do
  local next_words={}
  for _,prefix in ipairs(current) do for _,letter in ipairs(alphabet) do
   local value=prefix..letter; next_words[#next_words+1]=value; all[#all+1]=value
  end end
  current=next_words
 end
 return all
end
return {
run=function(check)
 local s,m=create([[
local many=fs.find('/tree/a*.lua')
local one=fs.find('tree/a?.lua')
local literal=fs.find('/tree/file[1].txt')
local nested=fs.find('/tree/*/*.lua')
local no=fs.find('/tree/missing*')
local rom=fs.find('/rc/programs/shell.lua')
local peer=fs.find('/mnt/*')
local hidden=fs.find('/bios.lua')
return #many,many[1],many[2],many[3],#one,one[1],literal[1],#nested,nested[1],#no,rom[1],#peer,#hidden,
 #fs.find('/tree/a**b.lua')
]])
 finish(s,20)
 check('native compiled glob handles exact paths star question segments literal metacharacters and ROM without peer or BIOS access',
  m.status=='return' and m.result.n==14 and m.result[1]==3 and m.result[2]=='/tree/ab.lua'
  and m.result[3]=='/tree/abc.lua' and m.result[4]=='/tree/axxb.lua' and m.result[5]==1
  and m.result[6]=='/tree/ab.lua' and m.result[7]=='/tree/file[1].txt' and m.result[8]==1
  and m.result[9]=='/tree/deep/ab.lua' and m.result[10]==0 and m.result[11]=='/rc/programs/shell.lua'
  and m.result[12]==0 and m.result[13]==0 and m.result[14]==2)
 local names=words({'a','b'},3); table.sort(names)
 local input={fs={['/']={type='dir'},['/set']={type='dir'}}}
 for _,name in ipairs(names) do input.fs['/set/'..name]={type='file',text=''} end
 _,m=create('return 1',input)
 local count=0
 for _,pattern in ipairs(words({'a','b','*','?'},4)) do
  local expected={}
  for _,name in ipairs(names) do if reference(pattern,name) then expected[#expected+1]='/set/'..name end end
  local actual=Glob.find(m,'/set/'..pattern,function() end)
  assert(table.concat(actual,'|')==table.concat(expected,'|'),'glob DP mismatch: '..pattern)
  count=count+#names
 end
 check('native finite host-side glob matcher property agrees with independent DP oracle across '..count..' name-pattern pairs',count>0)
 _,m=create('return 1'); local before=snapshot(m); local objects=m.objects
 local measured=0
 FS.services(function(amount) measured=measured+amount end)['fs.find'](m,{n=1,'/tree/a*.lua'})
 _,m=create('return 1'); objects=m.objects
 local used=0
 local ok=pcall(FS.services(function(amount) used=used+amount; return used<measured end)['fs.find'],m,{n=1,'/tree/a*.lua'})
 check('native glob final admission refuses before guest result allocation with unchanged disk',not ok
  and m.objects==objects and snapshot(m)==before)
 check('native glob zero-credit and malformed NUL inputs refuse without disk mutation',not pcall(
  FS.services(function() return false end)['fs.find'],m,{n=1,'/tree/*'})
  and not pcall(Glob.find,m,'bad\0path',function() end) and snapshot(m)==before)
 local maximum={fs={['/']={type='dir'}}}
 for i=1,Model.max_nodes-1 do maximum.fs[string.format('/f%04d',i)]={type='file',text=''} end
 s,m=create("local names=fs.find('/f*'); return #names,names[1],names[#names]",maximum)
 finish(s,100)
 check('native maximum local glob inventory produces sorted defensive result inside unchanged filesystem credits',
  m.status=='return' and m.result[1]==Model.max_nodes-1 and m.result[2]=='/f0001'
  and m.result[3]==string.format('/f%04d',Model.max_nodes-1)
  and s.budget.used.filesystem<=Limits.filesystem_work_per_computer)
 local long={fs={['/']={type='dir'},['/'..string.rep('x',1023)]={type='file',text=''}}}
 _,m=create('return 1',long); before=snapshot(m); local charged=0
 ok=pcall(Glob.find,m,'/'..string.rep('?',1023),function(amount)
  assert(charged+amount<=Limits.filesystem_work_per_computer,'fixture filesystem credit refused'); charged=charged+amount
 end)
 check('native maximum-width opaque matching refuses reserved quadratic work before execution or publication',
  not ok and snapshot(m)==before and charged<=Limits.filesystem_work_per_computer)
end,
suspend=function(check)
 local s,m=create([[
local find,protect=fs.find,pcall
local old=find('/tree/a*.lua')
fs=nil; coroutine.yield('glob-ready')
local ok=protect(find,'/tree/*'); coroutine.yield('glob-refused',ok)
local fresh=find('/tree/a?.lua'); return #fresh,fresh[1],old[1],old[2],old[3],nil
]])
 finish(s,500)
 Scheduler.begin_tick(s,501); assert(Scheduler.consume(s,1,'filesystem',Limits.filesystem_work_per_computer))
 assert(Events.admit(m,{n=1,'wake'})); Scheduler.tick(s,501)
 check('native glob suspension preserves captured service and old array through protected quota refusal',m.status=='yield'
  and m.yielded[1]=='glob-refused' and m.yielded[2]==false and Execution.get(m,m.env,'fs')==nil)
 Collector.start(m); while m.collector do Collector.step(m,32) end
 return s
end,
reload=function(s,check)
 local m=s.machines[1]; local blocks=m.blocks
 Scheduler.tick(s,501)
 check('native glob reload keeps same-tick filesystem exhaustion and suspended continuation',m.blocks==blocks
  and s.budget.machines[1].filesystem==Limits.filesystem_work_per_computer and m.status=='yield')
 assert(Events.admit(m,{n=1,'wake-later'})); finish(s,502)
 check('native glob captured service resumes cold after collected reload without lost result identities or replay',
  m.status=='return' and m.result.n==6 and m.result[1]==1 and m.result[2]=='/tree/ab.lua'
  and m.result[3]=='/tree/ab.lua' and m.result[4]=='/tree/abc.lua' and m.result[5]=='/tree/axxb.lua'
  and m.result[6]==nil and Execution.get(m,m.env,'fs')==nil)
end
}
