local ffi = require 'ffi'
local cl = require 'ffi.OpenCL'
local class = require 'ext.class'
local table = require 'ext.table'
local string = require 'ext.string'
local classert = require 'cl.assert'
local classertparam = require 'cl.assertparam'
local Wrapper = require 'cl.wrapper'

local Program = class(Wrapper(
	'cl_program',
	cl.clRetainProgram,
	cl.clReleaseProgram))

--[[
args:
	context
	code
	devices (optional)
--]]
function Program:init(args)
	assert(args)
	local context = assert(args.context)
	local code = assert(args.code)
	local strings = ffi.new('const char*[1]')
	strings[0] = ffi.cast('const char*',code)
	local lengths = ffi.new('size_t[1]')
	lengths[0] = #code
	self.id = classertparam('clCreateProgramWithSource', context.id, 1, strings, lengths)
	Program.super.init(self, self.id)

	if args.devices then
		local success, message = self:build(args.devices)
		if not success then
			print(require 'template.showcode'(code))
			error(message)
		end
	end
end

function Program:build(devices, options)
	local deviceIDs = ffi.new('cl_device_id[?]', #devices)
	for i=1,#devices do
		deviceIDs[i-1] = devices[i].id
	end
	local err = cl.clBuildProgram(self.id, #devices, deviceIDs, options, nil, nil)
	local success = err == cl.CL_SUCCESS
	local message
	if not success then 
		message = table{'failed to build'}
		for _,device in ipairs(devices) do
			message:insert(self:getLog(device))
		end	
		message = message:concat'\n'
	end
	return success, message 
end

function Program:getBuildInfo(device, name)
	assert(name, "expected name")
	local size = ffi.new('size_t[1]', 0)
	classert(cl.clGetProgramBuildInfo(self.id, device.id, name, 0, nil, size))
	local param = ffi.new('char[?]', size[0])
	classert(cl.clGetProgramBuildInfo(self.id, device.id, name, size[0], param, nil))
	return ffi.string(param, size[0])
end

function Program:getLog(device)
	return self:getBuildInfo(device, cl.CL_PROGRAM_BUILD_LOG)
end

--[[
usage:
	program:kernel(name, arg1, ...)
	program:kernel{name=name, args={...}}
--]]
function Program:kernel(args, ...)
	if type(args) == 'string' then
		args = {name=args}
		if select('#', ...) then
			args.args = {...}
		end
	end
	return require 'cl.kernel'(table(args, {program=self}))
end

return Program
