local class = require 'ext.class'
local cl = require 'ffi.OpenCL'

local CL = class()

local function classert(...)
	local err = ...
	if err ~= cl.CL_SUCCESS then
		error('err '..err)
	end
	return ...
end

function CL:init(args)
	self.platform = self:getPlatform(args.pickPlatform)
	self.device = self:getDevice(
		self.platform,
		args.useGPU and cl.CL_DEVICE_TYPE_GPU or cl.CL_DEVICE_TYPE_CPU,
		args.pickDevice)
	
	local properties
	if ffi.os == 'OSX' then
		ffi.cdef[[
typedef void* CGLContextObj;
CGLContextObj CGLGetCurrentContext();
		]]
		local kCGLContext = ffi.C.CGLGetCurrentContext()
		local kCGLShareGroup = ffi.C.CGLGetShareGroup(kCGLContext)
		properties = {
			cl.CL_CONTEXT_PLATFORM,
			self.platform,
			cl.CL_CONTEXT_PROPERTY_USE_CGL_SHAREGROUP_APPLE,
			kCGLShareGroup,
		}
	elseif ffi.os == 'Windows' then
		ffi.cdef[[
		]]
		properties = {
			cl.CL_CONTEXT_PLATFORM,
			ffi.C.cpPlatform,
			cl.CL_GL_CONTEXT_KHR,
			ffi.C.wglGetCurrentContext(),
			cl.CL_WGL_HDC_KHR,
			ffi.C.wglGetCurrentDC(),
		}
	else
		error("don't know what properties to use for this OS")
	end
	properties = ffi.new('cl_command_queue_properties[?]', properties)

	local devices = {self.device}
	local deviceIDs = ffi.new('cl_device_id[?]', devices)
	local err = ffi.new('cl_uint[1]',0)
	self.context = cl.clCreateContext(properties, #devices, deviceIDs, nil, nil, err)
	assert(err == cl.CL_SUCCESS)
	
	self.commands = cl.clCreateCommandQueue(self.context, self.device, properties, err)
	assert(err == cl.CL_SUCCESS)
end

function CL:getPlatform(query)
	local n = ffi.new('cl_uint[1]',0)
	classert(cl.clGetPlatformIDs(0, nil, n))
	local ids = ffi.new('cl_platform_id[?]', n[0])
	classert(cl.clGetPlatformIDs(n[0], ids, nil))
	for i=0,n[0]-1 do
		if query and query(ids[i]) then return ids[i] end
	end
	return ids[0]
end

function CL:getDevice(platform, deviceType, query)
	local n = ffi.new('cl_uint[1]',0)
	classert(cl.clGetDeviceIDs(platform, deviceType, 0, nil, n))
	local ids = ffi.new('cl_device_id[?]', n[0])
	classert(cl.clGetDeviceIDs(platform, deviceType, n[0], ids, nil))
	for i=0,n[0]-1 do
		if query and query(ids[i]) then return ids[i] end
	end
	return ids[0]
end

return CL
