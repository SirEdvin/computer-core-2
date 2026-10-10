local Shell=require('__computer_core_2__.scripts.shell.runtime')
local new=require('construct')
local Scheduler=require('__computer_core_2__.scripts.shell.scheduler')
local M={}
function M.run(check)
  local s,other=new(nil,51,19),new(nil,51,19)
  local ledger={version=1}
  local tick=0
  local function send(event)
    tick=tick+1
    assert(Scheduler.push(s,ledger,1,tick,event))
    assert(Scheduler.step(s,ledger,1,tick,true))
  end
  assert(Scheduler.step(s,ledger,1,0,true))
  assert(Scheduler.step(other,ledger,2,0,true))
  local palette=serpent.line(s.display.palette,{sortkeys=true})
  s.display.dirty={}
  for byte in ('abcd'):gmatch('.') do send({n=2,'char',byte}) end
  send({n=2,'key',268}); send({n=2,'key',262}); send({n=2,'char','X'})
  check('middle insertion retains suffix and cursor',s.command=='aXbcd' and s.cursor==2)
  send({n=2,'key',263}); send({n=2,'key',259})
  check('backspace removes preceding byte',s.command=='Xbcd' and s.cursor==0)
  send({n=2,'key',261}); send({n=2,'key',269}); send({n=2,'key',263}); send({n=2,'key',261})
  send({n=2,'char','e'})
  check('delete and end navigation preserve remainder',s.command=='bce' and s.cursor==3)
  check('input is routed to its own session only',other.command=='' and other.cursor==0)
  check('ordinary edit dirties only prompt row',next(s.display.dirty)==s.display.rows and s.display.dirty[s.display.rows]
    and s.display.blink and s.display.x==7 and s.display.lines[s.display.rows].text:sub(1,6)=='/> bce')
  check('typing preserves native colors and palette',serpent.line(s.display.palette,{sortkeys=true})==palette
    and s.display.lines[s.display.rows].foreground==string.rep('0',s.display.columns)
    and s.display.lines[s.display.rows].background==string.rep('f',s.display.columns))
  send({n=1,'terminate'}); send({n=2,'key',257})
  check('empty Enter returns usable prompt without job',s.command=='' and s.job==nil and s.display.blink)
  send({n=2,'paste','pwd extra'}); send({n=2,'key',257})
  check('argument error is a bounded builtin result',s.job and s.job.text=='pwd: no arguments accepted\n' and not s.display.blink)
  tick=tick+1; assert(Scheduler.step(s,ledger,1,tick,true))
  check('command error returns prompt',s.job==nil and s.status=='ready' and s.display.blink)
  send({n=2,'paste','pwd'}); send({n=2,'key',257})
  tick=tick+1; assert(Scheduler.step(s,ledger,1,tick,true))
  check('submitted command and output have separate rows',s.display.lines[s.display.rows-2].text:sub(1,6)=='/> pwd'
    and s.display.lines[s.display.rows-1].text:sub(1,1)=='/' and s.display.lines[s.display.rows].text:sub(1,3)=='/> ')
end
return M
