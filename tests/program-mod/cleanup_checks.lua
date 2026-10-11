-- Cleanup-only component fixture: real ports, synthetic ledger ticks, no latency claim.
local L=require('__computer_core_2__.scripts.lifecycle')
local R=require('__computer_core_2__.scripts.os_runtime')
local Circuit=require('__computer_core_2__.scripts.programs.circuit')
local Budget=require('__computer_core_2__.scripts.shell.budget')
local Limits=require('__computer_core_2__.scripts.guest.limits')
local M={}
function M.initial(check)
  local outer=storage; storage={}
  local ok,err=pcall(function()
    L.init(); R.init()
    local fixture=storage
    local function observe(name,value)
      storage=outer; local passed,message=pcall(check,name,value); storage=fixture; assert(passed,message)
    end
    local force=game.forces.player; force.technologies['computer-technology'].researched=true
    local bodies={}
    for i=1,Limits.active_computers do
      local entity=assert(game.surfaces[1].create_entity{name='blue-computer-interface-entity',
        position={1000+8*((i-1)%32),1000+8*math.floor((i-1)/32)},force=force,raise_built=true})
      local c=assert(L.build(entity)); entity.energy=0
      -- Minimal header is deliberately a host-cleanup component, not a claim of
      -- initialized script sessions or a second production scheduler.
      c.shell={status='ready',controller={version=1,compiler=1,api=1,status='running',
        owner={id=c.id,force=force.index,surface=entity.surface.index}}}
      local foreign=assert(c.sub.right_combinator.get_or_create_control_behavior().add_section())
      foreign.filters={{value={type='virtual',name='signal-B',quality='normal',comparator='='},min=17}}; foreign.active=false
      bodies[#bodies+1]={c=c,foreign=foreign}
    end
    local function arm()
      for _,entry in ipairs(bodies) do
        local c=entry.c; c.shell.controller.status='running'
        local port=c.native_ports.right
        port.section.filters={{value={type='virtual',name='signal-A',quality='normal',comparator='='},min=1}}
        port.section.active=true; port.active=true
      end
    end
    local function all_cleared()
      for _,entry in ipairs(bodies) do
        if #entry.c.native_ports.right.section.filters~=0 or entry.c.shell.controller.status~='paused'
          or entry.foreign.filters[1].min~=17 then return false end
      end
      return true
    end
    local ledger=fixture.terminal_scheduler
    arm(); Budget.begin(ledger,1); Circuit.priority(ledger,1)
    observe('simultaneous power cleanup clears every real private port at unchanged active cap',#bodies==512 and all_cleared())
    observe('active-cap cleanup spends original aggregate/per-machine ledger domains',ledger.execution_budget.instructions==Limits.active_computers
      and ledger.filesystem_budget.used==128*Limits.active_computers and ledger.table_budget.used==64*Limits.active_computers
      and Budget.remaining(ledger,1,'execution')==math.min(Limits.instructions_per_computer-1,Limits.instructions_per_tick-Limits.active_computers))
    local execution=ledger.execution_budget.instructions
    Circuit.priority(ledger,1); Budget.begin(ledger,1)
    observe('repeated same-tick priority does not multiply cleanup credits',ledger.execution_budget.instructions==execution and all_cleared())
    arm(); Budget.begin(ledger,2)
    assert(Budget.admit(ledger,1,{execution=Limits.instructions_per_tick}))
    Circuit.priority(ledger,2)
    local inactive=true
    for _,entry in ipairs(bodies) do
      inactive=inactive and #entry.c.native_ports.right.section.filters==1 and entry.c.shell.controller.status=='running'
    end
    observe('already exhausted tick cannot secretly renew credits or perform unadmitted cleanup',inactive and ledger.execution_budget.instructions==Limits.instructions_per_tick)
    Budget.begin(ledger,2); Circuit.priority(ledger,2)
    observe('same-tick exhausted retry remains refused',ledger.execution_budget.instructions==Limits.instructions_per_tick)
    Budget.begin(ledger,3); Circuit.priority(ledger,3)
    observe('next legitimate tick reserves cap-wide cleanup before ordinary admission',all_cleared()
      and ledger.execution_budget.instructions==Limits.active_computers and ledger.compile_budget.used==0)
    -- Dormant restored graphs are not active scheduler entries. They must not
    -- take all priority slots ahead of a registered controller with live output.
    for _,entry in ipairs(bodies) do entry.c.entity.energy=1 end
    local current=bodies[#bodies].c
    ledger.machines[current.id]=current.shell
    Budget.begin(ledger,4); Circuit.priority(ledger,4)
    observe('dormant restored records cannot starve registered cleanup admission',ledger.execution_budget.instructions==1
      and current.native_cleanup_tick==4 and bodies[1].c.native_cleanup_tick~=4)
    for _,entry in ipairs(bodies) do L.remove(entry.c.id); entry.c.entity.destroy{raise_destroy=true} end
    observe('cleanup fixture removal releases only its owned host records',next(fixture.computers)==nil and next(fixture.children)==nil)
  end)
  storage=outer; assert(ok,err)
end
return M
