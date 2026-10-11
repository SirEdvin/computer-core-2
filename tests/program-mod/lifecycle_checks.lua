-- Real port movement/repair/removal through the production lifecycle module.
local L=require('__computer_core_2__.scripts.lifecycle')
local M={}
function M.run(m,check,host)
  local outer,observer=storage,check
  check=function(name,value)
    local scoped=storage; storage=outer
    local ok,err=pcall(observer,name,value); storage=scoped; assert(ok,err)
  end
  host(function()
    local c=m.clone
    local left,right=c.sub.left_combinator,c.sub.right_combinator
    local force=game.create_force('cc2-native-lifecycle')
    force.technologies['computer-technology'].researched=true
    c.entity.force=force; L.ensure(c)
    check('native force reconciliation retains two owned port identities',c.sub.left_combinator==left and c.sub.right_combinator==right
      and left.force==force and right.force==force and storage.children[left.unit_number].id==c.id)
    local surface=game.create_surface('cc2-native-ports',{width=64,height=64})
    surface.request_to_generate_chunks({0,0},1); surface.force_generate_chunk_requests()
    -- Factorio cannot teleport this entity type across surfaces. The supported
    -- world operation is a fresh cross-surface clone, never moving old wires.
    local entity=assert(c.entity.clone{position={0,0},surface=surface,force=force})
    local moved=assert(L.clone(c.entity,entity))
    left,right=moved.sub.left_combinator,moved.sub.right_combinator
    check('cross-surface native clone owns fresh local ports without moving source',left.surface==surface and right.surface==surface
      and moved.id~=c.id and c.entity.surface~=surface and c.sub.left_combinator~=left and moved.surface_index==surface.index)
    c=moved
    local old_unit=left.unit_number; assert(left.destroy())
    L.ensure(c); local repaired=c.sub.left_combinator
    check('native repair replaces only missing port and removes stale registry identity',repaired.valid and repaired~=left and repaired.surface==surface
      and c.sub.right_combinator==right and storage.children[old_unit]==nil and storage.children[repaired.unit_number].id==c.id)
    local neighboring=assert(surface.create_entity{name='constant-combinator',position={4,0},force=force})
    L.remove(c.id)
    check('native removal destroys owned ports but not adjacent player entity or source',not repaired.valid and not right.valid
      and neighboring.valid and m.c.entity.valid and m.c.sub.left_combinator.valid and m.chest.valid)
    c.entity.destroy{raise_destroy=true}; neighboring.destroy()
  end)
end
return M
