local class = require 'ext.class'
local table = require 'ext.table'
local ffi = require 'ffi'
local cl = require 'ffi.OpenCL'
local classert = require 'cl.assert'
local Buffer = require 'cl.buffer'

local Kernel = class()

--[[
args:
	program
	name
	args (optional)
--]]
function Kernel:init(args)
	assert(args)
	local err = ffi.new('cl_int[1]',0)
	self.obj = cl.clCreateKernel(
		assert(args.program).obj, 
		assert(args.name), 
		err)
	classert(err[0])

	if args.args then
		self:setArgs(table.unpack(args.args))
	end
end

function Kernel:setArg(index, value)
	local size, ptr
	if type(value) == 'table' then
		if Buffer.is(value) then
			ptr = ffi.new('cl_mem[1]', value.obj)
			size = ffi.sizeof'cl_mem'
		else
			error("don't know how to handle value")
		end
	else
		ptr = value
		size = ffi.sizeof(ptr)
	end
	classert(cl.clSetKernelArg(self.obj, index, size, ptr))
end

function Kernel:setArgs(...)
	for i=1,select('#',...) do
		self:setArg(i-1, select(i,...))
	end
end

return Kernel
