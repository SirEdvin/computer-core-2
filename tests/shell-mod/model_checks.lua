-- Native prototype/research checks. Bodies here are prototype-only, not proof
-- of blue build/clone/runtime routing (task 4.3) or client graphics (task 5.2).
local M={}
function M.initial(check)
  local fresh=game.create_force('blue-fresh')
  local old_recipe=fresh.recipes['computer-recipe']
  local blue_recipe=fresh.recipes['blue-computer-recipe']
  check('fresh forces have both computer recipes locked by existing research',not old_recipe.enabled and not blue_recipe.enabled)
  fresh.technologies['computer-technology'].researched=true
  check('existing research unlocks both computer recipes without new technology',old_recipe.enabled and blue_recipe.enabled and fresh.technologies['blue-computer-technology']==nil)
  check('actual recipe products identify separate models with matching costs/time',serpent.line(old_recipe.ingredients,{sortkeys=true})==serpent.line(blue_recipe.ingredients,{sortkeys=true})
    and old_recipe.energy==blue_recipe.energy and old_recipe.products[1].name=='computer-item' and blue_recipe.products[1].name=='blue-computer-item')
  local legacy=game.create_force('blue-previously-researched')
  legacy.technologies['computer-technology'].researched=true
  legacy.recipes['blue-computer-recipe'].enabled=false -- Emulate a missing added unlock in a pre-update force.
  local locked=game.create_force('blue-still-locked')
  local surface=game.surfaces[1]
  local vm=assert(surface.create_entity{name='computer-interface-entity',position={24,36},force=fresh,raise_built=false})
  local blue=assert(surface.create_entity{name='blue-computer-interface-entity',position={30,36},force=fresh,raise_built=false})
  vm.energy=5000000; blue.energy=5000000
  local a,b=vm.bounding_box,blue.bounding_box
  check('engine creates blue and original bodies with identical footprint health and power buffer',vm.health==blue.health and blue.health==250
    and vm.electric_buffer_size==blue.electric_buffer_size and blue.electric_buffer_size==5000000
    and a.right_bottom.x-a.left_top.x==b.right_bottom.x-b.left_top.x and a.right_bottom.y-a.left_top.y==b.right_bottom.y-b.left_top.y)
  return {fresh=fresh.index,legacy=legacy.index,locked=locked.index,vm=vm,blue=blue,blue_unit=blue.unit_number,vm_unit=vm.unit_number}
end
function M.reload(saved,check,configured)
  local old=game.forces[saved.legacy]
  local locked=game.forces[saved.locked]
  if configured then
    check('real configuration change reconciles previously researched force only',old.technologies['computer-technology'].researched
      and old.recipes['blue-computer-recipe'].enabled and old.recipes['computer-recipe'].enabled
      and not locked.recipes['blue-computer-recipe'].enabled and not locked.recipes['computer-recipe'].enabled)
  else
    check('ordinary on_load does not reconcile force unlocks',not old.recipes['blue-computer-recipe'].enabled)
  end
  check('blue prototype survives actual map reload without replacing original body',saved.vm.valid and saved.blue.valid
    and saved.vm.unit_number==saved.vm_unit and saved.blue.unit_number==saved.blue_unit
    and saved.vm.name=='computer-interface-entity' and saved.blue.name=='blue-computer-interface-entity')
  saved.vm.destroy{raise_destroy=true}; saved.blue.destroy{raise_destroy=true}
end
return M
