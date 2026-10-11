local Shell=require('__computer_core_2__.scripts.shell.runtime')
local Scheduler=require('__computer_core_2__.scripts.shell.scheduler')
local Budget=require('__computer_core_2__.scripts.shell.budget')
local Editor=require('__computer_core_2__.scripts.programs.editor')
local VM=require('__computer_core_2__.scripts.guest.vm')
local Compiler=require('__computer_core_2__.scripts.guest.compiler')
local Native=require('__computer_core_2__.scripts.native.dispatch')
local NativeCompiler=require('__computer_core_2__.scripts.native.compiler')
local new=require('construct')
local M={}
local function packed(value) return serpent.line(value,{sortkeys=true}) end
local function isolate(fn)
  local old={VM.run,Compiler.compile,Native.run,NativeCompiler.compile}
  local function forbidden() error('editor entered VM/continuation execution',0) end
  VM.run,Compiler.compile,Native.run,NativeCompiler.compile=forbidden,forbidden,forbidden,forbidden
  local ok,result=pcall(fn)
  VM.run,Compiler.compile,Native.run,NativeCompiler.compile=table.unpack(old)
  assert(ok,result); return result
end
local function driver(s,ledger,tick)
  local d={tick=tick or 0}
  function d.step()
    d.tick=d.tick+1; assert(Scheduler.step(s,ledger,1,d.tick,true))
    assert(s.status~='recovery',s.recovery and s.recovery.message)
  end
  function d.send(event)
    d.tick=d.tick+1; assert(Scheduler.push(s,ledger,1,d.tick,event)); assert(Scheduler.step(s,ledger,1,d.tick,true))
    assert(s.status~='recovery',s.recovery and s.recovery.message)
  end
  function d.key(code) d.send({n=2,'key',code}) end
  function d.paste(text) d.send({n=2,'paste',text}) end
  function d.command(text) assert(not s.editor); d.paste(text); d.key(257) end
  function d.drain() local turns=0; while s.job do d.step(); turns=turns+1; assert(turns<20000) end end
  return d
end
function M.initial(check)
  return isolate(function()
    local disk={fs={['/']={type='dir'},['/doc']={type='file',text='abc\ndef'},['/large']={type='file',text=string.rep('x',Editor.bytes+1)}}}
    local s,ledger=new(disk,12,6),{version=1}; assert(Scheduler.step(s,ledger,1,0,true))
    local d=driver(s,ledger)
    d.command('edit doc')
    check('native edit opens exact existing local bytes and a versioned plain record',s.editor.version==1 and s.editor.text=='abc\ndef' and not s.editor.dirty and s.disk.fs['/doc'].text=='abc\ndef')
    local before=packed(s)
    check('zero-credit editor event has no document cursor or rendering effects',not Shell.handle(s,{n=2,'paste','NO'},function() return false end) and packed(s)==before)
    d.key(262); d.paste('X\r\nY\rZ')
    check('editor middle multiline paste normalizes CRLF without dropping suffix',s.editor.text=='aX\nY\nZbc\ndef' and s.editor.cursor==6 and s.editor.dirty)
    d.key(259); d.key(261)
    check('native editor deletes preceding and following bytes',s.editor.text=='aX\nY\nc\ndef' and s.editor.cursor==5)
    d.key(268); d.key(257)
    check('native Enter inserts document newline instead of submitting shell source',s.editor.text=='aX\nY\n\nc\ndef' and s.editor.cursor==6 and s.job==nil)
    d.key(269); d.key(265); d.key(264)
    check('native Home End Up Down stay at bounded document line positions',s.editor.cursor==#'aX\nY\n\nc')
    d.key(267); d.key(266)
    check('native Page navigation keeps visible viewport containing cursor',s.editor.top>=1 and s.editor.cursor>=0 and s.editor.cursor<=#s.editor.text)
    local text=s.editor.text; d.send({n=3,'term_resize',7,3})
    check('editor resize keeps text and repaints its own viewport immediately',s.editor.text==text and s.display.columns==7 and s.display.rows==3 and s.display.lines[1].text:sub(1,5)=='edit ')
    d.key(Editor.quit_key)
    check('dirty Ctrl Q asks explicit disposition without abandoning draft',s.editor.confirm and s.editor.disposition=='exit' and s.disk.fs['/doc'].text=='abc\ndef')
    d.paste('c'); check('cancel leaves same dirty editor and committed bytes',not s.editor.confirm and s.editor.text==text and s.editor.dirty)
    d.key(Editor.save_key)
    local candidate=s.job
    check('Ctrl S retains dirty draft until atomic publication',s.editor.saving and s.editor.dirty and candidate.op=='write' and s.disk.fs['/doc'].text=='abc\ndef')
    d.drain(); check('successful editor save marks clean only after publication',not s.editor.saving and not s.editor.dirty and s.editor.base==text and s.disk.fs['/doc'].text==text)
    d.key(Editor.quit_key); check('clean Ctrl Q returns usable shell prompt',s.editor==nil and s.display.blink and s.status=='ready')
    for _,path in ipairs({'/','/rom/help.txt','/missing/file','/large'}) do
      local committed=packed(s.disk); d.command('edit '..path)
      check('editor refuses target without changing committed files '..path,s.editor==nil and s.job and s.job.kind=='output' and packed(s.disk)==committed)
      d.drain()
    end
    d.command('edit new.lua'); check('native editor can draft a missing local file',s.editor.base==false and s.editor.dirty and not s.disk.fs['/new.lua'])
    d.paste('new'); d.send({n=1,'reboot'}); d.paste('c')
    check('dirty reboot cancellation keeps editor and disk',s.editor.text=='new' and not s.editor.confirm and s.status=='ready' and not s.disk.fs['/new.lua'])
    d.send({n=1,'shutdown'}); d.paste('d')
    check('dirty shutdown discard stops only after explicit disposition',s.status=='stopped' and s.editor==nil and not s.disk.fs['/new.lua'])
    d.send({n=1,'reboot'}); d.step(); d.command('edit new.lua'); d.paste('return {}')
    d.key(Editor.quit_key); d.paste('s')
    check('save-on-exit keeps editor while create remains unpublished',s.editor.saving and s.editor.disposition=='exit' and not s.disk.fs['/new.lua'])
    d.drain(); check('save-on-exit publishes source before returning shell',s.editor==nil and s.disk.fs['/new.lua'].text=='return {}')
    d.command('edit new.lua'); d.paste('changed '); local draft=s.editor.text
    s.disk.fs['/new.lua'].text='external'
    d.key(Editor.save_key)
    check('save conflict keeps dirty draft editable without starting write',s.editor.text==draft and s.editor.dirty and not s.editor.saving and s.job==nil and s.disk.fs['/new.lua'].text=='external')
    d.paste('x'); check('typing after failed save still updates only draft',s.editor.text~=draft and s.disk.fs['/new.lua'].text=='external')
    d.key(Editor.quit_key); d.paste('d'); d.command('edit cap')
    for _=1,4 do d.paste(string.rep('x',8192)) end
    check('editor accepts exactly 32 KiB',#s.editor.text==Editor.bytes)
    d.paste('y'); check('editor refuses one byte beyond cap atomically',#s.editor.text==Editor.bytes and s.editor.message:find('limit',1,true))
    d.send({n=3,'term_resize',160,60}); d.key(Editor.save_key); d.drain()
    check('maximum geometry editor saves maximum document under unchanged quotas',s.disk.fs['/cap'].text==string.rep('x',Editor.bytes) and not s.editor.dirty)
    d.key(Editor.quit_key); d.command('edit cold.lua'); d.paste('cold draft\nsecond line')
    d.key(Editor.save_key)
    while s.job.phase~='publish' do d.step() end
    local editor,job,committed=s.editor,s.job,s.disk
    Budget.begin(ledger,d.tick); assert(Budget.admit(ledger,1,{execution=Budget.remaining(ledger,1,'execution')}))
    return {shell=s,ledger=ledger,tick=d.tick,editor=editor,job=job,disk=committed,before=packed(s),budget=packed(ledger)}
  end)
end
function M.observe(saved)
  assert(packed(saved.shell)==saved.before and packed(saved.ledger)==saved.budget,'native editor changed on load')
end
function M.reload(saved,check)
  isolate(function()
    M.observe(saved)
    local s=saved.shell
    check('cold editor draft save job disk and counters preserve identity',s.editor==saved.editor and s.job==saved.job and s.disk==saved.disk and s.editor.dirty)
    check('cold editor publication cannot renew exhausted credits',not Scheduler.step(s,saved.ledger,1,saved.tick,true) and packed(s)==saved.before)
    local d=driver(s,saved.ledger,saved.tick); d.step()
    check('cold editor publishes exact multiline bytes once',s.job==nil and not s.editor.dirty and s.disk.fs['/cold.lua'].text=='cold draft\nsecond line')
    d.key(257); d.paste('continued'); check('cold native editor remains interactive without executable snapshots',s.editor.dirty and s.editor.text:find('continued',1,true))
    d.send({n=1,'terminate'}); d.paste('c')
    check('dirty termination cancel preserves resumed editor',s.editor and not s.editor.confirm and s.editor.dirty)
  end)
end
return M
