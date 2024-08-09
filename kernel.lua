local table = require 'ext.table'
local ffi = require 'ffi'
local cl = require 'ffi.req' 'OpenCL'
local classertparam = require 'cl.assertparam'
local clCheckError = require 'cl.checkerror'
local GCWrapper = require 'cl.gcwrapper'
local CLMemory = require 'cl.memory'
local CLBufferObj = require 'cl.obj.buffer'
local GetInfo = require 'cl.getinfo'

local Kernel = GetInfo(GCWrapper{
	ctype = 'cl_kernel',
	retain = function(self) return cl.clRetainKernel(self.id) end,
	release = function(self) return cl.clReleaseKernel(self.id) end,
}):subclass()

--[[
args:
	program
	name
	args (optional)
--]]
function Kernel:init(args)
	assert(args)
	self.id = classertparam('clCreateKernel',
		assert(args.program).id,
		assert(args.name))

	if args.args then
		self:setArgs(table.unpack(args.args))
	end
end

--[[
index = which arg index (0 based, like OpenCL)
value = value
	nil: skips assignment
	OpenCL Memory object: use the cl_mem member
	table: use {size=size, ptr=ptr}
	other non-table: use value and ffi.sizeof(value)
--]]
function Kernel:setArg(index, value)
	local size, ptr
	if value == nil then
		return
	elseif type(value) == 'table' then
		if CLBufferObj:isa(value) then
			value = value.obj	-- get the cl.memory
		end
		if CLMemory:isa(value) then
			assert(value.id)
			ptr = ffi.new('cl_mem[1]', value.id)
			size = ffi.sizeof'cl_mem'
		elseif value.size then
			ptr = value.ptr or ffi.cast('const void*', 0)
			size = value.size
		else
			error("don't know how to handle value")
		end
	else
		ptr = value
		size = ffi.sizeof(ptr)
	end
	local err = cl.clSetKernelArg(self.id, index, size, ptr)
	if err ~= cl.CL_SUCCESS then
		clCheckError(err, 'clSetKernelArg('..tostring(self.id)..', '..index..', '..size..', '..tostring(ptr)..') failed')
	end
end

function Kernel:setArgs(...)
	for i=1,select('#',...) do
		self:setArg(i-1, select(i,...))
	end
end

Kernel.getInfo = Kernel:makeGetter{
	getter = cl.clGetKernelInfo,
	vars = {
		-- 1.0
		{name='CL_KERNEL_FUNCTION_NAME', type='char[]'},
		{name='CL_KERNEL_NUM_ARGS', type='cl_uint'},
		{name='CL_KERNEL_REFERENCE_COUNT', type='cl_uint'},	-- ???
		{name='CL_KERNEL_CONTEXT', type='cl_context'},
		{name='CL_KERNEL_PROGRAM', type='cl_program'},
		-- 1.2
		{name='CL_KERNEL_ATTRIBUTES', type='char[]'},
		{name='CL_KERNEL_MAX_NUM_SUB_GROUPS', type=''},
		{name='CL_KERNEL_COMPILE_NUM_SUB_GROUPS', type=''},
	},
}

Kernel.getArgInfo = Kernel:makeGetter{
	getter = function(kernelID, paramName, paramValueSize, paramValue, paramValueSizeRet, argIndex)
		return cl.clGetKernelArgInfo(kernelID, argIndex, paramName, paramValueSize, paramValue, paramValueSizeRet)
	end,
	vars = {
		{name='CL_KERNEL_ARG_ADDRESS_QUALIFIER', type='cl_kernel_arg_address_qualifier'},
		{name='CL_KERNEL_ARG_ACCESS_QUALIFIER', type='cl_kernel_arg_access_qualifier'},
		{name='CL_KERNEL_ARG_TYPE_NAME', type='char[]'},
		{name='CL_KERNEL_ARG_TYPE_QUALIFIER', type='cl_kernel_arg_type_qualifer'},
		{name='CL_KERNEL_ARG_NAME', type='char[]'},
	},
}

Kernel.getWorkGroupInfo = Kernel:makeGetter{
	getter = function(kernelID, paramName, paramValueSize, paramValue, paramValueSizeRet, deviceID)
		if require 'cl.device':isa(deviceID) then deviceID = deviceID.id end
		return cl.clGetKernelWorkGroupInfo(kernelID, deviceID, paramName, paramValueSize, paramValue, paramValueSizeRet)
	end,
	vars = {
		{name='CL_KERNEL_WORK_GROUP_SIZE', type='size_t'}, -- ???
		{name='CL_KERNEL_COMPILE_WORK_GROUP_SIZE', type='size_t'}, -- ???
		{name='CL_KERNEL_LOCAL_MEM_SIZE', type='size_t'}, -- ???
		{name='CL_KERNEL_PREFERRED_WORK_GROUP_SIZE_MULTIPLE', type='size_t'}, -- ???
		{name='CL_KERNEL_PRIVATE_MEM_SIZE', type='size_t'}, -- ???
		{name='CL_KERNEL_GLOBAL_WORK_SIZE', type='size_t'}, -- ???
	},
}

--kernel:getSubGroupInfo(name, deviceID, inputValueSize, inputValue)
Kernel.getSubGroupInfo = Kernel:makeGetter{
	getter = function(kernelID, paramName, paramValueSize, paramValue, paramValueSizeRet, deviceID, inputValueSize, inputValue)
		if require 'cl.device':isa(deviceID) then deviceID = deviceID.id end
		return cl.clGetKernelSubGroupInfo(kernelID, deviceID, paramName, paramValueSize, paramValue, paramValueSizeRet)
	end,
	vars = {
		{name='CL_KERNEL_MAX_SUB_GROUP_SIZE_FOR_NDRANGE', type=''},
		{name='CL_KERNEL_SUB_GROUP_COUNT_FOR_NDRANGE', type=''},
		{name='CL_KERNEL_LOCAL_SIZE_FOR_SUB_GROUP_COUNT', type=''},
	},
}

-- these are for clSetKernelExecInfo.  where's the getter?  does clGetKernelInfo double as that?
--{name='CL_KERNEL_EXEC_INFO_SVM_PTRS', type=''},
--{name='CL_KERNEL_EXEC_INFO_SVM_FINE_GRAIN_SYSTEM', type=''},

return Kernel
