-- A targeted source-only module harness, not a substitute BIOS/shell boot.
local native_term = term
local rc = {}
package = {loaded = {term = term, fs = fs, io = io, bit32 = bit32, rc = rc}}
local paths = {
  ["cc.expect"] = "/rc/modules/main/cc/expect.lua",
  ["cc.strings"] = "/rc/modules/main/cc/strings.lua",
  ["rc.thread"] = "/rc/modules/main/rc/thread.lua",
  ["rc.copy"] = "/rc/modules/main/rc/copy.lua",
  ["rc.json"] = "/rc/modules/main/rc/json.lua",
  colors = "/rc/apis/colors.lua", keys = "/rc/apis/keys.lua",
  window = "/rc/apis/window.lua", textutils = "/rc/apis/textutils.lua",
  paintutils = "/rc/apis/paintutils.lua"
}
function require(name)
  if name == "colours" then name = "colors" end
  if package.loaded[name] ~= nil then return package.loaded[name] end
  local chunk = assert(loadfile(assert(paths[name], "unlisted module " .. name), "t"))
  local ok, module = pcall(chunk)
  assert(ok, name .. ": " .. tostring(module))
  package.loaded[name] = module
  return module
end
local started, failure = pcall(assert(loadfile("/rc/startup/15_term.lua", "t")), rc)
assert(started, "terminal startup: " .. tostring(failure))
term = require("term")
local colors, window = require("colors"), require("window")
assert(colors == require("colours") and colors.toBlit(colors.black) == "f")
assert(colors.combine(colors.red, colors.blue) == bit32.bor(colors.red, colors.blue))
assert(colors.subtract(colors.combine(colors.red, colors.blue), colors.blue) == colors.red)
assert(not pcall(colors.toBlit, "red"))
assert(term.native() == native_term and term.current() == native_term)
local surface = window.create(native_term, 1, 1, 18, 4, true)
local parent = window.create(surface, 2, 2, 8, 3, false)
parent.blit("ABCDEFGH", "01234567", "fedcba98")
assert(parent.getLine(1) == "ABCDEFGH")
local child = window.create(parent, -1, 1, 5, 2, false)
child.blit("vwxyz", "01234", "fedcb")
child.setVisible(true)
local text, fg, bg = parent.getLine(1)
assert(text == "xyzDEFGH" and fg == "23434567" and bg == "dcbcba98")
local previous = term.redirect(parent)
assert(previous == native_term and term.current() == parent, "boot-context redirect must return and replace the native target")
term.at(5, 2).write("R")
assert(parent.getLine(2):sub(5, 5) == "R")
assert(term.redirect(child) == parent and term.current() == child)
term.at(3, 2).write("N")
assert(parent.getLine(2):sub(1, 1) == "N")
assert(term.redirect(previous) == child and term.current() == native_term)
assert(surface.getLine(2) == string.rep(" ", 18) and surface.getLine(3) == string.rep(" ", 18), "hidden writes must not redraw the parent surface")
parent.setVisible(true)
assert(surface.getLine(2):sub(2, 9) == "xyzDEFGH" and surface.getLine(3):sub(2, 2) == "N", "revealing a hidden window must redraw its retained contents")
local paintutils = require("paintutils")
paintutils.drawFilledBox(12, 2, 14, 3, colors.red)
return "upstream-terminal-pass"
