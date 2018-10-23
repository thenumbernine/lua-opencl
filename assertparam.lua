local cl = require 'ffi.OpenCL'
local ffi = require 'ffi'
local table = require 'ext.table'
local clCheckError = require 'cl.checkerror'

return function(name, ...)
	local err = ffi.new('cl_int[1]', 0)
	local n = select('#', ...)
	local args = {...}
	args[n+1] = err
	local result = cl[name](table.unpack(args,1,n+1))
	clCheckError(err[0], name and (name..' failed with') or nil)
	return result
end
