local Shell=require('__computer_core_2__.scripts.shell.runtime')
local Scheduler=require('__computer_core_2__.scripts.shell.scheduler')
local Budget=require('__computer_core_2__.scripts.shell.budget')
local Parser=require('__computer_core_2__.scripts.shell.parser')
local new=require('construct')
local M={}
local function packed(s) return serpent.line(s,{sortkeys=true}) end
local function driver(s,ledger,tick)
  local d={tick=tick or 0}
  function d.step() d.tick=d.tick+1; assert(Scheduler.step(s,ledger,1,d.tick,true)); assert(s.status=='ready',s.recovery and s.recovery.message) end
  function d.send(e) d.tick=d.tick+1; assert(Scheduler.push(s,ledger,1,d.tick,e)); assert(Scheduler.step(s,ledger,1,d.tick,true)); assert(s.status=='ready',s.recovery and s.recovery.message) end
  function d.drain() local steps=0; while s.job do d.step(); steps=steps+1; assert(steps<20000) end end
  function d.line(text) for i=1,#text do d.send({n=2,'char',text:sub(i,i)}) end end
  function d.command(text) d.send({n=2,'paste',text}); d.send({n=2,'key',257}) end
  return d
end
function M.initial(check)
  local long=string.rep('x',1023)
  local escaped=string.rep('"',1023)
  local disk={fs={['/']={type='dir'},['/a']={type='file',text='A'},['/b']={type='file',text='B'},
    ['/space dir']={type='dir'},['/space dir/hello.lua']={type='file',text='return _G.no_execution()'},
    ['/'..long]={type='file',text='long-data'},['/'..escaped]={type='file',text='escaped-data'}}}
  local s,ledger=new(disk,51,19),{version=1}; assert(Scheduler.step(s,ledger,1,0,true))
  local d=driver(s,ledger)
  d.line('cl'); d.send({n=2,'key',258}); d.drain()
  check('real Tab changes command buffer then executes builtin',s.command=='clear' and s.cursor==5)
  d.send({n=2,'key',257}); check('completed clear actually runs',s.job==nil and s.display.blink)
  d.line('cat "space dir/he'); d.send({n=2,'key',258}); d.drain()
  check('real quoted file Tab completes literal argument',s.command=='cat "space dir/hello.lua"')
  d.send({n=2,'key',257}); check('completed Lua filename reads only data',s.job.kind=='cat' and s.job.text=='return _G.no_execution()'); d.drain()
  d.line('cat '); d.send({n=2,'key',258})
  while s.job.phase~='output' do d.step() end
  local items=s.job.items
  check('empty-prefix completion includes sorted local and read-only candidates',#items==6 and items[2].name=='a'
    and items[3].name=='b' and items[4].name=='rom/' and items[5].name=='space dir/')
  d.drain(); check('ambiguous completion preserves original editable line',s.command=='cat ' and s.cursor==4)
  d.send({n=1,'terminate'})
  d.line('clear suffix'); for _=1,10 do d.send({n=2,'key',263}) end
  d.send({n=2,'key',258}); d.drain()
  check('runtime completion preserves mid-token suffix',s.command=='clear suffix' and s.cursor==2)
  d.send({n=1,'terminate'}); d.line('ab'); d.send({n=2,'key',263}); d.send({n=2,'paste','X\r\nY\nZ\rQ'})
  check('multiline paste inserts data once at saved cursor',s.command=='aX Y Z Qb' and s.cursor==8 and s.job==nil)
  local before=packed(s)
  check('oversized paste ingress refuses atomically',not Scheduler.push(s,ledger,1,d.tick,{n=2,'paste',string.rep('z',Shell.command_bytes+1)}) and packed(s)==before)
  d.send({n=3,'term_resize',31,6})
  check('resize paints retained input without another character',s.display.columns==31 and s.display.rows==6
    and s.command=='aX Y Z Qb' and s.cursor==8 and s.display.lines[6].text:find('aX Y Z Qb',1,true))
  d.send({n=1,'terminate'}); d.command('cat '..long)
  check('maximum ordinary path is addressable by actual cat',s.job.kind=='cat' and s.job.text=='long-data'); d.drain()
  d.command('cat '..Parser.quote(escaped))
  check('maximum quote-escaped path is addressable by actual cat',s.job.kind=='cat' and s.job.text=='escaped-data'); d.drain()
  local two=assert(Parser.arguments(Parser.quote(escaped)..' '..Parser.quote(escaped),2))
  check('maximum two-path literal line fits without dropping filesystem quota',two[1]==escaped and two[2]==escaped
    and #('cp '..Parser.quote(escaped)..' '..Parser.quote(escaped))<=Shell.command_bytes)
  for i=1,5 do d.command(tostring(i)..string.rep('z',Shell.command_bytes-1)); d.drain() end
  local bytes=0; for _,line in ipairs(s.history) do bytes=bytes+#line end
  check('history byte bound evicts oldest full-size lines',#s.history==4 and bytes==Shell.history_bytes and s.history[1]:sub(1,1)=='2')
  for i=1,35 do d.command('pwd'); d.drain() end
  bytes=0; for _,line in ipairs(s.history) do bytes=bytes+#line end
  check('history entry bound keeps latest short lines',#s.history==Shell.history_count and bytes<=Shell.history_bytes and s.history[1]=='pwd')
  d.line('draft'); d.send({n=2,'key',263}); d.send({n=2,'key',265}); d.send({n=2,'key',264})
  check('history returns saved draft cursor',s.command=='draft' and s.cursor==4)
  d.send({n=1,'terminate'}); d.command('cd /rom'); check('read-only directory navigation is confined',s.disk.cwd=='/rom')
  d.command('cat help.txt'); check('read-only data resources have actual cat support',s.job.kind=='cat' and s.job.text:find('trusted built-in',1,true)); d.drain()
  d.command('ls /'); while s.job.phase~='output' do d.step() end
  local listed=s.job.items
  check('real ls orders complete literal children',#listed==6 and listed[4].name=='rom/' and listed[5].name=='space dir/')
  d.drain(); d.command('ls missing'); check('invalid ls yields error and preserves cwd',s.job.kind=='output' and s.disk.cwd=='/rom'); d.drain()
  d.command('cat help.txt | require x'); check('excluded operator syntax never selects a module',s.job.kind=='output' and s.job.text:find('unsupported shell syntax',1,true)); d.drain()
  d.command('cd /'); d.line('cat "space dir/he'); d.send({n=2,'key',258}); d.step()
  local job=s.job; assert(job and job.phase=='scan')
  Budget.begin(ledger,d.tick); assert(Budget.admit(ledger,1,{execution=Budget.remaining(ledger,1,'execution')}))
  return {shell=s,ledger=ledger,job=job,paths=job.paths,items=job.items,tick=d.tick,before=packed(s),budget=packed(ledger)}
end
function M.reload(saved,check)
  local s=saved.shell
  check('cold completion retains exact job input aliases and spent counters',packed(s)==saved.before and packed(saved.ledger)==saved.budget
    and s.job==saved.job and s.job.paths==saved.paths and s.job.items==saved.items)
  local before=packed(s)
  check('cold completion cannot renew same-tick credits',not Scheduler.step(s,saved.ledger,1,saved.tick,true) and packed(s)==before)
  local d=driver(s,saved.ledger,saved.tick); d.drain()
  check('cold completion changes original line exactly once',s.command=='cat "space dir/hello.lua"' and s.cursor==#s.command and s.display.blink)
  d.send({n=2,'key',257}); check('cold accepted completion really reads file',s.job.kind=='cat' and s.job.text=='return _G.no_execution()'); d.drain()
end
return M
