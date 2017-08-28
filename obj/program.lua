local class = require 'ext.class'
local table = require 'ext.table'
local CLBuffer = require 'cl.buffer'

local CLProgram = class()

-- kernel class to allocate upon Program:kernel
CLProgram.Kernel = require 'cl.obj.kernel'

--[[
args:
	env = required, cl.obj.env
	code = optional header code to all kernels, used for compiling
	kernels = optional list of all kernels attached
		kernels with code is incorporated into the compile
		upon compile, all kernels objects are assigned and args are bound
	domain = optional, domain passed to kernels, default results in kernels getting env.base
--]]
function CLProgram:init(args)
	self.env = assert(args.env)
	self.code = args.code
	self.kernels = table(args.kernels)
	self.domain = args.domain
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
	kernel:setSizeProps()
end

--[[
args are forwarded to cl.obj.kernel's ctor
if args is a string then {name=args} is forwarded 
--]]
function CLProgram:kernel(args, ...)
	if type(args) == 'string' then
		args = {
			name = args,
			domain = self.domain,
		}
		local n = select('#', ...)
		if n > 0 then
			args.setArgs = table()
			for i=1,n do
				local obj = select(i, ...)
				if obj.obj then obj = obj.obj end
				args.setArgs:insert(obj)
			end
		end
	else
		args.domain = args.domain or self.domain
	end
	local kernel = self.Kernel(table(args, {env=self.env, program=self}))
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
