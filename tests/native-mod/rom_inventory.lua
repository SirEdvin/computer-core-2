-- Diagnostic preflight of actual shipped sources, never a native OS acceptance
-- substitute. Keep every refusal; do not raise production limits for this audit.
local Rom = require('__computer_core_2__.scripts.native.rom')
local VmRom = require('__computer_core_2__.scripts.guest.rom')
local Compiler = require('__computer_core_2__.scripts.native.compiler')
local Execution = require('__computer_core_2__.scripts.native.execution')
return function(check)
 local paths={}
 local resources,changed=0,0
 for path,text in pairs(Rom) do
  resources=resources+1
  assert(VmRom[path]~=nil,'native ROM expanded the pinned allowlist')
  if text~=VmRom[path] then
   assert(path=='/rc/editors/basic.lua' or path=='/rc/editors/advanced.lua' or path=='/rc/modules/main/rc/io.lua','unexpected native adaptation')
   changed=changed+1
  end
 end
 for path in pairs(VmRom) do assert(Rom[path]~=nil,'native ROM omitted pinned resource') end
 check('native ROM preserves exact pinned resource inventory with native editor and IO adaptations',resources==64 and changed==3)
 for path in pairs(Rom) do if path:sub(-4)=='.lua' then paths[#paths+1]=path end end
 table.sort(paths)
 local failures=0
 for _,path in ipairs(paths) do
  local metrics={}
  local bundle,err=Compiler.compile(Rom[path],path,metrics)
  if not bundle then
   failures=failures+1
   log('CC2 NATIVE ROM REFUSAL PROTOTYPE path='..path..' prototype='..tostring(metrics.prototype)..' total='..tostring(metrics.prototypes))
  end
  if bundle then
   local blocks=Execution.executable(bundle)
   for i,proto in ipairs(bundle.prototypes) do assert(#blocks[i]==proto.blocks and #proto.maps==proto.blocks) end
   check('native exact-engine ROM generated bundle loads '..path,true)
  end
  log('CC2 NATIVE ROM COMPILE path='..path..' source_bytes='..#Rom[path]..' ok='..tostring(bundle~=nil)..' generated_bytes='..tostring(metrics.output_bytes or 0)..' parse_work='..tostring(metrics.parse_work or 0)..' generation_work='..tostring(metrics.generate_work or 0)..' diagnostic='..tostring(err):gsub('[\r\n]',' '))
 end
 log('CC2 NATIVE ROM AUDIT total='..#paths..' failed='..failures)
 check('native required shipped-ROM compiler preflight passes without exceptions',failures==0 and #paths==63)
end
