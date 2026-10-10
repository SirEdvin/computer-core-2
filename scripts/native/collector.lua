-- Stop-the-guest incremental graph collector. Every cursor/worklist is plain
-- data and can be saved; executable caches and compiler ASTs are never scanned.
local Limits = require('__computer_core_2__.scripts.guest.limits')
local M = {}
local function push(gc, value, mode)
  if type(value) == 'table' then gc.jobs[#gc.jobs + 1] = {value = value, mode = mode or 'plain'} end
end
local function mark(machine, gc, id)
  assert(machine.heap[id], 'collector encountered invalid native identity')
  if not gc.marked[id] then
    gc.marked[id] = true
    gc.jobs[#gc.jobs + 1] = {id = id, mode = 'object'}
  end
end
local function edge(machine, gc, value)
  if type(value) == 'table' then
    if value.native_ref then mark(machine, gc, value.native_ref)
    else push(gc, value) end
  end
end
function M.start(machine)
  if machine.collector then return end
  machine.collector = {phase = 'roots', cursor = 1, marked = {}, bundles = {}, jobs = {}}
end
function M.step(machine, credits)
  assert(type(credits) == 'number' and credits >= 0 and credits == math.floor(credits), 'invalid native collection credits')
  local gc, spent = machine.collector, 0
  if not gc then return 0 end
  while gc and spent < credits do
    spent = spent + 1
    if gc.phase == 'roots' then
      local roots = {machine.env, {native_ref = machine.root}, {native_ref = machine.active}, machine.result, machine.error,
        machine.yielded, machine.external_roots, machine.events, machine.string_library, machine.waiting,
        machine.ipairs_iterator, machine.next_iterator, machine.pattern_functions}
      -- Explicit root cases avoid # on a nil-containing root sequence.
      if gc.cursor <= 13 then edge(machine, gc, roots[gc.cursor]); gc.cursor = gc.cursor + 1
      elseif gc.cursor == 14 and machine.cell_pool then
        push(gc, machine.cell_pool.ids, 'ids'); gc.cursor = gc.cursor + 1
      else gc.phase = 'mark' end
    elseif gc.phase == 'mark' then
      local job = gc.jobs[#gc.jobs]
      if not job then gc.phase, gc.cursor = 'sweep', 1
      elseif job.mode == 'object' then
        gc.jobs[#gc.jobs] = nil
        local o = machine.heap[job.id]
        if o.kind == 'cell' then edge(machine, gc, o.value)
        elseif o.kind == 'closure' then
          if gc.bundles then gc.bundles[o.bundle_id or 1] = true end
          push(gc, o.upvalues, 'ids')
        elseif o.kind == 'wrapped' then mark(machine, gc, o.thread)
        elseif o.kind == 'table' then
          edge(machine, gc, o.metatable)
          edge(machine, gc, o.file_handle)
          push(gc, o.values, 'values')
        elseif o.kind == 'thread' then
          edge(machine, gc, o.target)
          push(gc, o.frames)
          push(gc, o.pending)
          push(gc, o.waiting)
          push(gc, o.boundaries)
          if o.resumer then mark(machine, gc, o.resumer.owner) end
        elseif o.kind == 'service' then edge(machine, gc, o.data)
        else assert(o.kind == 'handle', 'unsupported native collector object') end
      else
        local field, value = next(job.value, job.cursor)
        if field == nil then gc.jobs[#gc.jobs] = nil
        else
          job.cursor = field
          if job.mode == 'ids' then mark(machine, gc, value)
          elseif job.mode == 'values' then
            -- Reference-key encoding is disjoint from scalar string keys.
            if type(field) == 'string' and field:sub(1, 1) == 'r' then mark(machine, gc, assert(tonumber(field:sub(2)))) end
            edge(machine, gc, value)
          elseif field == 'bundle_id' then
            if gc.bundles then gc.bundles[value] = true end
          elseif field == 'cells' or field == 'upvalues' then push(gc, value, 'ids')
          else edge(machine, gc, value) end
        end
      end
    elseif gc.phase == 'sweep' then
      local id = machine.object_ids[gc.cursor]
      if not id then
        gc.phase, gc.cursor = 'bundles', 2
      elseif gc.marked[id] then gc.cursor = gc.cursor + 1
      else
        local removed = machine.heap[id]
        if removed.kind == 'handle' and not removed.closed then
          machine.open_handles = machine.open_handles - 1
          machine.handle_bytes = machine.handle_bytes - #removed.text
          removed.closed, removed.text = true, ''
        end
        local last = machine.object_ids[#machine.object_ids]
        machine.object_ids[gc.cursor] = last
        machine.heap[last].object_slot = gc.cursor
        machine.object_ids[#machine.object_ids] = nil
        machine.heap[id] = nil
        machine.objects = machine.objects - 1
      end
    else
      assert(gc.phase == 'bundles', 'invalid native collector phase')
      if gc.cursor <= Limits.call_frames then
        -- Older mid-mark collectors have no bundle inventory: preserve every
        -- source until a complete new collection has observed its edges.
        if gc.bundles and not gc.bundles[gc.cursor] and machine.bundles then machine.bundles[gc.cursor] = nil end
        gc.cursor = gc.cursor + 1
      else
        machine.collector = nil
        machine.collect_at = machine.objects + Limits.collection_interval
        gc = nil
      end
    end
  end
  machine.collection_work = (machine.collection_work or 0) + spent
  return spent
end
return M
