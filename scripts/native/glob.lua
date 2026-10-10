-- Bounded byte-wise local/ROM globbing; never host patterns or peer mounts.
local Files=require('__computer_core_2__.scripts.native.files')
local Model=require('__computer_core_2__.scripts.filesystem')
local Limits=require('__computer_core_2__.scripts.guest.limits')
local M={}
local function matches(pattern,name,spend)
  -- The iterative last-star retry can revisit a suffix, at most m*n byte tests.
  -- Reserve the complete conservative bound before any opaque string work.
  spend(1+4*(#pattern+1)*(#name+1))
  local p,n,star,retry=1,1,nil,nil
  while n<=#name do
    local token=pattern:sub(p,p)
    if token=='?' or (token~='*' and token==name:sub(n,n)) then p,n=p+1,n+1
    elseif token=='*' then star,retry=p,n; p=p+1
    elseif star then retry=retry+1; n,p=retry,star+1
    else return false end
  end
  while pattern:sub(p,p)=='*' do p=p+1 end
  return p>#pattern
end
function M.find(machine,name,spend)
  assert(type(name)=='string' and #name<=1024,'invalid path')
  spend(1+16*(#name+#machine.disk.cwd+1))
  local normalized=Model.path(machine.disk,name=='' and '/' or name)
  if not normalized:find('*',1,true) and not normalized:find('?',1,true) then
    return Files.exists(machine,normalized,spend) and {normalized} or {}
  end
  local frontier={'/'}
  for component in normalized:gmatch('[^/]+') do
    local next_paths={}
    for _,parent in ipairs(frontier) do
      if Files.is_dir(machine,parent,spend) then
        for _,leaf in ipairs(Files.list(machine,parent,spend)) do
          if matches(component,leaf,spend) then
            spend(1+4*(#parent+#leaf+1))
            local candidate=parent=='/' and '/'..leaf or parent..'/'..leaf
            assert(#candidate<=1024,'normalized path exceeds length limit')
            if Files.exists(machine,candidate,spend) then
              assert(#next_paths<Limits.table_keys,'native glob result quota exceeded')
              next_paths[#next_paths+1]=candidate
            end
          end
        end
      end
    end
    frontier=next_paths
    if #frontier==0 then break end
  end
  table.sort(frontier,function(a,b) spend(1+#a+#b); return a<b end)
  return frontier
end
return M
