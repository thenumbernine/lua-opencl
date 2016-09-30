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

function Kernel:setArg(index, value)
	local size, ptr
	if type(value) == 'table' then
		if require 'cl.memory'.is(value) then
			assert(value.id)
			ptr = ffi.new('cl_mem[1]', value.id)
			size = ffi.sizeof'cl_mem'
		else
			error("don't know how to handle value")
		end
	else
		ptr = value
		size = ffi.sizeof(ptr)
	end
	local err = cl.clSetKernelArg(self.id, index, size, ptr)
	if err ~= cl.CL_SUCCESS then
		error('clSetKernelArg('..tostring(self.id)..', '..index..', '..size..', '..tostring(ptr)..') failed with error '..err)
	end
end

function Kernel:setArgs(...)
	for i=1,select('#',...) do
		self:setArg(i-1, select(i,...))
	end
end

return Kernel
