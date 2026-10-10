local Compiler = require('__computer_core_2__.scripts.native.compiler')
local Execution = require('__computer_core_2__.scripts.native.execution')
local Codegen = require('__computer_core_2__.scripts.native.codegen')
local source = 'local x=1; x=x+2; x=x+3; return x,nil'
local function finish(m,b,blocks,quantum)
 local turns=0
 repeat
  local before=m.blocks
  local status,spent=Execution.run(m,b,blocks,quantum)
  assert(status~='error',m.error and m.error.message)
  assert(spent<=quantum and m.blocks-before==spent)
  turns=turns+1
  assert(turns<1000,'coalesced checkpoint failed to progress')
 until m.status~='running'
 assert(m.status=='return' and m.result.n==2 and m.result[1]==6 and m.result[2]==nil)
end
return {
 run=function(check)
  local b=assert(Compiler.compile(source,'=native-layout'))
  local blocks=Execution.executable(b)
  local p=b.prototypes[1]
  check('native layout shares functions without losing logical labels',p.merged_groups>0 and p.functions<p.blocks and #blocks[1]==p.blocks)
  check('native coalesced bodies and checkpoint fanout retain caps',p.max_function_bytes<=Codegen.BLOCK_BYTES and p.max_group_steps<=Codegen.MERGE_STEPS and #b.generated<=Codegen.OUTPUT_BYTES)
  local small,large=Execution.new(b),Execution.new(b)
  finish(small,b,blocks,1)
  finish(large,b,blocks,97)
  check('native coalescing preserves exact logical costs across quantum sizes',small.blocks==large.blocks)
  local bad=assert(Compiler.compile('local x=1\nx=x+2\nprior=x\nreturn x+nil','=native-coalesced-location'))
  local m=Execution.new(bad)
  repeat Execution.run(m,bad,Execution.executable(bad),7) until m.status~='running'
  check('native merged failure keeps current source location and earlier effects',m.status=='error' and m.error.line==4 and Execution.get(m,m.env,'prior')==3)
  local literal='a.one(f.t[5]); a.upvalue(f,2); if s(1)then game.print(1) end'
  local inert=assert(Compiler.compile('return '..string.format('%q',literal),'=native-compact-literal'))
  m=Execution.new(inert)
  check('native compact ABI never rewrites guest literal contents',Execution.run(m,inert,Execution.executable(inert),100)=='return' and m.result[1]==literal)
 end,
 suspend=function(check)
  local b=assert(Compiler.compile(source,'=native-layout-reload'))
  local m=Execution.new(b)
  local blocks=Execution.executable(b)
  local found=false
  for _=1,100 do
   local f=m.frames[1]
   local previous=blocks[f.proto][f.pc]
   Execution.run(m,b,blocks,1)
   if m.status~='running' then break end
   f=m.frames[1]
   if blocks[f.proto][f.pc]==previous then found=true; break end
  end
  assert(found,'fixture did not reach an interior shared-function checkpoint')
  local pc,count=m.frames[1].pc,m.blocks
  local _,spent=Execution.run(m,b,blocks,0)
  check('native mid-shared-function zero credits preserve exact checkpoint',spent==0 and m.frames[1].pc==pc and m.blocks==count)
  return {machine=m,bundle=b,pc=pc,blocks=count}
 end,
 reload=function(state,check)
  local m=state.machine
  check('native saved interior coalesced label survives read-only load',m.status=='running' and m.frames[1].pc==state.pc and m.blocks==state.blocks)
  local code=Execution.executable(state.bundle)
  check('native shared-code reconstruction executes no application step',m.frames[1].pc==state.pc and m.blocks==state.blocks)
  finish(m,state.bundle,code,1)
  check('native interior shared function resumes once after separate process',m.result[1]==6 and m.result.n==2)
 end,
}
