local class = require 'ext.class'
local table = require 'ext.table'
local ffi = require 'ffi'
local cl = require 'ffi.OpenCL'
local classertparam = require 'cl.assertparam'
local Wrapper = require 'cl.wrapper'

-- here and commandqueue.lua
local function ffi_new_table(T, src)
	return ffi.new(T..'['..#src..']', src)
end

local Context = class(Wrapper(
	'cl_context',
	cl.clRetainContext,
	cl.clReleaseContext))

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
		ffi.cast('cl_context_properties', platform.id),
	}
	if args.glSharing then
		if ffi.os == 'OSX' then
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
		elseif ffi.os == 'Windows' then
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
		else
			error("don't know how to setup GL context sharing for OS "..ffi.os)
		end
	end
	properties:insert(0)
	properties = ffi_new_table('cl_context_properties', properties)

	local devices = {device.id}
	local deviceIDs = ffi_new_table('cl_device_id', devices)
	self.id = classertparam('clCreateContext', properties, #devices, deviceIDs, nil, nil)

	Context.super.init(self, self.id)
end

function Context:buffer(args)
	return require 'cl.buffer'(table(args, {context=self}))
end

return Context
