-- Incremental mark/sweep at instruction-quantum boundaries. The VM must remain
-- paused until a collection completes: there are no write barriers during marking.
local M = {}

local function enqueue(state, value, mode)
  if type(value) ~= "table" or state.seen[value] then return end
  state.seen[value] = true
  state.stack[#state.stack + 1] = {value = value, mode = mode}
end
local function mark(vm, state, id)
  if not id or state.marked[id] then return end
  assert(vm.objects[id], "dangling guest reference")
  state.marked[id] = true
  enqueue(state, vm.objects[id])
end
function M.start(vm)
  assert(not vm.collection, "collection already active")
  local state = {marked = {}, seen = {}, stack = {}, phase = "mark", reclaimed = 0}
  vm.collection = state
  for _, root in ipairs({vm.env, vm.main, vm.string_meta, vm.ipairs_next}) do
    if root then mark(vm, state, root.ref) end
  end
  mark(vm, state, vm.current)
  enqueue(state, vm.free_cells, "ids")
  enqueue(state, vm.events)
  enqueue(state, vm.wait)
  enqueue(state, vm.pending_operation)
end
function M.step(vm, budget)
  local state = assert(vm.collection, "no collection active")
  local used = 0
  while used < budget do
    used = used + 1
    if state.phase == "mark" then
      local frame = state.stack[#state.stack]
      if not frame then state.phase = "sweep"
      else
        local key, value = next(frame.value, frame.key)
        frame.key = key
        if key == nil then table.remove(state.stack)
        elseif key == "ref" or (frame.mode == "ids" and type(value) == "number") or (frame.mode == "resumer" and key == "id") then
          mark(vm, state, value)
        elseif key == "proto" and (frame.value.kind == "closure" or frame.value.kind == "frame") then
          -- Normalized prototypes contain scalar constants/descriptors, no guest IDs.
          -- Their plain tables remain owned by closures/frames, not the guest heap.
        elseif (key == "known" or key == "order") and frame.value.kind == "table" then
          -- Encoded scalar key history has no references; live keys/values are
          -- traced through entries (including table/function keys).
        else
          local mode = (key == "registers" or key == "upvals") and "ids" or (key == "resumer" and "resumer" or nil)
          enqueue(state, value, mode)
          enqueue(state, key)
        end
      end
    else
      local id = next(vm.objects, state.key)
      state.key = id
      if not id then
        vm.collection = nil
        vm.allocations_since_collection = 0
        return true, used, state.reclaimed
      end
      if not state.marked[id] then
        local value = vm.objects[id]
        if value.kind == "handle" and not value.closed then
          vm.open_handles = vm.open_handles - 1
          vm.handle_bytes = vm.handle_bytes - #value.text
        end
        vm.objects[id] = nil
        vm.object_count = vm.object_count - 1
        state.reclaimed = state.reclaimed + 1
      end
    end
  end
  return false, used, state.reclaimed
end
return M
