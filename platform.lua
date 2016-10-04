local class = require 'ext.class'
local table = require 'ext.table'
local ffi = require 'ffi'
local cl = require 'ffi.OpenCL'
local classert = require 'cl.assert'
local GetInfo = require 'cl.getinfo'

local Platform = class(GetInfo())

function Platform:init(id)
	self.id = id	
end

-- static method
function Platform.getAll(verbose)
	local n = ffi.new('cl_uint[1]',0)
	classert(cl.clGetPlatformIDs(0, nil, n))
	local ids = ffi.new('cl_platform_id[?]', n[0])
	classert(cl.clGetPlatformIDs(n[0], ids, nil))
	local platforms = table()
	for i=0,n[0]-1 do
		platforms:insert(Platform(ids[i]))

		if verbose then
			local plat = platforms:last()
			print()
			print('plat '..i)
			for name,infotype in pairs(Platform.infos) do
				print(name, plat:getInfo(name))
			end
		end

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
function Platform.getFirst(getDevicesArgs)
	local platform = Platform.getAll()[1]
	local device = platform:getDevices(getDevicesArgs)[1]
	return platform, device
end

--[[
args:
	deviceType
	cpu
	gpu
	verbose
--]]
function Platform:getDevices(args)
	local Device = require 'cl.device'
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
	classert(cl.clGetDeviceIDs(self.id, deviceType, 0, nil, n))
	local ids = ffi.new('cl_device_id[?]', n[0])
	classert(cl.clGetDeviceIDs(self.id, deviceType, n[0], ids, nil))
	local devices = table()
	for i=0,n[0]-1 do
		devices:insert(Device(ids[i]))

		if args.verbose then
			local dev = devices:last()
			print()
			print('dev '..i)
			for name,infotype in pairs(Device.infos) do
				print(name, require 'ext.tolua'(dev:getInfo(name)))
			end
		end

	end
	return devices

end

Platform.infoGetter = cl.clGetPlatformInfo
Platform.infos = {
	CL_PLATFORM_PROFILE = 'string',
	CL_PLATFORM_VERSION = 'string',
	CL_PLATFORM_NAME = 'string',
	CL_PLATFORM_VENDOR = 'string',
	CL_PLATFORM_EXTENSIONS = 'string',
}
function Platform:getProfile() return self:getInfo'CL_PLATFORM_PROFILE' end
function Platform:getVersion() return self:getInfo'CL_PLATFORM_VERSION' end
function Platform:getName() return self:getInfo'CL_PLATFORM_NAME' end
function Platform:getVendor() return self:getInfo'CL_PLATFORM_VENDOR' end
function Platform:getExtensions() return self:getInfo'CL_PLATFORM_EXTENSIONS' end

return Platform
