local assert = require 'ext.assert'
local table = require 'ext.table'
local ffi = require 'ffi'
local cl = require 'cl'
local classertparam = require 'cl.assertparam'
local GCWrapper = require 'cl.gcwrapper'
local GetInfo = require 'cl.getinfo'

-- here and commandqueue.lua
local function ffi_new_table(T, src)
	return ffi.new(T..'['..#src..']', src)
end

local Context = GetInfo(GCWrapper{
	ctype = 'cl_context',
	retain = function(self) return cl.clRetainContext(self.id) end,
	release = function(self) return cl.clReleaseContext(self.id) end,
}):subclass()

--[[
args:
	platform
	devices
	glSharing
--]]
function Context:init(args)
	assert(args)
	local platform = assert.index(args, 'platform')
	local devices = assert.index(args, 'devices')

	local properties = table{
		cl.CL_CONTEXT_PLATFORM,
		ffi.cast('cl_context_properties', platform.id),
	}
	if args.glSharing then

		for _,device in ipairs(devices) do
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
			local gl = require 'gl'
			local ctx = gl.wglGetCurrentContext()
			local dc = gl.wglGetCurrentDC()
--DEBUG:print('wglGetCurrentContext()', ctx)
--DEBUG:print('wglGetCurrentDC()', dc)
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
-- [=[ right around sdl3 this just stopped working, glXGet* returns 0's ...
			ffi.cdef[[
typedef void Display;
typedef intptr_t GLXContext;
GLXContext glXGetCurrentContext();
Display* glXGetCurrentDisplay();
]]
			local gl = require 'gl'
--DEBUG:print('glXGetCurrentContext', gl.glXGetCurrentContext())
--DEBUG:print('glXGetCurrentDisplay', gl.glXGetCurrentDisplay())
			properties:append{
				cl.CL_GL_CONTEXT_KHR,
				ffi.cast('cl_context_properties', gl.glXGetCurrentContext()),
				cl.CL_GLX_DISPLAY_KHR,
				ffi.cast('cl_context_properties', gl.glXGetCurrentDisplay()),
			}
--]=]
--[=[ while I get nonzero values back, this is segfaulting ... looks like some vendors just dont support EGL and OpenCL
			local sdl = require'sdl'
			local egl = require 'ffi.req' 'EGL'
			properties:append{
				cl.CL_GL_CONTEXT_KHR,
				ffi.cast('cl_context_properties', sdl.SDL_GL_GetCurrentContext()),	-- https://stackoverflow.com/a/39476759
				cl.CL_EGL_DISPLAY_KHR,
				ffi.cast('cl_context_properties', egl.eglGetDisplay(egl.EGL_DEFAULT_DISPLAY)),
			}
--]=]
		end
	end
	properties:insert(0)
--DEBUG:print('properties: '..require 'ext.tolua'(properties))
	properties = ffi_new_table('cl_context_properties', properties)

	devices = table.mapi(devices, function(device) return device.id end)
--DEBUG:print('devices: '..require 'ext.tolua'(devices))
	local deviceIDs = ffi_new_table('cl_device_id', devices)

	--[[
	if you're on AMD and GL sharing won't work ...
		TODO FIXME NOTICE READ THIS
	it seems with AMD you will always fail unless you pick the device listed as current:
	then, before any of that, let's see what's avaiable ...
	--]]
	if args.glSharing then
		local CLDevice = require 'cl.device'
		local classert = require 'cl.assert'
		local clGetGLContextInfoKHR = ffi.cast('clGetGLContextInfoKHR_fn', cl.clGetExtensionFunctionAddressForPlatform(platform.id, 'clGetGLContextInfoKHR'))
--DEBUG:print('clGetGLContextInfoKHR function pointer', clGetGLContextInfoKHR)

		local currentGLDeviceID = ffi.new'cl_device_id[1]'
		currentGLDeviceID[0] = ffi.cast('cl_device_id', nil)
		classert(clGetGLContextInfoKHR(properties, cl.CL_CURRENT_DEVICE_FOR_GL_CONTEXT_KHR, ffi.sizeof'cl_device_id', currentGLDeviceID, nil))
--DEBUG:print('clGetGLContextInfoKHR CL_CURRENT_DEVICE_FOR_GL_CONTEXT_KHR', currentGLDeviceID[0])

		local numGLDevicesRef = ffi.new'size_t[1]'
		classert(clGetGLContextInfoKHR(properties, cl.CL_DEVICES_FOR_GL_CONTEXT_KHR, 0, nil, numGLDevicesRef))
--DEBUG:print('numGLDevicesRef', numGLDevicesRef)
		local numGLDevices = tonumber(numGLDevicesRef[0]) / ffi.sizeof'cl_device_id'
--DEBUG:print('clGetGLContextInfoKHR: '..numGLDevices..' devices that have GL sharing')
		local allGLDeviceIDs = ffi.new('cl_device_id[?]', numGLDevices)
		classert(clGetGLContextInfoKHR(properties, cl.CL_DEVICES_FOR_GL_CONTEXT_KHR, ffi.sizeof'cl_device_id' * numGLDevices, allGLDeviceIDs, nil))
--DEBUG:print'clGetGLContextInfoKHR: all devices with GL sharing:'
		local allGLDevices = table()
		for i=0,tonumber(numGLDevices)-1 do
			local device = CLDevice(allGLDeviceIDs[i])
			allGLDevices:insert(device)
--DEBUG:print('', device:getName())
		end

		local currentGLDeviceIDRef = ffi.new'cl_device_id[1]'
		classert(clGetGLContextInfoKHR(properties, cl.CL_CURRENT_DEVICE_FOR_GL_CONTEXT_KHR, ffi.sizeof'cl_device_id', currentGLDeviceIDRef, nil))
		local gldeviceid = currentGLDeviceIDRef[0]
		local gldevice = CLDevice(gldeviceid)
--DEBUG:print('clGetGLContextInfoKHR: current GL device:', gldevice:getName())
	end

	--[[
	With AMD, if you just use any device that says it has cl_khr_gl_sharing, this will probably fail.
	Why? BECAUSE THE AMD CL EXTENSION REPORTS BULLSHIT INFORMATION.
	My AMD OpenCL reports two devices, both claim to have "cl_khr_gl_sharing", but only one of them shows up on the list of clGetGLContextInfoKHR.
	With AMD you *cannot* only go by extension. You must also query clGetGLContextInfoKHR
	Otherwise here you will get an error -1000: CL_INVALID_GL_SHAREGROUP_REFERENCE_KHR
	--]]
	self.id = classertparam('clCreateContext', properties, #devices, deviceIDs, nil, nil)
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
