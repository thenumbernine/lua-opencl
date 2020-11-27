local class = require 'ext.class'
local table = require 'ext.table'
local template = require 'template'

local CLKernel = class()

--[[
args:
	env = CLEnv
	name = kernel name.
		optional if body is provided (and kernel code body generation is used)
		required if this object is linking from a kernel elsewhere in code (header or program.code)
	argsOut = cl.obj.buffer output arguments.  these go first
	argsIn = cl.obj.buffer input arguments.  these go next
		these next two are useful for creating kernels from already-provided code:
	setArgObjs = list of extra cl.obj.buffers to bind, but not to generate param code for.  these go next.
	setArgs = list of extra cl.buffers to bind, just like setArgObjs
	program = CLProgram.  optional.  if one is not provided, one is generated upon :compile()
	header = prefix code.  optional.
	body = kernel body generated code.  optional.  if body is nil then no kernel body code will be generated.
	domain = used in conjunction with setSizeProps to calculate localSizes and globalSize based on kernel's maxWorkGroupSize

use cases:
	k = env:kernel{body=...} creates a kernel
	k()						 and executes it
	upon execution it will be compiled into its own program and it will link to its kernel

	p = env:program{code=...}	creates a program
	k = p:kernel{name=...}		creates a kernel
	p:compile()					compiles kernel and sets all kernel links
	k()							executes kernel
	if p:compile() is omitted then you'll get a warning that your kernel has a program but it didn't compile
--]]
function CLKernel:init(args)
	self.env = assert(args.env)
	self.name = args.name or 'kernel_'..tostring(self):sub(10)
	self.argsOut = args.argsOut
	self.argsIn = args.argsIn
	--[[
	if argsIn and argsOut are cl.obj.buffer's then all works well
	if you don't want to pass a cl.obj.buffer then you can still define a buffer by setting {name=..., obj=true},
		by setting obj=true instead of obj= a cl.obj.buffer object
		this fixes the code gen
		but still doesn't fix the argBuffers
	so instead of fixing the argBuffers I'm going to detect :isa
	I'm going to change the binding (which happens in cl.obj.program) 
	
	Ugh I don't like having two separate paradigms.
	since argBuffers is used for setArgs upon kernel setup,
	add any extra cl.obj.buffer's via args.setArgObjs
	and add any extra cl.buffer's via args.setArgs
	--]]
	self.argBuffers = table()
		:append(self.argsOut)
		:append(self.argsIn)
		:append(args.setArgObjs or {})
		:mapi(function(arg) 
			return arg.obj
		end)
		:append(args.setArgs or {})
	
	self.domain = args.domain or self.env.base
	self.event = args.event
	self.wait = args.wait
	
	self.program = args.program

	self.code = table{
		args.header or '',
		args.body and template([[
kernel void <?=self.name?>(<?
local sep = ''
for _,arg in ipairs(self.argsOut or {}) do 
	?><?=sep?>
	<?
	if arg.obj then
		?>global <?=arg.type or 'real'?>* <?=arg.name?><?
	else
		?><?=arg.type or 'real'?> <?=arg.name?><?
	end
	sep = ','
end
for _,arg in ipairs(self.argsIn or {}) do
	?><?=sep?>
	<?
	if arg.obj then
		if arg.constant then
			?>constant <?
		else
			?>global const <?
		end
	end
	?><?=arg.type or 'real'?><?
	if arg.obj then
		?>* <?
	else
		?> <?
	end
	?><?=arg.name?><?
	sep = ','
end
?>) {
<? -- don't forget that kernel domains may not match the env domain -- which is the default domain
?>	initKernelForSize(<?=
	tonumber(self.domain.size.x)?>,<?=
	tonumber(self.domain.size.y)?>,<?=
	tonumber(self.domain.size.z)?>);
<?=args.body?>
}
]], {self=self, args=args}) or ''
	}:concat'\n'

	-- strictly forwarding to program upon :compile()
	self.showCodeOnError = args.showCodeOnError
end

-- used for stand-alone compiling
-- if you want to compile this kernel with other kernels, use CLEnv:compileKernels
function CLKernel:compile()
	if self.obj then
		error("already compiled")
	end
	if self.program then
		error("this kernel already has a program -- use program:compile")
	end
	self.program = self.env:program{
		kernels = {self},
		showCodeOnError = self.showCodeOnError,
	}
	self.program:compile()
end

--[[
how to handle multiple command queues?
honestly, time to move this function to obj/commandqueue
--]]
function CLKernel:__call(...)
	-- if we get a call request when we have no kernel/program, make sure to get one 
	if not self.obj then
		self:compile()
	end

	if select('#', ...) > 0 then
		self.obj:setArgs(...)
	end

	self.env.cmds[1]:enqueueNDRangeKernel{
		kernel = self.obj,
		dim = self.domain.dim,
		globalSize = (self.globalSize or self.domain.globalSize).s,
		localSize = (self.localSize or self.domain.localSize).s,
		-- these have to be specified beforehand
		wait = self.wait,
		event = self.event,
	}
end

-- also used in hydro-cl ... don't know where i would put it to share it though
local function roundup(a, b)
	local mod = a % b
	if mod ~= 0 then
		a = a - mod + b
	end
	return a
end

--[[
TODO what to do here
these props are based on device info
so we need one per kernel per device
for now I'll use self.domain's device
--]]
local vec3sz = require 'vec-ffi.vec3sz'
function CLKernel:setSizeProps()
	if not self.domain then
-- if no env.domain, kernel.domain, or program.domain is provided
-- then this has no domain,
-- and that means no enqueueNDRange localSize/globalSize info can be calculated for it
io.stderr:write('!!!! kernel has no domain -- skipping setSizeProps !!!!\n')
	end
	
	self.maxWorkGroupSize = tonumber(self.obj:getWorkGroupInfo('CL_KERNEL_WORK_GROUP_SIZE', self.domain.device))

	self.localSize1d = math.min(self.maxWorkGroupSize, tonumber(self.domain.size:volume()))

	if self.domain.dim == 3 then
		local localSizeX = math.min(tonumber(self.domain.size.x), 2^math.ceil(math.log(self.maxWorkGroupSize,2)/2))
		local localSizeY = self.maxWorkGroupSize / localSizeX
		self.localSize2d = {localSizeX, localSizeY}
	end

--	self.localSize = self.domain.dim < 3 and vec3sz(16,16,16) or vec3sz(4,4,4)
	-- TODO better than constraining by math.min(self.domain.size),
	-- look at which domain sizes have the most room, and double them accordingly, until all of maxWorkGroupSize is taken up
	self.localSize = vec3sz(1,1,1)
	local rest = self.maxWorkGroupSize
	local localSizeX = math.min(tonumber(self.domain.size.x), 2^math.ceil(math.log(rest,2)/self.domain.dim))
	self.localSize.x = localSizeX
	if self.domain.dim > 1 then
		rest = rest / localSizeX
		if self.domain.dim == 2 then
			self.localSize.y = math.min(tonumber(self.domain.size.y), rest)
		elseif self.domain.dim == 3 then
			local localSizeY = math.min(tonumber(self.domain.size.y), 2^math.ceil(math.log(math.sqrt(rest),2)))
			self.localSize.y = localSizeY
			self.localSize.z = math.min(tonumber(self.domain.size.z), rest / localSizeY)
		end
	end

	-- this is grid size, but rounded up to the next self.localSize
	self.globalSize = vec3sz(
		roundup(self.domain.size.x, self.localSize.x),
		roundup(self.domain.size.y, self.localSize.y),
		roundup(self.domain.size.z, self.localSize.z))
	
	self.volume = tonumber(self.domain.size:volume())
end

return CLKernel
