local class = require 'ext.class'
local table = require 'ext.table'
local ffi = require 'ffi'
local cl = require 'ffi.OpenCL'
local classert = require 'cl.assert'
local Device = require 'cl.device'

local Platform = class()

function Platform:init(obj)
	self.obj = obj	
end

-- static method
function Platform.getAll()
	local n = ffi.new('cl_uint[1]',0)
	classert(cl.clGetPlatformIDs(0, nil, n))
	local ids = ffi.new('cl_platform_id[?]', n[0])
	classert(cl.clGetPlatformIDs(n[0], ids, nil))
	local platforms = table()
	for i=0,n[0]-1 do
		platforms:insert(Platform(ids[i]))
	end
	return platforms
end

--[[
shortcut method
takes the first platform
and takes the first device
and returns both
args is passed to platform:getDevices
--]]
function Platform.getFirst(args)
	local platform = Platform.getAll()[1]
	local device = platform:getDevices(args)[1]
	return platform, device
end

--[[
shortcut method
takes the first platform and device
creates a context and commands
args:
	device = platform:getDevices arguments
	context = Context() arguments
	commands = Commands() arguments
	program (optional) Program() arguments (which is built upon creation)
--]]
function Platform.quickstart(args)
	local platform, device = Platform.getFirst(args.device)
	local context = require 'cl.context'(table({platform=platform, device=device}, args.context))
	local commands = require 'cl.commands'(table({context=context, device=device}, args.commands))
	local program
	if args.program then
		program = require 'cl.program'(table({
			context=context, 
			devices={device}
		}, args.program))
	end
	return platform, device, context, commands, program
end

--[[
args:
	deviceType
	cpu
	gpu
--]]
function Platform:getDevices(args)
	local deviceType = args and args.deviceType 
	if args ~= nil and deviceType == nil then
		if args.cpu ~= nil then 
			deviceType = args.cpu and cl.CL_DEVICE_TYPE_CPU or cl.CL_DEVICE_TYPE_GPU 
		end
		if args.gpu ~= nil then
			deviceType = args.gpu and cl.CL_DEVICE_TYPE_GPU or cl.CL_DEVICE_TYPE_CPU
		end
	end
	local n = ffi.new('cl_uint[1]',0)
	classert(cl.clGetDeviceIDs(self.obj, deviceType, 0, nil, n))
	local ids = ffi.new('cl_device_id[?]', n[0])
	classert(cl.clGetDeviceIDs(self.obj, deviceType, n[0], ids, nil))
	local devices = table()
	for i=0,n[0]-1 do
		devices:insert(Device(ids[i]))
	end
	return devices

end

return Platform
