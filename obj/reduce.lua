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
//printf("reduce() begin\n");

//printf(" local_id(0)=%ld", get_local_id(0));
//printf(" global_id(0)=%ld", get_global_id(0));
//printf(" group_id(0)=%ld", get_group_id(0));
//printf(" local_size(0)=%ld", get_local_size(0));
//printf(" global_size(0)=%ld", get_global_size(0));
//printf("\n");

	//threads 0...get_local_size(0)-1 start 
	size_t global_index = get_global_id(0);

	//with accumulator values set to initial values 
	<?=ctype?> accumulator = <?=initValue?>;
	
	//loop sequentially over chunks of the input vector
	// this grabs the first element as the global_index
	// then reduces it with every next element + global_size
	// ... which means, this loop will only run once if your global size >= your length
	while (global_index < length) {
//printf("reading accumulator <= buffer[global_index+offset=%ld]\n", global_index);
		<?=ctype?> const element = buffer[global_index];
		accumulator = <?=op('accumulator', 'element')?>;
		global_index += get_global_size(0);
	}

//printf("done with first accum\n");

	// Perform parallel reduction
	// now we write to the scratch memory at local_index
	// that means the scratch memory should be equal to the local size
	size_t const local_index = get_local_id(0);
//printf("writing scratch[local_index=%ld] <= accumulator\n", local_index);	
	scratch[local_index] = accumulator;
	
	barrier(CLK_LOCAL_MEM_FENCE);
	
	for (int offset = get_local_size(0) >> 1; offset > 0; offset >>= 1) {
		if (local_index < offset) {
			<?=ctype?> const other = scratch[local_index + offset];
			<?=ctype?> const mine = scratch[local_index];
//printf("scratch[local_index=%ld] <= scratch[local_index=%ld] + scratch[local_index+offset=%ld]\n", local_index, local_index, local_index + offset);
			scratch[local_index] = <?=op('mine', 'other')?>;
		}
		
		barrier(CLK_LOCAL_MEM_FENCE);
	}

	//result[get_group_id(0)] is going to hold the reduction from get_local_size(0)*localIndex through length?
	if (local_index == 0) {
//printf("result[group_id=%ld] <= scratch[0]\n", get_group_id(0));
		result[get_group_id(0)] = scratch[0];
	}

//printf("reduce() done\n");
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
		devices = env.devices or provided

	for providing the data:
		buffer = (optional) cl buffer of ctype[count]
		count = number of ctype's. env.volume or provided.
		swapBuffer (optional) = cl buffer of ctype[count / get_local_size(0)]
		allocate = (optional) env.clalloc or provided. cl allocation function accepts size, in bytes
		result = (optional) C buffer of ctype to contain the result
		secondPassInCPU = (optional) default false.  Whether to perform the second pass on the CPU, mind you not in parallel and in Lua.

	for executing:
		cmds

	env = provides for:
		header
		ctype = env.real
		ctx
		devices
		count = env.base.volume
		allocate = env:clalloc
		cmds
--]]
function Reduce:init(args)
	local env = args.env
	local ctx = assert(args.ctx or (env and env.ctx))
	local devices = assert(args.devices or (env and env.devices))
	self.cmds = assert(args.cmds or (env and env.cmds[1]))
	self.ctype = args.type or (env and env.real) or 'float'	
	local name = args.name or 'reduce'
	local header = args.header or ''
	if env then header = header .. '\n' .. env.code end

	self.initValue = args.initValue or '0.'
	self.op = args.op or function(x,y) return 'min('..x..', '..y..')' end

	local code = template(reduceCode, {
		header = header,
		name = name,
		ctype = self.ctype,
		initValue = self.initValue,
		op = self.op,
	})

	self.program = require 'cl.program'{
		context = ctx,
		devices = devices,
		code = code,
	}
	
	self.kernel = self.program:kernel(name)

	-- how to handle multiple devices ...
	self.maxWorkGroupSize = tonumber(self.kernel:getWorkGroupInfo('CL_KERNEL_WORK_GROUP_SIZE', devices[1]))

assert(not args.size, "size is deprecated.  use 'count' instead.")
	self.count = assert(args.count or (env and env.base.volume))
	
	local allocate = args.allocate 
		or (env and function(size, name)
			return env:clalloc(size, name, self.ctype)
		end)
		or function(size, name)
			return ctx:buffer{rw=true, size=size}
		end

	self.ctypeSize = args.typeSize or ffi.sizeof(self.ctype)
	self.buffer = args.buffer 
		or allocate(self.count * self.ctypeSize, 'reduce.buffer')
	self.swapBufferSize = math.ceil(self.count / self.maxWorkGroupSize)
	self.swapBuffer = args.swapBuffer 
		or allocate(self.swapBufferSize * self.ctypeSize, 'reduce.swapBuffer')
	
	self.kernel:setArg(0, self.buffer)
	self.kernel:setArg(1, {ptr=nil, size=self.maxWorkGroupSize * self.ctypeSize})
	self.kernel:setArg(2, ffi.new('int[1]', self.count))
	self.kernel:setArg(3, self.swapBuffer)

	self.secondPassInCPU = args.secondPassInCPU
	if not self.secondPassInCPU
	and self.maxWorkGroupSize == 1
	then
--		print("WARNING - your reduce() had a workgroup size of 1, so it must do the second pass in CPU")
		self.secondPassInCPU = true
	end

	if self.secondPassInCPU then
		local nextSize = math.ceil(self.count/self.maxWorkGroupSize)
		self.cpuResult = ffi.new(self.ctype..'[?]', nextSize)
	end
	self.result = args.result or ffi.new(self.ctype..'[1]')
end

function Reduce:__call(buffer, reduceSize)
	-- allow source override
	-- this won't destroy the source, instead it'll switch over to the internal buffer after the first iteration
	local src = buffer or self.buffer
	local dst = self.swapBuffer

--print('call')

	-- allow overriding the size
	-- this only works if the new size is <= the allocated size
	if not reduceSize then
		reduceSize = self.count
	else
		assert(reduceSize <= self.count, "reduceSize parameter "..reduceSize.." is not <= reduce.count "..self.count)
	end

	-- ok this is a bad idea because now we need the operators and initial value in both CL and Lua ...
	if self.secondPassInCPU then
		local nextSize = math.ceil(reduceSize/self.maxWorkGroupSize)
		local localSize = self.maxWorkGroupSize
		local globalSize = localSize

		self.kernel:setArg(0, src)
		self.kernel:setArg(2, ffi.new('int[1]', reduceSize))
		self.kernel:setArg(3, dst)
		self.cmds:enqueueNDRangeKernel{kernel=self.kernel, dim=1, globalSize=globalSize, localSize=localSize}
		if src == buffer then src = self.buffer end
		src, dst = dst, src

		self.cmds:enqueueReadBuffer{buffer=src, block=true, size=self.ctypeSize, ptr=self.cpuResult}

--print('initValue', self.initValue)
		if not self.cpuAccumInitValue then 
			self.cpuAccumInitValue = assert(loadstring('return '..
				(
					self.initValue
					:gsub('INFINITY', 'math.huge')
				)
			))()
		end
		local accumValue = self.cpuAccumInitValue
--print('accumValue', accumValue)		
		if not self.cpuAccumFunc then
			self.cpuAccumFunc = assert(loadstring('local a,b = ... return '..
				(
					self.op('a', 'b')
					-- TODO ... bleh, I don't like this.  why not just do it all on the GPU?
					:gsub('min', 'math.min')
					:gsub('max', 'math.max')
				)
			))
		end
		local accumFunc = self.cpuAccumFunc
		for i=0,nextSize-1 do
--print('reading result['..i..'] = ', self.cpuResult[i])
			accumValue = accumFunc(accumValue, self.cpuResult[i])
		end
--print('accumValue', accumValue)	
		-- in case self.result was provided externally ...
		self.result[0] = accumValue
		return accumValue
	else
	-- learning experience: 
	-- if maxWorkGroupSize is 1 (as it is on my debug cpu single-threaded implementation)
	-- then this will run forever. 
	-- so in that case, use "secondPassInCPU"
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
	end

--[[ debugging ... I think I'm writing oob
print('globalSize', globalSize)
print('localSize', localSize)
print('self.ctypeSize', self.ctypeSize)
print('self.result', self.result)
print('self.result[0]', self.result[0])
--]]	
	return self.result[0]
end

return Reduce
