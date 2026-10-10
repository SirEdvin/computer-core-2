-- Direct handlers are required at script parsing; on_load only observes data.
local Shell = require('__computer_core_2__.scripts.shell.runtime')
local new=require('construct')
local VM = require('__computer_core_2__.scripts.guest.vm')
local Compiler = require('__computer_core_2__.scripts.guest.compiler')
local Native = require('__computer_core_2__.scripts.native.dispatch')
local NativeCompiler = require('__computer_core_2__.scripts.native.compiler')
local budget_checks = require('budget_checks')
local input_checks = require('input_checks')
local file_checks = require('file_checks')
local import_checks = require('import_checks')
local parser_checks = require('parser_checks')
local interaction_checks = require('interaction_checks')
local mutation_checks = require('mutation_checks')
local persistence_checks = require('persistence_checks')
local backend_checks = require('backend_checks')
local runtime_routing_checks = require('runtime_routing_checks')
local mixed_runtime_checks = require('mixed_runtime_checks')
local model_checks = require('model_checks')
local physical_lifecycle_checks = require('physical_lifecycle_checks')
local loaded = false
local function check(name, value)
  assert(value, 'shell probe: '..name)
  storage.checks = storage.checks + 1
  log('CC2 SHELL PASS '..name)
end
local function plain(value, seen)
  local kind = type(value)
  assert(kind == 'nil' or kind == 'boolean' or kind == 'number' or kind == 'string' or kind == 'table', 'non-data shell value')
  if kind == 'number' then assert(value == value and math.abs(value) < math.huge) end
  if kind ~= 'table' then return end
  assert(getmetatable(value) == nil, 'metatable in shell state')
  if seen[value] then return end
  seen[value] = true
  for k,v in pairs(value) do plain(k,seen); plain(v,seen) end
end
local function event(state, tuple, admission)
  local ok, err = Shell.handle(state, tuple, admission or function() return true end)
  assert(ok, err)
  plain(state,{})
end
local function isolated(fn)
  local original = {VM.run, Compiler.compile, Native.run, NativeCompiler.compile}
  local function forbidden() error('shell entered a compiler/interpreter',0) end
  VM.run, Compiler.compile, Native.run, NativeCompiler.compile = forbidden, forbidden, forbidden, forbidden
  local ok,err = pcall(fn)
  VM.run, Compiler.compile, Native.run, NativeCompiler.compile = table.unpack(original)
  assert(ok,err)
end
local function initial()
  local disk={fs={['/']={type='dir'},['/evil.lua']={type='file',text='game.print("EXECUTED"); while true do end'}}}
  local s=new(disk,51,19)
  disk.fs['/evil.lua'].text='changed outside shell'
  check('distinct event-shell state',s.backend=='event-shell' and s.version==Shell.VERSION and s.frames==nil and s.heap==nil and s.bundle==nil)
  local before=serpent.line(s,{sortkeys=true})
  check('zero-credit boot is unchanged',not Shell.handle(s,{n=1,'boot'},function() return false end) and serpent.line(s,{sortkeys=true})==before)
  event(s,{n=1,'boot'})
  check('snapshot owns plain local data',s.disk.fs['/evil.lua'].text:find('EXECUTED',1,true)~=nil)
  check('direct boot paints prompt',s.status=='ready' and s.display.lines[s.display.rows].text:sub(1,3)=='/> ')
  event(s,{n=2,'char','p'}); event(s,{n=2,'char','w'}); event(s,{n=2,'char','d'})
  check('individual characters use ordinary session data',s.command=='pwd' and s.cursor==3)
  event(s,{n=2,'key',257})
  check('builtin produces fixed output job',s.job and s.job.kind=='output' and s.job.text=='/\n')
  event(s,{n=1,'advance'})
  check('builtin job completes without suspended calls',s.job==nil and s.command=='' and s.status=='ready')
  for _,request in ipairs({'evil.lua','lua evil.lua','edit evil.lua','load evil.lua','__computer_core_2__.scripts.guest.vm'}) do
    event(s,{n=2,'paste',request}); event(s,{n=2,'key',257})
    check('unknown command never executes '..request,s.job and s.job.text:find('unsupported',1,true)~=nil)
    while s.job do event(s,{n=1,'advance'}) end
  end
  before=serpent.line(s,{sortkeys=true})
  check('unknown event cannot choose a handler',not Shell.handle(s,{n=2,'require','__computer_core_2__.scripts.guest.vm'},function() return true end) and serpent.line(s,{sortkeys=true})==before)
  check('executable event payload rejected',not Shell.handle(s,{n=2,'char',function() end},function() return true end) and serpent.line(s,{sortkeys=true})==before)
  local bad=new(nil,51,19)
  bad.job={version=1,kind='require',module='scripts.guest.vm'}
  local job=bad.job
  check('forged job halts with original data',not Shell.handle(bad,{n=1,'advance'},function() return true end) and bad.status=='recovery' and bad.job==job)
  local bad_disk={fs={['/']={type='dir'},['/bad.lua']={type='file',text=function() end}}}
  check('executable snapshot refused',not pcall(new,bad_disk,51,19))
  local old={version=5,heap={preserved=7},status='yield',disk=s.disk}
  check('experimental graph not converted',not Shell.handle(old,{n=1,'boot'},function() return true end) and old.heap.preserved==7 and old.version==5 and old.disk==s.disk)
  event(s,{n=2,'char','c'})
  storage.shell=s
  storage.display=s.display
  storage.before=serpent.line(s,{sortkeys=true})
  plain(s,{})
end
script.on_init(function()
  storage.checks=0
  storage.model_session=model_checks.initial(check)
  isolated(initial)
  storage.budget_session=budget_checks.initial(check)
  input_checks.run(check)
  storage.file_session=file_checks.initial(check)
  storage.import_session=import_checks.initial(check)
  parser_checks.initial(check)
  storage.interaction_session=interaction_checks.initial(check)
  plain(storage.interaction_session,{})
  storage.mutation_session=mutation_checks.initial(check)
  plain(storage.mutation_session,{})
  storage.persistence_session=persistence_checks.initial(check)
  plain(storage.persistence_session,{})
  storage.backend_session=backend_checks.initial(check)
  storage.routing_session=runtime_routing_checks.initial(check)
  storage.mixed_session=mixed_runtime_checks.initial(check)
  storage.physical_session=physical_lifecycle_checks.initial(check)
  plain(storage.routing_session.computer.shell,{})
  plain(storage.backend_session.computer.shell,{})
  -- The shared ledger also owns the unchanged VM neighbor, whose math library
  -- legitimately contains infinity. Apply the shell's finite/plain contract to
  -- its owned graph, not to the separate VM execution graph.
  plain(storage.import_session.shell,{})
  plain(storage.file_session,{})
  plain(storage.budget_session,{})
  storage.stage='armed'
  log('CC2 SHELL BOOTSTRAP PASS')
end)
script.on_configuration_changed(function()
  storage.model_configuration_changed=true
  log('CC2 BLUE CONFIGURATION CHANGED')
end)
script.on_load(function()
  loaded=true
  assert(serpent.line(storage.shell,{sortkeys=true})==storage.before,'shell mutated on load')
  assert(serpent.line(storage.import_session.shell,{sortkeys=true})==storage.import_session.before,'import mutated on load')
  assert(serpent.line(storage.interaction_session.shell,{sortkeys=true})==storage.interaction_session.before,'interaction mutated on load')
  assert(serpent.line(storage.mutation_session.shell,{sortkeys=true})==storage.mutation_session.before,'mutation mutated on load')
  persistence_checks.observe(storage.persistence_session)
  backend_checks.observe(storage.backend_session)
  runtime_routing_checks.observe(storage.routing_session)
  mixed_runtime_checks.observe(storage.mixed_session)
  physical_lifecycle_checks.observe(storage.physical_session)
end)
script.on_event(defines.events.on_tick,function()
  if storage.stage=='armed' then
    loaded=false -- Consume the bootstrap map's load before the acceptance save.
    if not physical_lifecycle_checks.prepare(storage.physical_session,check) then return end
    if not mixed_runtime_checks.prepare(storage.mixed_session,check) then return end
    for _,c in pairs(storage.mixed_session.host.computers) do if c.shell then plain(c.shell,{}) end end
    storage.stage='snapshot'
    game.server_save('cc2-resume')
    log('CC2 SHELL SNAPSHOT')
    log('CC2 SHELL COMPLETE FIRST checks='..storage.checks)
  elseif loaded and storage.stage=='snapshot' then
    loaded=false
    isolated(function()
      check('cold reload retains session/display identity',storage.shell.display==storage.display and storage.shell.command=='c')
      event(storage.shell,{n=2,'char','d'})
      check('cold registry resumes direct input once',storage.shell.command=='cd' and storage.shell.cursor==2)
    end)
    storage.stage='mixed-resume'
    budget_checks.reload(storage.budget_session,check)
    file_checks.reload(storage.file_session,check)
    import_checks.reload(storage.import_session,check)
    interaction_checks.reload(storage.interaction_session,check)
    mutation_checks.reload(storage.mutation_session,check)
    persistence_checks.reload(storage.persistence_session,check)
    backend_checks.reload(storage.backend_session,check)
    runtime_routing_checks.reload(storage.routing_session,check)
    model_checks.reload(storage.model_session,check,storage.model_configuration_changed)
  elseif storage.stage=='mixed-resume' then
    if mixed_runtime_checks.resume(storage.mixed_session,check) then storage.stage='mixed-finish' end
  elseif storage.stage=='mixed-finish' then
    if not physical_lifecycle_checks.resume(storage.physical_session,check) then return end
    if mixed_runtime_checks.finish(storage.mixed_session,check) then
      storage.stage='done'
      log('CC2 SHELL COMPLETE RELOAD checks='..storage.checks)
    end
  end
end)
