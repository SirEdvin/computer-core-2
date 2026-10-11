-- Read-only data resources for the rewritten shell, not executable VM ROM.
return {
  ['/rom']={type='dir'},
  ['/rom/help.txt']={type='file',text='Blue computer: native edit and restricted Lua controllers. Use Save / Exit editor buttons above the terminal; dirty exit offers Save / Discard / Cancel. Factorio suppresses custom shortcuts while typing. Copy /rom/examples/stock-controller.lua locally, edit, save, then run PATH. No loops, modules, general Lua, pipes or substitutions.\n'},
  ['/rom/examples']={type='dir'},
  ['/rom/examples/stock-controller.lua']={type='file',text=require('__computer_core_2__.resources.programs.stock-controller')},
}
