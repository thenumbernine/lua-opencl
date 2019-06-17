local ffi = require 'ffi'
local cl = require 'ffi.OpenCL'
local class = require 'ext.class'
local table = require 'ext.table'
local string = require 'ext.string'
local classert = require 'cl.assert'
local classertparam = require 'cl.assertparam'
local clCheckError = require 'cl.checkerror'
local Wrapper = require 'cl.wrapper'
local GetInfo = require 'cl.getinfo'

local Program = class(GetInfo(Wrapper(
	'cl_program',
	cl.clRetainProgram,
	cl.clReleaseProgram)))

--[[
args:
	context
	code = string
	binaries = table of strings of binary data to create with clCreateProgramWithBinary
	programs = table of Programs created with clBuildProgram
	code / binaries / programs are exclusive arguments.
	devices = array of device ids (optional, but required for binaries)
		if 'devices' is provided then the program is immediately compiled.
	dontLink = optional.  when devices is specified, if this is not set then :build is used, if this is set then :compile is used.
	buildOptions = options to pass through to Program:build or Program:compile (only if we are compiling, therefore only if 'devices' is provided)
--]]
function Program:init(args)
	assert(args)
	local context = assert(args.context)
	local code = args.code
	local binaries = args.binaries
	local programs = args.programs
	assert(code or binaries or programs, "expected either code, binaries, or program")
	if code then	
		local strings = ffi.new('const char*[1]')
		strings[0] = ffi.cast('const char*',code)
		local lengths = ffi.new('size_t[1]')
		lengths[0] = #code
		self.id = classertparam('clCreateProgramWithSource', context.id, 1, strings, lengths)
	-- create from binary
	elseif binaries then
		local devices = assert(args.devices, "binaries expects devices")
		local numDevices = #devices
		local deviceIDs = ffi.new('cl_device_id[?]', numDevices)
		for i=1,numDevices do
			deviceIDs[i-1] = devices[i].id
		end
		local n = #binaries
		local lengths = ffi.new('size_t[?]', n)
		local binptrs = ffi.new('unsigned char*[?]', n)
		local binary_status = ffi.new('cl_int[?]', n)
		for i,bin in ipairs(binaries) do
			lengths[i-1] = #bin
			binptrs[i-1] = ffi.cast('unsigned char*', bin)
			binary_status[i-1] = cl.CL_SUCCESS
		end
		self.id = classertparam('clCreateProgramWithBinary', context.id, numDevices, deviceIDs, lengths, ffi.cast('const unsigned char**', binptrs), binary_status)
		for i=1,n do
			clCheckError(binary_status[i-1], 'clCreateProgramWithBinary failed on binary #'..i)
		end
	elseif programs then
		assert(#programs > 0, "can't link an empty program")
		-- cl.hpp doesn't pass devices
		local devices = assert(args.devices, "binaries expects devices")
		local deviceIDs = ffi.new('cl_device_id[?]', #devices)
		for i=1,#devices do
			deviceIDs[i-1] = devices[i].id
		end
		local programIDs = ffi.new('cl_program[?]', #programs)
		for i=1,#programs do
			local p = programs[i]
			assert(p, "tried to link a nil program")
			if type(p) == 'table' and p.obj then p = p.obj end
			programIDs[i-1] = p.id
		end
		self.id = classertparam('clLinkProgram', context.id, #devices, deviceIDs, args.buildOptions, #programs, programIDs, nil, nil)
	end
	Program.super.init(self, self.id)
	
	if args.devices and not programs then
		if args.dontLink then
			local success, message = self:compile(args.devices, args.buildOptions)
			if not success then
				error(message)
			end
		else
			local success, message = self:build(args.devices, args.buildOptions)
			if not success then
				if code then print(require 'template.showcode'(code)) end
				error(message)
			end
		end
	end
end

-- calls clCompileProgram, which just does source -> obj 
function Program:compile(devices, options)
	-- notice, cl.hpp doesn't use devices
	local devices = assert(devices, "binaries expects devices")
	local deviceIDs = ffi.new('cl_device_id[?]', #devices)
	for i=1,#devices do
		deviceIDs[i-1] = devices[i].id
	end
	local err = cl.clCompileProgram(self.id, #devices, deviceIDs, options, 0, nil, nil, nil, nil)
	local success = err == cl.CL_SUCCESS
	local message
	if not success then 
		message = table{'failed to compile with error '..tostring(err)}
		for _,device in ipairs(devices) do
			message:insert(self:getLog(device))
		end
		message = message:concat'\n'
	end
	return success, message 
end

-- calls clBuildProgram, which compiles source -> obj and then obj -> exe
function Program:build(devices, options)
	local deviceIDs = ffi.new('cl_device_id[?]', #devices)
	for i=1,#devices do
		deviceIDs[i-1] = devices[i].id
	end
	local err = cl.clBuildProgram(self.id, #devices, deviceIDs, options, nil, nil)
	local success = err == cl.CL_SUCCESS
	local message
	if not success then 
		message = table{'failed to build with error '..tostring(err)}
		for _,device in ipairs(devices) do
			message:insert(self:getLog(device))
		end
		message = message:concat'\n'
	end
	return success, message 
end

function Program:getBuildInfo(device, name)
	assert(name, "expected name")
	local size = ffi.new('size_t[1]', 0)
	classert(cl.clGetProgramBuildInfo(self.id, device.id, name, 0, nil, size))
	local param = ffi.new('char[?]', size[0])
	classert(cl.clGetProgramBuildInfo(self.id, device.id, name, size[0], param, nil))
	return ffi.string(param, size[0])
end

function Program:getLog(device)
	return self:getBuildInfo(device, cl.CL_PROGRAM_BUILD_LOG)
end

--[[
usage:
	program:kernel(name, arg1, ...)
	program:kernel{name=name, args={...}}
--]]
function Program:kernel(args, ...)
	if type(args) == 'string' then
		args = {name=args}
		if select('#', ...) then
			args.args = {...}
		end
	end
	return require 'cl.kernel'(table(args, {program=self}))
end

Program.infoGetter = cl.clGetProgramInfo
Program.infos = {
	{name='CL_PROGRAM_REFERENCE_COUNT', type='cl_uint'},
	{name='CL_PROGRAM_CONTEXT', type='cl_uint'},
	{name='CL_PROGRAM_NUM_DEVICES', type='cl_uint'},
	{name='CL_PROGRAM_DEVICES', type='cl_device_id[]'},
	{name='CL_PROGRAM_SOURCE', type='string'},
	{name='CL_PROGRAM_BINARY_SIZES', type='size_t[]'},
	{name='CL_PROGRAM_BINARIES', type='string[]'},
	{name='CL_PROGRAM_NUM_KERNELS', type='cl_uint'},
	{name='CL_PROGRAM_KERNEL_NAMES', type='string'},
	{name='CL_PROGRAM_IL', type='string[]'},	-- ???
	
	-- these are for clGetProgramBuildInfo
	--{name='CL_PROGRAM_BUILD_STATUS', type='unsigned char*[]'},
	--{name='CL_PROGRAM_BUILD_OPTIONS', type='cl_uint'},
	--{name='CL_PROGRAM_BUILD_LOG', type='cl_uint'},
	--{name='CL_PROGRAM_BINARY_TYPE', type='cl_uint'},	-- ??? 
	--{name='CL_PROGRAM_BUILD_GLOBAL_VARIABLE_TOTAL_SIZE', type='cl_uint'},	-- ???

	--[[
	CL_PROGRAM_BINARY_TYPE_NONE                 = 0x0,
	CL_PROGRAM_BINARY_TYPE_COMPILED_OBJECT      = 0x1,
	CL_PROGRAM_BINARY_TYPE_LIBRARY              = 0x2,
	CL_PROGRAM_BINARY_TYPE_EXECUTABLE           = 0x4,
	--]]
}

function Program:getRefCount() return self:getInfo'CL_PROGRAM_REFERENCE_COUNT' end
function Program:getContext() return self:getInfo'CL_PROGRAM_CONTEXT' end
function Program:getDevices() return self:getInfo'CL_PROGRAM_DEVICES' end
function Program:getSource() return self:getInfo'CL_PROGRAM_SOURCE' end

function Program:getBinaries() 
	local binSizes = self:getInfo'CL_PROGRAM_BINARY_SIZES' 
	local bins = ffi.new('unsigned char*[?]', #binSizes)
	for i,size in ipairs(binSizes) do
		bins[i-1] = ffi.new('unsigned char[?]', size)
	end
	classert(cl.clGetProgramInfo(self.id, cl.CL_PROGRAM_BINARIES, ffi.sizeof(bins), bins, nil))
	return binSizes:mapi(function(size,i) return ffi.string(bins[i-1],size) end)
end

return Program
