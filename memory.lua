local cl = require 'ffi.req' 'OpenCL'
local class = require 'ext.class'
local GCWrapper = require 'ffi.gcwrapper.gcwrapper'
local GetInfo = require 'cl.getinfo'

local Memory = class(GetInfo(GCWrapper{
	ctype = 'cl_mem',
	retain = function(ptr) return cl.clRetainMemObject(ptr[0]) end,
	release = function(ptr) return cl.clReleaseMemObject(ptr[0]) end,
}))

Memory.getInfo = Memory:makeGetter{
	getter = cl.clGetMemObjectInfo,
	vars = {
		{name='CL_MEM_TYPE', type='cl_device_local_mem_type'},	-- ???
		{name='CL_MEM_FLAGS', type='cl_mem_flags'},	-- ???
		{name='CL_MEM_SIZE', type='size_t'},	-- ???
		{name='CL_MEM_HOST_PTR', type='void*'},	-- ???
		{name='CL_MEM_MAP_COUNT', type='cl_uint'},	-- ???
		{name='CL_MEM_REFERENCE_COUNT', type='cl_uint'},	-- ???
		{name='CL_MEM_CONTEXT', type='cl_context'},	-- ???
		{name='CL_MEM_ASSOCIATED_MEMOBJECT', type=''},	-- ???
		{name='CL_MEM_OFFSET', type='size_t'},	-- ???
		{name='CL_MEM_USES_SVM_POINTER', type='cl_bool'},	-- ???
	},
}

function Memory:init(...)
	Memory.super.init(self, ...)
	self.id = self.gc.ptr[0]
end

return Memory
