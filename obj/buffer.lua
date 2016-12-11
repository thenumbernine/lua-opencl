local class = require 'ext.class'
local ffi = require 'ffi'

local CLBuffer = class()

function CLBuffer:init(args)
	self.env = assert(args.env)
	self.name = assert(args.name) -- or 'buffer_'..tostring(self):sub(10)
	self.type = args.type
	self.buf = self.env:clalloc(self.env.volume * ffi.sizeof(self.type), name, self.type)
	
	-- TODO use hostptr of cl.buffer, which is hidden behind env:clalloc
	if args.data then self:fromCPU(args.data) end
end

function CLBuffer:fromCPU(ptr)
	if type(ptr) == 'table' then	-- convert to ffi memory
		local cptr = ffi.new(self.type..'[?]', self.env.volume)
		local m = math.min(#ptr, self.env.volume)
		for i=1,m do
			cptr[i-1] = ffi.cast(self.type, ptr[i])
		end
		--[[
		for i=m,self.env.volume-1 do
			cptr[i] = ffi.cast(self.type, 0)	-- ?
		end
		--]]
		ptr = cptr
	end
	self.env.cmds:enqueueWriteBuffer{buffer=self.buf, block=true, size=ffi.sizeof(self.type) * self.env.volume, ptr=ptr}
end

function CLBuffer:toCPU()
	local ptr = ffi.new(self.type..'[?]', self.env.volume)
	self.env.cmds:enqueueReadBuffer{buffer=self.buf, block=true, size=ffi.sizeof(self.type) * self.env.volume, ptr=ptr}
	return ptr
end

return CLBuffer
