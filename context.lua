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
	local verbose = args.verbose

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
			if verbose then
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
	if verbose then
		print('properties: '..require 'ext.tolua'(properties))
	end
	properties = ffi_new_table('cl_context_properties', properties)

	local devices = table.mapi(args.devices, function(device) return device.id end)
	local deviceIDs = ffi_new_table('cl_device_id', devices)

	--[[
	if you're on AMD and GL sharing won't work ...
		TODO FIXME NOTICE READ THIS
	it seems with AMD you will always fail unless you pick the device listed as current: 
	then, before any of that, let's see what's avaiable ...
	--]]
	if args.glSharing and verbose then
		local CLDevice = require 'cl.device'
		local classert = require 'cl.assert'
		local clGetGLContextInfoKHR = ffi.cast('clGetGLContextInfoKHR_fn', cl.clGetExtensionFunctionAddressForPlatform(platform.id, 'clGetGLContextInfoKHR'))
	
		local numGLDevicesRef = ffi.new'size_t[1]'
		classert(clGetGLContextInfoKHR(properties, cl.CL_DEVICES_FOR_GL_CONTEXT_KHR, 0, nil, numGLDevicesRef))
		local numGLDevices = tonumber(numGLDevicesRef[0]) / ffi.sizeof'cl_device_id'
		print('clGetGLContextInfoKHR: '..numGLDevices..' devices that have GL sharing')
		local allGLDeviceIDs = ffi.new('cl_device_id[?]', numGLDevices)
		classert(clGetGLContextInfoKHR(properties, cl.CL_DEVICES_FOR_GL_CONTEXT_KHR, ffi.sizeof'cl_device_id' * numGLDevices, allGLDeviceIDs, nil))
		print'clGetGLContextInfoKHR: all devices with GL sharing:'
		local allGLDevices = table()
		for i=0,tonumber(numGLDevices)-1 do
			local device = CLDevice(allGLDeviceIDs[i])
			allGLDevices:insert(device)
			print('', device:getName())
		end

		local currentGLDeviceIDRef = ffi.new'cl_device_id[1]'
		classert(clGetGLContextInfoKHR(properties, cl.CL_CURRENT_DEVICE_FOR_GL_CONTEXT_KHR, ffi.sizeof'cl_device_id', currentGLDeviceIDRef, nil))
		local gldeviceid = currentGLDeviceIDRef[0]
		local gldevice = CLDevice(gldeviceid)
		print('clGetGLContextInfoKHR: current GL device:', gldevice:getName())
	end

	--[[
	With AMD, if you just use any device that says it has cl_khr_gl_sharing, this will probably fail.
	Why? BECAUSE THE AMD CL EXTENSION REPORTS BULLSHIT INFORMATION.
	My AMD OpenCL reports two devices, both claim to have "cl_khr_gl_sharing", but only one of them shows up on the list of clGetGLContextInfoKHR.
	With AMD you *cannot* only go by extension. You must also query clGetGLContextInfoKHR
	Otherwise here you will get an error -1000: CL_INVALID_GL_SHAREGROUP_REFERENCE_KHR
	--]]
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
