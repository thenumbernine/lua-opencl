local ffi = require 'ffi'
local cl = require 'ffi.OpenCL'
local class = require 'ext.class'
local classert = require 'cl.assert'

local Program = class()

--[[
args:
	context
	code
--]]
function Program:init(args)
	assert(args)
	local context = assert(args.context)
	local code = assert(args.code)
	local strings = ffi.new('const char*[1]')
	strings[0] = ffi.cast('const char*',code)
	local lengths = ffi.new('size_t[1]')
	lengths[0] = #code
	local err = ffi.new('cl_uint[1]',0)
	self.obj = cl.clCreateProgramWithSource(context.obj, 1, strings, lengths, err)
	assert(err[0] == cl.CL_SUCCESS)
end

function Program:build(devices, options)
	local deviceIDs = ffi.new('cl_device_id[?]', #devices)
	for i=1,#devices do
		deviceIDs[i-1] = devices[i].obj
	end
	local err = cl.clBuildProgram(self.obj, #devices, deviceIDs, options, nil, nil)
	local success = err == cl.CL_SUCCESS
	local message
	if not success then 
		message = "failed to build"
	end
	return success, message 
end

function Program:getBuildInfo(device, name)
	assert(name, "expected name")
	local size = ffi.new('size_t[1]', 0)
	classert(cl.clGetProgramBuildInfo(self.obj, device.obj, name, 0, nil, size))
	local param = ffi.new('char[?]', size[0])
	classert(cl.clGetProgramBuildInfo(self.obj, device.obj, name, size[0], param, nil))
	return ffi.string(param, size[0])
end

return Program
