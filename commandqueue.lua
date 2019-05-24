local class = require 'ext.class'
local table = require 'ext.table'
local ffi = require 'ffi'
local cl = require 'ffi.OpenCL'
local classert = require 'cl.assert'
local classertparam = require 'cl.assertparam'
local Wrapper = require 'cl.wrapper'

-- here and commandqueue.lua
local function ffi_new_table(T, src)
	return ffi.new(T..'['..#src..']', src)
end

local CommandQueue = class(Wrapper(
	'cl_command_queue',
	cl.clRetainCommandQueue,
	cl.clReleaseCommandQueue))

--[[
args
	context
	device
	properties
--]]
function CommandQueue:init(args)
	assert(args, "expected args")
	self.id = classertparam('clCreateCommandQueue',
		assert(args.context, "expected context").id,
		assert(args.device, "expected device").id,
		args.properties or 0)
	CommandQueue.super.init(self, self.id)
end

--[[
args:
	buffer
	block
	offset (optional) default 0
	size
	ptr
--]]
function CommandQueue:enqueueReadBuffer(args)
	classert(cl.clEnqueueReadBuffer(
		self.id,
		assert(args.buffer, "expected buffer").id,
		args.block,
		args.offset or 0,
		assert(args.size, "expected size"),
		assert(args.ptr, "expected ptr"),
		0,
		nil,
		nil))
end

--[[
args:
	buffer
	block
	offset (optional) default 0
	size
	ptr
--]]
function CommandQueue:enqueueWriteBuffer(args)
	classert(cl.clEnqueueWriteBuffer(
		self.id,
		assert(args.buffer, "expected buffer").id,
		args.block,
		args.offset or 0,
		assert(args.size, "expected size"),
		assert(args.ptr, "expected ptr"),
		0,
		nil,
		nil))
end

--[[
args:
	buffer
	pattern (optional)
	patternSize (optional)
	offset (optional)
	size (bytes)
--]]
local defaultPattern = ffi.new('int[1]', 0)
function CommandQueue:enqueueFillBuffer(args)
	local pattern = args.pattern
	local patternSize = args.patternSize
	if not pattern then
		pattern = defaultPattern
		patternSize = ffi.sizeof'int'
	end
	classert(cl.clEnqueueFillBuffer(
		self.id,
		assert(args.buffer, "expected buffer").id,
		pattern,
		patternSize,
		args.offset or 0,
		assert(args.size, "expected size"),
		0,
		nil,
		nil))
end

--[[
args:
	src
	dst
	srcOffset (optional)
	dstOffset (optional)
	size
--]]
function CommandQueue:enqueueCopyBuffer(args)
	classert(cl.clEnqueueCopyBuffer(
		self.id,
		assert(args.src, "expected src").id,
		assert(args.dst, "expected dst").id,
		args.srcOffset or 0,
		args.dstOffset or 0,
		assert(args.size, "expected size"),
		0,
		nil,
		nil))
end

--[[
args:
	kernel
	dim (optional) if not provided then offset, globalSize, or localSize must be a table?
	offset (optional)
	globalSize
	localSize
--]]
local size_t_ptr_type = ffi.typeof(ffi.new('size_t[1]')+1)
local offset = ffi.new('size_t[3]')
local globalSize = ffi.new('size_t[3]')
local localSize = ffi.new('size_t[3]')

local function fillParam(dim, src, dst)
	if type(src) == 'number' then
		if not dim then
			dim = 1
		else
			assert(dim == 1)
		end
		dst[0] = src
	elseif type(src) == 'table' then
		if not dim then
			dim = #src
		else
			assert(dim == #src)
		end
		for i=1,dim do
			dst[i-1] = src[i]
		end
	elseif type(src) == 'cdata'
	and ffi.typeof(src) == size_t_ptr_type
	then
		assert(dim)
		for i=0,dim-1 do
			dst[i] = src[i]
		end
	end
	return dim
end

--[[
args:
	dim
	offset
	globalSize
	localSize
	kernel	=> cl.kernel object
	wait => table of cl.event
	event => cl.event
--]]
function CommandQueue:enqueueNDRangeKernel(args)
	local dim = args.dim
	dim = fillParam(dim, args.offset, offset)
	dim = fillParam(dim, args.globalSize, globalSize)
	dim = fillParam(dim, args.localSize, localSize)
	local numWait = args.wait and #args.wait or 0
	local wait
	if numWait > 0 then
		wait = ffi.new('cl_event[?]', numWait)
		for i=1,numWait do
			wait[i-1] = args.wait[i].id
		end
	end
	
	classert(cl.clEnqueueNDRangeKernel(
		self.id,
		assert(args.kernel, "expected kernel").id,
		dim,
		offset,
		globalSize,
		localSize,
		numWait,
		wait,
		args.event and args.event.gc.ptr or nil))
	
	-- hmm should I even use 'id' if gc.ptr[0] will be holding the same information?
	if args.event then
		args.event.id = args.event.gc.ptr[0]
	end
end

--[[
args:
	objs
--]]
function CommandQueue:enqueueAcquireGLObjects(args)
	local objs = assert(args.objs, "expected objs")
	classert(cl.clEnqueueAcquireGLObjects(
		self.id,
		#objs,
		ffi_new_table('cl_mem', table.mapi(objs, function(obj) return obj.id end)),
		0,
		nil,
		nil))
end

--[[
args:
	objs
--]]
function CommandQueue:enqueueReleaseGLObjects(args)
	local objs = assert(args.objs, "expected objs")
	classert(cl.clEnqueueReleaseGLObjects(
		self.id,
		#objs,
		ffi_new_table('cl_mem', table.mapi(objs, function(obj) return obj.id end)),
		0,
		nil,
		nil))
end

function CommandQueue:finish()
	cl.clFinish(self.id)
end

return CommandQueue
