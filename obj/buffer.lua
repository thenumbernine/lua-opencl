local class = require 'ext.class'
local ffi = require 'ffi'

local CLBuffer = class()

--[[
readwrite = rw|read|write. default rw
--]]
function CLBuffer:init(args)
	self.env = assert(args.env)
	self.name = args.name or 'buffer_'..tostring(self):sub(10)
	self.type = args.type or args.env.real
	self.count = args.count or args.env.base.volume
	self.readwrite = args.readwrite or 'rw'
	self.obj = self.env:clalloc(self.count * ffi.sizeof(self.type), self.name, self.type, self.readwrite)
	
	-- TODO use hostptr of cl.buffer, which is hidden behind env:clalloc
	if args.data then self:fromCPU(args.data) end
	
	-- TODO optionally keep track of data as self.data with self.keep flag
end

function CLBuffer:fromCPU(ptr)
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
	self.env.cmds:enqueueWriteBuffer{buffer=self.obj, block=true, size=ffi.sizeof(self.type) * self.count, ptr=ptr}
end

function CLBuffer:toCPU(ptr)
	ptr = ptr or ffi.new(self.type..'[?]', self.count)
	self.env.cmds:enqueueReadBuffer{buffer=self.obj, block=true, size=ffi.sizeof(self.type) * self.count, ptr=ptr}
	return ptr
end

function CLBuffer:fill(pattern, patternSize)
	if not pattern then pattern = 0 end
	if type(pattern) ~= 'cdata' then
		pattern = ffi.new(self.type..'[1]', pattern)
	end
	if not patternSize then
		patternSize = ffi.sizeof(pattern)
	end
	self.env.cmds:enqueueFillBuffer{
		buffer = self.obj,
		pattern = pattern,
		patternSize = patternSize,
		size = ffi.sizeof(self.type) * self.count,
	}
end

-- TODO support for arguments.  varying size, offset, etc.
function CLBuffer:copyFrom(src)
	self.env.cmds:enqueueCopyBuffer{
		src = src.obj,
		dst = self.obj,
		size = ffi.sizeof(self.type) * self.count,
	}
end

return CLBuffer
