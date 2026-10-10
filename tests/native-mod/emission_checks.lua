local Compiler = require('__computer_core_2__.scripts.native.compiler')
local Codegen = require('__computer_core_2__.scripts.native.codegen')
local Execution = require('__computer_core_2__.scripts.native.execution')
local Limits = require('__computer_core_2__.scripts.guest.limits')
local VM = require('__computer_core_2__.scripts.guest.vm')
return function(check)
  local metrics = {}
  -- Compaction accepts the former 500-statement case (127303 bytes). Keep the
  -- same production cap; use a larger authored input to exercise its refusal.
  local bundle, failure = Compiler.compile('local x=0;' .. string.rep('x=x+1;', 600), '=native-emission-cap', metrics)
  log('CC2 NATIVE EMISSION REFUSAL reason=' .. tostring(failure) .. ' bytes=' .. tostring(metrics.output_bytes))
  check('native generated output refuses before exceeding limit', not bundle
    and failure == 'native generated output limit exceeded' and metrics.output_bytes <= Codegen.OUTPUT_BYTES)
  bundle, failure = Compiler.compile('local t={}; t:' .. string.rep('x', 2000) .. '()', '=native-block-cap')
  check('native block size refuses excessive uncheckpointed code', not bundle and failure == 'native generated block byte limit exceeded')
  bundle, failure = Compiler.compile('return ' .. string.rep('1,', Limits.tuple_values) .. '1', '=native-list-cap')
  check('native literal expression lists are statically bounded', not bundle and failure == 'native expression list limit exceeded')
  local deep = 'return 0' .. string.rep('+1', 128)
  bundle, failure = Compiler.compile(deep, '=native-depth-cap')
  check('native generation guards left-associated recursion', not bundle and failure == 'native generation nesting limit exceeded')
  local admitted = 0
  metrics = {}
  bundle, failure = Compiler.compile('return 1', '=native-shared-refusal', metrics, function(amount)
    if metrics.phase == 'generate' then error('fixture emission admission refused', 0) end
    admitted = admitted + amount
  end)
  check('native generation cannot bypass shared admission', not bundle and failure == 'fixture emission admission refused' and admitted > 0)
  local literal = string.rep(']]\nend; game.print("escape");--\0', 80)
  bundle = assert(Compiler.compile('return ' .. string.format('%q', literal), '=native-long-literal'))
  local machine = Execution.new(bundle)
  local previous, calls = VM.run, 0
  VM.run = function() calls = calls + 1; error('unexpected VM execution', 0) end
  local ok, result = pcall(function()
    return Execution.run(machine, bundle, Execution.executable(bundle), 100)
  end)
  VM.run = previous
  check('native generated execution never dispatches guest VM', ok and result == 'return' and calls == 0)
  check('hostile long source literal remains inert exact data', machine.result[1] == literal)
  check('native bundles contain only versioned source and metadata', bundle.version == Codegen.VERSION
    and bundle.source and bundle.generated and bundle.prototypes and not bundle.instructions)
  local invalid = {version = Codegen.VERSION + 1, generated = 'return game', name = '=bad-version'}
  check('native host load rejects unsupported bundle formats', not pcall(Execution.executable, invalid))
  invalid = {version = Codegen.VERSION, generated = string.rep(' ', Codegen.OUTPUT_BYTES + 1), name = '=bad-size'}
  check('native host load bounds bytes before opaque compilation', not pcall(Execution.executable, invalid))
  -- This boundary probe is trusted test code, not a compiler entry point.
  local probe = {version = Codegen.VERSION, name = '=minimal-environment', generated = 'return {game,script,storage,_G,debug,load,require,coroutine}' }
  check('generated-code loader has no privileged global environment', next(Execution.executable(probe)) == nil)
  check('native compiler recovers after all generation refusals', Compiler.compile('return 42', '=native-recovered') ~= nil)
  bundle, failure = Compiler.compile('local x=1\nlocal =', '=native-syntax-location')
  check('native syntax refusal identifies source line', not bundle and failure:find('=native-syntax-location:2:', 1, true))
  bundle = assert(Compiler.compile('local x=1\nreturn x+nil', '=native-runtime-location'))
  machine = Execution.new(bundle)
  local status = Execution.run(machine, bundle, Execution.executable(bundle), 100)
  check('native runtime failure identifies source line', status == 'error' and machine.error.source == '=native-runtime-location' and machine.error.line == 2)
end
