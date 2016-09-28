local cl = require 'ffi.OpenCL'

local function classert(...)
	local err = ...
	if err ~= cl.CL_SUCCESS then
		error('err '..tostring(err))
	end
	return ...
end

return classert
