-- Atomic admission using the existing VM scheduler's durable ledger layout.
-- This module imports limits only; it never dispatches or grants a second cap.
local Limits=require('__computer_core_2__.scripts.guest.limits')
local M={}
local domains={
  execution={field='execution_budget',counter='instructions',per=Limits.instructions_per_computer,total=Limits.instructions_per_tick},
  collection={field='execution_budget',counter='collection',per=Limits.collection_work_per_computer,total=Limits.collection_work_per_tick},
}
local order={'execution','collection','compiler','string','terminal','filesystem','event','advance','table','continuation'}
for _,name in ipairs(order) do
  if not domains[name] then domains[name]={field=name=='compiler' and 'compile_budget' or name..'_budget',
    counter='used',per=Limits[name..'_work_per_computer'],total=Limits[name..'_work_per_tick']} end
end
local function integer(n)
  return type(n)=='number' and n>=0 and n<9007199254740992 and n==math.floor(n)
end
function M.begin(state,tick)
  assert(state.version==1 and integer(tick),'invalid shell work ledger')
  -- Validate every retained clock before changing any ledger.
  for _,name in ipairs(order) do
    local b=state[domains[name].field]
    assert(not b or b.tick==nil or tick>=b.tick,'work tick cannot move backwards')
  end
  for _,name in ipairs(order) do
    local cap=domains[name]
    local b=state[cap.field]
    if not b or b.tick~=tick then
      if cap.field=='execution_budget' then state[cap.field]={tick=tick,instructions=0,collection=0,machines={}}
      else state[cap.field]={tick=tick,used=0,limit=cap.total,machines={}} end
    end
  end
end
function M.remaining(state,id,name)
  local cap=assert(domains[name],'unknown work domain')
  local b=assert(state[cap.field],'work tick not initialized')
  local machine=b.machines[id]
  return math.min(cap.total-(b[cap.counter] or 0),cap.per-(machine and machine[cap.counter] or 0))
end
function M.admit(state,id,cost)
  assert(integer(id) and id>0 and type(cost)=='table' and getmetatable(cost)==nil,'invalid work request')
  local fields=0
  for name,amount in pairs(cost) do
    fields=fields+1
    assert(fields<=#order and domains[name] and integer(amount),'invalid work charge')
  end
  for _,name in ipairs(order) do
    local amount=cost[name] or 0
    if amount>M.remaining(state,id,name) then return false end
  end
  for _,name in ipairs(order) do
    local amount=cost[name] or 0
    if amount>0 then
      local cap=domains[name]
      local b=state[cap.field]
      local machine=b.machines[id]
      if not machine then
        machine=cap.field=='execution_budget' and {instructions=0,collection=0} or {used=0,limit=cap.per}
        b.machines[id]=machine
      end
      machine[cap.counter]=(machine[cap.counter] or 0)+amount
      b[cap.counter]=(b[cap.counter] or 0)+amount
    end
  end
  return true
end
return M
