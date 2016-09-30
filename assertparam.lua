local cl = require 'ffi.OpenCL'
local ffi = require 'ffi'

local unpack = table.unpack or unpack
return function(name, ...)
	local err = ffi.new('cl_int[1]', 0)
	local n = select('#', ...)
	local args = {...}
	args[n+1] = err
	local result = cl[name](unpack(args,1,n+1))
	if err[0] ~= cl.CL_SUCCESS then
		error(name..' failed with error '..err[0])
	end
	return result
end
