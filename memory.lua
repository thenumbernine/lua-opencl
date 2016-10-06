local class = require 'ext.class'
local cl = require 'ffi.OpenCL'

local Wrapper = require 'cl.wrapper'

local Memory = class(Wrapper(
	'cl_mem',
	cl.clRetainMemObject,
	cl.clReleaseMemObject))

return Memory
