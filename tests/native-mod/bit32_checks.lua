local Compiler=require('__computer_core_2__.scripts.native.compiler')
local Execution=require('__computer_core_2__.scripts.native.execution')
local Helpers=require('__computer_core_2__.scripts.native.helpers')
local Scheduler=require('__computer_core_2__.scripts.native.scheduler')
local Collector=require('__computer_core_2__.scripts.native.collector')
local Events=require('__computer_core_2__.scripts.native.events')
local FS=require('__computer_core_2__.scripts.native.filesystem')
local Terminal=require('__computer_core_2__.scripts.native.terminal')
local Limits=require('__computer_core_2__.scripts.guest.limits')
local function create(source)
 local m=Execution.new(assert(Compiler.compile(source,'=native-bit32')))
 Execution.install_core(m); Helpers.install(m); Events.install_services(m)
 FS.install(m); Terminal.install(m,7,3)
 local s=Scheduler.new(); Scheduler.add(s,1,m); return s,m
end
local function finish(s,tick,terminal)
 local m=s.machines[1]
 for i=0,150 do
  Scheduler.tick(s,tick+i)
  if m.status=='return' or m.status=='error' or (m.status=='yield' and not terminal) then return m end
 end
 error('native bit32 fixture deadline exceeded')
end
local source=[[
return bit32.arshift(0x80000000,1),bit32.band(0xf0f0,0x0ff0),bit32.bnot(0),bit32.bor(1,2,4),
 bit32.btest(4,12),bit32.bxor(0xff,0x0f),bit32.extract(0x1234,4,8),
 bit32.lrotate(0x80000001,1),bit32.lshift(1,31),bit32.replace(0xffff,0,4,8),
 bit32.rrotate(0x80000001,1),bit32.rshift(0x80000000,31),
 bit32.band(),bit32.bor(),bit32.bxor(),bit32.btest(),
 bit32.lshift(1,-1),bit32.lshift(1,32),bit32.arshift(0x80000000,32),
 bit32.lrotate(1,33),bit32.rrotate(1,-33),bit32.band(-1,0xffffffff),
 bit32.bor(4294967296,3),bit32.band(7.9,3.1),nil
]]
-- The resolver below exposes only authentic installed services or the actual
-- shipped cc.expect module. It is not a stub or the future OS package loader.
local colors=[[
local expect=assert(loadfile('/rc/modules/main/cc/expect.lua'))()
term.setPaletteColor(1,0)
term.setPaletteColor(2048,0)
local globals=_ENV
local environment=setmetatable({require=function(name)
 if name=='term' then return term end
 if name=='bit32' then return bit32 end
 if name=='cc.expect' then return expect end
 error('unsupported test dependency',0)
end},{__index=globals})
local colors=assert(loadfile('/rc/apis/colors.lua','t',environment))()
local combined=colors.combine(colors.white,colors.blue,colors.black)
local removed=colors.subtract(combined,colors.blue)
local rgb=colors.packRGB(1,0.5,0)
local r,g,b=colors.unpackRGB(0xff8000)
return combined,removed,colors.test(combined,colors.blue),rgb,r,g,b,colors.toBlit(colors.blue),
 colors.gray==colors.grey,colors.lightGray==colors.lightGrey,colors
]]
return {
 run=function(check)
  local s,m=create(source); finish(s,10)
  local expected=table.pack(assert(load(source,'=bit32-reference','t',{bit32=bit32}))())
  check('native every fixed-width bit helper preserves exact engine tuple arity',m.status=='return' and m.result.n==expected.n)
  for i=1,expected.n do check('native bit32 engine reference value '..i,m.result[i]==expected[i]) end
  s,m=create([[
return pcall(bit32.band,'1'),pcall(bit32.bor,{}),pcall(bit32.band,math.huge),
 pcall(bit32.band,0/0),pcall(bit32.extract,1,32),pcall(bit32.replace,1,1,0,33),
 pcall(bit32.bnot,nil)
]])
  finish(s,200)
  check('native bit helpers explicitly reject invalid operands and field ranges',m.status=='return'
   and m.result[1]==false and m.result[2]==false and m.result[3]==false and m.result[4]==false
   and m.result[5]==false and m.result[6]==false and m.result[7]==false)
  s,m=create('return 1'); Scheduler.begin_tick(s,300)
  local services=Helpers.services(function(domain,amount) return Scheduler.consume(s,1,domain,amount) end)
  local args={n=Limits.tuple_values}; for i=1,args.n do args[i]=i end
  local _,maximum=services['bit32.bor'](m,args)
  check('native maximum bitwise operand tuple fits unchanged admitted continuation credits',maximum[1]==bit32.bor(table.unpack(args,1,args.n))
   and s.budget.used.continuation==1+4*args.n)
  local before=s.budget.used.continuation
  local oversized={n=Limits.tuple_values+1}
  check('native oversized bitwise operand tuple refuses before native work or counters',not pcall(services['bit32.bor'],m,oversized)
   and s.budget.used.continuation==before)
  assert(Scheduler.consume(s,1,'continuation',Scheduler.remaining(s,1,'continuation')))
  local objects=m.objects
  check('native zero-credit bitwise helper cannot execute or publish identities',not pcall(services['bit32.bor'],m,table.pack(1,2))
   and m.objects==objects and s.budget.used.continuation==Limits.continuation_work_per_computer)
  s,m=create(colors); finish(s,400)
  check('native actual shipped colors and expect modules use bit services through guest source loading',m.status=='return'
   and m.result[1]==0x8801 and m.result[2]==0x8001 and m.result[3] and m.result[4]==0xff7f80
   and m.result[5]==1 and m.result[6]==128/255 and m.result[7]==0 and m.result[8]=='b'
   and m.result[9] and m.result[10])
  check('native actual colors module initializes real terminal palette',m.display.palette[1].r==240/255
   and m.display.palette[12].r==51/255)
 end,
 suspend=function(check)
  -- Compile a real application which loads the unchanged colors module and
  -- retains it across suspension after removing the original helper global.
  local body=colors:gsub('return combined,removed,colors.test%(combined,colors.blue%),rgb,r,g,b,colors.toBlit%(colors.blue%),',
   'bit32=nil; boot=(boot or 0)+1; coroutine.yield("bits-ready"); combined=colors.combine(colors.white,colors.blue,colors.black); return combined,removed,colors.test(combined,colors.blue),rgb,r,g,b,colors.toBlit(colors.blue),')
  local s,m=create(body); finish(s,game.tick); assert(m.status=='yield')
  assert(Scheduler.consume(s,1,'continuation',Scheduler.remaining(s,1,'continuation')))
  Collector.start(m)
  check('native colors suspension retains imported module despite removed bit32 global',Execution.get(m,m.env,'bit32')==nil)
  return {scheduler=s,tick=s.budget.tick,blocks=m.blocks,palette=m.display.palette}
 end,
 reload=function(state,check)
  local s,m=state.scheduler,state.scheduler.machines[1]
  check('native bit32 reload retains palette identity credits and no load effects',m.blocks==state.blocks
   and m.display.palette==state.palette and Scheduler.remaining(s,1,'continuation')==0)
  assert(Events.admit(m,table.pack('char','resume')))
  finish(s,state.tick+1,true)
  check('native collected imported colors module resumes with private bit library intact',m.status=='return'
   and m.result[1]==0x8801 and m.result[2]==0x8001 and m.result[3] and m.result[8]=='b'
   and Execution.get(m,m.env,'boot')==1)
 end,
}
