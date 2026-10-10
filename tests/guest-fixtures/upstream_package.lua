-- Exercise the actual pinned startup/searcher, not the targeted helper loader.
local rc = {}
_G._RC_ROM_DIR = '/rc'
assert(loadfile('/rc/startup/00_fs.lua', 't'))(rc)
assert(loadfile('/rc/startup/10_package.lua', 't'))(rc)
local fs = require('fs')
assert(package.searchpath('cc.expect', package.path) == '/rc/modules/main/cc/expect.lua')
assert(package.searchpath('colors', package.path) == '/rc/apis/colors.lua')
assert(package.searchpath('missing_module', package.path) == nil)
local colors = require('colors')
assert(colors == require('colors') and colors.toBlit(colors.red) == 'e')
assert(require('cc.expect').expect(1, 7, 'number') == 7)
assert(not pcall(require, 'peripheral') and not pcall(require, 'http'))
assert(not pcall(require, 'native_module'))
local splits = fs.split('/rc/../local/./file.lua')
assert(table.concat(splits, '/') == 'local/file.lua')
assert(fs.isDir('/rc') and fs.isReadOnly('/rc/apis/colors.lua'))
return 'upstream-package-pass'
