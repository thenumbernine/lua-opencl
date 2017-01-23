local class = require 'ext.class'
local table = require 'ext.table'
local template = require 'template'

local CLKernel = class()

--[[
env = CLEnv
name = kernel name.
	optional if body is provided (and kernel code body generation is used)
	required if this object is linking from a kernel elsewhere in code (header or program.code)
argsOut = cl.obj.buffer output arguments.  these go first
argsIn = cl.obj.buffer input arguments.  these go next
program = CLProgram.  optional.  if one is not provided, one is generated upon :compile()
header = prefix code.  optional.
body = kernel body generated code.  optional.  if body is nil then no kernel body code will be generated.

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
	--]]
	self.argBuffers = table()
		:append(self.argsOut)
		:append(self.argsIn)
		:map(function(arg) 
			return arg.obj
		end)
	
	self.domain = args.domain or self.env.base
	self.event = args.event
	self.wait = args.wait
	
	self.program = args.program

	self.code = table{
		args.header or '',
		args.body and template([[
kernel void <?=self.name?>(
<?
local sep = ''
for _,arg in ipairs(self.argsOut or {}) do 
	if arg.obj then
		?>	<?=sep?>global <?=arg.type or 'real'?>* <?=arg.name?>
<?	else
		?>	<?=sep?><?=arg.type or 'real'?> <?=arg.name?>
<?	end
	sep = ', '
end
for _,arg in ipairs(self.argsIn or {}) do
	if arg.obj then
		?>	<?=sep?>global const <?=arg.type or 'real'?>* <?=arg.name?>
<?	else
		?>	<?=sep?><?=arg.type or 'real'?> <?=arg.name?>
<?	end
	sep = ', '
end
?>) {
<? -- don't forget that kernel domains may not match the env domain -- which is the default domain
?>	initKernelForSize(<?=self.domain.size.x?>,<?=self.domain.size.y?>,<?=self.domain.size.z?>);
<?=args.body?>
}
]], {self=self, args=args}) or ''
	}:concat'\n'
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
	self.env:program{kernels={self}}:compile()	
end

function CLKernel:__call(...)
	-- if we get a call request when we have no kernel/program, make sure to get one 
	if not self.obj then
		self:compile()
	end

	if select('#', ...) > 0 then
		self.obj:setArgs(...)
	end
	
	self.env.cmds:enqueueNDRangeKernel{
		kernel = self.obj,
		dim = self.domain.dim,
		globalSize = self.domain.globalSize:ptr(),
		localSize = self.domain.localSize:ptr(),
		-- these have to be specified beforehand
		wait = self.wait,
		event = self.event,
	}
end

return CLKernel
