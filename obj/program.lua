local class = require 'ext.class'
local table = require 'ext.table'
local CLBuffer = require 'cl.buffer'

local CLProgram = class()

function CLProgram:init(args)
	self.env = assert(args.env)
	self.code = args.code
	self.kernels = table(args.kernels)
end

function CLProgram:setupKernel(kernel)
	kernel.program = self
	-- if any argBuffers are booleans (from arg.obj=true, for non-cl.obj.buffer parameters
	-- then don't bind them
	kernel.obj = self.obj:kernel(kernel.name)	--, kernel.argBuffers:unpack())
	for i,arg in ipairs(kernel.argBuffers) do
		if CLBuffer.is(arg) then
			kernel.obj:setArg(i-1, arg)
		end
	end
	-- while we're here, store the max work group size	
	kernel.maxWorkGroupSize = tonumber(kernel.obj:getWorkGroupInfo(self.env.device, 'CL_KERNEL_WORK_GROUP_SIZE'))
end

function CLProgram:kernel(args)
	if type(args) == 'string' then args = {name = args} end
	local kernel = require 'cl.obj.kernel'(table(args, {env=self.env, program=self}))
	self.kernels:insert(kernel)

	-- already compiled? set up the kernel
	if self.obj then
		self:setupKernel(kernel)
	end
	
	return kernel
end

function CLProgram:compile()
	local code = table{
		self.env.code or '',
		
		-- size globals come from domain code
		-- but is only included by env code
		
		self.code or '',
	}:append(table.map(self.kernels, function(kernel)
		return kernel.code
	end)):concat'\n'

	self.obj = require 'cl.program'{context=self.env.ctx, devices={self.env.device}, code=code}
	
	for _,kernel in ipairs(self.kernels) do
		self:setupKernel(kernel)
	end
end

return CLProgram
