local alias = {value = 7}
os.queueEvent("first", alias, nil, "last", nil)
os.queueEvent("second", 2)
local first = table.pack(os.pullEventRaw())
assert(first.n == 5 and first[1] == "first" and first[2] == alias and first[3] == nil and first[4] == "last" and first[5] == nil)
assert(os.pullEvent() == "second")
os.queueEvent("skip", 1)
os.queueEvent("wanted", 3)
local name, value = os.pullEvent("wanted")
assert(name == "wanted" and value == 3)
os.queueEvent("terminate")
local ok, err = pcall(os.pullEvent, "never")
assert(not ok and type(err) == "string")
os.queueEvent("terminate")
assert(os.pullEventRaw("never") == "terminate")
assert(not pcall(os.queueEvent, "bad", 0/0))
assert(not pcall(os.startTimer, math.huge))
assert(not pcall(os.startTimer, -1))
-- Filling/draining a maximum queue may span native-work credits now that
-- instruction quanta are larger. Recover only that explicit quota refusal;
-- retrying burns guest instructions until the next scheduler tick renews it.
local function event_call(fn, ...)
  while true do
    local ok, first, second = pcall(fn, ...)
    if ok then return first, second end
    assert(type(first) == "string" and first:find("event work limit exceeded", 1, true), first)
  end
end
for i = 1, 256 do event_call(os.queueEvent, "flood", i) end
assert(not pcall(os.queueEvent, "overflow"))
for i = 1, 256 do
  local event, sequence = event_call(os.pullEventRaw)
  assert(event == "flood" and sequence == i)
end
local marker = {value = "preserved"}
os.queueEvent("object", marker)
marker = nil
for i = 1, 3000 do local discard = {i} end
local _, kept = os.pullEventRaw()
assert(kept.value == "preserved")
return "events-pass"
