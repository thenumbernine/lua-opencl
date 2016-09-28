local ffi = require 'ffi'
local bit = require 'bit'
local cl = require 'ffi.OpenCL'
local class = require 'ext.class'
local classert = require 'cl.assert'

local Buffer = class()

--[[
args:
	context
	
	one of the following:
		flags
		read
		write
		rw

	size
	
	hostptr (optional)
	alloc (optional)
	copy (optional)
--]]
function Buffer:init(args)
	assert(args)
	local err = ffi.new('cl_int[1]',0)
	local flags = args.flags or 0
	if args.read then flags = bit.bor(flags, cl.CL_MEM_READ_ONLY) end
	if args.write then flags = bit.bor(flags, cl.CL_MEM_WRITE_ONLY) end
	if args.rw then flags = bit.bor(flags, cl.CL_MEM_READ_WRITE) end
	if args.hostptr then flags = bit.bor(flags, cl.CL_MEM_USE_HOST_PTR) end
	if args.alloc then flags = bit.bor(flags, cl.CL_MEM_ALLOC_HOST_PTR) end
	if args.copy then flags = bit.bor(flags, cl.CL_MEM_COPY_HOST_PTR) end
	self.obj = cl.clCreateBuffer(
		assert(args.context).obj, 
		flags,
		assert(args.size),
		args.hostptr,
		err)
	classert(err[0])
end

return Buffer
