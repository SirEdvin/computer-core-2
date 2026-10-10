local Shell=require('__computer_core_2__.scripts.shell.runtime')
local new=require('construct')
local Scheduler=require('__computer_core_2__.scripts.shell.scheduler')
local Limits=require('__computer_core_2__.scripts.guest.limits')
local M={}
local function packed(s) return serpent.line(s,{sortkeys=true}) end
function M.initial(check)
  local disk={fs={['/']={type='dir'},['/space dir']={type='dir'},
    ['/space dir/hello.lua']={type='file',text='return _G.this_must_never_execute()'},
    ['/large']={type='file',text=string.rep('x',Limits.string_bytes+1)}}}
  local s,ledger=new(disk,51,19),{version=1}
  local tick=0
  local function send(event)
    tick=tick+1
    assert(Scheduler.push(s,ledger,1,tick,event)); assert(Scheduler.step(s,ledger,1,tick,true))
  end
  local function command(line)
    send({n=2,'paste',line}); send({n=2,'key',257})
  end
  local function drain()
    while s.job do tick=tick+1; assert(Scheduler.step(s,ledger,1,tick,true)) end
  end
  assert(Scheduler.step(s,ledger,1,0,true))
  command('cd "space dir"')
  check('quoted directory changes confined cwd',s.disk.cwd=='/space dir' and s.job==nil)
  command('cat hello.lua')
  check('file containing Lua is only an immutable data output',s.job.kind=='cat' and s.job.text==disk.fs['/space dir/hello.lua'].text)
  drain()
  local literal=disk.fs['/space dir/hello.lua'].text
  check('file without final newline survives prompt restoration',s.display.lines[s.display.rows-1].text:sub(1,#literal)==literal)
  command('cd ../../..'); check('parents clamp to local root',s.disk.cwd=='/')
  command('cd missing'); check('missing directory gives bounded error without cwd mutation',s.job.kind=='output' and s.disk.cwd=='/'); drain()
  command('cat "unterminated'); check('unterminated quote is data error',s.job.kind=='output'); drain()
  command('clear'); check('clear preserves disk and usable prompt',s.job==nil and s.display.lines[1].text==string.rep(' ',s.display.columns)
    and s.disk.fs['/large'].text==disk.fs['/large'].text)
  command('cat large'); tick=tick+1; assert(Scheduler.step(s,ledger,1,tick,true))
  local cursor=s.job.cursor
  assert(Scheduler.push(s,ledger,1,tick,{n=2,'char','Z'}))
  assert(Scheduler.push(s,ledger,1,tick,{n=3,'term_resize',43,8}))
  tick=tick+1; assert(Scheduler.step(s,ledger,1,tick,true))
  check('resize during output takes effect without consuming its data or later typing',s.display.columns==43 and s.display.rows==8
    and s.display.y==8 and s.display.x<=43 and s.job.cursor==cursor and s.command=='' and #s.events.queue==1)
  assert(Scheduler.push(s,ledger,1,tick,{n=1,'terminate'}))
  tick=tick+1; assert(Scheduler.step(s,ledger,1,tick,true))
  check('interrupt cancels foreground job but preserves accepted later input',s.job==nil and #s.events.queue==1 and s.display.blink)
  tick=tick+1; assert(Scheduler.step(s,ledger,1,tick,true))
  check('input after interruption is delivered once',s.command=='Z' and #s.events.queue==0)
  send({n=1,'terminate'})
  send({n=2,'paste','draft'}); send({n=2,'key',263})
  local draft_cursor=s.cursor
  send({n=2,'key',265}); check('Up recalls most recent command',s.command=='cat large')
  send({n=2,'key',264}); check('Down restores unsent draft and cursor',s.command=='draft' and s.cursor==draft_cursor)
  send({n=1,'terminate'}); command('cat large')
  tick=tick+1; assert(Scheduler.step(s,ledger,1,tick,true))
  return {shell=s,ledger=ledger,tick=tick,before=packed(s),job=s.job,display=s.display,disk=s.disk,
    cursor=s.job.cursor,text=s.job.text,bytes=s.disk.bytes}
end
function M.reload(saved,check)
  local s=saved.shell
  check('cold file job preserves session and aliases without load-time work',packed(s)==saved.before and s.job==saved.job
    and s.display==saved.display and s.disk==saved.disk and s.job.cursor==saved.cursor and s.job.text==saved.text)
  local tick=saved.tick+1
  assert(Scheduler.step(s,saved.ledger,1,tick,true))
  check('cold file job resumes from saved byte cursor',s.job.cursor>saved.cursor and s.disk.bytes==saved.bytes)
  assert(Scheduler.push(s,saved.ledger,1,tick,{n=1,'terminate'}))
  tick=tick+1; assert(Scheduler.step(s,saved.ledger,1,tick,true))
  check('cold file job cancellation preserves file data',s.job==nil and s.disk.fs['/large'].text==saved.text)
end
return M
