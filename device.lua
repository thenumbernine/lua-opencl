local cl = require 'ffi.OpenCL'
local class = require 'ext.class'
local Wrapper = require 'cl.wrapper'
local GetInfo = require 'cl.getinfo'

local Device = class(GetInfo(Wrapper(
	'cl_device_id',
	cl.clRetainDevice,
	cl.clReleaseDevice)))
Device.infoGetter = cl.clGetDeviceInfo
Device.infos = {
	CL_DEVICE_TYPE = 'cl_device_type',
	CL_DEVICE_VENDOR_ID = 'cl_uint',
	CL_DEVICE_MAX_COMPUTE_UNITS = 'cl_uint',
	CL_DEVICE_MAX_WORK_ITEM_DIMENSIONS = 'cl_uint',
	CL_DEVICE_MAX_WORK_GROUP_SIZE = 'size_t',
	CL_DEVICE_MAX_WORK_ITEM_SIZES = 'size_t[]',
	CL_DEVICE_PREFERRED_VECTOR_WIDTH_CHAR = 'cl_uint',
	CL_DEVICE_PREFERRED_VECTOR_WIDTH_SHORT = 'cl_uint',
	CL_DEVICE_PREFERRED_VECTOR_WIDTH_INT = 'cl_uint',
	CL_DEVICE_PREFERRED_VECTOR_WIDTH_LONG = 'cl_uint',
	CL_DEVICE_PREFERRED_VECTOR_WIDTH_FLOAT = 'cl_uint',
	CL_DEVICE_PREFERRED_VECTOR_WIDTH_DOUBLE = 'cl_uint',
	CL_DEVICE_MAX_CLOCK_FREQUENCY = 'cl_uint',
	CL_DEVICE_ADDRESS_BITS = 'cl_uint',
	CL_DEVICE_MAX_READ_IMAGE_ARGS = 'cl_uint',
	CL_DEVICE_MAX_WRITE_IMAGE_ARGS = 'cl_uint',
	CL_DEVICE_MAX_MEM_ALLOC_SIZE = 'cl_ulong',
	CL_DEVICE_IMAGE2D_MAX_WIDTH = 'size_t',
	CL_DEVICE_IMAGE2D_MAX_HEIGHT = 'size_t',
	CL_DEVICE_IMAGE3D_MAX_WIDTH = 'size_t',
	CL_DEVICE_IMAGE3D_MAX_HEIGHT = 'size_t',
	CL_DEVICE_IMAGE3D_MAX_DEPTH = 'size_t',
	CL_DEVICE_IMAGE_SUPPORT = 'cl_bool',
	CL_DEVICE_MAX_PARAMETER_SIZE = 'size_t',
	CL_DEVICE_MAX_SAMPLERS = 'cl_uint',
	CL_DEVICE_MEM_BASE_ADDR_ALIGN = 'cl_uint',
	CL_DEVICE_MIN_DATA_TYPE_ALIGN_SIZE = 'cl_uint',
	CL_DEVICE_SINGLE_FP_CONFIG = 'cl_device_fp_config',
	CL_DEVICE_GLOBAL_MEM_CACHE_TYPE = 'cl_device_mem_cache_type',
	CL_DEVICE_GLOBAL_MEM_CACHELINE_SIZE = 'cl_uint',
	CL_DEVICE_GLOBAL_MEM_CACHE_SIZE = 'cl_ulong',
	CL_DEVICE_GLOBAL_MEM_SIZE = 'cl_ulong',
	CL_DEVICE_MAX_CONSTANT_BUFFER_SIZE = 'cl_ulong',
	CL_DEVICE_MAX_CONSTANT_ARGS = 'cl_uint',
	CL_DEVICE_LOCAL_MEM_TYPE = 'cl_device_local_mem_type',
	CL_DEVICE_LOCAL_MEM_SIZE = 'cl_ulong',
	CL_DEVICE_ERROR_CORRECTION_SUPPORT = 'cl_bool',
	CL_DEVICE_PROFILING_TIMER_RESOLUTION = 'size_t',
	CL_DEVICE_ENDIAN_LITTLE = 'cl_bool',
	CL_DEVICE_AVAILABLE = 'cl_bool',
	CL_DEVICE_COMPILER_AVAILABLE = 'cl_bool',
	CL_DEVICE_EXECUTION_CAPABILITIES = 'cl_device_exec_capabilities',
	CL_DEVICE_QUEUE_PROPERTIES = 'cl_command_queue_properties',
	CL_DEVICE_PLATFORM = 'cl_platform_id',
	CL_DEVICE_NAME = 'string',
	CL_DEVICE_VENDOR = 'string',
	CL_DRIVER_VERSION = 'string',
	CL_DEVICE_PROFILE = 'string',
	CL_DEVICE_VERSION = 'string',
	CL_DEVICE_EXTENSIONS = 'string',
}
function Device:init(id)
	self.id = id
	Device.super.init(self, self.id)
end

return Device
