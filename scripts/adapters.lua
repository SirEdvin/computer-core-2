local U = require("scripts.util")
local M = {}
local function identity(signal)
  return (signal.type or "item") .. ":" .. signal.name .. ":" .. (signal.quality or "normal")
end
function M.normalize(signals)
  assert(type(signals) == "table", "signals must be a table")
  local aggregate, count = {}, 0
  for _, entry in pairs(signals) do
    count = count + 1
    assert(count <= 1000 and type(entry) == "table" and type(entry.signal) == "table", "invalid/too many signals")
    local s = U.data(entry.signal)
    s.type, s.quality = s.type or "item", s.quality or "normal"
    assert(type(s.name) == "string" and (s.type == "item" or s.type == "fluid" or s.type == "virtual"), "invalid signal")
    assert(prototypes[s.type == "virtual" and "virtual_signal" or s.type][s.name], "unknown signal: " .. s.name)
    assert(prototypes.quality[s.quality], "unknown quality")
    local n = math.floor(U.finite(entry.count, "signal count"))
    assert(n >= -2147483648 and n <= 2147483647, "signal count out of range")
    local key = identity(s)
    local prior = aggregate[key]
    if prior then prior.count = prior.count + n else aggregate[key] = {signal = s, count = n} end
    assert(aggregate[key].count >= -2147483648 and aggregate[key].count <= 2147483647, "signal total out of range")
  end
  local out = {}
  for _, k in ipairs(U.keys(aggregate)) do
    if aggregate[k].count ~= 0 then out[#out + 1] = aggregate[k] end
  end
  return out
end
function M.write(entity, signals)
  assert(entity and entity.valid, "circuit port unavailable")
  local normalized = M.normalize(signals)
  local filters = {}
  for i, v in ipairs(normalized) do filters[i] = {value = {type = v.signal.type, name = v.signal.name, quality = v.signal.quality, comparator = "="}, min = v.count} end
  local cb = entity.get_or_create_control_behavior()
  -- Exactly one private manual section; replace atomically after validation.
  if cb.sections_count == 0 then cb.add_section() end
  cb.get_section(1).filters = filters
  for i = cb.sections_count, 2, -1 do cb.remove_section(i) end
  cb.enabled = true
  return normalized
end
function M.read(entity, wire, fallback)
  assert(entity and entity.valid, "circuit port unavailable")
  local signals = {}
  if wire ~= nil then
    assert(wire == "red" or wire == "green", "wire must be red or green")
    local network = entity.get_circuit_network(defines.wire_connector_id["circuit_" .. wire])
    if network then signals = network.signals or {} else signals = fallback or {} end
  else
    -- No wire parameter reads this computer's outputs, as in Computer Core.
    signals = fallback or {}
  end
  return M.normalize(signals)
end
function M.connect(a, b)
  return a.get_wire_connector(defines.wire_connector_id.circuit_red, true).connect_to(b.get_wire_connector(defines.wire_connector_id.circuit_red, true), false, defines.wire_origin.script)
end
function M.mute(c)
  local sub = c.sub
  if not sub or not sub.speaker or not sub.speaker.valid then return end
  local speaker = sub.speaker
  speaker.alert_parameters = {show_alert = false, show_on_map = false, alert_message = ""}
  speaker.get_or_create_control_behavior().circuit_condition = {condition = {comparator = ">", first_signal = {type = "virtual", name = "signal-music-note"}, constant = 0}}
  if sub.speaker_combinator and sub.speaker_combinator.valid then M.write(sub.speaker_combinator, {}) end
  c.sound = nil
end
function M.instruments(c)
  assert(c.sub and c.sub.speaker and c.sub.speaker.valid, "speaker unavailable")
  return c.sub.speaker.prototype.instruments
end
function M.play(c, note, instrument, volume, polyphony)
  local instruments = M.instruments(c)
  instrument = instrument or 1
  if type(instrument) == "string" then
    for i, v in ipairs(instruments) do if v.name == instrument then instrument = i; break end end
  end
  assert(type(instrument) == "number" and instruments[instrument], "unknown instrument")
  if type(note) == "string" then
    for i, v in ipairs(instruments[instrument].notes) do if v.name == note then note = i; break end end
  end
  assert(type(note) == "number" and instruments[instrument].notes[note], "unknown note")
  volume = volume == nil and 1 or U.finite(volume, "volume")
  assert(volume >= 0 and volume <= 1, "volume must be 0..1")
  local speaker, cb = c.sub.speaker, c.sub.speaker.get_or_create_control_behavior()
  speaker.parameters = {playback_volume = volume, playback_globally = false, allow_polyphony = not not polyphony}
  speaker.alert_parameters = {show_alert = false, show_on_map = false, alert_message = ""}
  cb.circuit_parameters = {signal_value_is_pitch = true, instrument_id = instrument - 1, note_id = 0}
  cb.circuit_condition = {condition = {first_signal = {type = "virtual", name = "signal-music-note"}, comparator = ">", constant = 0}}
  M.connect(c.sub.speaker_combinator, speaker)
  M.write(c.sub.speaker_combinator, {{signal = {type = "virtual", name = "signal-music-note"}, count = note}})
  c.sound = {kind = "note", note = note, instrument = instrument, volume = volume, polyphony = not not polyphony}
end
function M.alert(c, text, signal, sound)
  M.instruments(c)
  local normalized = M.normalize({{signal = signal or {type = "virtual", name = "signal-info"}, count = 1}})
  local speaker = c.sub.speaker
  local instruments = speaker.prototype.instruments
  sound = sound or 1
  if type(sound) == "string" then
    for i, v in ipairs(instruments[1].notes) do if v.name == sound then sound = i; break end end
  end
  assert(type(sound) == "number" and instruments[1].notes[sound], "unknown alert sound")
  speaker.parameters = {playback_volume = 1, playback_globally = true, allow_polyphony = false}
  speaker.alert_parameters = {show_alert = true, show_on_map = true, icon_signal_id = normalized[1].signal, alert_message = tostring(text)}
  local cb = speaker.get_or_create_control_behavior()
  cb.circuit_parameters = {signal_value_is_pitch = false, instrument_id = 0, note_id = sound - 1}
  cb.circuit_condition = {condition = {first_signal = {type = "virtual", name = "signal-music-note"}, comparator = ">", constant = 0}}
  M.connect(c.sub.speaker_combinator, speaker)
  M.write(c.sub.speaker_combinator, {{signal = {type = "virtual", name = "signal-music-note"}, count = 1}})
  c.sound = {kind = "alert", text = tostring(text), signal = normalized[1].signal, sound = sound}
end
return M
