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
	IL = optional intermediate-language string of binary data to construct program from.
	programs = optional list of programs.  provide this to immediately link these programs and create an executable program.
	code, binaries, and programs are exclusive
--]]
function CLProgram:init(args)
	self.env = assert(args.env)
	self.kernels = table(args.kernels)
	self.domain = args.domain

	-- strictly for forwarding:
	self.showCodeOnError = args and args.showCodeOnError or nil

	if args.code then
		self.code = args.code
		self.cacheFile = args.cacheFile
		self.cacheFileCL = args.cacheFileCL
		self.cacheFileBin = args.cacheFileBin
	elseif args.binaries then
		self.binaries = args.binaries
	elseif args.IL then
		self.IL = args.IL
	elseif args.programs then
		-- unlike providing code or binaries, this will immediately link
		self.obj = Program{
			context = self.env.ctx,
			devices = self.env.devices,
			programs = args.programs,
			buildOptions = args and args.buildOptions,
			showCodeOnError = self.showCodeOnError,
		}
	end
end

function CLProgram:setupKernel(kernel)
	kernel.program = self
	-- if any argBuffers are booleans (from arg.obj=true, for non-cl.obj.buffer parameters
	-- then don't bind them
	kernel.obj = self.obj:kernel(kernel.name)	--, kernel.argBuffers:unpack())
	for i,arg in ipairs(kernel.argBuffers) do
		if Memory:isa(arg) then
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

--[[
TODO rename to :build
args:
	verbose = for now just debugging whether the cached file is used or not
	dontLink = just build an object, for linking later
	buildOptions
--]]
function CLProgram:compile(args)
	local verbose = args and args.verbose

	-- this is also being fudged in
	-- I need to straighten this all out
	-- TODO make this compat with caching?
	if args and args.dontLink then
		local code
		local binaries
		local IL
		if self.binaries then
			binaries = self.binaries
		elseif self.IL then
			IL = self.IL
		else
			code = self:getCode()
		end
		self.obj = Program{
			context = self.env.ctx,
			devices = self.env.devices,
			code = code,
			binaries = binaries,
			IL = IL,
			buildOptions = args and args.buildOptions,
			dontLink = args and args.dontLink,
			showCodeOnError = self.showCodeOnError,
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
			showCodeOnError = self.showCodeOnError,
		}
	elseif self.IL then
		self.obj = Program{
			context = self.env.ctx,		-- not actually needed at all.  but expected.
			devices = self.env.devices,	-- needed for compile() but not for clCreateProgramWithIL
			IL = self.IL,
			showCodeOnError = self.showCodeOnError,
		}
	else
		local code = self:getCode()

		-- define either cacheFile, or define both cacheFileCL and cacheFileBin
		local usingCache
		local clfn, binfn
		if self.cacheFile then
			assert(not self.cacheFileCL, "you defined cacheFile and cacheFileCL")
			assert(not self.cacheFileBin, "you defined cacheFile and cacheFileBin")
			clfn = self.cacheFile..'.cl'
			binfn = self.cacheFile..'.bin'
			usingCache = true
		elseif self.cacheFileCL or self.cacheFileBin then
			clfn = assert(self.cacheFileCL, "you defined cacheFileBin but not cacheFileCL")
			binfn = assert(self.cacheFileBin, "you defined cacheFileCL but not cacheFileBin")
			usingCache = true
		end

		-- if the code matches what is cached then use the cached binary
		local cacheMatches
		if usingCache then
			if code == file(clfn):read() then
if verbose then
	print("*** CL CACHE *** 111 *** CL FILE MATCHES CACHED CL FILE: "..clfn)
end
				if file(binfn):exists() then
if verbose then
	print("*** CL CACHE *** 222 *** AND BINARY FILE EXISTS -- USING CACHED BINARY FOR: "..clfn)
end
					cacheMatches = true
				else
					-- we have a cl file but not a bin file ...
					-- cache doesn't match clearly.
					-- delete the cl file too?  no need to, why destroy what someone might be working on?
if verbose then
	print("*** CL CACHE *** ### *** BUT BINARY FILE DOESN'T EXIST -- REBUILDING BINARY FOR "..clfn)
end
				end
			else
if verbose then
	print("*** CL CACHE *** ### *** CL FILE DOES NOT MATCH CACHED CL FILE -- REBUILDING BINARY FOR "..clfn)
end
--[[ want to see the diffs?
file(tmp_compare_cl_cache):write(code)
os.execute(('diff %q %q'):format(clfn, 'tmp_compare_cl_cache'))
file(tmp_compare_cl_cache):remove()
--]]
-- [[ want to save the old, for manually diffing later?
				file(clfn..'.old'):write(file(clfn):read())
--]]
			end
		else
if verbose then
	print("*** CL CACHE *** ### *** WE ARE NOT USING CACHE FOR FILE "..tostring(clfn))
end
		end

		--[[ should we verify that the source file was not modified?
		-- this is starting to get out of the scope of the cl library ...
		if cacheMatches then
			local clattr = file(clfn):attr()
			local binattr = file(binfn):attr()
			if clattr and binattr then
				if clattr.change > binattr.change then
					cacheMatches = false
				end
			else
				-- if lfs is not found then always reload the program
				-- lfs not found, can't determine last file write time, can't verify that the cached code is correct
				cacheMatches = false
			end
		end
		--]]

		if cacheMatches then
			-- load cached binary
			local bindata = assert(file(binfn):read(), "failed to find opencl compiled program "..binfn)
			local bins = require 'ext.fromlua'(bindata)
if verbose then
	print("*** CL CACHE *** 333 *** BUILDING PROGRAM FROM CACHED BINARY: "..clfn)
end
			self.obj = Program{
				context = self.env.ctx,
				devices = self.env.devices,
				binaries = bins,
				buildOptions = args and args.buildOptions,
				dontLink = args and args.dontLink,
				showCodeOnError = self.showCodeOnError,
			}
		else
if verbose then
	print("*** CL CACHE *** ### *** BUILDING PROGRAM FROM CL: "..tostring(clfn))
end
			-- save cached code before compiling
			-- also delete the cached bin so that the two don't go out of sync
			if usingCache then
if verbose then
	if file(binfn):exists() then
		print("*** CL CACHE *** ### *** DELETING OLD CL BINARY: "..clfn)
	else
		print("*** CL CACHE *** ### *** BUILDING FULLY NEW CL BINARY: "..clfn)
	end
end
				file(clfn):write(code)
				file(binfn):remove()
			end

			self.obj = Program{
				context = self.env.ctx,
				devices = self.env.devices,
				code = code,
				buildOptions = args and args.buildOptions,
				dontLink = args and args.dontLink,
				showCodeOnError = self.showCodeOnError,
			}

			if usingCache then
				-- save binary
				local bins = self.obj:getBinaries()
				-- how well does encoding binary files work ...
				file(binfn):write(require 'ext.tolua'(bins))

				-- [[ double check for safety ...
				local bindata = assert(file(binfn):read(), "failed to find opencl compiled program "..binfn)
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
