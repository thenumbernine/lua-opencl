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
		cacheFileCL = optional.  uses args.cacheFile..'.cl' otherwise.
		cacheFileBin = optional.  uses args.cacheFile..'.bin' otherwise.
	binaries = optional binaries to construct the program from.
	programs = optional list of programs.  provide this to immediately link these programs and create an executable program.
	code, binaries, and programs are exclusive
--]]
function CLProgram:init(args)
	self.env = assert(args.env)
	self.kernels = table(args.kernels)
	self.domain = args.domain
	if args.code then
		self.code = args.code
		self.cacheFile = args.cacheFile
		self.cacheFileCL = args.cacheFileCL
		self.cacheFileBin = args.cacheFileBin
	elseif args.binaries then
		self.binaries = args.binaries
	elseif args.programs then
		-- unlike providing code or binaries, this will immediately link
		self.obj = Program{
			context = self.env.ctx,
			devices = self.env.devices,
			programs = args.programs,
			buildOptions = args and args.buildOptions,
		}
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

-- TODO rename to :build
function CLProgram:compile(args)
	-- this is also being fudged in
	-- I need to straighten this all out
	-- TODO make this compat with caching?
	if args and args.dontLink then
		local code, binaries
		if self.binaries then
			binaries = self.binaries
		else
			code = self:getCode()
		end
		self.obj = Program{
			context = self.env.ctx,
			devices = self.env.devices,
			code = code,
			binaries = binaries,
			buildOptions = args and args.buildOptions,
			dontLink = args and args.dontLink,
		}
		return
	end
	
	-- right now this is just for construction by binaries
	-- if we are caching binaries then it doesn't save it in the object -- just to the cache file
	if self.binaries then
		self.obj = Program{
			context = self.env.ctx,
			devices = self.env.devices,
			binaries = self.binaries,
			buildOptions = args and args.buildOptions,
		}
	else
		local code = self:getCode()

		-- define either cacheFile, or define both cacheFileCL and cacheFileBin
		local usingCache
		local clfile, binfile
		if self.cacheFile then
			assert(not self.cacheFileCL, "you defined cacheFile and cacheFileCL")
			assert(not self.cacheFileBin, "you defined cacheFile and cacheFileBin")
			clfile = self.cacheFile..'.cl'
			binfile = self.cacheFile..'.bin'
			usingCache = true
		elseif self.cacheFileCL or self.cacheFileBin then
			clfile = assert(self.cacheFileCL, "you defined cacheFileBin but not cacheFileCL")
			binfile = assert(self.cacheFileBin, "you defined cacheFileCL but not cacheFileBin")
			usingCache = true
		end

		if usingCache and code == file[clfile] then
			-- load cached
			local bindata = assert(file[binfile], "failed to find opencl compiled program "..binfile)
			local bins = require 'ext.fromlua'(bindata)
			self.obj = Program{
				context = self.env.ctx,
				devices = self.env.devices,
				binaries = bins,
				buildOptions = args and args.buildOptions,
				dontLink = args and args.dontLink,
			}
		else
			self.obj = Program{
				context = self.env.ctx,
				devices = self.env.devices,
				code = code,
				buildOptions = args and args.buildOptions,
				dontLink = args and args.dontLink,
			}

			-- save cached
			if usingCache then
				file[clfile] = code
				-- save binary
				local bins = self.obj:getBinaries()
				-- how well does encoding binary files work ...
				file[binfile] = require 'ext.tolua'(bins)
			
				-- [[ double check for safety ...
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
