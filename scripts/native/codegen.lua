-- Native continuation emission. No AST or symbolic instructions survive compilation.
local Limits = require('__computer_core_2__.scripts.guest.limits')
local M = {VERSION = 4, OUTPUT_BYTES = 131072, BLOCKS = 8192, BLOCK_BYTES = 1024, MERGE_STEPS = 8}
local function quote(value) return string.format('%q', value) end
local function temp(slot) return 't[' .. slot .. ']' end
local function scalar(slot) return temp(slot) .. '[1]' end

function M.generate(ast, metrics, spend)
  metrics.generate_work, metrics.output_bytes = 0, 0
  metrics.temp_slots, metrics.temp_reuses = 0, 0
  metrics.phase = 'generate'
  local function charge(amount)
    amount = amount or 1
    if amount > Limits.compiler_generate_work - metrics.generate_work then
      error('native generation work limit exceeded', 0)
    end
    if spend then spend(amount) end
    metrics.generate_work = metrics.generate_work + amount
  end
  local prototypes, ids, definitions, nodes = {}, {}, {}, {}
  local depth = 0
  local function guarded(fn, ...)
    depth = depth + 1
    if depth > Limits.compiler_generate_depth then error('native generation nesting limit exceeded', 0) end
    charge()
    local result = table.pack(fn(...))
    depth = depth - 1
    return table.unpack(result, 1, result.n)
  end
  local function collect(node)
    return guarded(function()
      if node.node_type == 'functiondef' then
        charge(#prototypes + 1)
        ids[node] = #prototypes + 1
        prototypes[#prototypes + 1] = {source = node.source, params = {}, upvalues = {}, maps = {}, constants = {}}
        nodes[#nodes + 1] = node
      end
      local owner = node
      while owner.node_type ~= 'functiondef' do charge(); owner = owner.parent_scope end
      local proto = prototypes[ids[owner]]
      proto.locals = proto.locals or 0
      for _, def in ipairs(node.locals) do
        charge()
        proto.locals = proto.locals + 1
        definitions[def] = {owner = ids[owner], slot = proto.locals}
      end
      local stat = node.body.first
      while stat do
        charge()
        if stat.node_type == 'ifstat' then
          for _, branch in ipairs(stat.ifs) do collect(branch) end
          if stat.elseblock then collect(stat.elseblock) end
        elseif stat.body then collect(stat) end
        stat = stat.next
      end
      if node.node_type == 'functiondef' then
        for _, child in ipairs(node.func_protos) do collect(child) end
      end
    end)
  end
  collect(ast)
  metrics.prototypes = #nodes
  local chunks, total_blocks = {}, 0
  local function output(text)
    charge(#text)
    if #text > M.OUTPUT_BYTES - metrics.output_bytes then error('native generated output limit exceeded', 0) end
    metrics.output_bytes = metrics.output_bytes + #text
    chunks[#chunks + 1] = text
  end
  output('local r,b,c={};')
  for pid, node in ipairs(nodes) do
    metrics.prototype = pid
    local proto, blocks, slots, moves = prototypes[pid], {}, 0, {}
    local free_slots, leased = {}, nil
    -- Compile nested expressions/statements with their own temporary leases.
    -- Caller-owned destinations, operands and loop controls stay reserved until
    -- their complete continuation region has been emitted, including transfers.
    local function with_temps(fn, ...)
      local parent, owned = leased, {}
      leased = owned
      local result = table.pack(guarded(fn, ...))
      leased = parent
      for i = #owned, 1, -1 do
        charge()
        free_slots[#free_slots + 1] = owned[i]
      end
      return table.unpack(result, 1, result.n)
    end
    local upvalues = {}
    for index, def in ipairs(node.upvals) do
      charge()
      upvalues[def] = index
      local parent = def.parent_def
      if parent.scope.node_type == 'env_scope' then
        proto.upvalues[index] = {kind = 'environment'}
      elseif parent.def_type == 'local' then
        proto.upvalues[index] = {kind = 'local', slot = assert(definitions[parent]).slot}
      else
        local parent_node = node.parent_scope
        while parent_node.node_type ~= 'functiondef' do charge(); parent_node = parent_node.parent_scope end
        local found
        for i, candidate in ipairs(parent_node.upvals) do charge(); if candidate == parent then found = i; break end end
        proto.upvalues[index] = {kind = 'upvalue', slot = assert(found)}
      end
    end
    if node.is_method then proto.params[1] = definitions[node.locals[1]].slot end
    for _, param in ipairs(node.params) do charge(); proto.params[#proto.params + 1] = definitions[param.reference_def].slot end
    if #proto.params > Limits.tuple_values or #proto.upvalues > Limits.tuple_values then
      error('native frame binding limit exceeded', 0)
    end
    proto.vararg = node.is_vararg
    local function slot()
      charge()
      local id = free_slots[#free_slots]
      if id then
        free_slots[#free_slots] = nil
        metrics.temp_reuses = metrics.temp_reuses + 1
      else slots = slots + 1; id = slots end
      assert(leased, 'native temporary outside continuation lease')
      leased[#leased + 1] = id
      return id
    end
    local function add(code, at)
      charge()
      if #code > M.BLOCK_BYTES then error('native generated block byte limit exceeded', 0) end
      if total_blocks >= M.BLOCKS then error('native generated block limit exceeded', 0) end
      total_blocks = total_blocks + 1
      local id = #blocks + 1
      blocks[id] = code
      local pos = at and (at.local_token or at.return_token or at.function_token or at.op_token or at)
      proto.maps[id] = {line = pos and pos.line or 1, column = pos and pos.column or 1}
      return id
    end
    local function move(code, next, at)
      local id = add(code .. ';f.pc=' .. next, at)
      moves[id] = next
      return id
    end
    local function ref(node)
      local def = node.reference_def
      if def.def_type == 'local' then return 'a.r(f,' .. definitions[def].slot .. ')' end
      return 'a.u(f,' .. assert(upvalues[def]) .. ')'
    end
    local expression, list, statement, scope
    local labels, exits = {}, {}
    local function label(stat)
      if not labels[stat] then labels[stat] = add('', stat) end
      return labels[stat]
    end
    list = function(expressions, dest, next, prefix, single)
      charge(#expressions + 1)
      if #expressions > Limits.tuple_values then error('native expression list limit exceeded', 0) end
      -- A single expression already produces the required adjusted tuple. Avoid
      -- allocating an empty tuple and copying it through a second temporary.
      if #expressions == 1 and not prefix then
        return expression(expressions[1], dest, next, not single)
      end
      local entries = {}
      for i = 1, #expressions do entries[i] = slot() end
      local start = next
      for i = #expressions, (not prefix and #expressions > 0) and 2 or 1, -1 do
        start = move('a.p(' .. temp(dest) .. ',' .. temp(entries[i]) .. ',' .. tostring(not single and i == #expressions) .. ')', start, expressions[i])
      end
      local initial = prefix and 'a.o(' .. prefix .. ')'
        or #expressions > 0 and 'a.o(' .. scalar(entries[1]) .. ')' or 'a.e()'
      start = move(temp(dest) .. '=' .. initial, start, expressions[1])
      for i = #expressions, 1, -1 do start = expression(expressions[i], entries[i], start, not single and i == #expressions) end
      return start
    end
    expression = function(ex, dest, next, expand, tail)
      return with_temps(function()
        local kind, out = ex.node_type, temp(dest)
        if kind == 'call' then
          local callee, args = slot(), slot()
          local receiver
          if ex.is_selfcall then receiver = slot() end
          -- The common publisher already supports scalar receivers. Adjust there
          -- instead of publishing a full tuple then running a redundant copy block.
          local result_receiver = (not expand or ex.force_single_result)
            and '{mode="scalar",slot=' .. dest .. '}' or tostring(dest)
          local transfer = add('f.pc=' .. next .. ';return "' .. (tail and 'tailcall' or 'call') .. '",' .. scalar(callee) .. ',' .. temp(args) .. ',' .. result_receiver, ex)
          local start = list(ex.args, args, transfer, receiver and scalar(receiver))
          if receiver then
            start = add('f.pc=' .. start .. ';return "index",' .. scalar(receiver) .. ',' .. quote(ex.suffix.value) .. ',' .. callee, ex)
            start = expression(ex.ex, receiver, start, false)
          else start = expression(ex.ex, callee, start, false) end
          return start
        elseif kind == 'vararg' then
          return move(out .. '=' .. ((expand and not ex.force_single_result) and 'a.copy(f.args)' or 'a.o(f.args[1])'), next, ex)
        elseif kind == 'local_ref' or kind == 'upval_ref' then
          return move(out .. '=a.o(' .. ref(ex) .. ')', next, ex)
        elseif kind == 'number' or kind == 'string' or kind == 'nil' or kind == 'boolean' then
          local value = 'nil'
          if kind == 'string' then
            if #ex.value <= 128 then value = quote(ex.value)
            else
              charge(#ex.value)
              proto.constants[#proto.constants + 1] = ex.value
              value = 'a.constant(' .. pid .. ',' .. #proto.constants .. ')'
            end
          elseif kind == 'number' then value = ex.value == math.huge and '(1/0)' or string.format('%.17g', ex.value)
          elseif kind == 'boolean' then value = tostring(ex.value) end
          return move(out .. '=a.o(' .. value .. ')', next, ex)
        elseif kind == 'binop' then
          local left, right = slot(), slot()
          local operation, prepare
          if ex.op == 'and' or ex.op == 'or' then operation = scalar(right)
          elseif ex.op == '==' or ex.op == '~=' then
            operation = (ex.op == '~=' and 'not ' or '') .. 'a.equal(' .. scalar(left) .. ',' .. scalar(right) .. ')'
          elseif ex.op == '<' or ex.op == '<=' or ex.op == '>' or ex.op == '>=' then
            prepare = 'local l,r=a.q(' .. scalar(left) .. ',' .. scalar(right) .. ');'
            operation = 'l' .. ex.op .. 'r'
          else
            prepare = 'local l,r=a.b(' .. scalar(left) .. ',' .. scalar(right) .. ');'
            operation = 'l' .. ex.op .. 'r'
          end
          local finish = move((prepare or '') .. out .. '=a.o(' .. operation .. ')', next, ex)
          local rhs = expression(ex.right, right, finish, false)
          if ex.op == 'and' or ex.op == 'or' then
            local keep = move(out .. '=a.o(' .. scalar(left) .. ')', next, ex)
            local yes, no = ex.op == 'and' and rhs or keep, ex.op == 'and' and keep or rhs
            rhs = add('if ' .. scalar(left) .. ' then f.pc=' .. yes .. ' else f.pc=' .. no .. ' end', ex)
            -- The branch's evaluated-right path needs only a value copy, not a second short-circuit operation.
          end
          return expression(ex.left, left, rhs, false)
        elseif kind == 'unop' then
          local value = slot()
          local operand = scalar(value)
          local operation = ex.op == 'not' and 'not ' .. operand
            or ex.op == '#' and 'a.length(' .. operand .. ')' or '-a.n(' .. operand .. ')'
          return expression(ex.ex, value, move(out .. '=a.o(' .. operation .. ')', next, ex), false)
        elseif kind == 'index' then
          local object, key = slot(), slot()
          local finish = add('f.pc=' .. next .. ';return "index",' .. scalar(object) .. ',' .. scalar(key) .. ',' .. dest, ex)
          return expression(ex.ex, object, expression(ex.suffix, key, finish, false), false)
        elseif kind == 'func_proto' then
          return move(out .. '=a.o(a.closure(f,' .. assert(ids[ex.func_def]) .. '))', next, ex)
        elseif kind == 'concat' then
          local values = slot()
          return list(ex.exp_list, values, move(out .. '=a.o(a.concat(' .. temp(values) .. '))', next, ex), nil, true)
        elseif kind == 'constructor' then
          local object, array = slot(), 0
          local finish = move(out .. '=' .. temp(object), next, ex)
          local starts = {}
          for i, field in ipairs(ex.fields) do
            charge()
            local key, value = slot(), slot()
            if field.type == 'list' then array = array + 1 end
            starts[i] = {field = field, key = key, value = value, array = array}
          end
          for i = #starts, 1, -1 do
            local part = starts[i]
            local setter
            if part.field.type == 'list' then
              setter = move('a.array(' .. scalar(object) .. ',' .. part.array .. ',' .. temp(part.value) .. ')', finish, ex)
              finish = expression(part.field.value, part.value, setter, i == #starts)
            else
              setter = move('a.set(' .. scalar(object) .. ',' .. scalar(part.key) .. ',' .. scalar(part.value) .. ')', finish, ex)
              finish = expression(part.field.key, part.key, expression(part.field.value, part.value, setter, false), false)
            end
          end
          return move(temp(object) .. '=a.o(a.table())', finish, ex)
        end
        error('unsupported native expression ' .. kind .. ' at ' .. proto.source .. ':' .. (ex.line or 1), 0)
      end)
    end
    local function assignment(lhs, rhs, next, declare, at)
      charge(#lhs + 1)
      local values, targets = slot(), {}
      for i, target in ipairs(lhs) do
        charge()
        if target.node_type == 'index' then targets[i] = {object = slot(), key = slot()} end
      end
      local start = next
      for i = #lhs, 1, -1 do
        local target, code = lhs[i]
        local value = temp(values) .. '[' .. i .. ']'
        if target.node_type == 'index' then
          code = 'f.pc=' .. start .. ';return "set",{n=3,' .. scalar(targets[i].object) .. ',' .. scalar(targets[i].key) .. ',' .. value .. '}'
        elseif target.node_type == 'local_ref' then
          code = 'a.' .. (declare and 'd' or 'write') .. '(f,' .. definitions[target.reference_def].slot .. ',' .. value .. ')'
        elseif target.node_type == 'upval_ref' then
          code = 'a.v(f,' .. assert(upvalues[target.reference_def]) .. ',' .. value .. ')'
        else error('unsupported native assignment ' .. target.node_type, 0) end
        start = target.node_type == 'index' and add(code, at) or move(code, start, at)
      end
      start = list(rhs or {}, values, start)
      for i = #lhs, 1, -1 do
        if targets[i] then
          start = expression(lhs[i].ex, targets[i].object, expression(lhs[i].suffix, targets[i].key, start, false), false)
        end
      end
      return start
    end
    statement = function(stat, next)
      return with_temps(function()
        local kind = stat.node_type
        if kind == 'localstat' or kind == 'assignment' then
          return assignment(stat.lhs, stat.rhs, next, kind == 'localstat', stat)
        elseif kind == 'retstat' then
          local result = slot()
          if #stat.exp_list == 1 and stat.exp_list[1].node_type == 'call' and not stat.exp_list[1].force_single_result then
            return expression(stat.exp_list[1], result, next, true, true)
          end
          return list(stat.exp_list, result, add('return "return",' .. temp(result), stat))
        elseif kind == 'call' then return expression(stat, slot(), next, false)
        elseif kind == 'localfunc' then
          local declare = definitions[stat.name.reference_def].slot
          local bind = move('a.write(f,' .. declare .. ',a.closure(f,' .. ids[stat.func_def] .. '))', next, stat)
          return move('a.d(f,' .. declare .. ',nil)', bind, stat)
        elseif kind == 'funcstat' then
          return assignment({stat.name}, {{node_type = 'func_proto', func_def = stat.func_def}}, next, false, stat)
        elseif kind == 'dostat' then return scope(stat, next)
        elseif kind == 'label' then
          local id = label(stat)
          blocks[id] = 'f.pc=' .. next
          return id
        elseif kind == 'gotostat' then return move('', label(assert(stat.linked_label)), stat)
        elseif kind == 'breakstat' then return move('', assert(exits[stat.linked_loop]), stat)
        elseif kind == 'ifstat' then
          local otherwise = stat.elseblock and scope(stat.elseblock, next) or next
          for i = #stat.ifs, 1, -1 do
            charge()
            local branch, condition = stat.ifs[i], slot()
            local body = scope(branch, next)
            local test = add('if ' .. scalar(condition) .. ' then f.pc=' .. body .. ' else f.pc=' .. otherwise .. ' end', branch)
            otherwise = expression(branch.condition, condition, test, false)
          end
          return otherwise
        elseif kind == 'whilestat' or kind == 'repeatstat' then
          local header, condition = add('', stat), slot()
          exits[stat] = next
          if kind == 'whilestat' then
            local body = scope(stat, header)
            local test = add('if ' .. scalar(condition) .. ' then f.pc=' .. body .. ' else f.pc=' .. next .. ' end', stat)
            blocks[header] = 'f.pc=' .. expression(stat.condition, condition, test, false)
          else
            local test = add('if ' .. scalar(condition) .. ' then f.pc=' .. next .. ' else f.pc=' .. header .. ' end', stat)
            blocks[header] = 'f.pc=' .. scope(stat, expression(stat.condition, condition, test, false))
          end
          return header
        elseif kind == 'fornum' then
          local initial, limit, step, index = slot(), slot(), slot(), slot()
          local header = add('', stat)
          exits[stat] = next
          local increment = move(temp(index) .. '=a.o(' .. scalar(index) .. '+' .. scalar(step) .. ')', header, stat)
          local body = scope(stat, increment)
          body = move('a.d(f,' .. definitions[stat.var.reference_def].slot .. ',' .. scalar(index) .. ')', body, stat)
          blocks[header] = 'if (' .. scalar(step) .. '>=0 and ' .. scalar(index) .. '<=' .. scalar(limit)
            .. ') or (' .. scalar(step) .. '<0 and ' .. scalar(index) .. '>=' .. scalar(limit)
            .. ') then f.pc=' .. body .. ' else f.pc=' .. next .. ' end'
          local initialize = move(temp(index) .. ',' .. temp(limit) .. ',' .. temp(step)
            .. '=a.j(' .. scalar(initial) .. ',' .. scalar(limit) .. ',' .. scalar(step) .. ')', header, stat)
          local step_start = stat.step and expression(stat.step, step, initialize, false)
            or move(temp(step) .. '=a.o(1)', initialize, stat)
          return expression(stat.start, initial, expression(stat.stop, limit, step_start, false), false)
        elseif kind == 'forlist' then
          local values, args, result, control = slot(), slot(), slot(), slot()
          local header = add('', stat)
          exits[stat] = next
          local body = scope(stat, header)
          for i = #stat.name_list, 1, -1 do
            body = move('a.d(f,' .. definitions[stat.name_list[i].reference_def].slot .. ',' .. temp(result) .. '[' .. i .. '])', body, stat)
          end
          body = move(temp(control) .. '=a.o(' .. temp(result) .. '[1])', body, stat)
          local test = add('if ' .. temp(result) .. '[1]~=nil then f.pc=' .. body .. ' else f.pc=' .. next .. ' end', stat)
          local call = add('f.pc=' .. test .. ';return "call",' .. temp(values) .. '[1],' .. temp(args) .. ',' .. result, stat)
          blocks[header] = temp(args) .. '={n=2,' .. temp(values) .. '[2],' .. scalar(control) .. '};f.pc=' .. call
          local initialize = move(temp(control) .. '=a.o(' .. temp(values) .. '[3])', header, stat)
          return list(stat.exp_list, values, initialize)
        elseif kind == 'empty' then return next end
        error('unsupported native statement ' .. kind .. ' at ' .. proto.source .. ':' .. (stat.line or 1), 0)
      end)
    end
    scope = function(block, next)
      return guarded(function()
        local cursor = block.body.last
        while cursor do charge(); next = statement(cursor, next); cursor = cursor.prev end
        return next
      end)
    end
    proto.entry = scope(node, add('return "return",a.e()', node))
    proto.temps, proto.blocks = slots, #blocks
    metrics.temp_slots = metrics.temp_slots + slots
    -- Consecutive descending straight-line labels can share executable code.
    -- Every label stays addressable after preemption/reload. No branch, loop
    -- header or potentially suspending transfer is folded across a boundary.
    output('b={};r[' .. pid .. ']=b;')
    local id = 1
    proto.functions, proto.merged_groups, proto.max_function_bytes, proto.max_group_steps = 0, 0, 0, 1
    while id <= #blocks do
      charge()
      local last, size = id, 0
      local guard_bytes = #'if s(' + #')then ' + #' end;'
      size = guard_bytes + #tostring(id) + #blocks[id]
      if moves[id] then
        while last < #blocks and last - id + 1 < M.MERGE_STEPS and moves[last + 1] == last do
          charge()
          local part_bytes = guard_bytes + #tostring(last + 1) + #blocks[last + 1]
          if part_bytes > M.BLOCK_BYTES - size then break end
          size, last = size + part_bytes, last + 1
        end
      end
      proto.functions = proto.functions + 1
      if last > id then
        proto.max_function_bytes = math.max(proto.max_function_bytes, size)
        proto.max_group_steps = math.max(proto.max_group_steps, last - id + 1)
        proto.merged_groups = proto.merged_groups + 1
        output('c=function(f,a,t,s)')
        for current = last, id, -1 do
          output('if s(' .. current .. ')then ' .. blocks[current] .. ' end;')
        end
        output('end;for i=' .. id .. ',' .. last .. ' do b[i]=c end;')
      else
        if #blocks[id] > M.BLOCK_BYTES then error('native generated block byte limit exceeded', 0) end
        proto.max_function_bytes = math.max(proto.max_function_bytes, #blocks[id])
        output('b[' .. id .. ']=function(f,a,t)' .. blocks[id] .. ' end;')
      end
      id = last + 1
    end
    output('\n')
  end
  output('return r\n')
  metrics.phase = 'complete'
  return {version = M.VERSION, name = ast.source, generated = table.concat(chunks), prototypes = prototypes}
end
return M
