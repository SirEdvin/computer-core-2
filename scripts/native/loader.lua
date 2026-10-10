-- Guest source loading always uses the bounded compiler, never host load.
local Compiler = require('__computer_core_2__.scripts.native.compiler')
local Execution = require('__computer_core_2__.scripts.native.execution')
local Files = require('__computer_core_2__.scripts.native.files')
local Limits = require('__computer_core_2__.scripts.guest.limits')
local M = {}
function M.install(machine)
  if machine.loader_installed then return end
  for _,name in ipairs({'load','loadfile','dofile'}) do Execution.service(machine,name) end
  machine.loader_installed = true
end
function M.services(admit)
  assert(type(admit)=='function','native loading admission required')
  local function spend(domain,amount)
    assert(admit(domain,amount)~=false,'native '..domain..' work quota exceeded')
  end
  local function compile(machine,source,name,mode,environment)
    if mode~=nil then
      if type(mode)~='string' then return {n=2,nil,'only source text loading is supported'} end
      local admitted,err=pcall(spend,'compiler',1+#mode)
      if not admitted then return {n=2,nil,tostring(err):sub(1,4096)} end
      if not mode:find('t',1,true) then return {n=2,nil,'only source text loading is supported'} end
    end
    if type(source)~='string' then return {n=2,nil,'source must be a string (reader functions are not supported)'} end
    if type(name)=='string' and #name<=Limits.string_bytes then
      local admitted,err=pcall(spend,'compiler',1+4*#name)
      if not admitted then return {n=2,nil,tostring(err):sub(1,4096)} end
    end
    if environment~=nil then
      Execution.validate_value(machine,environment)
      assert(Execution.type(machine,environment)=='table','native table environment expected')
    end
    local bundle,err=Compiler.compile(source,name,nil,function(amount) spend('compiler',amount) end)
    if not bundle then return {n=2,nil,err} end
    local ok,entry=pcall(Execution.register_bundle,machine,bundle,spend,environment)
    if not ok then return {n=2,nil,tostring(entry):sub(1,4096)} end
    return {n=1,entry}
  end
  local function file(machine,args)
    local ok,source=pcall(Files.read_source,machine,args[1],function(amount) spend('filesystem',amount) end)
    if not ok then return {n=2,nil,tostring(source):sub(1,4096)} end
    return compile(machine,source,'='..args[1],args[2],args[3])
  end
  return {
    load=function(machine,args) return 'return',compile(machine,args[1],args[2],args[3],args[4]) end,
    loadfile=function(machine,args) return 'return',file(machine,args) end,
    dofile=function(machine,args)
      Execution.admit_helper(machine,spend)
      local result=file(machine,{n=1,args[1]})
      assert(result[1],result[2])
      return 'continue',{kind='helper',service='native.load.step',phase='call',callee=result[1]}
    end,
    ['native.load.step']=function(_,p)
      if p.phase=='call' then
        p.phase='result'
        return 'call',{callee=p.callee,args={n=0}}
      end
      assert(p.phase=='result','invalid native source call phase')
      return 'return',p.values
    end,
  }
end
return M
