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
	const int length,	//size we're reducing from
	global <?=ctype?>* result)
{
	//for the first iteration
	
	//threads 0...get_local_size(0)-1 start 
	int global_index = get_global_id(0);
	
	//with accumulator values set to initial values 
	<?=ctype?> accumulator = <?=initValue?>;
	
	//loop sequentially over chunks of the input vector
	//so for N elements of size get_local_size(0) we perform N/get_local_size(0) iterations
	while (global_index < length) {
		<?=ctype?> element = buffer[global_index];
		accumulator = <?=op('accumulator', 'element')?>;
		global_index += get_global_size(0);
	}

	// Perform parallel reduction
	//as many times as log2(get_local_size(0))
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
	
	//result[get_group_id(0)] is going to hold the reduction from get_local_size(0)*localIndex through length?
	if (local_index == 0) {
		result[get_group_id(0)] = scratch[0];
	}
}
]]

local function rup2(x)
	local y = 1
	x = x - 1
	while x > 0 do
		x = bit.rshift(x, 1)
		y = bit.lshift(y, 1)
	end
	return y
end

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
		swapBuffer (optional) = cl buffer of ctype[size / get_local_size(0)]
		allocate = (optional) env.clalloc or provided. cl allocation function accepts size, in bytes
		result = (optional) C buffer of ctype to contain the result

	for executing:
		cmds

	env = provides for:
		header
		ctype = env.real
		ctx
		device
		size =  env.base.volume
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
	self.size = assert(args.size or (env and env.base.volume))
	
	local allocate = args.allocate 
		or (env and function(size, name)
			return env:clalloc(size, name, self.ctype)
		end)
		or function(size, name)
			return ctx:buffer{rw=true, size=size}
		end

	self.ctypeSize = args.typeSize or ffi.sizeof(self.ctype)
	self.buffer = args.buffer 
		or allocate(self.size * self.ctypeSize, 'reduce.buffer')
	self.swapBufferSize = math.ceil(self.size / self.maxWorkGroupSize)
	self.swapBuffer = args.swapBuffer 
		or allocate(self.swapBufferSize * self.ctypeSize, 'reduce.swapBuffer')
	
	self.kernel = self.program:kernel(
		name,
		self.buffer,
		{ptr=nil, size=self.maxWorkGroupSize * self.ctypeSize},
		ffi.new('int[1]', self.size),
		self.swapBuffer)

	self.result = args.result or ffi.new(self.ctype..'[1]')
end

function Reduce:__call(buffer, reduceSize)
	-- allow source override
	-- this won't destroy the source, instead it'll switch over to the internal buffer after the first iteration
	local src = buffer or self.buffer
	local dst = self.swapBuffer

	-- allow overriding the size
	-- this only works if the new size is <= the allocated size
	if not reduceSize then
		reduceSize = self.size
	else
		assert(reduceSize <= self.size)
	end

	while reduceSize > 1 do
		local nextSize = math.ceil(reduceSize/self.maxWorkGroupSize)
		local globalSize, localSize
		-- if it's the last iteration then make the local size as small as possible
		if nextSize == 1 then
			localSize = rup2(reduceSize)
			globalSize = localSize
		else
			globalSize = nextSize * self.maxWorkGroupSize
			localSize = self.maxWorkGroupSize
		end
		
		self.kernel:setArg(0, src)
		self.kernel:setArg(2, ffi.new('int[1]', reduceSize))
		self.kernel:setArg(3, dst)
		self.cmds:enqueueNDRangeKernel{kernel=self.kernel, dim=1, globalSize=globalSize, localSize=localSize}
		
		-- only use buffer for reading the first iteration, so it doesn't destroy the buffer for multiple iterations
		if src == buffer then src = self.buffer end
	
		-- swap buffers
		src, dst = dst, src

		reduceSize = nextSize
	end
	self.cmds:enqueueReadBuffer{buffer=src, block=true, size=self.ctypeSize, ptr=self.result}
	
	return self.result[0]
end

return Reduce
