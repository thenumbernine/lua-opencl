local ffi = require 'ffi'
local cl = require 'ffi.req' 'OpenCL'
local class = require 'ext.class'
local table = require 'ext.table'
local classert = require 'cl.assert'
local classertparam = require 'cl.assertparam'
local clCheckError = require 'cl.checkerror'
local GCWrapper = require 'ffi.gcwrapper.gcwrapper'
local GetInfo = require 'cl.getinfo'

local Program = class(GetInfo(GCWrapper{
	ctype = 'cl_program',
	retain = function(ptr) return cl.clRetainProgram(ptr[0]) end,
	release = function(ptr) return cl.clReleaseProgram(ptr[0]) end,
}))

Program.showCodeOnError = true

--[[
args:
	context
	code = string
	binaries = table of strings of binary data to create with clCreateProgramWithBinary
	programs = table of Programs created with clBuildProgram
	code / binaries / IL / programs are exclusive arguments.
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
	local IL = args.IL	-- intermediateLanguage
	local programs = args.programs
	assert(code or binaries or IL or programs, "expected either code, binaries, IL, or programs")
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
	elseif IL then
		assert(type(IL) == 'string')
		self.id = classertparam('clCreateProgramWithIL', context.id, ffi.cast('void const *', IL), #IL)
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
		local err = ffi.new'cl_int[1]'
		self.id = cl.clLinkProgram(context.id, #devices, deviceIDs, args.buildOptions, #programs, programIDs, nil, nil, err)
		if err[0] ~= cl.CL_SUCCESS then
			local message = table{'clLinkProgram failed with error '..tostring(err[0])}
			for i,device in ipairs(devices) do
				message:insert('device #'..i..' log:\n'
					..tostring(
						-- ok what if the program didn't create / such that getLog() isn't valid?
						-- then my API is set up to throw an exception...
						(select(2,
							xpcall(function()
								return self:getLog(device)
							end, function(err)
								return "(can't get log ... "..err..")"
							end)
						))
					)
				)
			end
			message = message:concat'\n'
			clCheckError(err[0], message)
		end
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
				if code and (self.showCodeOnError or args.showCodeOnError) then
					print(require 'template.showcode'(code))
				end
				error(message)
			end
		end
	end
end

-- calls clCompileProgram, which just does source -> obj
function Program:compile(devices, options)
	-- notice, cl.hpp doesn't use devices
	assert(devices, "binaries expects devices")
	local deviceIDs = ffi.new('cl_device_id[?]', #devices)
	for i=1,#devices do
		deviceIDs[i-1] = devices[i].id
	end
	local err = cl.clCompileProgram(self.id, #devices, deviceIDs, options, 0, nil, nil, nil, nil)
	local success = err == cl.CL_SUCCESS
	local message
	if not success then
		message = table{'clCompileProgram failed with error '..tostring(err)}
		for i,device in ipairs(devices) do
			message:insert('device #'..i..' log:\n'..tostring(self:getLog(device)))
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
		message = table{'clBuildProgram failed with error '..tostring(err)}
		for _,device in ipairs(devices) do
			message:insert(self:getLog(device))
		end
		message = message:concat'\n'
	end
	return success, message
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

-- program:getInfo(name of cl_program_build_info)
Program.getInfo = Program:makeGetter{
	getter = cl.clGetProgramInfo,
	vars = {
		{name='CL_PROGRAM_REFERENCE_COUNT', type='cl_uint'},
		{name='CL_PROGRAM_CONTEXT', type='cl_uint'},
		{name='CL_PROGRAM_NUM_DEVICES', type='cl_uint'},
		{name='CL_PROGRAM_DEVICES', type='cl_device_id[]'},
		{name='CL_PROGRAM_SOURCE', type='char[]'},
		{name='CL_PROGRAM_BINARY_SIZES', type='size_t[]'},
		{name='CL_PROGRAM_BINARIES', type='unsigned char*[]'},	-- ???
		{name='CL_PROGRAM_NUM_KERNELS', type='size_t'},
		{name='CL_PROGRAM_KERNEL_NAMES', type='char[]', separator=';'},
		{name='CL_PROGRAM_IL', type='void*'},	-- ???
	},
}

function Program:getRefCount() return self:getInfo'CL_PROGRAM_REFERENCE_COUNT' end
function Program:getContext() return self:getInfo'CL_PROGRAM_CONTEXT' end
function Program:getDevices() return self:getInfo'CL_PROGRAM_DEVICES' end
function Program:getSource() return self:getInfo'CL_PROGRAM_SOURCE' end

-- TODO add to cl/getinfo.lua an entry for char*[], and maybe a field for associated sizes getter variable name
function Program:getBinaries()
	local binSizes = self:getInfo'CL_PROGRAM_BINARY_SIZES'
	local bins = ffi.new('unsigned char*[?]', #binSizes)
	for i,size in ipairs(binSizes) do
		bins[i-1] = ffi.new('unsigned char[?]', size)
	end
	classert(cl.clGetProgramInfo(self.id, cl.CL_PROGRAM_BINARIES, ffi.sizeof(bins), bins, nil))
	return binSizes:mapi(function(size,i) return ffi.string(bins[i-1],size) end)
end

-- program:getBuildInfo(name of cl_program_build_info, cl_device_id)
Program.getBuildInfo = Program:makeGetter{
	getter = function(programID, paramName, paramValueSize, paramValue, paramValueSizeRet, deviceID)
		return cl.clGetProgramBuildInfo(programID, deviceID, paramName, paramValueSize, paramValue, paramValueSizeRet)
	end,
	vars = {
		{name='CL_PROGRAM_BUILD_STATUS', type='unsigned char*[]'},	-- TODO implement this in getinfo.lua
		{name='CL_PROGRAM_BUILD_OPTIONS', type='cl_uint'},
		{name='CL_PROGRAM_BUILD_LOG', type='char[]'},	-- ???
		{name='CL_PROGRAM_BINARY_TYPE', type='cl_program_binary_type'},
		{name='CL_PROGRAM_BUILD_GLOBAL_VARIABLE_TOTAL_SIZE', type='cl_uint'},	-- ???
	},
}

function Program:getLog(device)
	return self:getBuildInfo('CL_PROGRAM_BUILD_LOG', device.id)
end

return Program
