local ffi = require 'ffi'
local bit = require 'bit'
local cl = require 'ffi.OpenCL'
local class = require 'ext.class'
local classertparam = require 'cl.assertparam'

local Memory = require 'cl.memory'

local Buffer = class(Memory)

--[[
args:
	context
	
	one of the following:
		flags
		read
		write
		rw
	(TODO change to 'readwrite' field instead of multiple fields)

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
	self.size = assert(args.size)	-- in bytes
	self.id = classertparam('clCreateBuffer',
		assert(args.context).id, 
		flags,
		self.size,
		args.hostptr)
	Buffer.super.init(self, self.id)
end

return Buffer
