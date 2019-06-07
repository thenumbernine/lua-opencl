local class = require 'ext.class'
local table = require 'ext.table'
local file = require 'ext.file'
local Memory = require 'cl.memory'
local Program = require 'cl.program'

local CLProgram = class()

-- kernel class to allocate upon CLProgram:kernel
CLProgram.Kernel = require 'cl.obj.kernel'

--[[
args:
	env = required, cl.obj.env
	code = optional header code to all kernels, used for compiling
	kernels = optional list of all kernels attached
		kernels with code is incorporated into the compile
		upon compile, all kernels objects are assigned and args are bound
	domain = optional, domain passed to kernels, default results in kernels getting env.base
	cacheFile = optional, set this to cache the binary (.bin) and source (.cl), and only rebuild the program if the source doesn't match the cache file contents
	binaries = optional binaries to construct the program from.
		if this is used then code and cacheFile will be ignored
--]]
function CLProgram:init(args)
	self.env = assert(args.env)
	self.code = args.code
	self.cacheFile = args.cacheFile
	self.kernels = table(args.kernels)
	self.domain = args.domain
	if args.binaries then
		self.binaries = args.binaries
		self.code = nil
		self.cacheFile = nil
	end
end

function CLProgram:setupKernel(kernel)
	kernel.program = self
	-- if any argBuffers are booleans (from arg.obj=true, for non-cl.obj.buffer parameters
	-- then don't bind them
	kernel.obj = self.obj:kernel(kernel.name)	--, kernel.argBuffers:unpack())
	for i,arg in ipairs(kernel.argBuffers) do
		if Memory.is(arg) then
			kernel.obj:setArg(i-1, arg)
		end
	end
	-- while we're here, store the max work group size	
	kernel:setSizeProps()
end

--[[
args are forwarded to cl.obj.kernel's ctor
if args is a string then 
	{name=args} is forwarded 
	with setArgs a table of ..., and setArgs.n the # of ... (to preserve nils)
--]]
function CLProgram:kernel(args, ...)
	local setArgs
	if type(args) == 'string' then
		args = {
			name = args,
			domain = self.domain,
		}
		if select('#', ...) > 0 then
			setArgs = table.pack(...)
		end
	else
		args.domain = args.domain or self.domain
		setArgs = args.setArgs
	end
	if setArgs then
		for i=1,setArgs.n or #setArgs do
			local obj = setArgs[i]
			if type(obj) == 'table' and obj.obj then obj = obj.obj end
			setArgs[i] = obj
		end
		args.setArgs = setArgs
	end
	local kernel = self.Kernel(table(args, {env=self.env, program=self}))
	self.kernels:insert(kernel)

	-- already compiled? set up the kernel
	if self.obj then
		self:setupKernel(kernel)
	end
	
	return kernel
end

-- returns the final compiled code, which is the env's and the program's code
function CLProgram:getCode()
	return table{
		self.env.code or '',
		
		-- size globals come from domain code
		-- but is only included by env code
		
		self.code or '',
	}:append(table.mapi(self.kernels, function(kernel)
		return kernel.code
	end)):concat'\n'
end

function CLProgram:compile(args)
	-- right now this is just for construction by binaries
	-- if we are caching binaries then it doesn't save it in the object -- just to the cache file
	if self.binaries then
		self.obj = Program{
			context = self.env.ctx,
			devices = {self.env.device},
			binaries = self.binaries,
			buildOptions = args and args.buildOptions,
		}
	else
		local code = self:getCode()

		if self.cacheFile
		and code == file[self.cacheFile..'.cl']
		then
			-- load cached
			local binfile = self.cacheFile..'.bin'
			local bindata = assert(file[binfile], "failed to find opencl compiled program "..binfile)
			local bins = require 'ext.fromlua'(bindata)
			self.obj = Program{
				context=self.env.ctx,
				devices={self.env.device},
				binaries=bins,
				buildOptions=args and args.buildOptions,
			}
		else
			self.obj = Program{
				context=self.env.ctx,
				devices={self.env.device},
				code=code,
				buildOptions=args and args.buildOptions,
			}
			
			-- save cached
			if self.cacheFile then
				file[self.cacheFile..'.cl'] = code
				-- save binary
				local bins = self.obj:getBinaries()
				-- how well does encoding binary files work ...
				file[self.cacheFile..'.bin'] = require 'ext.tolua'(bins)
			
				-- [[ double check for safety ...
				local binfile = self.cacheFile..'.bin'
				local bindata = assert(file[binfile], "failed to find opencl compiled program "..binfile)
				local binsCheck = require 'ext.fromlua'(bindata)
				assert(#binsCheck == #bins, 'somehow you encoded a different number of binary blobs than you were given.')
				for i=1,#bins do
					assert(bins[i] == binsCheck[i], 'error in encoding a binary blob!')
				end
				--]]
			end
		end
	end

	for _,kernel in ipairs(self.kernels) do
		self:setupKernel(kernel)
	end
end

return CLProgram
