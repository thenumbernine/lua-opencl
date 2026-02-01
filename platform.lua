local table = require 'ext.table'
local ffi = require 'ffi'
local bit = require 'bit'
local cl = require 'cl'
local classert = require 'cl.assert'
local GetInfo = require 'cl.getinfo'


local cl_uint_1 = ffi.typeof'cl_uint[1]'
local cl_platform_id_array = ffi.typeof'cl_platform_id[?]'
local cl_device_id_array = ffi.typeof'cl_device_id[?]'


local Platform = GetInfo():subclass()

-- platform has no retain/release, so no need to wrap it
-- hence the manual assignment of id here:
function Platform:init(id)
	self.id = id
end

-- static method
function Platform.getAll()
	local n = cl_uint_1()
	classert(cl.clGetPlatformIDs(0, nil, n))
	local ids = cl_platform_id_array(n[0])
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
function Platform.getFirst(getDevicesArgs)
	local platform = Platform.getAll()[1]
	local device = platform:getDevices(getDevicesArgs)[1]
	return platform, device
end

--[[
args:
	one of the following:
	deviceType = explicitly state the CL_DEVICE_TYPE_*, either as a constant or as a string, otherwise...
	default = CL_DEVICE_TYPE_DEFAULT
	cpu = CL_DEVICE_TYPE_CPU
	gpu = CL_DEVICE_TYPE_GPU
	accelerator = CL_DEVICE_TYPE_ACCELERATOR
	all = CL_DEVICE_TYPE_ALL

--]]
function Platform:getDevices(args)
	local Device = require 'cl.device'
	local deviceType = args and args.deviceType
	if args then
		if args.default then deviceType = bit.bor(deviceType or 0, cl.CL_DEVICE_TYPE_DEFAULT) end
		if args.cpu then deviceType = bit.bor(deviceType or 0, cl.CL_DEVICE_TYPE_CPU) end
		if args.gpu then deviceType = bit.bor(deviceType or 0, cl.CL_DEVICE_TYPE_GPU) end
		if args.accelerator then deviceType = bit.bor(deviceType or 0, cl.CL_DEVICE_TYPE_ACCELERATOR) end
		if args.all then deviceType = bit.bor(deviceType or 0, cl.CL_DEVICE_TYPE_ALL) end
	end
	deviceType = deviceType or cl.CL_DEVICE_TYPE_ALL
	local n = cl_uint_1()
--DEBUG:print('getting device type '..('0x%x'):format(deviceType))
	classert(cl.clGetDeviceIDs(self.id, deviceType, 0, nil, n))
	local ids = cl_device_id_array(n[0])
	classert(cl.clGetDeviceIDs(self.id, deviceType, n[0], ids, nil))
	local devices = table()
	for i=0,n[0]-1 do
		devices:insert(Device(ids[i]))
	end
	return devices

end

Platform.getInfo = Platform:makeGetter{
	getter = cl.clGetPlatformInfo,
	vars = {
		-- 1.0
		{name='CL_PLATFORM_PROFILE', type='char[]'},
		{name='CL_PLATFORM_VERSION', type='char[]'},
		{name='CL_PLATFORM_NAME', type='char[]'},
		{name='CL_PLATFORM_VENDOR', type='char[]'},
		{name='CL_PLATFORM_EXTENSIONS', type='char[]', separator=' '},
		-- 2.1
		{name='CL_PLATFORM_HOST_TIMER_RESOLUTION', type='cl_ulong'},
	},
}

function Platform:getProfile() return self:getInfo'CL_PLATFORM_PROFILE' end
function Platform:getVersion() return self:getInfo'CL_PLATFORM_VERSION' end
function Platform:getName() return self:getInfo'CL_PLATFORM_NAME' end
function Platform:getVendor() return self:getInfo'CL_PLATFORM_VENDOR' end
function Platform:getExtensions() return self:getInfo'CL_PLATFORM_EXTENSIONS' end

return Platform
