-- Untimed structural fixtures still use real per-domain admission. Production
-- and initialization-pressure tests instead share the caller's scheduler ledger.
local Shell=require('__computer_core_2__.scripts.shell.runtime')
local Budget=require('__computer_core_2__.scripts.shell.budget')
return function(disk,columns,rows)
  local ledger={version=1}
  Budget.begin(ledger,0)
  local state,err=Shell.new(disk,columns,rows,function(cost) return Budget.admit(ledger,1,cost) end)
  assert(state,err)
  return state
end
