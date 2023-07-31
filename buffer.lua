local ffi = require 'ffi'
local bit = require 'bit'
local cl = require 'ffi.req' 'OpenCL'
local class = require 'ext.class'
local classertparam = require 'cl.assertparam'

local Memory = require 'cl.memory'

local Buffer = class(Memory)

--[[
args:
	context

	flags = buffer init flags
		(flags are also inferred from the following):
	readwrite (optional) = read | write | rw
	hostptr (optional)
	alloc (optional)
	copy (optional)

	size
--]]
function Buffer:init(args)
	assert(args)
	local flags = args.flags or 0
	self.readwrite = args.readwrite
	if args.readwrite == 'read' then flags = bit.bor(flags, cl.CL_MEM_READ_ONLY) end
	if args.readwrite == 'write' then flags = bit.bor(flags, cl.CL_MEM_WRITE_ONLY) end
	if args.readwrite == 'rw' then flags = bit.bor(flags, cl.CL_MEM_READ_WRITE) end
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

--[[
args:
	one of the following:
	flags (optional)
		if flags is not provided then they are inferred from self.readwrite


	origin (optional) default = 0
	size (optional) default = self.size
--]]
local region = ffi.new'cl_buffer_region[1]'
function Buffer:createSubBuffer(args)
	local flags = args.flags
	if flags == nil then
		flags = 0
		if self.readwrite == 'read' then flags = bit.bor(flags, cl.CL_MEM_READ_ONLY) end
		if self.readwrite == 'write' then flags = bit.bor(flags, cl.CL_MEM_WRITE_ONLY) end
		if self.readwrite == 'rw' then flags = bit.bor(flags, cl.CL_MEM_READ_WRITE) end
	end

	region[0].origin = args.origin or 0
	region[0].size = args.size or self.size

	local id = classertparam('clCreateSubBuffer',
		self.id,
		flags,
		cl.CL_BUFFER_CREATE_TYPE_REGION,
		region)

	local sub = setmetatable({
		id = id,
		origin = tonumber(region[0].origin),
		size = tonumber(region[0].size),
	}, Buffer)
	Memory.init(sub, sub.id)
	return sub
end

return Buffer
