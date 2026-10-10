-- Complete original prototype comparison against the frozen pre-blue source.
-- Only the added shared research unlock is permitted to differ.
local original=assert(cc2_shell_original_prototypes,'missing data-stage original capture')
cc2_shell_original_prototypes=nil
local function same(a,b,path)
  assert(type(a)==type(b),'prototype type changed: '..path)
  if type(a)~='table' then assert(a==b,'prototype changed: '..path); return end
  for k,v in pairs(a) do same(v,b[k],path..'.'..tostring(k)) end
  for k in pairs(b) do assert(a[k]~=nil,'extra original prototype field: '..path..'.'..tostring(k)) end
end
for _,expected in ipairs(original) do
  local actual=table.deepcopy(assert(data.raw[expected.type][expected.name]))
  if expected.name=='computer-technology' then
    assert(#actual.effects==2 and actual.effects[2].type=='unlock-recipe' and actual.effects[2].recipe=='blue-computer-recipe')
    table.remove(actual.effects,2)
  end
  same(expected,actual,expected.name)
end
local kind='electric-energy-interface'
local blue=data.raw[kind]['blue-computer-interface-entity']
local vm=data.raw[kind]['computer-interface-entity']
local normalized=table.deepcopy(blue)
normalized.name=vm.name; normalized.icon=vm.icon; normalized.minable.result=vm.minable.result; normalized.picture.filename=vm.picture.filename
same(vm,normalized,'blue body defaults')
assert(blue.picture.filename=='__computer_core_2__/graphics/entities/blue-computer_hr.png' and blue.icon=='__computer_core_2__/graphics/icons/blue-computer-icon.png')
local item=table.deepcopy(data.raw.item['blue-computer-item'])
local old_item=data.raw.item['computer-item']
assert(item.place_result==blue.name and item.icon==blue.icon)
item.name=old_item.name; item.icon=old_item.icon; item.order=old_item.order; item.place_result=old_item.place_result
same(old_item,item,'blue item defaults')
local recipe=table.deepcopy(data.raw.recipe['blue-computer-recipe'])
local old_recipe=data.raw.recipe['computer-recipe']
assert(recipe.results[1].name=='blue-computer-item' and #recipe.results==1 and not recipe.enabled)
recipe.name=old_recipe.name; recipe.results=table.deepcopy(old_recipe.results)
same(old_recipe,recipe,'blue recipe costs/defaults')
assert(data.raw['constant-combinator']['computer-combinator'].selection_priority>blue.selection_priority)
log('CC2 BLUE DATA PASS original prototypes preserved and blue model inherits geometry/power/costs')
