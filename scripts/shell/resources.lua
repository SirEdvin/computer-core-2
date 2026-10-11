-- Read-only data resources for the rewritten shell, not executable VM ROM.
return {
  ['/rom']={type='dir'},
  ['/rom/help.txt']={type='file',text='Blue computer: native edit and restricted Lua controllers. Ctrl+S saves; Ctrl+Q exits. Copy /rom/examples/stock-controller.lua locally, edit, save, then run PATH. No loops, modules, general Lua, pipes or substitutions.\n'},
  ['/rom/examples']={type='dir'},
  ['/rom/examples/stock-controller.lua']={type='file',text=require('__computer_core_2__.resources.programs.stock-controller')},
}
