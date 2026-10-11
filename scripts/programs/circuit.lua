-- Host-only owned circuit capabilities. No engine reference reaches a program.
local Budget=require('__computer_core_2__.scripts.shell.budget')
local Limits=require('__computer_core_2__.scripts.guest.limits')
local Compiler=require('__computer_core_2__.scripts.programs.compiler')
local U=require('__computer_core_2__.scripts.util')
local M={}
local keys={left='left_combinator',right='right_combinator'}
local kinds={item='item',fluid='fluid',virtual='virtual_signal'}
local function plain(t) return type(t)=='table' and getmetatable(t)==nil end
local function integer(n,a,b) return type(n)=='number' and n==math.floor(n) and n>=a and n<=b end
function M.valid_banks(banks)
  if not plain(banks) then return false end
  local sides=0
  for side,bank in pairs(banks) do
    sides=sides+1
    if sides>2 or not keys[side] or not plain(bank) then return false end
    local count=0
    for identity,entry in pairs(bank) do
      count=count+1
      if count>32 or type(identity)~='string' or #identity>264 or not plain(entry) then return false end
      local fields=0
      for key in pairs(entry) do fields=fields+1; if fields>3 or key~='type' and key~='name' and key~='count' then return false end end
      if not kinds[entry.type] or type(entry.name)~='string' or #entry.name>256 or not integer(entry.count,-2147483648,2147483647)
        or identity~=entry.type..':'..entry.name or entry.count==0 then return false end
    end
  end
  return sides==2 and banks.left~=nil and banks.right~=nil
end
local function owned(c,side)
  local port=c.native_ports and c.native_ports[side]
  local child=c.sub and c.sub[keys[side]]
  local owner=child and child.valid and storage.children[child.unit_number]
  return port and child and child.valid and child.name=='computer-combinator' and port.entity==child
    and owner and owner.id==c.id and owner.key==keys[side] and port
end
function M.ensure(c)
  c.native_ports=c.native_ports or {}
  for _,side in ipairs({'left','right'}) do
    local child=c.sub[keys[side]]
    local port=c.native_ports[side]
    if not port or port.entity~=child or not port.section.valid then
      local section=assert(child.get_or_create_control_behavior().add_section(),'cannot create private circuit section')
      section.active=false
      c.native_ports[side]={entity=child,section=section,active=false}
    end
  end
end
function M.clear(c)
  local ok=true
  for _,side in ipairs({'left','right'}) do
    local port=owned(c,side)
    if port and port.section.valid then
      local success=pcall(function()
        port.section.active=false
        -- Never mutate the filters of a section reassigned to a shared group.
        if port.section.is_manual and port.section.group=='' then port.section.filters={} end
        port.active=false
      end)
      ok=ok and success
    elseif port then port.active=false end
  end
  c.native_clear_pending=not ok
  return ok
end
local function body(c)
  local e=c.entity
  return c.backend=='event-shell' and not c.personal and not c.external and e and e.valid
    and e.name=='blue-computer-interface-entity' and storage.computers[c.id]==c and storage.units[e.unit_number]==c.id
end
local function powered(c) return body(c) and c.entity.energy>0 end
local function lease(c,controller)
  local owner=controller and controller.owner
  local technology=body(c) and c.entity.force.technologies['computer-technology']
  return technology and technology.researched and plain(owner) and owner.id==c.id
    and owner.force==c.entity.force.index and owner.surface==c.entity.surface.index
end
function M.priority(ledger,tick)
  if ledger.native_priority_tick==tick then return end
  -- The production ingress/readback paths call this before ordinary admission.
  -- Reserved credits are spent once, not refreshed or a separate allowance.
  ledger.native_priority_tick=tick
  local count=0
  for _,id in ipairs(U.keys(storage.computers or {})) do
    local c=storage.computers[id]
    local retained=c.backend=='event-shell' and plain(c.shell) and c.shell.controller
    local controller=plain(retained) and retained or nil
    -- Inspect only bounded header fields before cleanup admission. Unsupported
    -- application graphs are retained inertly, never dereferenced as controllers.
    local known=controller and controller.version==1 and controller.compiler==Compiler.VERSION and controller.api==Compiler.API
      and (controller.status=='running' or controller.status=='paused' or controller.status=='stopped' or controller.status=='faulted')
    local active=c.native_ports and (c.native_ports.left and c.native_ports.left.active or c.native_ports.right and c.native_ports.right.active)
    local registered=ledger.machines and ledger.machines[id]==c.shell
    if retained or active or c.native_clear_pending then
      if count>=Limits.active_computers then break end
      local needs=known and registered and (controller.status=='running' or controller.status=='paused' and powered(c)) or active or c.native_clear_pending
      if needs then
        count=count+1
        if Budget.admit(ledger,id,{execution=1,filesystem=128,table=64}) then
          c.native_cleanup_tick=tick
          if not known or c.os_error or not powered(c) or not lease(c,controller) or c.shell.status~='ready'
            or controller.status=='stopped' or controller.status=='faulted' or c.native_clear_pending then
            M.clear(c)
            if known then
              if not lease(c,controller) then controller.status='faulted'; controller.message='Computer ownership/research changed'
              elseif controller.status=='running' and not powered(c) then controller.status='paused' end
            end
          end
        end
      end
    end
  end
end
function M.service(c,state,tick)
  local service={}
  function service.prepare(controller)
    -- Called only after whole-callback admission, which includes bounded
    -- failure cleanup. A newly registered/restored session may not have been
    -- eligible during the earlier priority sweep; do not borrow another cap.
    assert(body(c) and c.shell==state and state.controller==controller and lease(c,controller) and powered(c),'unauthorized/unpowered circuit controller')
    assert(not c.native_clear_pending,'circuit cleanup pending')
    c.native_cleanup_tick=tick
  end
  function service.identity()
    assert(body(c),'computer body unavailable')
    return {id=c.id,force=c.entity.force.index,surface=c.entity.surface.index}
  end
  function service.validate(controller,side)
    assert(body(c) and c.shell==state and state.controller==controller and lease(c,controller) and powered(c),'unauthorized/unpowered circuit controller')
    assert(c.native_cleanup_tick==tick and not c.native_clear_pending,'circuit cleanup admission pending')
    assert(controller.generation==state.controller.generation,'stale program generation')
    assert(keys[side],'side must be left or right')
    local port=assert(owned(c,side),'owned circuit port unavailable')
    assert(port.entity.force.index==controller.owner.force and port.entity.surface.index==controller.owner.surface,'circuit port ownership changed')
    assert(port.section.valid and port.section.is_manual and port.section.group=='','private circuit section unavailable or reassigned')
    return port
  end
  function service.signal(kind,name)
    assert(kinds[kind] and type(name)=='string' and #name<=256,'invalid signal identity')
    assert(prototypes[kinds[kind]][name],'unknown signal prototype')
  end
  function service.read(controller,side,wire,kind,name)
    local port=service.validate(controller,side); service.signal(kind,name)
    assert(wire=='red' or wire=='green','wire must be red or green')
    local network=port.entity.get_circuit_network(defines.wire_connector_id['circuit_'..wire])
    return network and network.get_signal{type=kind,name=name,quality='normal'} or 0
  end
  function service.publish(controller,banks)
    assert(M.valid_banks(banks),'malformed output banks')
    local plans={}
    for _,side in ipairs({'left','right'}) do
      local port=service.validate(controller,side)
      local filters={}
      for _,identity in ipairs(U.keys(banks[side])) do
        local entry=banks[side][identity]; service.signal(entry.type,entry.name)
        filters[#filters+1]={value={type=entry.type,name=entry.name,quality='normal',comparator='='},min=entry.count}
      end
      plans[#plans+1]={side=side,port=port,filters=filters}
    end
    -- Validate both targets before the first engine write. Unexpected engine
    -- errors cannot promise rollback; clear only our private sections instead.
    local ok,err=pcall(function()
      for _,plan in ipairs(plans) do
        service.validate(controller,plan.side)
        plan.port.section.filters=plan.filters; plan.port.section.active=#plan.filters>0; plan.port.active=#plan.filters>0
      end
    end)
    if not ok then M.clear(c); error('circuit publication fault: '..tostring(err),0) end
  end
  function service.clear() return M.clear(c) end
  return service
end
return M
