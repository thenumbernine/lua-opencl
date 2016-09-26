local ffi = require 'ffi'
local cl = require 'ffi.OpenCL'
local class = require 'ext.class'

local Buffer = class()

function Buffer:init(context, flags, size, host_ptr)
	local err = ffi.new('cl_int[1]',0)
	self.object_ = cl.clCreateBuffer(context, flags, size, host_ptr, err)
	if err[0] ~= cl.CL_SUCCESS then error("failed with error "..err[0]) end
end

return Buffer
