local class = require 'ext.class'
local table = require 'ext.table'
local ffi = require 'ffi'
local cl = require 'ffi.OpenCL'
local classert = require 'cl.assert'
local classertparam = require 'cl.assertparam'
local Wrapper = require 'cl.wrapper'

local Kernel = class(Wrapper(
	'cl_kernel',
	cl.clRetainKernel,
	cl.clReleaseKernel))

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
	Kernel.super.init(self, self.id)

	if args.args then
		self:setArgs(table.unpack(args.args))
	end
end

--[[
index = which arg index (0 based, like OpenCL)
value = value
	OpenCL Memory object: use the cl_mem member
	table: use {size=size, ptr=ptr}
	other non-table: use value and ffi.sizeof(value)
--]]
function Kernel:setArg(index, value)
	local size, ptr
	if type(value) == 'table' then
		if require 'cl.obj.buffer'.is(value) then
			value = value.obj	-- get the cl.memory
		end
		if require 'cl.memory'.is(value) then
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
		require 'cl.checkerror'(err, 'clSetKernelArg('..tostring(self.id)..', '..index..', '..size..', '..tostring(ptr)..') failed')
	end
end

function Kernel:setArgs(...)
	for i=1,select('#',...) do
		self:setArg(i-1, select(i,...))
	end
end

-- infoGetter would need one extra argument ...
function Kernel:getWorkGroupInfo(device, name)
	local infoType = 'size_t'
	local nameValue = assert(cl[name])
	local result = ffi.new(infoType..'[1]')
	classert(cl.clGetKernelWorkGroupInfo(self.id, device.id, nameValue, ffi.sizeof(infoType), result, nil))
	return result[0]
end

return Kernel
