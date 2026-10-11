-- Real factory entities, actual edit/copy/save/run handlers and one shared
-- ledger with the terminal echo fixture. This is not graphical acceptance.
local L=require('__computer_core_2__.scripts.lifecycle')
local R=require('__computer_core_2__.scripts.os_runtime')
local Circuit=require('__computer_core_2__.scripts.programs.circuit')
local Budget=require('__computer_core_2__.scripts.shell.budget')
local Scheduler=require('__computer_core_2__.scripts.guest.scheduler')
local Editor=require('__computer_core_2__.scripts.programs.editor')
local VM=require('__computer_core_2__.scripts.guest.vm')
-- Capture only for this fixture's explicitly original VM neighbor before the
-- control module poisons compiler entry points for every native application.
local compile_vm=require('__computer_core_2__.scripts.guest.compiler').compile
local example=require('__computer_core_2__.resources.programs.stock-controller')
local CircuitChecks=require('circuit_checks')
local LifecycleChecks=require('lifecycle_checks')
local M={}
local function packed(value) return serpent.line(value,{sortkeys=true}) end
local function host(m,fn)
  local old=storage; storage=m.host
  local ok,a,b=pcall(fn); storage=old; assert(ok,a); return a,b
end
local function wire(a,b)
  assert(a.get_wire_connector(defines.wire_connector_id.circuit_red,true).connect_to(b.get_wire_connector(defines.wire_connector_id.circuit_red,true),false))
end
local function send(m,event) host(m,function() assert(R.event(m.c,event)) end) end
local function command(m,text) send(m,{n=2,'paste',text}); send(m,{n=2,'key',257}) end
local function stock(m) return m.chest.get_inventory(defines.inventory.chest).get_item_count('iron-plate') end
local function signal(m)
  local network=m.c.sub.right_combinator.get_circuit_network(defines.wire_connector_id.circuit_red)
  return network and network.get_signal{type='virtual',name='signal-A',quality='normal'} or 0
end
function M.new()
  local m={host={next_computer=2},phase='boot',ticks=0}
  host(m,L.init)
  m.host.terminal_scheduler=Scheduler.new()
  local force=game.create_force('native-program-factory')
  force.technologies['computer-technology'].researched=true
  force.technologies['computer-gauntlet-technology'].researched=true
  local surface=game.surfaces[1]
  local function create(name,position,direction)
    -- Register the body with the real control script too: its world-wide orphan
    -- sweep must recognize these ports while isolated host consumers exercise them.
    return assert(surface.create_entity{name=name,position=position,direction=direction,force=force,raise_built=name=='blue-computer-interface-entity'})
  end
  host(m,function() m.c=assert(L.build(create('blue-computer-interface-entity',{226,0}))) end)
  host(m,function()
    m.vm=assert(L.build(create('computer-interface-entity',{242,0})))
    m.vm.terminal_schema=1
    m.vm.guest=VM.new(assert(compile_vm('while true do local _,c=os.pullEvent("char"); term.setCursorPos(1,1); term.write(c) end','=native-factory-vm-neighbor')),nil,nil,{columns=51,rows=19},true)
    m.vm.fs=m.vm.guest.disk.fs
  end)
  m.vm_samples=0; m.vm_latencies={}
  m.power=create('electric-energy-interface',{m.c.entity.position.x+6,m.c.entity.position.y})
  m.power.power_production=1000000
  m.power.electric_buffer_size=10000000
  m.power.energy=10000000
  m.pole=create('substation',{m.c.entity.position.x,m.c.entity.position.y+3})
  m.inserter=create('fast-inserter',{m.c.entity.position.x-3,m.c.entity.position.y},defines.direction.north)
  m.chest=create('steel-chest',m.inserter.drop_position)
  m.feeder=create('steel-chest',m.inserter.pickup_position)
  assert(m.feeder.insert{name='iron-plate',count=100}==100)
  m.chest.get_or_create_control_behavior().read_contents=true
  local cb=m.inserter.get_or_create_control_behavior()
  cb.circuit_condition={first_signal={type='virtual',name='signal-A'},comparator='>',constant=0}
  cb.circuit_enable_disable=true
  m.inserter.inserter_stack_size_override=1
  wire(m.c.sub.left_combinator,m.chest); wire(m.c.sub.right_combinator,m.inserter)
  m.foreign=m.c.sub.right_combinator.get_or_create_control_behavior().add_section()
  m.foreign.filters={{value={type='virtual',name='signal-B',quality='normal',comparator='='},min=17}}
  return m
end
function M.tick(m,check)
  if m.phase=='frozen' or m.phase=='done' then return end
  m.ticks=m.ticks+1
  m.vm.entity.energy=5000000
  if not m.vm_pending and m.vm_samples<100 and m.ticks>2 then
    m.vm_pending={tick=game.tick,revision=m.vm.guest.display.revision}
    host(m,function() assert(R.event(m.vm,{n=2,'char','V'})) end)
  end
  if not m.power_off then m.c.entity.energy=5000000 else m.c.entity.energy=0 end
  m.inserter.energy=100000
  host(m,function() L.tick(); R.tick() end)
  local s=m.c.shell
  if m.vm_pending then
    local pending=m.vm_pending
    if m.vm.guest.display.revision>pending.revision and m.vm.guest.display.lines[1].text:sub(1,1)=='V' then
      m.vm_latencies[#m.vm_latencies+1]=game.tick-pending.tick; m.vm_samples=m.vm_samples+1; m.vm_pending=nil
      if m.vm_samples==100 then
        table.sort(m.vm_latencies)
        check('actual original VM input shares native factory ledger with p95 two-tick echo',m.vm_latencies[95]<=2
          and m.host.terminal_scheduler.machines[m.vm.id]==m.vm.guest and (m.host.terminal_scheduler.backends[m.vm.id] or 'vm')=='vm')
      end
    else assert(game.tick-pending.tick<=2,'native factory stalled original VM input') end
  end
  assert(m.phase~='below' or m.ticks<1000,'factory did not transfer stock')
  if m.phase=='boot' and s and s.status=='ready' then
    local left=m.c.sub.left_combinator.get_circuit_network(defines.wire_connector_id.circuit_red)
    local right=m.c.sub.right_combinator.get_circuit_network(defines.wire_connector_id.circuit_red)
    if not left or not right then assert(m.ticks<20,'factory wiring never produced circuit networks'); return end
    check('factory has two owned ports, no legacy bundle, and separate real red networks',m.c.sub.left_combinator and m.c.sub.right_combinator
      and not m.c.sub.lamp and not m.c.sub.speaker
      and left.network_id~=right.network_id)
    command(m,'cp /rom/examples/stock-controller.lua /stock.lua'); m.phase='copy'
  elseif m.phase=='copy' and not s.job and s.disk.fs['/stock.lua'] then
    check('bundled source was copied through actual admitted filesystem command',s.disk.fs['/stock.lua'].text==example)
    command(m,'edit /stock.lua'); m.phase='open'
  elseif m.phase=='open' and s.editor then
    -- Move using the genuine keyboard consumer; never assign draft or cursor.
    local first=assert(example:find('100',1,true))
    m.moves=first+2; m.phase='move'
  elseif m.phase=='move' and #s.events.queue==0 then
    if m.moves>0 then send(m,{n=2,'key',262}); m.moves=m.moves-1
    else
      send(m,{n=2,'key',259}); send(m,{n=2,'key',259}); send(m,{n=2,'key',259}); send(m,{n=2,'char','5'}); send(m,{n=2,'key',Editor.save_key}); m.phase='save'
    end
  elseif m.phase=='save' and not s.job and s.editor and not s.editor.dirty then
    check('actual edited threshold, not bundled default, is atomically committed',s.disk.fs['/stock.lua'].text==example:gsub('stock < 100','stock < 5',1))
    send(m,{n=2,'key',Editor.quit_key}); m.phase='exit'
  elseif m.phase=='exit' and not s.editor then command(m,'run /stock.lua'); m.phase='below'
  elseif m.phase=='below' and s.controller and s.controller.state.stock and stock(m)>=1 then
    check('native stock controller drives real inserter transfer below edited threshold',s.controller.state.starts==1 and stock(m)>=1
      and m.feeder.get_inventory(defines.inventory.chest).get_item_count('iron-plate')<100)
    m.chest.clear_items_inside(); m.chest.insert{name='iron-plate',count=25}; m.phase='above'
  elseif m.phase=='above' and s.controller.state.stock and s.controller.state.stock>=25 and signal(m)==0
    and not m.inserter.held_stack.valid_for_read then
    m.wait_tick=game.tick; m.before_stock=stock(m); m.phase='above-stable'
  elseif m.phase=='above-stable' and game.tick-m.wait_tick>=20 then
    check('stock between edited and original thresholds disables signal A and real inserter',signal(m)==0 and stock(m)==m.before_stock
      and m.inserter.status==defines.entity_status.disabled_by_control_behavior)
    m.chest.clear_items_inside(); m.phase='enable'
  elseif m.phase=='enable' and signal(m)==1 then
    m.c.entity.energy=0; m.power_off=true; m.starts=s.controller.state.starts; m.phase='pause'
  elseif m.phase=='pause' and s.controller.status=='paused' and signal(m)==0 then
    check('real power loss clears only private outputs and retains start/state',s.controller.state.starts==m.starts
      and #m.c.native_ports.right.section.filters==0 and m.foreign.filters[1].min==17)
    m.power_off=false; m.chest.clear_items_inside(); m.chest.insert{name='iron-plate',count=25}; m.phase='restore'
  elseif m.phase=='restore' and s.controller.status=='running' and s.controller.state.stock>=25 and signal(m)==0 then
    check('restoration re-evaluates current stock without on_start replay or stale enable',s.controller.state.starts==1 and #m.c.native_ports.right.section.filters==0)
    CircuitChecks.run(m,check,function(fn) return host(m,fn) end)
    command(m,'edit /unsaved.lua'); m.phase='copy-open'
  elseif m.phase=='copy-open' and s.editor then
    send(m,{n=2,'paste','unsaved clone draft'}); m.phase='copy-snapshot'
  elseif m.phase=='copy-snapshot' and s.editor.text=='unsaved clone draft' and #s.events.queue==0 then
    local tags,err=host(m,function() return L.snapshot(m.c) end)
    if not tags then assert(err=='work deferred',err); return end
    m.copy_tags=tags; m.phase='copy-clone'
  elseif m.phase=='copy-clone' then
    local entity=assert(m.c.entity.surface.create_entity{name=m.c.entity.name,position={m.c.entity.position.x+12,0},force=m.c.entity.force,raise_built=true})
    local clone,err=host(m,function() return L.clone(m.c.entity,entity) end)
    if not clone then assert(err=='work deferred',err); return end
    m.clone=clone; clone.entity.energy=5000000; m.phase='copy-blueprint'
  elseif m.phase=='copy-blueprint' then
    local entity=assert(m.c.entity.surface.create_entity{name=m.c.entity.name,position={m.c.entity.position.x+24,0},force=m.c.entity.force,raise_built=true})
    m.blueprint=host(m,function() return assert(L.build(entity,m.copy_tags)) end)
    m.blueprint.entity.energy=5000000; m.phase='copy-ready'
  elseif m.phase=='copy-ready' and m.clone.shell and m.clone.shell.status=='ready' and m.blueprint.shell and m.blueprint.shell.status=='ready' then
    local clean=true
    for _,copy in ipairs({m.clone,m.blueprint}) do
      clean=clean and copy.shell.disk.fs['/stock.lua'].text==s.disk.fs['/stock.lua'].text and not copy.shell.disk.fs['/unsaved.lua']
        and copy.shell.editor==nil and copy.shell.controller==nil and copy.shell.program_output==nil
        and #copy.native_ports.right.section.filters==0 and not copy.native_ports.right.active
    end
    check('live-controller clone/blueprint copies only committed source, never dirty draft state or outputs',clean
      and s.editor.text=='unsaved clone draft' and s.editor.dirty and s.controller.status=='running' and s.controller.state.starts==1)
    send(m,{n=2,'key',Editor.quit_key}); send(m,{n=2,'char','d'}); m.phase='copy-exit'
  elseif m.phase=='copy-exit' and not s.editor then
    m.phase='ready'
  end
end
function M.ready(m) return m.phase=='ready' and m.vm_samples==100 end
function M.freeze(m)
  assert(M.ready(m))
  m.phase='frozen'; m.shell=m.c.shell; m.controller=m.shell.controller
  m.before=packed(m.shell); m.credits=packed(m.host.terminal_scheduler); m.saved_tick=game.tick
  m.before_vm=packed(m.vm.guest); m.guest=m.vm.guest
end
function M.observe(m)
  if m.phase=='frozen' then
    assert(m.c.shell==m.shell and m.shell.controller==m.controller and packed(m.shell)==m.before
      and packed(m.host.terminal_scheduler)==m.credits,'factory source/state/deadline/work changed on load')
    assert(m.vm.guest==m.guest and packed(m.vm.guest)==m.before_vm,'factory VM neighbor changed on load')
  end
end
function M.resume(m,check)
  if m.phase=='frozen' then
    M.observe(m)
    check('cold factory preserves exact source/controller/deadline/ledger aliases without effects',m.controller.state.starts==1)
    m.phase='cold'; return
  end
  if m.phase=='cold' then
    m.c.entity.energy=5000000; m.inserter.energy=100000
    host(m,function() L.tick(); R.tick() end)
    if m.controller.next_tick>m.saved_tick and m.controller.state.starts==1 and game.tick>m.saved_tick+65 then
      check('cold native factory reconstruction neither replays start nor re-enables above threshold',signal(m)==0 and m.controller.state.stock>=25)
      m.chest.clear_items_inside(); m.phase='cold-enable'
    end
  elseif m.phase=='cold-enable' then
    m.c.entity.energy=5000000; m.inserter.energy=100000
    host(m,function() L.tick(); R.tick() end)
    if signal(m)==1 then command(m,'stop'); m.phase='stop' end
  elseif m.phase=='stop' then
    m.c.entity.energy=5000000; m.inserter.energy=100000
    host(m,function() L.tick(); R.tick() end)
    if m.controller.status=='stopped' and signal(m)==0 then
      check('explicit native stop clears owned outputs and preserves unrelated section/entities',#m.c.native_ports.right.section.filters==0
        and m.foreign.filters[1].min==17 and m.chest.valid and m.feeder.valid and m.inserter.valid)
      LifecycleChecks.run(m,check,function(fn) return host(m,fn) end)
      m.phase='done'
    end
  end
  return m.phase=='done'
end
return M
