local U = require("scripts.util")
local FS = require("scripts.filesystem")
local R = require("scripts.runtime")
local M = {}
M.help = {
  cat = "cat <file> ... — concatenate files", cd = "cd <directory> — change working directory", clear = "clear — clear terminal", cp = "cp <source> <destination> — copy a file", date = "date — current game tick", edit = "edit <file> — open source editor", exit = "exit — close computer", help = "help [apis|API] — show help", id = "id — deterministic computer ID", label = "label [get|set <name>|clear] — shared mount/network label", ls = "ls [directory] — list directory", mkdir = "mkdir <directory> — create directory", mv = "mv <source> <destination> — move a file", position = "position — surface and coordinates", pwd = "pwd — working directory", rm = "rm <path> — remove file/directory recursively", run = "run <file> [args...] — execute Lua source", stop = "stop — stop program and clear circuit/speaker outputs", time = "time — game time", touch = "touch <file> — create file/update timestamps", tree = "tree [directory] — directory tree", waypoint = "waypoint — manage force-shared locations"
}
M.api_help = {
  os = "os.getComputerID(), getComputerLabel(), setComputerLabel(label), time(), date(), set(name,...), get(name), clear(name), pcall(fn,...), require(path)\nos.wait('handler',seconds,...), cancelTimer(id), register(name,fn)\nPersistent programs return {init=function() ... end, handler=function(...) ... end}. Keep durable values in state.",
  term = "term.write(...), setOutput(...), getOutput(), setInput(text), getInput(), read(), clear()\nterm.addInputListener('handler'), addOutputListener('handler'), removeListener(id)",
  disk = "disk.readFile(path), writeFile(path,...), appendFile(path,...), removeFile(path), fileExist(path)",
  lan = "lan.readLeftSignals([wire]), readRightSignals([wire]), writeLeftSignals(signals), writeRightSignals(signals)\nget/set aliases retained. wire: red or green; omit to read local outputs. Signals: {signal={type,name,quality},count}.",
  wlan = "wlan.on(event,'handler',...), onBuiltComputer('handler',...), emit(label,event,...), broadcast(event,...)\nMessages deliver no earlier than the next tick, only within the same force/surface. Callbacks use serializable arguments.",
  speaker = "speaker.print(text,[toForce]), mute(), setAlert(text,signal,[sound]), playNote(note,[instrument,volume,polyphony]), getInstruments()"
}
function M.execute(c, line)
  local ok, result, action = pcall(function()
    assert(type(line) == "string" and #line <= 4096, "command too long")
    local args = U.words(line)
    local cmd = table.remove(args, 1)
    if not cmd then return "" end
    local function need(n) assert(#args >= n, M.help[cmd] or "missing arguments") end
    if cmd == "help" then
      if args[1] == "apis" then
        local list = {"os", "term", "disk", "wlan"}; if c.sub then list[#list + 1] = "lan"; list[#list + 1] = "speaker" end
        for _, name in ipairs(U.keys(storage.extensions)) do list[#list + 1] = name end
        return table.concat(list, "\n")
      elseif args[1] then return M.api_help[args[1]] or R.extension_help(c, args[1]) or "Unknown API: " .. args[1]
      else local list = {}; for _, k in ipairs(U.keys(M.help)) do list[#list + 1] = M.help[k] end; return table.concat(list, "\n") end
    elseif cmd == "cat" then need(1); local list = {}; for _, path in ipairs(args) do list[#list + 1] = FS.read(c, path) end; return table.concat(list)
    elseif cmd == "cd" then local path = FS.path(c, args[1] or "/"); local node = FS.get(c, path); assert(node and node.type == "dir", "not a directory"); c.cwd = path
    elseif cmd == "pwd" then return c.cwd
    elseif cmd == "ls" then local children = FS.list(c, args[1]); local list = {}; for _, name in ipairs(U.keys(children)) do list[#list + 1] = (children[name].type == "dir" and "d " or "- ") .. name end; return table.concat(list, "\n")
    elseif cmd == "tree" then
      local path = FS.path(c, args[1] or c.cwd)
      local lines = {path}
      local function walk(root, indent, depth)
        if depth > 32 then return end
        local children = FS.list(c, root)
        for _, name in ipairs(U.keys(children)) do
          local child = children[name]
          lines[#lines + 1] = indent .. (child.type == "dir" and "+ " or "- ") .. name
          -- Display mount labels but never recursively expand mounts.
          if child.type == "dir" and not child.virtual then walk(root .. "/" .. name, indent .. "  ", depth + 1) end
        end
      end
      walk(path, "  ", 0); return table.concat(lines, "\n")
    elseif cmd == "mkdir" then need(1); FS.mkdir(c, args[1])
    elseif cmd == "touch" then need(1); FS.write(c, args[1], FS.exists(c, args[1]) and FS.read(c, args[1]) or "")
    elseif cmd == "cp" or cmd == "mv" then
      need(2)
      local from_owner, from_key = FS.resolve(c, args[1]); local to_owner, to_key = FS.resolve(c, args[2])
      if from_owner == to_owner and from_key == to_key then return "" end
      FS.write(c, args[2], FS.read(c, args[1]))
      if cmd == "mv" then FS.remove(c, args[1]) end
    elseif cmd == "rm" then need(1); FS.remove(c, args[1])
    elseif cmd == "label" then
      if args[1] == "set" then need(2); FS.label(c, args[2])
      elseif args[1] == "clear" then FS.label(c, nil)
      elseif not args[1] or args[1] == "get" then return c.label or "(unlabelled)"
      else error(M.help.label) end
    elseif cmd == "id" then return tostring(c.id)
    elseif cmd == "position" then return "surface " .. c.surface_index .. ": " .. c.position.x .. ", " .. c.position.y
    elseif cmd == "date" then return tostring(game.tick)
    elseif cmd == "time" then local hours = (game.tick % 25000 / 25000 * 24 + 12) % 24; return string.format("%02d:%02d", math.floor(hours), math.floor((hours % 1) * 60))
    elseif cmd == "clear" then R.output(c, "", true)
    elseif cmd == "edit" then need(1); local path = FS.path(c, args[1]); if not FS.exists(c, path) then FS.write(c, path, "") end; FS.read(c, path); return "", {view = "editor", path = path}
    elseif cmd == "run" then
      need(1); assert(R.powered(c), "computer has no power")
      local path = FS.path(c, table.remove(args, 1))
      local success, err = R.start(c, FS.read(c, path), path, U.pack(table.unpack(args)))
      assert(success, err); return ""
    elseif cmd == "stop" then R.stop(c)
    elseif cmd == "exit" then return "", {view = "close"}
    elseif cmd == "waypoint" then return "", {view = "waypoint"}
    else error("unknown command: " .. cmd .. "; enter help") end
    return ""
  end)
  if not ok then return "Error: " .. tostring(result), nil, false end
  return result, action, true
end
return M
