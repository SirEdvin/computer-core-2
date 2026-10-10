-- Reuse the bounded Lua matcher as native-generated application frames.
-- Keep the existing VM source untouched; split only at its public API boundary.
local Source = require('__computer_core_2__.scripts.guest.patterns')
local Compiler = require('__computer_core_2__.scripts.native.compiler')
local Execution = require('__computer_core_2__.scripts.native.execution')
local Limits = require('__computer_core_2__.scripts.guest.limits')
local boundary = assert(Source:find('\nfunction string.find', 1, true))
local function replace(source, before, after)
  local first, last = assert(source:find(before, 1, true))
  assert(not source:find(before, last + 1, true), 'ambiguous native pattern adaptation')
  return source:sub(1, first - 1) .. after .. source:sub(last + 1)
end
local iterator = assert(Source:find('\nfunction string.gmatch', boundary, true))
local substitution = assert(Source:find('\nfunction string.gsub', iterator, true))
local iterator_source = Source:sub(iterator + 1, substitution)
-- The exact engine's iterator terminates with zero returns, not a single nil.
iterator_source = replace(iterator_source, 'if at > #value + 1 then return nil end', 'if at > #value + 1 then return end')
iterator_source = replace(iterator_source, 'if not first then at = #value + 2; return nil end', 'if not first then at = #value + 2; return end')
local substitution_source = Source:sub(substitution + 1)
substitution_source = replace(substitution_source,
  'local compiled, pieces, bytes, at, count = parse(pattern, true), {}, 0, 1, 0',
  'local compiled, pieces, bytes, at, count, piece_count = parse(pattern, true), {}, 0, 1, 0, 0')
substitution_source = replace(substitution_source, [[  local function append(piece)
    bytes = bytes + #piece]], [[  local function append(piece)
    if #piece == 0 then return end
    bytes = bytes + #piece]])
substitution_source = replace(substitution_source, [[    if #pieces == 1024 then pieces = {table.concat(pieces)} end
    pieces[#pieces + 1] = piece]], [[    if piece_count == 1024 then pieces = {table.concat(pieces)}; piece_count = 1 end
    piece_count = piece_count + 1
    pieces[piece_count] = piece]])
substitution_source = replace(substitution_source, 'return table.concat(pieces), count',
  "if piece_count <= 1 then return pieces[1] or '', count end\n  return table.concat(pieces), count")
-- Literal replacement needs no character expansion or temporary key inventory.
-- Use the existing metered plain search, never host pattern matching.
substitution_source = replace(substitution_source, [[      else
        local expanded, expanded_bytes, cursor = {}, 0, 1]], [[      elseif plain_find(replacement, '%', 1, true) == nil then result = replacement
      else
        local expanded, expanded_bytes, cursor = {}, 0, 1]])
-- Copy literal runs through fixed-size probes rather than creating one table
-- slot per byte. Explicit occupancy avoids repeated dense-prefix length scans.
substitution_source = replace(substitution_source, [[        local expanded, expanded_bytes, cursor = {}, 0, 1
        while cursor <= #replacement do
          local letter = sub(replacement, cursor, cursor)
          if letter == '%' then
            cursor = cursor + 1
            letter = sub(replacement, cursor, cursor)
            if letter == '%' then letter = '%'
            elseif letter == '0' then letter = sub(value, at, finish - 1)
            elseif letter >= '1' and letter <= '9' then
              local index = tonumber(letter)
              assert(values[index] ~= nil, 'invalid replacement capture')
              letter = tostring(values[index])
            else error('invalid replacement escape') end
          end
          expanded_bytes = expanded_bytes + #letter
          assert(expanded_bytes <= 65536, 'replacement result byte limit exceeded')
          if #expanded == 1024 then expanded = {table.concat(expanded)} end
          expanded[#expanded + 1] = letter
          cursor = cursor + 1
        end
        result = table.concat(expanded)]], [[        local expanded, expanded_bytes, occupancy, cursor = {}, 0, 0, 1
        while cursor <= #replacement do
          local fragment = sub(replacement, cursor, math.min(#replacement, cursor + 255))
          local marker = plain_find(fragment, '%', 1, true)
          local letter
          if marker == 1 then
            local repetitions = 1
            local pairs = math.floor(#fragment / 2)
            if pairs > 1 and fragment == repeat_text(sub(fragment, 1, 2), pairs) then repetitions = pairs end
            letter = sub(replacement, cursor + 1, cursor + 1)
            if letter == '%' then letter = '%'
            elseif letter == '0' then letter = sub(value, at, finish - 1)
            elseif letter >= '1' and letter <= '9' then
              local index = tonumber(letter)
              assert(values[index] ~= nil, 'invalid replacement capture')
              letter = tostring(values[index])
            else error('invalid replacement escape') end
            assert(#letter * repetitions <= 65536 - expanded_bytes, 'replacement result byte limit exceeded')
            if repetitions > 1 then letter = repeat_text(letter, repetitions) end
            cursor = cursor + 2 * repetitions
          else
            local size = marker and marker - 1 or #fragment
            letter = size == #fragment and fragment or sub(fragment, 1, size)
            cursor = cursor + size
          end
          expanded_bytes = expanded_bytes + #letter
          assert(expanded_bytes <= 65536, 'replacement result byte limit exceeded')
          if occupancy == 1024 then expanded = {table.concat(expanded)}; occupancy = 1 end
          occupancy = occupancy + 1
          expanded[occupancy] = letter
        end
        result = table.concat(expanded)]])
local core = 'local string = ...\n' .. Source:sub(1, boundary) .. [[
return {text=text,parse=parse,initial=initial,locate=locate,captured=captured,matchfrom=matchfrom,sub=sub,plain_find=string.find,rep=string.rep}
]]
local api = [[
local core = ...
local text,parse,initial,locate,captured,matchfrom,sub = core.text,core.parse,core.initial,core.locate,core.captured,core.matchfrom,core.sub
local plain_find = core.plain_find
local repeat_text = core.rep
local string = {}
]] .. Source:sub(boundary + 1, iterator) .. iterator_source .. substitution_source .. '\nreturn string\n'
local M = {}
function M.sources() return core, api end
function M.start(machine, args, method, spend)
  spend('continuation', 1 + 4 * args.n)
  Execution.admit_helper(machine, spend)
  local thread = machine.heap[machine.active]
  assert(#thread.frames < Limits.call_frames, 'native pattern frame quota exceeded')
  return 'continue', {kind = 'helper', service = 'native.pattern.step', method = method, args = args,
    phase = machine.pattern_functions and 'invoke' or 'core',
    core_source = not machine.pattern_functions and core or nil, api_source = not machine.pattern_functions and api or nil}
end
local function compile(machine, source, name, spend)
  local bundle, err = Compiler.compile(source, name, nil, function(amount) spend('compiler', amount) end)
  assert(bundle, err)
  return Execution.register_bundle(machine, bundle, spend)
end
function M.step(machine, p, spend)
  if p.phase == 'core' then
    p.entry = compile(machine, assert(p.core_source, 'missing retained pattern core source'), '=native-pattern-core', spend)
    p.core_source = nil
    p.phase = 'core_result'
    return 'call', {callee = p.entry, args = {n = 1, machine.string_library}}
  elseif p.phase == 'core_result' then
    p.core, p.values, p.entry = assert(p.values[1], 'missing native pattern core'), nil, nil
    p.phase = 'api'
  elseif p.phase == 'api' then
    p.entry = compile(machine, assert(p.api_source, 'missing retained pattern API source'), '=native-pattern-api', spend)
    p.api_source = nil
    p.phase = 'api_result'
    return 'call', {callee = p.entry, args = {n = 1, p.core}}
  elseif p.phase == 'api_result' then
    machine.pattern_functions = assert(p.values[1], 'missing native pattern functions')
    p.core, p.values, p.entry, p.phase = nil, nil, nil, 'invoke'
  elseif p.phase == 'invoke' then
    local callee = assert(Execution.get(machine, machine.pattern_functions, p.method), 'missing native pattern method')
    p.phase = 'result'
    return 'call', {callee = callee, args = p.args}
  elseif p.phase == 'result' then return 'return', p.values
  else error('invalid native pattern phase', 0) end
  return 'continue', p
end
return M
