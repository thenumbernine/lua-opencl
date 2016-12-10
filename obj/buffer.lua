local class = require 'ext.class'
local ffi = require 'ffi'

local CLBuffer = class()

function CLBuffer:init(args)
	self.env = assert(args.env)
	self.name = assert(args.name) -- or 'buffer_'..tostring(self):sub(10)
	self.type = args.type
	self.buf = self.env:clalloc(self.env.volume * ffi.sizeof(self.type), name, self.type)
end

function CLBuffer:toCPU()
	local cpuMem = ffi.new(self.type..'[?]', self.env.volume)
	self.env.cmds:enqueueReadBuffer{buffer=self.buf, block=true, size=ffi.sizeof(self.type) * self.volume, ptr=cpuMem}
	return cpuMem
end

return CLBuffer
