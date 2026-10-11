-- Real owned ports with focused host-service oracles; no client/latency claims.
local Circuit=require('__computer_core_2__.scripts.programs.circuit')
local Compiler=require('__computer_core_2__.scripts.programs.compiler')
local Programs=require('__computer_core_2__.scripts.programs.runtime')
local Budget=require('__computer_core_2__.scripts.shell.budget')
local M={}
local function source(body) return 'return {interval=1,on_tick=function(event,state) '..body..' end}' end
function M.run(m,check,host)
  local observer,outer=check,storage
  check=function(name,value)
    local scoped=storage; storage=outer
    local ok,err=pcall(observer,name,value)
    storage=scoped; assert(ok,err)
  end
  host(function()
    local c=m.c; local shell=c.shell
    local function make(body)
      Circuit.clear(c)
      local s={}; c.shell=s
      local service=Circuit.service(c,s,game.tick)
      local ok,err=Programs.activate(s,{source=source(body),path='/circuit-test.lua'},game.tick,service)
      assert(ok,err)
      s.controller.started=true
      return s,service
    end
    local function run(s,service)
      return Programs.step(s,game.tick,true,function() return true end,service)
    end
    local s,service=make('state.count=circuit.read("left","green","item","iron-plate")')
    assert(run(s,service))
    check('disconnected valid green network returns scalar zero',s.controller.status=='running' and s.controller.state.count==0 and type(s.controller.state.count)=='number')
    check('owned port registries and red player wires survive repeated lifecycle ensure',storage.children[c.sub.left_combinator.unit_number].id==c.id
      and storage.children[c.sub.right_combinator.unit_number].key=='right_combinator'
      and c.sub.left_combinator.get_wire_connector(defines.wire_connector_id.circuit_red,true).connection_count==1
      and c.sub.right_combinator.get_wire_connector(defines.wire_connector_id.circuit_red,true).connection_count==1)
    for _,bad in ipairs({
      'circuit.read("other","red","item","iron-plate")',
      'circuit.read("left","blue","item","iron-plate")',
      'circuit.read("left","red","unknown","iron-plate")',
      'circuit.read("left","red","item","not-a-prototype")',
      'circuit.write("right","virtual","signal-A",2147483648)',
      'circuit.write("right","virtual","signal-A",-2147483649)',
      'circuit.write("right","virtual","signal-A",0.5)',
      'circuit.write("right","virtual","signal-A",false)',
    }) do
      s,service=make('state.staged=1; print("UNCOMMITTED"); '..bad)
      local values=s.controller.state; assert(run(s,service))
      check('invalid circuit callback publishes no staged effects '..bad,s.controller.status=='faulted' and s.controller.state==values
        and values.staged==nil and #s.program_output.queue==0 and #c.native_ports.right.section.filters==0 and m.foreign.filters[1].min==17)
    end
    s,service=make('circuit.write("right","virtual","signal-A",-2147483648); circuit.write("left","virtual","signal-A",2147483647)')
    assert(run(s,service))
    check('both exact int32 endpoints publish to private sections',s.controller.status=='running' and c.native_ports.right.section.filters[1].min==-2147483648
      and c.native_ports.left.section.filters[1].min==2147483647)
    s,service=make('circuit.write("right","virtual","signal-A",0); circuit.clear("left")')
    assert(run(s,service))
    check('zero write and clear remove private output identities',s.controller.status=='running' and next(s.controller.outputs.right)==nil and #c.native_ports.left.section.filters==0)
    local names={}; for name in pairs(prototypes.virtual_signal) do names[#names+1]=name end; table.sort(names); assert(#names>=33)
    s,service=make('circuit.write("right","virtual",state.signal,1)')
    for i=1,32 do
      s.controller.state.signal=names[i]; s.controller.next_tick=game.tick
      assert(run(s,service)); assert(s.controller.status=='running',s.controller.message)
    end
    check('32 accumulated signal identities fit one owned output bank',#c.native_ports.right.section.filters==32 and Programs.valid(s.controller))
    local banks=s.controller.outputs
    s.controller.state.signal=names[33]; s.controller.next_tick=game.tick; assert(run(s,service))
    check('33rd output identity faults without publishing bank or touching foreign section',s.controller.status=='faulted' and s.controller.outputs==banks
      and banks.right['virtual:'..names[33]]==nil and #c.native_ports.right.section.filters==0 and m.foreign.filters[1].min==17)
    local result,err=Compiler.compile(source(string.rep('circuit.clear("left");',17)),'/too-many.lua')
    check('17 circuit calls are refused by path-effect cap',not result and err:find('16 circuit',1,true))
    for _,field in ipairs({'force','surface','id'}) do
      s,service=make('state.staged=1; circuit.write("right","virtual","signal-A",1)')
      s.controller.owner[field]=s.controller.owner[field]+1
      assert(run(s,service))
      check('changed controller ownership refuses circuit publication '..field,s.controller.status=='faulted' and s.controller.state.staged==nil and #c.native_ports.right.section.filters==0)
    end
    s,service=make('circuit.read("left","red","item","iron-plate")')
    local child=c.sub.left_combinator; c.sub.left_combinator=nil
    assert(run(s,service)); c.sub.left_combinator=child
    check('missing port faults instead of reporting disconnected zero',s.controller.status=='faulted' and s.controller.message:find('owned circuit port unavailable',1,true))
    s,service=make('circuit.write("right","virtual","signal-A",1)')
    local owner=storage.children[c.sub.right_combinator.unit_number]
    storage.children[c.sub.right_combinator.unit_number]={id=c.id+1,key='right_combinator'}
    assert(run(s,service)); storage.children[c.sub.right_combinator.unit_number]=owner
    check('stolen child registry refuses publication without claiming foreign ownership',s.controller.status=='faulted' and #c.native_ports.right.section.filters==0)
    s,service=make('state.staged=1; circuit.write("left","virtual","signal-A",1); circuit.write("right","virtual","signal-A",1)')
    local port=c.native_ports.right; local section=port.section
    -- Inject an unexpected publication exception on the second target. The first
    -- target is a real engine section; this does not claim engine reentrancy.
    port.section=setmetatable({valid=true,is_manual=true,group='',active=true},{__newindex=function() error('injected publication exception',0) end})
    assert(run(s,service))
    check('unexpected second-target exception clears real first target and marks retry',s.controller.status=='faulted' and s.controller.state.staged==nil
      and #s.program_output.queue==0 and #c.native_ports.left.section.filters==0 and c.native_clear_pending and m.foreign.filters[1].min==17)
    port.section=section; assert(Circuit.clear(c))
    check('restored private target permits bounded clear retry',not c.native_clear_pending and #section.filters==0)
    for _,bad in ipairs({true,{version=99,status='running'},{version=1,compiler=99,api=1,status='running'}}) do
      s,service=make('circuit.write("right","virtual","signal-A",1)')
      assert(run(s,service)); assert(#c.native_ports.right.section.filters==1)
      s.controller=bad
      local ledger={version=1}; Budget.begin(ledger,game.tick)
      local ok,err=pcall(Circuit.priority,ledger,game.tick)
      check('incompatible retained application cannot crash cleanup or leave live outputs',ok and #c.native_ports.right.section.filters==0
        and s.controller==bad and not c.native_clear_pending)
      Budget.begin(ledger,game.tick+1); Circuit.priority(ledger,game.tick+1)
      check('inert incompatible records do not consume active cleanup slots forever',ledger.execution_budget.instructions==0 and s.controller==bad)
    end
    s,service=make('')
    Programs.stop(s,service); Programs.open_repl(s,game.tick,service)
    local text,diagnostic=Programs.evaluate_repl(s,'state.read=circuit.read("left","red","item","iron-plate"); return state.read',game.tick,service)
    assert(text,diagnostic)
    check('REPL reads actual owned red network as a scalar',type(s.controller.state.read)=='number' and text==tostring(s.controller.state.read)..'\n')
    text,diagnostic=Programs.evaluate_repl(s,'state.kept=7; circuit.write("right","virtual","signal-A",7)',game.tick,service)
    assert(text,diagnostic)
    check('REPL publishes native state and real private signal transaction',s.controller.state.kept==7 and c.native_ports.right.section.filters[1].min==7)
    local values,banks=s.controller.state,s.controller.outputs
    text,diagnostic=Programs.evaluate_repl(s,'state.kept=99; circuit.write("right","virtual","signal-A",99); print("UNCOMMITTED"); state.bad=1/0',game.tick,service)
    check('REPL runtime failure preserves previously committed state and real signals',not text and diagnostic and s.controller.state==values
      and s.controller.outputs==banks and values.kept==7 and c.native_ports.right.section.filters[1].min==7 and m.foreign.filters[1].min==17)
    local energy=c.entity.energy; c.entity.energy=0
    local ledger={version=1}; Budget.begin(ledger,game.tick); Circuit.priority(ledger,game.tick)
    check('REPL power failure clears real private output and retains state',s.controller.status=='paused'
      and c.native_ports.right.section.active==false and s.controller.state==values)
    c.entity.energy=energy
    text,diagnostic=Programs.evaluate_repl(s,'circuit.clear("right"); state.kept=8',game.tick,service); assert(text,diagnostic)
    check('REPL restored explicit submission resumes without previous-line replay',s.controller.status=='running'
      and s.controller.state.kept==8 and #c.native_ports.right.section.filters==0)
    s.controller.owner.force=s.controller.owner.force+1
    values=s.controller.state
    text,diagnostic=Programs.evaluate_repl(s,'state.kept=9',game.tick,service)
    check('REPL changed owner refuses even scalar publication',not text and diagnostic and s.controller.state==values and values.kept==8)
    Programs.stop(s,service); s.repl=nil
    check('REPL exit cleanup preserves unrelated section',#c.native_ports.right.section.filters==0 and m.foreign.filters[1].min==17)
    c.shell=shell; assert(Circuit.clear(c))
  end)
end
return M
