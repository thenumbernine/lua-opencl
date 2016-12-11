local class = require 'ext.class'
local table = require 'ext.table'
local template = require 'template'

local CLKernel = class()

--[[
env = CLEnv
name = kernel name.
	optional if body is provided (and kernel code body generation is used)
	required if this object is linking from a kernel elsewhere in code (header or program.code)
argsOut = CLBuffer output arguments.  these go first
argsIn = CLBuffer input arguments.  these go next
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
	self.program = args.program
	self.argBuffers = table()
		:append(self.argsOut)
		:append(self.argsIn)
		:map(function(arg) return arg.buf end)
	self.code = table{
		args.header or '',
		args.body and template([[
kernel void <?=self.name?>(
<?
local sep = ''
for _,arg in ipairs(self.argsOut or {}) do 
?>	<?=sep?>global <?=arg.type?>* <?=arg.name?>
<?
sep = ', '
end
for _,arg in ipairs(self.argsIn or {}) do
?>	<?=sep?>global const <?=arg.type?>* <?=arg.name?>
<?
sep = ', '
end
?>) {
INIT_KERNEL();
<?=args.body?>
}
]], {self=self, args=args}) or ''
	}:concat'\n'
end

-- used for stand-alone compiling
-- if you want to compile this kernel with other kernels, use CLEnv:compileKernels
function CLKernel:compile()
	if self.kernel then
		error("already compiled")
	end
	if self.program then
		error("this kernel already has a program -- use program:compile")
	end
	self.env:program{kernels={self}}:compile()	
end

function CLKernel:__call(...)
	-- if we get a call request when we have no kernel/program, make sure to get one 
	if not self.kernel then
		self:compile()
	end

	self.env:clcall(self.kernel, ...)
end

return CLKernel
