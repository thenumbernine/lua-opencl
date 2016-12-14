local cl = require 'ffi.OpenCL'
local clCheckError = require 'cl.checkerror'

return function(err, ...)
	clCheckError(err)
	return err, ...
end
