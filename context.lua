local class = require 'ext.class'
local table = require 'ext.table'
local ffi = require 'ffi'
local cl = require 'ffi.OpenCL'

-- here and opencl.lua
local function ffi_new_table(T, src)
	return ffi.new(T..'['..#src..']', src)
end

local Context = class()

--[[
args:
	platform
	device
	glSharing
--]]
function Context:init(args)
	assert(args)
	local platform = assert(args.platform)
	local device = assert(args.device)
	
	local properties = table{
		cl.CL_CONTEXT_PLATFORM,
		ffi.cast('cl_context_properties', platform.obj),
	}
	if ffi.os == 'OSX' then
		if args.useGLSharing then
			ffi.cdef[[
typedef void* CGLContextObj;
CGLContextObj CGLGetCurrentContext();
			]]
			local kCGLContext = ffi.C.CGLGetCurrentContext()
			local kCGLShareGroup = ffi.C.CGLGetShareGroup(kCGLContext)
			properties:append{
				cl.CL_CONTEXT_PROPERTY_USE_CGL_SHAREGROUP_APPLE,
				kCGLShareGroup,
			}
		end
	elseif ffi.os == 'Windows' then
		if args.useGLSharing then
			ffi.cdef[[
typedef intptr_t HGLRC;
typedef intptr_t HDC;
HGLRC wglGetCurrentContext();
HDC wglGetCurrentDC();
			]]
			local gl = require 'ffi.OpenGL'
			properties:append{
				cl.CL_GL_CONTEXT_KHR,
				ffi.cast('cl_context_properties', gl.wglGetCurrentContext()),
				cl.CL_WGL_HDC_KHR,
				ffi.cast('cl_context_properties', gl.wglGetCurrentDC()),
			}
		end
	elseif ffi.os == 'Linux' then
	else
		error("don't know what properties to use for this OS")
	end
	properties:insert(0)
	properties = ffi_new_table('cl_context_properties', properties)

	local devices = {device.obj}
	local deviceIDs = ffi_new_table('cl_device_id', devices)
	local err = ffi.new('cl_uint[1]',0)
	self.obj = cl.clCreateContext(properties, #devices, deviceIDs, nil, nil, err)
	if err[0] ~= cl.CL_SUCCESS then
		error('clCreateContext failed with error '..('%x'):format(err[0]))
	end
end

return Context
