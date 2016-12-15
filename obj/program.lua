local class = require 'ext.class'
local table = require 'ext.table'
local CLBuffer = require 'cl.buffer'

local CLProgram = class()

function CLProgram:init(args)
	self.env = assert(args.env)
	self.code = args.code
	self.kernels = table(args.kernels)
end

function CLProgram:kernel(args)
	local kernel = require 'cl.obj.kernel'(table(args, {env=self.env, program=self}))
	self.kernels:insert(kernel)
	return kernel
end

function CLProgram:compile()
	local code = table{
		self.env.code or '',
		self.code or '',
	}:append(table.map(self.kernels, function(kernel)
		return kernel.code
	end)):concat'\n'

	self.program = require 'cl.program'{context=self.env.ctx, devices={self.env.device}, code=code}
	
	for _,kernel in ipairs(self.kernels) do
		kernel.program = self
		-- if any argBuffers are booleans (from arg.buf=true, for non-cl.obj.buffer parameters
		-- then don't bind them
		kernel.kernel = self.program:kernel(kernel.name)	--, kernel.argBuffers:unpack())
		for i,arg in ipairs(kernel.argBuffers) do
			if CLBuffer.is(arg) then
				kernel.kernel:setArg(i-1, arg)
			end
		end
	end
end

return CLProgram
