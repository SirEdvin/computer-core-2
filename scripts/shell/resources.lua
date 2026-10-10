-- Read-only data resources for the rewritten shell, not executable VM ROM.
return {
  ['/rom']={type='dir'},
  ['/rom/help.txt']={type='file',text='Blue computer: trusted built-in shell only. Files are data. No editors, Lua programs, modules, pipes or substitutions.\n'},
}
