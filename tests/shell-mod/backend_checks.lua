local Backend=require('__computer_core_2__.scripts.backend')
local Shell=require('__computer_core_2__.scripts.shell.runtime')
local Scheduler=require('__computer_core_2__.scripts.shell.scheduler')
local VM=require('__computer_core_2__.scripts.guest.vm')
local Compiler=require('__computer_core_2__.scripts.guest.compiler')
local new=require('construct')
local M={}
local function packed(value) return serpent.line(value,{sortkeys=true}) end
function M.initial(check)
  local vm=VM.new(assert(Compiler.compile('return 1','=backend-readback')))
  local original={id=31,fs={['/']={type='dir'}},guest=vm}
  local before=packed(original)
  check('absent backend tag selects original VM readback',Backend.kind(original)=='vm'
    and Backend.files(original)==vm.disk.fs and Backend.display(original)==vm.display and Backend.running(original))
  check('VM backend inspection does not execute or rewrite state',packed(original)==before and vm.instructions==0)
  local personal={personal=true,fs=original.fs}
  check('personal computer without backend remains stopped-before-boot VM',Backend.kind(personal)=='vm'
    and Backend.files(personal)==personal.fs and Backend.display(personal)==nil and Backend.status(personal)=='boot' and not Backend.running(personal))
  local shell=new({fs={['/']={type='dir'},['/data']={type='file',text='committed'}}},51,19)
  local c={id=32,backend='event-shell',shell=shell,fs=original.fs,guest=vm}
  before=packed(shell)
  local files,err=Backend.files(c)
  check('initializing shell cannot fall through to stale host or VM files',files==nil and err:find('not ready',1,true)
    and Backend.display(c)==shell.display and Backend.status(c)=='initializing' and Backend.running(c))
  check('shell readback performs no initialization or migration',packed(shell)==before)
  assert(Shell.handle(shell,{n=1,'boot'},function() return true end))
  check('shell readback selects only its committed disk and display',Backend.files(c)==shell.disk.fs
    and Backend.files(c)~=original.fs and Backend.files(c)~=vm.disk.fs and Backend.display(c)~=vm.display and Backend.status(c)=='ready')
  local old=shell.disk
  shell.disk={fs={['/']={type='dir'},['/replacement']={type='file',text='published'}},cwd='/',nodes=2,bytes=9,paths={'/','/replacement'}}
  check('backend reads authoritative replacement rather than boot-time aliases',Backend.files(c)==shell.disk.fs
    and Backend.files(c)['/replacement'].text=='published' and not Backend.files(c)['/data'] and old.fs['/data'].text=='committed')
  local ledger={version=1}
  assert(Scheduler.push(shell,ledger,c.id,1,{n=1,'shutdown'})); assert(Scheduler.step(shell,ledger,c.id,1,true))
  check('shell stopped status preserves committed readback',Backend.status(c)=='stopped' and not Backend.running(c) and Backend.files(c)==shell.disk.fs)
  local unknown={id=33,backend='native',guest=vm,shell=shell,fs=old.fs,experiment={version=5,retained=17}}
  before=packed(unknown)
  check('unknown backend never chooses VM or shell as fallback',Backend.kind(unknown)==nil and Backend.files(unknown)==nil
    and Backend.display(unknown)==nil and Backend.status(unknown)=='recovery' and not Backend.running(unknown))
  check('unknown backend inspection preserves all recovery data',packed(unknown)==before and unknown.experiment.retained==17)
  personal.backend='event-shell'; personal.shell=shell
  check('tagged personal shell is rejected rather than executing unsupported model',Backend.kind(personal)==nil and Backend.status(personal)=='recovery')
  local invalid=new(nil,51,19); invalid.version=99
  local incompatible={backend='event-shell',shell=invalid,guest=vm,fs=old.fs}; before=packed(invalid)
  check('incompatible shell metadata is visible without conversion or fallback',Backend.status(incompatible)=='recovery'
    and Backend.files(incompatible)==nil and Backend.display(incompatible)==nil and packed(invalid)==before)
  return {computer=c,disk=shell.disk,display=shell.display,unknown=unknown,invalid=incompatible,
    before=packed(c),unknown_before=packed(unknown),invalid_before=packed(incompatible)}
end
function M.observe(saved)
  assert(packed(saved.computer)==saved.before and packed(saved.unknown)==saved.unknown_before
    and packed(saved.invalid)==saved.invalid_before,'backend readback changed state during load')
end
function M.reload(saved,check)
  M.observe(saved)
  local c=saved.computer
  check('cold backend readback preserves authoritative disk and display identities',Backend.files(c)==saved.disk.fs
    and Backend.display(c)==saved.display and Backend.status(c)=='stopped' and not Backend.running(c))
  check('cold backend inspection cannot execute retained unknown or incompatible state',Backend.files(saved.unknown)==nil
    and Backend.status(saved.unknown)=='recovery' and Backend.status(saved.invalid)=='recovery'
    and packed(saved.unknown)==saved.unknown_before and packed(saved.invalid)==saved.invalid_before)
end
return M
