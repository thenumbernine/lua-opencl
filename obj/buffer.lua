local class = require 'ext.class'
local ffi = require 'ffi'
local half = require 'cl.obj.half'

local CLBuffer = class()

--[[
readwrite = rw|read|write. default rw.  used in allocation
constant = used in kernel parameter generation
--]]
function CLBuffer:init(args)
	self.env = assert(args.env)
	self.name = args.name or 'buffer_'..tostring(self):sub(10)
	self.type = args.type or args.env.real
	self.count = args.count or args.env.base.volume
	self.readwrite = args.readwrite or 'rw'
	self.constant = args.constant
	self.obj = self.env:clalloc(self.count * ffi.sizeof(self.type), self.name, self.type, self.readwrite)

	-- TODO use hostptr of cl.buffer, which is hidden behind env:clalloc
	if args.data then self:fromCPU(args.data) end

	-- TODO optionally keep track of data as self.data with self.keep flag
end

--[[
	ptr = pointer to copy to
	cmd = command-queue to use to copy.
		default = self.env.cmds[1]
--]]
function CLBuffer:fromCPU(ptr, cmd)
	cmd = cmd or self.env.cmds[1]
	if type(ptr) == 'table' then	-- convert to ffi memory
		local cptr = ffi.new(self.type..'[?]', self.count)
		local m = math.min(#ptr, self.count)
		for i=1,m do
			cptr[i-1] = ffi.cast(self.type, ptr[i])
		end
		--[[
		for i=m,self.count-1 do
			cptr[i] = ffi.cast(self.type, 0)	-- ?
		end
		--]]
		ptr = cptr
	end
	assert(type(ptr) == 'cdata')
	cmd:enqueueWriteBuffer{buffer=self.obj, block=true, size=ffi.sizeof(self.type) * self.count, ptr=ptr}
end

--[[
ptr = pointer to use
cmd = command-queue to use
--]]
function CLBuffer:toCPU(ptr, cmd)
	cmd = cmd or self.env.cmds[1]
	ptr = ptr or ffi.new(self.type..'[?]', self.count)
	cmd:enqueueReadBuffer{buffer=self.obj, block=true, size=ffi.sizeof(self.type) * self.count, ptr=ptr}
	return ptr
end

function CLBuffer:fill(pattern, patternSize, cmd)
	cmd = cmd or self.env.cmds[1]
	if not pattern then pattern = half.toreal(0) end
	if type(pattern) ~= 'cdata' then
		pattern = ffi.new(self.type..'[1]', pattern)
	end
	if not patternSize then
		patternSize = ffi.sizeof(pattern)
	end
	cmd:enqueueFillBuffer{
		buffer = self.obj,
		pattern = pattern,
		patternSize = patternSize,
		size = ffi.sizeof(self.type) * self.count,
	}
end

-- TODO support for arguments.  varying size, offset, etc.
function CLBuffer:copyFrom(src, cmd)
	cmd = cmd or self.env.cmds[1]
	cmd:enqueueCopyBuffer{
		src = src.obj,
		dst = self.obj,
		size = ffi.sizeof(self.type) * self.count,
	}
end

--[[
args:
	flags = read/write flags.

	TODO use origin and size, use bytes, instead of treating buffers like arrays
	start = optional, default 0
	count = optional, default self.count * sizeof(self.type)
--]]
function CLBuffer:subBuffer(args)
	local start = args.start or 0
	local count = args.count or self.count
	local origin = start * ffi.sizeof(self.type)
	local size = count * ffi.sizeof(self.type)

	return setmetatable({
		obj = self.obj:createSubBuffer{
			readwrite = self.readwrite,
			origin = origin,
			size = size,
		},
		env = self.env,
		name = 'subbuffer_'..tostring(self):sub(10),
		type = self.type,
		start = start,
		count = count,
		readwrite = self.readwrite,
		constant = args.constant,
	}, CLBuffer)
end

return CLBuffer
