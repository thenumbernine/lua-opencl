local class = require 'ext.class'
local ffi = require 'ffi'
local cl = require 'ffi.OpenCL'
local classert = require 'cl.assert'

local Commands = class()

--[[
args
	context
	device
	properties
--]]
function Commands:init(args)
	assert(args)
	local err = ffi.new('cl_uint[1]',0)
	self.obj = cl.clCreateCommandQueue(
		assert(args.context).obj,
		assert(args.device).obj,
		args.properties or 0,
		err)
	classert(err[0])
end

return Commands
