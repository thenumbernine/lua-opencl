local class = require 'ext.class'
local table = require 'ext.table'
local ffi = require 'ffi'
local cl = require 'ffi.OpenCL'
local classertparam = require 'cl.assertparam'
local Wrapper = require 'cl.wrapper'
local GetInfo = require 'cl.getinfo'

-- here and commandqueue.lua
local function ffi_new_table(T, src)
	return ffi.new(T..'['..#src..']', src)
end

local Context = class(GetInfo(Wrapper(
	'cl_context',
	cl.clRetainContext,
	cl.clReleaseContext)))

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
		
if not device:getExtensions():find'_gl_sharing' then
	print"warning: couldn't find gl_sharing in device extensions:"
	print(device:getExtensions())
end
		
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
			ffi.cdef[[
typedef void Display;
typedef intptr_t GLXContext;
GLXContext glXGetCurrentContext();
Display* glXGetCurrentDisplay();
]]
			local gl = require 'ffi.OpenGL'
			properties:append{
				cl.CL_GL_CONTEXT_KHR,
				ffi.cast('cl_context_properties', gl.glXGetCurrentContext()),
				cl.CL_GLX_DISPLAY_KHR,
				ffi.cast('cl_context_properties', gl.glXGetCurrentDisplay()),
			}
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

Context.infoGetter = cl.clGetContextInfo 

Context.infos = {
	{name='CL_CONTEXT_REFERENCE_COUNT', type='cl_uint'},
	{name='CL_CONTEXT_DEVICES', type='cl_device_id[]'},
	{name='CL_CONTEXT_PROPERTIES', type='cl_context_properties[]'},
}

return Context