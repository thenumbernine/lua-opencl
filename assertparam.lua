local cl = require 'ffi.OpenCL'
local ffi = require 'ffi'
local clCheckError = require 'cl.checkerror'

local unpack = table.unpack or unpack
return function(name, ...)
	local err = ffi.new('cl_int[1]', 0)
	local n = select('#', ...)
	local args = {...}
	args[n+1] = err
	local result = cl[name](unpack(args,1,n+1))
	clCheckError(err[0], name and (name..' failed with') or nil)
	return result
end
