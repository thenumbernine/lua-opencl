local cl = require 'ffi.OpenCL'

return function(err, ...)
	if err ~= cl.CL_SUCCESS then
		error('err '..tostring(err))
	end
	return err, ...
end
