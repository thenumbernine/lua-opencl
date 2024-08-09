local cl = require 'ffi.req' 'OpenCL'
local GCWrapper = require 'cl.gcwrapper'
local GetInfo = require 'cl.getinfo'

local Memory = GetInfo(GCWrapper{
	ctype = 'cl_mem',
	retain = function(self) return cl.clRetainMemObject(self.id) end,
	release = function(self) return cl.clReleaseMemObject(self.id) end,
}):subclass()

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

function Memory:init(id)
	self.id = id
end

return Memory
