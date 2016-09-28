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
args:
	deviceType
	useCPU
	useGPU
--]]
function Platform:getDevices(args)
	local deviceType = args and args.deviceType 
	if args ~= nil and deviceType == nil then
		if args.useCPU ~= nil then 
			deviceType = args.useCPU and cl.CL_DEVICE_TYPE_CPU or cl.CL_DEVICE_TYPE_GPU 
		end
		if args.useGPU ~= nil then
			deviceType = args.useGPU and cl.CL_DEVICE_TYPE_GPU or cl.CL_DEVICE_TYPE_CPU
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
