local class = require 'ext.class'
local ffi = require 'ffi'

local CLBuffer = class()

function CLBuffer:init(args)
	self.env = assert(args.env)
	self.name = args.name or 'buffer_'..tostring(self):sub(10)
	self.type = args.type or self.real
	self.size = args.size or args.env.domain.volume
	self.buf = self.env:clalloc(self.size * ffi.sizeof(self.type), self.name, self.type)
	
	-- TODO use hostptr of cl.buffer, which is hidden behind env:clalloc
	if args.data then self:fromCPU(args.data) end
end

function CLBuffer:fromCPU(ptr)
	if type(ptr) == 'table' then	-- convert to ffi memory
		local cptr = ffi.new(self.type..'[?]', self.size)
		local m = math.min(#ptr, self.size)
		for i=1,m do
			cptr[i-1] = ffi.cast(self.type, ptr[i])
		end
		--[[
		for i=m,self.size-1 do
			cptr[i] = ffi.cast(self.type, 0)	-- ?
		end
		--]]
		ptr = cptr
	end
	assert(type(ptr) == 'cdata')
	self.env.cmds:enqueueWriteBuffer{buffer=self.buf, block=true, size=ffi.sizeof(self.type) * self.size, ptr=ptr}
end

function CLBuffer:toCPU(ptr)
	ptr = ptr or ffi.new(self.type..'[?]', self.size)
	self.env.cmds:enqueueReadBuffer{buffer=self.buf, block=true, size=ffi.sizeof(self.type) * self.size, ptr=ptr}
	return ptr
end

function CLBuffer:fill(pattern, patternSize)
	if pattern and not patternSize then
		pattern = ffi.new(self.type..'[1]', pattern)
		patternSize = ffi.sizeof(pattern)
	end
	self.env.cmds:enqueueFillBuffer{
		buffer = self.buf,
		pattern = pattern,
		patternSize = patternSize,
		size = ffi.sizeof(self.type) * self.size,
	}
end

-- TODO support for arguments.  varying size, offset, etc.
function CLBuffer:copyFrom(src)
	self.env.cmds:enqueueCopyBuffer{
		src = src.buf,
		dst = self.buf,
		size = ffi.sizeof(self.type) * self.size,
	}
end

return CLBuffer
