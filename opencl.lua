local class = require 'ext.class'
local ffi = require 'ffi'
local cl = require 'ffi.OpenCL'

local CL = class()

local function ffi_new_table(T, src)
	return ffi.new(T..'['..#src..']', src)
end

function CL:assert(...) 
	return require 'opencl.assert'(...) 
end

function CL:init(args)
	args = args or {}
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
			0
		}
	elseif ffi.os == 'Windows' then
		ffi.cdef[[
typedef intptr_t HGLRC;
typedef intptr_t HDC;
HGLRC wglGetCurrentContext();
HDC wglGetCurrentDC();
		]]
		local gl = require 'ffi.OpenGL'
		properties = {
			cl.CL_CONTEXT_PLATFORM,
			ffi.cast('cl_context_properties', self.platform),
--[[ enable to use CL/GL context sharing
			cl.CL_GL_CONTEXT_KHR,
			ffi.cast('cl_context_properties', gl.wglGetCurrentContext()),
			cl.CL_WGL_HDC_KHR,
			ffi.cast('cl_context_properties', gl.wglGetCurrentDC()),
--]]			
			0
		}
	else
		error("don't know what properties to use for this OS")
	end
	--properties = ffi.new('cl_context_properties[?]', properties)
	properties = ffi_new_table('cl_context_properties', properties)

	local devices = {self.device}
	local deviceIDs = ffi_new_table('cl_device_id', devices)
	local err = ffi.new('cl_uint[1]',0)
	self.context = cl.clCreateContext(properties, #devices, deviceIDs, nil, nil, err)
	if err[0] ~= cl.CL_SUCCESS then
		error('clCreateContext failed with error '..('%x'):format(err[0]))
	end
	
	self.commands = cl.clCreateCommandQueue(self.context, self.device, cl.CL_QUEUE_PROFILING_ENABLE, err)
	assert(err[0] == cl.CL_SUCCESS)
end

function CL:getPlatform(query)
	local n = ffi.new('cl_uint[1]',0)
	self:assert(cl.clGetPlatformIDs(0, nil, n))
	local ids = ffi.new('cl_platform_id[?]', n[0])
	self:assert(cl.clGetPlatformIDs(n[0], ids, nil))
	for i=0,n[0]-1 do
		if query and query(ids[i]) then return ids[i] end
	end
	return ids[0]
end

function CL:getDevice(platform, deviceType, query)
	local n = ffi.new('cl_uint[1]',0)
	self:assert(cl.clGetDeviceIDs(platform, deviceType, 0, nil, n))
	local ids = ffi.new('cl_device_id[?]', n[0])
	self:assert(cl.clGetDeviceIDs(platform, deviceType, n[0], ids, nil))
	for i=0,n[0]-1 do
		if query and query(ids[i]) then return ids[i] end
	end
	return ids[0]
end

return CL
