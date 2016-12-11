local class = require 'ext.class'
local ffi = require 'ffi'

local CLBuffer = class()

function CLBuffer:init(args)
	self.env = assert(args.env)
	self.name = assert(args.name) -- or 'buffer_'..tostring(self):sub(10)
	self.type = args.type
	self.buf = self.env:clalloc(self.env.volume * ffi.sizeof(self.type), name, self.type)
end

function CLBuffer:fromCPU(mem)
	if type(mem) == 'table' then	-- convert to ffi memory
		local cpuMem = ffi.new(self.type..'[?]', self.env.volume)
		local m = math.min(#mem, self.env.volume)
		for i=1,m do
			cpuMem[i-1] = ffi.cast(self.type, mem[i])
		end
		--[[
		for i=m,self.env.volume-1 do
			cpuMem[i] = ffi.cast(self.type, 0)	-- ?
		end
		--]]
		mem = cpuMem
	end
	self.env.cmds:enqueueWriteBuffer{buffer=self.buf, block=true, size=ffi.sizeof(self.type) * self.env.volume, ptr=mem}
end

function CLBuffer:toCPU()
	local cpuMem = ffi.new(self.type..'[?]', self.env.volume)
	self.env.cmds:enqueueReadBuffer{buffer=self.buf, block=true, size=ffi.sizeof(self.type) * self.env.volume, ptr=cpuMem}
	return cpuMem
end

return CLBuffer
