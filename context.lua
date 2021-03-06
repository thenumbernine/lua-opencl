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
	devices
	glSharing
--]]
function Context:init(args)
	assert(args)
	local platform = assert(args.platform)
	local devices = assert(args.devices)
	
	local properties = table{
		cl.CL_CONTEXT_PLATFORM,
		ffi.cast('cl_context_properties', platform.id),
	}
	if args.glSharing then

		for _,device in ipairs(args.devices) do
			if not device:getExtensions():mapi(string.lower):find(nil, function(s)
				return s:match'_gl_sharing'
			end) then
				print("warning: couldn't find gl_sharing in device "..device:getName().." extensions:")
				print('',device:getExtensions():concat'\n\t')
			end
		end

		if ffi.os == 'OSX' then
			ffi.cdef[[
typedef void* CGLContextObj;
CGLContextObj CGLGetCurrentContext();
typedef void* CGLShareGroupObj;
CGLShareGroupObj CGLGetShareGroup(CGLContextObj ctx);
]]
			local kCGLContext = ffi.C.CGLGetCurrentContext()
			local kCGLShareGroup = ffi.C.CGLGetShareGroup(kCGLContext)
			if kCGLShareGroup == nil then
				print'GL sharing extension found, but CGLGetShareGroup() is null -- cannot enable GL sharing'
			else
				properties:append{
					cl.CL_CONTEXT_PROPERTY_USE_CGL_SHAREGROUP_APPLE,
					ffi.cast('cl_context_properties', kCGLShareGroup),
				}
			end
		elseif ffi.os == 'Windows' then
			ffi.cdef[[
typedef intptr_t HGLRC;
typedef intptr_t HDC;
HGLRC wglGetCurrentContext();
HDC wglGetCurrentDC();
]]
			--local gl = require 'ffi.OpenGL'
			local gl = require 'gl'
			local ctx = gl.wglGetCurrentContext()
			local dc = gl.wglGetCurrentDC()
			if args and args.verbose then
				print('wglGetCurrentContext()', ctx)
				print('wglGetCurrentDC()', dc)
			end
			if ctx == 0 or dc == 0 then
				io.stderr:write("No GL context or DC found.  GL sharing will not be enabled.\n")
			else
				properties:append{
					cl.CL_GL_CONTEXT_KHR,
					ffi.cast('cl_context_properties', ctx),
					cl.CL_WGL_HDC_KHR,
					ffi.cast('cl_context_properties', dc),
				}
			end
		else	-- linux
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
	if args and args.verbose then
		print('properties: '..require 'ext.tolua'(properties))
	end
	properties = ffi_new_table('cl_context_properties', properties)

	local devices = table.mapi(args.devices, function(device) return device.id end)
	local deviceIDs = ffi_new_table('cl_device_id', devices)

	-- useGLSharing on windows with the AMD is failing here with error -1000: CL_INVALID_GL_SHAREGROUP_REFERENCE_KHR
	self.id = classertparam('clCreateContext', properties, #devices, deviceIDs, nil, nil)

	Context.super.init(self, self.id)
end

function Context:buffer(args)
	return require 'cl.buffer'(table(args, {context=self}))
end

function Context:program(args)
	return require 'cl.program'(table(args, {context=self}))
end

Context.getInfo = Context:makeGetter{
	getter = cl.clGetContextInfo,
	vars = {
		{name='CL_CONTEXT_REFERENCE_COUNT', type='cl_uint'},
		{name='CL_CONTEXT_NUM_DEVICES', type='cl_uint'},
		{name='CL_CONTEXT_DEVICES', type='cl_device_id[]'},
		{name='CL_CONTEXT_PROPERTIES', type='cl_context_properties[]'},
	},
}

return Context
