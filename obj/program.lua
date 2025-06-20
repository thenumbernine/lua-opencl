local assert = require 'ext.assert'
local class = require 'ext.class'
local string = require 'ext.string'
local table = require 'ext.table'
local path = require 'ext.path'
local Memory = require 'cl.memory'
local Program = require 'cl.program'

local makeTargets = require 'make.targets'
local writeChanged = require 'make.writechanged'
local exec = require 'make.exec'

local CLProgram = class()

-- kernel class to allocate upon CLProgram:kernel
CLProgram.Kernel = require 'cl.obj.kernel'

local ccname = 'clang'
local ldname = 'llvm-spirv'

--[[
args:
	env = required, cl.obj.env
	code = optional header code to all kernels, used for compiling
	kernels = optional list of all kernels attached
		kernels with code is incorporated into the compile
		upon compile, all kernels objects are assigned and args are bound
	domain = optional, domain passed to kernels, default results in kernels getting env.base

		--- used for binary caching / reusing: ---
	cacheFile = optional, set this to cache the binary (.bin) and source (.cl), and only rebuild the program if the source doesn't match the cache file contents
		TODO maybe rename this to binaryFile / binaryFileCL / binaryFileBin, to distinguish it as the clCreateProgramWithBinary caching pathway (versus the clCreateProgramWithIL caching pathway)
		cacheFileCL = optional.  uses args.cacheFile..'.cl' otherwise.
		cacheFileBin = optional.  uses args.cacheFile..'.bin' otherwise.
	binaries = optional binaries to construct the program from.
		--- used for spirv toolchain caching / reusing: ---
	spirvToolchainFile = optional, set this to use clang & llvm-spirv for saving the .cl and building the .bc and .spv files, then loading the IL
	IL = optional, intermediate-language string of binary data to construct program from.

	programs = optional list of programs.  provide this to immediately link these programs and create an executable program.
	code, binaries, and programs are exclusive
--]]
function CLProgram:init(args)
	self.env = assert.index(args, 'env')
	self.kernels = table(args.kernels)
	self.domain = args.domain

	-- strictly for forwarding:
	self.showCodeOnError = args and args.showCodeOnError or nil

	-- handle .spirvToolchainFile before .code
	if args.spirvToolchainFile
	or args.spirvToolchainFileCL
	or args.spirvToolchainFileBC
	or args.spirvToolchainFileSPV
	then
		-- save for later
		self.spirvToolchainFile = args.spirvToolchainFile
		self.spirvToolchainFileCL = args.spirvToolchainFileCL or self.spirvToolchainFile..'.cl' or error("you must either provide .spirvToolchainFile or .spirvToolchainFileCL")
		self.spirvToolchainFileBC = args.spirvToolchainFileBC or self.spirvToolchainFile..'.bc' or error("you must either provide .spirvToolchainFile or .spirvToolchainFileBC")
		self.spirvToolchainFileSPV = args.spirvToolchainFileSPV or self.spirvToolchainFile..'.spv' or error("you must either provide .spirvToolchainFile or .spirvToolchainFileSPV")
		path(self.spirvToolchainFileCL):getdir():mkdir(true)
		path(self.spirvToolchainFileBC):getdir():mkdir(true)
		path(self.spirvToolchainFileSPV):getdir():mkdir(true)

		-- If we specify multiple programs as input then we link immediately and return.
		-- Same behavior as with Binaries.
		if args.programs then
			assert(not args.code, "either .programs for linking or .code for building, but not both")
			local programs = args.programs
			args.programs = nil	-- dont do the .programs in super / dont make a .obj yet
			assert.gt(#programs, 0, "can't link from programs if no programs are provided")
			-- assert all our input programs have .bc files
			local srcs = table.mapi(programs, function(program)
				return (assert.index(program, 'spirvToolchainFileBC', "CLProgram constructed with .programs, expected all those programs to have .spirvToolchainFileBC's, but one didn't: "..tostring(program.spirvToolchainFile)))
			end)
			makeTargets{
				{
					srcs = srcs,
					dsts = {self.spirvToolchainFileBC},
					rule = function()
						-- other .bc' => our .bc
						exec(table{
							'llvm-link',
							srcs:mapi(function(src)
								return ('%q'):format(src)
							end):concat' ',
							'-o', ('%q'):format(self.spirvToolchainFileBC),
						}:concat' ')
					end,
				},
			-- TODO this is the same rule as in :compile() for building from .cl ...
				{
					srcs = {self.spirvToolchainFileBC},
					dsts = {self.spirvToolchainFileSPV},
					rule = function()
						exec(table{
							ldname,
							--'--spirv-max-version=1.0',
							('%q'):format(self.spirvToolchainFileBC),
							'-o',
							('%q'):format(self.spirvToolchainFileSPV),
						}:concat' ')
					end,
				},
			}:run(self.spirvToolchainFileSPV)
			-- TODO the rest of this is just like the spirvToolchain :compile() pathway too...
			local IL = assert(path(self.spirvToolchainFileSPV):read())
			self.obj = Program{
				context = self.env.ctx,
				devices = self.env.devices,
				IL = IL,
				buildOptions = args and args.buildOptions,
				showCodeOnError = self.showCodeOnError,
			}
			-- TODO make an always-print-logs function? or use cl.program?
			do--if self.obj then	-- did compile
				print((self.spirvToolchainFile and self.spirvToolchainFile..' ' or '')..'log:')
				-- TODO log per device ...
				print(string.trim(self.obj:getLog(self.env.devices[1])))
			end
			assert.eq(self.code, nil)
		else
			-- save code for later, when :compile is called
			self.code = assert.index(args, 'code')
			args.code = nil
		end
	elseif args.code then
		self.code = args.code
		-- save for the :compile() call
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

function CLProgram:clangCompile(dst, src, buildOptions)
	exec(table{
		ccname,
		buildOptions or '',
		'-c',
		'-cl-std=clc++',
		'-v',
		--'-Xclang -finclude-default-header',	-- required for clang<13.0 according to https://www.khronos.org/blog/offline-compilation-of-opencl-kernels-into-spir-v-using-open-source-tooling
		'--target=spirv64-unknown-unknown',	--compiling works but linking complains
		--'--target=spirv64',	--compiling works but linking complains
		--'--target=spir64',	--compiling works but linking complains
		--'-std=c++2a',
		--'-O0',
		--'-O3',
		'-emit-llvm',
		'-o', ('%q'):format(path(dst):fixpathsep()),
		('%q'):format(path(src):fixpathsep()),
	}:concat' ')
end

--[[
TODO rename to :build
args:
	dontLink = just build an object, for linking later
	buildOptions
--]]
function CLProgram:compile(args)
	if self.obj then
		error("tried to compile a program that was already compiled...")
	end

	-- handle spirv toolchain first:
	-- if we're using the spirv toolchain...
	if self.spirvToolchainFileCL
	or self.spirvToolchainFileBC
	or self.spirvToolchainFileSPV
	then
		-- technicality: if dontLink is used then the .spv file will not be used also, but can still be set to the default name...
		assert(self.spirvToolchainFileCL and self.spirvToolchainFileBC and self.spirvToolchainFileSPV)
		local buildTargets = makeTargets{
			verbose = true,
			{
				srcs = {self.spirvToolchainFileCL},
				dsts = {self.spirvToolchainFileBC},
				rule = function(rule)
					assert.len(rule.dsts, 1)
					assert.len(rule.srcs, 1)
					self:clangCompile(rule.dsts[1], rule.srcs[1], args and args.buildOptions or nil)
				end,
			},
			{
				srcs = {self.spirvToolchainFileBC},
				dsts = {self.spirvToolchainFileSPV},
				rule = function()
					exec(table{
						ldname,
						args and args.linkOptions or '',
						('%q'):format(self.spirvToolchainFileBC),
						'-o', ('%q'):format(self.spirvToolchainFileSPV),
					}:concat' ')
				end,
			},
		}

		-- cl -> bc
		-- only write (and invalidate) when necessary
		if not (args and args.useCachedCode) then
			local code = self:getCode()
			writeChanged(self.spirvToolchainFileCL, code)
		end
		buildTargets:run(self.spirvToolchainFileBC)

		-- if 'dontLink' then just leave the .bc file for another Program to use ... or not?
		if args and args.dontLink then return end

		-- cl -> bc -> spv
		buildTargets:run(self.spirvToolchainFileSPV)
		self.IL = assert(path(self.spirvToolchainFileSPV):read())

		args = table(args):setmetatable(nil)

		-- TODO print all logs regardless?
		--[[
		local results = CLProgram.super.compile(self, args)
		assert(self.obj, "there must have been an error in your error handler")	-- otherwise it would have thrown an error
		do--if self.obj then	-- did compile
			print((self.spirvToolchainFile and self.spirvToolchainFile..' ' or '')..'log:')
			-- TODO log per device ...
			print(string.trim(self.obj:getLog(self.env.devices[1])))
		end
		return results
		--]]
	end

-- [[
	-- this is also being fudged in
	-- I need to straighten this all out
	-- TODO make this compat with caching?
	-- though tbh I'm not sure OpenCL itself supports unlinked object binaries
	-- https://registry.khronos.org/OpenCL/sdk/3.0/docs/man/html/clCreateProgramWithBinary.html
	-- "These executables can now be queried and cached by the application"
	-- ... sounds like it is only caching the linked executable, not the objects.
	-- ... but on the other hand ...
	-- https://registry.khronos.org/OpenCL/sdk/3.0/docs/man/html/clLinkProgram.html
	-- "If the program was created using clCreateProgramWithBinary and options is a NULL pointer, the program will be linked as if options were the same as when the program binary was originally built."
	-- that sounds like clLinkProgram should run on program-objects created from clCreateProgramWithBinary
	if args
	and args.dontLink
	--and (self.binaries or self.IL)	-- only skip this pathway when self.code exists
	then
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
--]]

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
			clfn = assert.index(self, 'cacheFileCL', "you defined cacheFileBin but not cacheFileCL")
			binfn = assert.index(self, 'cacheFileBin', "you defined cacheFileCL but not cacheFileBin")
			usingCache = true
		end

		-- if the code matches what is cached then use the cached binary
		local cacheMatches
		if usingCache then

			path(clfn):getdir():mkdir(true)
			path(binfn):getdir():mkdir(true)

			if code == path(clfn):read() then
--DEBUG:print("*** CL CACHE *** 111 *** CL FILE MATCHES CACHED CL FILE: "..clfn)
				if path(binfn):exists() then
--DEBUG:print("*** CL CACHE *** 222 *** AND BINARY FILE EXISTS -- USING CACHED BINARY FOR: "..clfn)
					cacheMatches = true
				else
					-- we have a cl file but not a bin file ...
					-- cache doesn't match clearly.
					-- delete the cl file too?  no need to, why destroy what someone might be working on?
--DEBUG:print("*** CL CACHE *** ### *** BUT BINARY FILE DOESN'T EXIST -- REBUILDING BINARY FOR "..clfn)
				end
			else
--DEBUG:print("*** CL CACHE *** ### *** CL FILE DOES NOT MATCH CACHED CL FILE -- REBUILDING BINARY FOR "..clfn)
--[[ want to see the diffs?
path(tmp_compare_cl_cache):write(code)
os.execute(('diff %q %q'):format(clfn, 'tmp_compare_cl_cache'))
path(tmp_compare_cl_cache):remove()
--]]
-- [[ want to save the old, for manually diffing later?
				local oldcl = path(clfn):read()
				if oldcl then
					path(clfn..'.old'):write(oldcl)
				end
--]]
			end
		else
--DEBUG:print("*** CL CACHE *** ### *** WE ARE NOT USING CACHE FOR FILE "..tostring(clfn))
		end

		--[[ should we verify that the source file was not modified?
		-- this is starting to get out of the scope of the cl library ...
		if cacheMatches then
			local clattr = path(clfn):attr()
			local binattr = path(binfn):attr()
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
			local bindata = assert(path(binfn):read(), "failed to find opencl compiled program "..binfn)
			local bins = require 'ext.fromlua'(bindata)
--DEBUG:print("*** CL CACHE *** 333 *** BUILDING PROGRAM FROM CACHED BINARY: "..binfn)
			self.obj = Program{
				context = self.env.ctx,
				devices = self.env.devices,
				binaries = bins,
				buildOptions = args and args.buildOptions,
				dontLink = args and args.dontLink,
				showCodeOnError = self.showCodeOnError,
			}
		else
--DEBUG:print("*** CL CACHE *** ### *** BUILDING PROGRAM FROM CL: "..tostring(clfn))
			-- save cached code before compiling
			-- also delete the cached bin so that the two don't go out of sync
			if usingCache then
--DEBUG:if path(binfn):exists() then
--DEBUG:	print("*** CL CACHE *** ### *** DELETING OLD CL BINARY: "..clfn)
--DEBUG:else
--DEBUG:	print("*** CL CACHE *** ### *** BUILDING FULLY NEW CL BINARY: "..clfn)
--DEBUG:end
				path(clfn):write(code)
				path(binfn):remove()
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
				path(binfn):write(require 'ext.tolua'(bins))

				-- [[ double check for safety ...
				local bindata = assert(path(binfn):read(), "failed to find opencl compiled program "..binfn)
				local binsCheck = require 'ext.fromlua'(bindata)
				assert.eq(#binsCheck, #bins, 'somehow you encoded a different number of binary blobs than you were given.')
				for i=1,#bins do
					assert.type(bins[i], 'string')
					assert.type(binsCheck[i], 'string')
					assert.eq(bins[i], binsCheck[i], 'error in encoding a binary blob!')
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
