-- Reuse the bounded local disk implementation with a separate immutable ROM.
local Files=require('__computer_core_2__.scripts.guest.files')
local Rom=require('__computer_core_2__.scripts.native.rom')
return Files.with_sources(Rom)
