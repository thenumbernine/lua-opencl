local class = require 'ext.class'
local ffi = require 'ffi'
local template = require 'template'

local Reduce = class()

local reduceCode = [[
<?=header?>

//http://developer.amd.com/resources/documentation-articles/articles-whitepapers/opencl-optimization-case-study-simple-reductions/
//calculate min of all elements on buffer[0..length-1]
kernel void <?=name?>(
	const global <?=ctype?>* buffer,
	local <?=ctype?>* scratch,
	const int length,
	global <?=ctype?>* result)
{
	int global_index = get_global_id(0);
	<?=ctype?> accumulator = <?=initValue?>;
	
	// Loop sequentially over chunks of input vector
	while (global_index < length) {
		<?=ctype?> element = buffer[global_index];
		accumulator = <?=op('accumulator', 'element')?>;
		global_index += get_global_size(0);
	}

	// Perform parallel reduction
	int local_index = get_local_id(0);
	scratch[local_index] = accumulator;
	barrier(CLK_LOCAL_MEM_FENCE);
	for (int offset = get_local_size(0) / 2; offset > 0; offset = offset / 2) {
		if (local_index < offset) {
			<?=ctype?> other = scratch[local_index + offset];
			<?=ctype?> mine = scratch[local_index];
			scratch[local_index] = <?=op('mine', 'other')?>;
		}
		barrier(CLK_LOCAL_MEM_FENCE);
	}
	if (local_index == 0) {
		result[get_group_id(0)] = scratch[0];
	}
}
]]

--[[
args:
	for making the code:
		header (optional) = env.code or provided
		name (optional) default 'reduce'
		ctype (optional) default env.real or 'float'
		initValue (optional) default 0
		op (optional) default min(x,y).  provides a function(x,y) that returns a string of the code to be run. 
	
	for making the kernel:
		ctx = env.ctx or provided
		device = env.device or provided

	for providing the data:
		buffer = (optional) cl buffer of ctype[size]
		size = size (in ctype's). env.volume or provided.
		swapBuffer (optional) = cl buffer of ctype[size / localSize]
		allocate = (optional) env.clalloc or provided. cl allocation function accepts size, in bytes
		result = (optional) C buffer of ctype to contain the result

	for executing:
		cmds

	env = provides for:
		header
		ctype = env.real
		ctx
		device
		size =  env.domain.volume
		allocate = env:clalloc
		cmds
--]]
function Reduce:init(args)
	local env = args.env
	local ctx = assert(args.ctx or (env and env.ctx))
	local device = assert(args.device or (env and env.device))
	self.cmds = assert(args.cmds or (env and env.cmds))
	self.ctype = args.type or (env and env.real) or 'float'	
	local name = args.name or 'reduce'
	local header = args.header or ''
	if env then header = header .. '\n' .. env.code end

	local code = template(reduceCode, {
		header = header,
		name = name,
		ctype = self.ctype,
		initValue = args.initValue or '0.',
		op = args.op or function(x,y) return 'min('..x..', '..y..')' end,
	})

	self.program = require 'cl.program'{
		context = ctx,
		devices = {device},
		code = code,
	}
	
	self.maxWorkGroupSize = tonumber(device:getInfo'CL_DEVICE_MAX_WORK_GROUP_SIZE')
	self.size = assert(args.size or (env and env.domain.volume))
	local localSize = math.min(self.maxWorkGroupSize, self.size)

	local allocate = args.allocate 
		or (env and function(size)
			return env:clalloc(size, 'reduce', self.ctype)
		end)
		or function(size)
			return ctx:buffer{rw=true, size=size}
		end

	self.ctypeSize = args.typeSize or ffi.sizeof(self.ctype)
	self.buffer = args.buffer or allocate(self.size * self.ctypeSize)
	self.swapBuffer = args.swapBuffer or allocate(math.ceil(self.size / localSize) * self.ctypeSize)
	
	self.kernel = self.program:kernel(
		name,
		self.buffer,
		{ptr=nil, size=localSize * self.ctypeSize},
		ffi.new('int[1]', self.size),
		self.swapBuffer)

	self.result = args.result or ffi.new(self.ctype..'[1]')
end

function Reduce:__call()
	local push
	if buf then
		push = self.buffer
		self.buffer = buf
	end
	
	local reduceSize = self.size
	local dst = self.swapBuffer
	local src = self.buffer

	-- TODO should be the min of the rounded-up/down? power-of-2 of reduceSize
	local reduceLocalSize1D = math.min(reduceSize, self.maxWorkGroupSize)
	
	while reduceSize > 1 do
		
		local nextSize = math.floor(reduceSize / reduceLocalSize1D)
		if 0 ~= bit.band(reduceSize, reduceLocalSize1D - 1) then 
			nextSize = nextSize + 1 
		end
		local reduceGlobalSize = math.max(reduceSize, reduceLocalSize1D)

		self.kernel:setArg(0, src)
		self.kernel:setArg(2, ffi.new('int[1]', reduceSize))
		self.kernel:setArg(3, dst)

		self.cmds:enqueueNDRangeKernel{kernel=self.kernel, dim=1, globalSize=reduceGlobalSize, localSize=math.min(reduceGlobalSize, reduceLocalSize1D)}
		--self.cmds:finish()
		dst, src = src, dst
		reduceSize = nextSize
	end
	self.cmds:enqueueReadBuffer{buffer=src, block=true, size=self.ctypeSize, ptr=self.result}
	
	if push then
		self.buffer = push
	end
	
	return self.result[0]
end

return Reduce
