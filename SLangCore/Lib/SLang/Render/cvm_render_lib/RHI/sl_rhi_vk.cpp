/* =========================================================================
 * sl_rhi_vk.cpp —— RHI 后端：Vulkan（纯离屏，无 surface / 无 swapchain）
 *
 * （C++ 编译单元；跨编译单元符号经 sl_render_internal.h 的 extern "C"
 *   保持 C 链接）
 *
 * 与 GL / D3D11 后端渲染完全一致效果的 Vulkan 实现（同一像素契约）：
 *   - 零构建依赖：vulkan-1.dll 运行期 LoadLibrary，全部函数经
 *     vkGetInstanceProcAddr 解析（无 Vulkan SDK 头 / .lib）；
 *   - 着色器：六组槽位的 SPIR-V 由 glslang 一次性预编译，以 C 数组固化
 *     在 RHI/sl_rhi_vk_shaders.h（源码见该文件注释，可随时重生成）；
 *   - 执行模型：即时风格 —— 每个"开启 pass"的 RHI 调用先把上一段命令
 *     缓冲收尾（结束 render pass -> 提交 -> 队列等待空闲），再开新段；
 *     绘制项按序记录进当前段，回读时最终提交。一帧约 4 次提交。
 *
 * 与 GL 的语义差异处理（保证同效果）：
 *   - NDC y 翻转在全部 VS 内完成（gl_Position.y = -y）：光栅化等价于
 *     D3D11 的 y-up clip space + 行 0 = 图像顶部，相机视口换算
 *     TopLeftY = target_h - (y + h) 与 D3D11 完全一致；
 *   - 相机局部清屏直接 vkCmdClearAttachments（矩形级，不受 scissor 影响，
 *     与 GL 的 scissor+clear 语义精确对齐；无需 D3D11 的清屏 quad hack）；
 *   - PerDraw 常量缓冲（std140 UBO 5120B）+ uObjIndex 走 push constant，
 *     v1 的 MVP/Color（80B）与后处理参数（16B）同样走 push constant；
 *   - 网格数据与 D3D11 后端逐字节一致（fs_tri 的 V 翻转版）；
 *   - 回读：vkCmdCopyImageToBuffer 行 0 = 图像顶部，紧密行距（RGBA8 行
 *     字节数恒为 4 的倍数），拷贝后无需翻行；
 *   - 帧间布局跟踪：颜色附件在 pass 外恒为 COLOR_ATTACHMENT_OPTIMAL，
 *     回读后为 TRANSFER_SRC_OPTIMAL，采样式屏障按当前布局取 oldLayout。
 * ========================================================================= */
#include "sl_render_internal.h"
#include "RHI/sl_rhi_vk_shaders.h"

/* ===================================================================== */
/* Vulkan 类型 / 常量（手写，值对齐官方 vulkan_core.h；零 SDK 依赖）        */
/* ===================================================================== */
typedef struct VkInstance_T*        VkInstance;
typedef struct VkPhysicalDevice_T* VkPhysicalDevice;
typedef struct VkDevice_T*         VkDevice;
typedef struct VkQueue_T*           VkQueue;
typedef struct VkCommandPool_T*     VkCommandPool;
typedef struct VkCommandBuffer_T*   VkCommandBuffer;
typedef struct VkBuffer_T*          VkBuffer;
typedef struct VkImage_T*            VkImage;
typedef struct VkDeviceMemory_T*     VkDeviceMemory;
typedef struct VkImageView_T*        VkImageView;
typedef struct VkRenderPass_T*       VkRenderPass;
typedef struct VkFramebuffer_T*      VkFramebuffer;
typedef struct VkShaderModule_T*     VkShaderModule;
typedef struct VkPipelineLayout_T*   VkPipelineLayout;
typedef struct VkPipeline_T*         VkPipeline;
typedef struct VkPipelineCache_T*    VkPipelineCache;
typedef struct VkSampler_T*          VkSampler;
typedef struct VkDescriptorPool_T*    VkDescriptorPool;
typedef struct VkDescriptorSetLayout_T* VkDescriptorSetLayout;
typedef struct VkDescriptorSet_T*    VkDescriptorSet;
typedef struct VkFence_T*            VkFence;

typedef uint32_t VkBool32;
typedef uint32_t VkFlags;
typedef uint64_t VkDeviceSize;
typedef int32_t  VkStructureType;
typedef int32_t  VkResult;
typedef int32_t  VkFormat;
typedef int32_t  VkImageLayout;
typedef int32_t  VkImageTiling;
typedef int32_t  VkImageViewType;
typedef int32_t  VkSharingMode;
typedef int32_t  VkPipelineBindPoint;
typedef int32_t  VkShaderStageFlagBits;
typedef int32_t  VkCullModeFlags;
typedef int32_t  VkPolygonMode;
typedef int32_t  VkFrontFace;
typedef int32_t  VkCompareOp;
typedef int32_t  VkBlendFactor;
typedef int32_t  VkBlendOp;
typedef int32_t  VkDynamicState;
typedef int32_t  VkPrimitiveTopology;
typedef int32_t  VkVertexInputRate;
typedef int32_t  VkFilter;
typedef int32_t  VkSamplerMipmapMode;
typedef int32_t  VkSamplerAddressMode;
typedef int32_t  VkDescriptorType;
typedef int32_t  VkAttachmentLoadOp;
typedef int32_t  VkAttachmentStoreOp;
typedef int32_t  VkCommandBufferLevel;
typedef int32_t  VkSubpassContents;
typedef int32_t  VkPhysicalDeviceType;

#define VK_NULL_HANDLE            ((void*)0)
#define VK_TRUE                   1
#define VK_FALSE                  0

/* VkResult */
#define VK_SUCCESS                0
#define VK_INCOMPLETE             5
#define VK_ERROR_OUT_OF_HOST_MEMORY    (-1)
#define VK_ERROR_OUT_OF_DEVICE_MEMORY  (-2)
#define VK_ERROR_INITIALIZATION_FAILED (-3)
#define VK_ERROR_MEMORY_MAP_FAILED     (-5)
#define VK_ERROR_TOO_MANY_OBJECTS      (-10)
#define VK_ERROR_FORMAT_NOT_SUPPORTED  (-11)

/* VkStructureType */
#define VK_STRUCTURE_TYPE_APPLICATION_INFO                   0
#define VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO               1
#define VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO           2
#define VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO                 3
#define VK_STRUCTURE_TYPE_SUBMIT_INFO                        4
#define VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO               5
#define VK_STRUCTURE_TYPE_MAPPED_MEMORY_RANGE                6
#define VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO                 12
#define VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO                  14
#define VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO             15
#define VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO          16
#define VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO  18
#define VK_STRUCTURE_TYPE_PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO 19
#define VK_STRUCTURE_TYPE_PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO 20
#define VK_STRUCTURE_TYPE_PIPELINE_VIEWPORT_STATE_CREATE_INFO 22
#define VK_STRUCTURE_TYPE_PIPELINE_RASTERIZATION_STATE_CREATE_INFO 23
#define VK_STRUCTURE_TYPE_PIPELINE_MULTISAMPLE_STATE_CREATE_INFO   24
#define VK_STRUCTURE_TYPE_PIPELINE_DEPTH_STENCIL_STATE_CREATE_INFO 25
#define VK_STRUCTURE_TYPE_PIPELINE_COLOR_BLEND_STATE_CREATE_INFO   26
#define VK_STRUCTURE_TYPE_PIPELINE_DYNAMIC_STATE_CREATE_INFO  27
#define VK_STRUCTURE_TYPE_GRAPHICS_PIPELINE_CREATE_INFO      28
#define VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO        30
#define VK_STRUCTURE_TYPE_SAMPLER_CREATE_INFO                31
#define VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO  32
#define VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO       33
#define VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO       34
#define VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET               35
#define VK_STRUCTURE_TYPE_FRAMEBUFFER_CREATE_INFO            37
#define VK_STRUCTURE_TYPE_RENDER_PASS_CREATE_INFO           38
#define VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO          39
#define VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO       40
#define VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO         42
#define VK_STRUCTURE_TYPE_RENDER_PASS_BEGIN_INFO            43
#define VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER               45

/* VkFormat */
#define VK_FORMAT_R8G8B8A8_UNORM    37
#define VK_FORMAT_R32G32_SFLOAT     103
#define VK_FORMAT_D32_SFLOAT        126
#define VK_FORMAT_D24_UNORM_S8_UINT 129

/* VkImageLayout */
#define VK_IMAGE_LAYOUT_UNDEFINED                    0
#define VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL     2
#define VK_IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL 3
#define VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL     5
#define VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL         6
#define VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL         7

/* 各类 flag bits */
#define VK_QUEUE_GRAPHICS_BIT                       0x00000001
#define VK_IMAGE_USAGE_TRANSFER_SRC_BIT             0x00000001
#define VK_IMAGE_USAGE_TRANSFER_DST_BIT             0x00000002
#define VK_IMAGE_USAGE_SAMPLED_BIT                  0x00000004
#define VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT         0x00000010
#define VK_IMAGE_USAGE_DEPTH_STENCIL_ATTACHMENT_BIT 0x00000020
#define VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT        0x00000001
#define VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT        0x00000002
#define VK_MEMORY_PROPERTY_HOST_COHERENT_BIT       0x00000004
#define VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT          0x00000001
#define VK_PIPELINE_STAGE_VERTEX_SHADER_BIT        0x00000008
#define VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT      0x00000080
#define VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT 0x00000400
#define VK_PIPELINE_STAGE_TRANSFER_BIT             0x00001000
#define VK_ACCESS_SHADER_READ_BIT                  0x00000020
#define VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT       0x00000100
#define VK_ACCESS_TRANSFER_READ_BIT               0x00000800
#define VK_ACCESS_TRANSFER_WRITE_BIT               0x00001000
#define VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT 0x00000001
#define VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT 0x00000002
#define VK_DESCRIPTOR_POOL_CREATE_FREE_DESCRIPTOR_SET_BIT 0x00000001
#define VK_ATTACHMENT_LOAD_OP_LOAD   0
#define VK_ATTACHMENT_LOAD_OP_CLEAR   1
#define VK_ATTACHMENT_LOAD_OP_DONT_CARE 2
#define VK_ATTACHMENT_STORE_OP_STORE  0
#define VK_IMAGE_ASPECT_COLOR_BIT     0x00000001
#define VK_IMAGE_ASPECT_DEPTH_BIT     0x00000002
#define VK_IMAGE_ASPECT_STENCIL_BIT   0x00000004
#define VK_COMPARE_OP_LESS            1
#define VK_BLEND_FACTOR_SRC_ALPHA     6
#define VK_BLEND_FACTOR_ONE_MINUS_SRC_ALPHA 7
#define VK_BLEND_OP_ADD               0
#define VK_DYNAMIC_STATE_VIEWPORT     0
#define VK_DYNAMIC_STATE_SCISSOR      1
#define VK_SHADER_STAGE_VERTEX_BIT    0x00000001
#define VK_SHADER_STAGE_FRAGMENT_BIT  0x00000010
#define VK_PIPELINE_BIND_POINT_GRAPHICS 0
#define VK_CULL_MODE_NONE             0
#define VK_POLYGON_MODE_FILL          0
#define VK_FRONT_FACE_COUNTER_CLOCKWISE 0
#define VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_EDGE 2
#define VK_FILTER_LINEAR              1
#define VK_SAMPLER_MIPMAP_MODE_NEAREST 0
#define VK_VERTEX_INPUT_RATE_VERTEX   0
#define VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST 3
#define VK_IMAGE_TILING_OPTIMAL       0
#define VK_IMAGE_VIEW_TYPE_2D         1
#define VK_SHARING_MODE_EXCLUSIVE     0
#define VK_COMMAND_BUFFER_LEVEL_PRIMARY 0
#define VK_SUBPASS_CONTENTS_INLINE    0
#define VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER 1
#define VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER 6
#define VK_COLOR_COMPONENT_RGBA       0x0000000F
#define VK_FORMAT_FEATURE_DEPTH_STENCIL_ATTACHMENT_BIT 0x00000200
#define VK_MAX_MEMORY_TYPES 32
#define VK_MAX_MEMORY_HEAPS 16
#define VK_MAX_PHYSICAL_DEVICE_NAME_SIZE 256
#define VK_API_VERSION_1_0  0x00400000u   /* VK_MAKE_API_VERSION(0,1,0,0) */
#define VK_UUID_SIZE 16

typedef struct VkOffset2D { int32_t x, y; } VkOffset2D;
typedef struct VkExtent2D { uint32_t width, height; } VkExtent2D;
typedef struct VkExtent3D { uint32_t width, height, depth; } VkExtent3D;
typedef struct VkOffset3D { int32_t x, y, z; } VkOffset3D;
typedef struct VkRect2D   { VkOffset2D offset; VkExtent2D extent; } VkRect2D;

typedef struct VkViewport
{
    float x, y, width, height, minDepth, maxDepth;
} VkViewport;

typedef struct VkApplicationInfo
{
    VkStructureType sType; const void* pNext;
    const char* pApplicationName; uint32_t applicationVersion;
    const char* pEngineName;      uint32_t engineVersion;
    uint32_t apiVersion;
} VkApplicationInfo;

typedef struct VkInstanceCreateInfo
{
    VkStructureType sType; const void* pNext; VkFlags flags;
    const VkApplicationInfo* pApplicationInfo;
    uint32_t enabledLayerCount; const char* const* ppEnabledLayerNames;
    uint32_t enabledExtensionCount; const char* const* ppEnabledExtensionNames;
} VkInstanceCreateInfo;

typedef struct VkDeviceQueueCreateInfo
{
    VkStructureType sType; const void* pNext; VkFlags flags;
    uint32_t queueFamilyIndex; uint32_t queueCount; const float* pQueuePriorities;
} VkDeviceQueueCreateInfo;

typedef struct VkDeviceCreateInfo
{
    VkStructureType sType; const void* pNext; VkFlags flags;
    uint32_t queueCreateInfoCount; const VkDeviceQueueCreateInfo* pQueueCreateInfos;
    uint32_t enabledLayerCount; const char* const* ppEnabledLayerNames;
    uint32_t enabledExtensionCount; const char* const* ppEnabledExtensionNames;
    const void* pEnabledFeatures;
} VkDeviceCreateInfo;

/* VkPhysicalDeviceProperties：仅取前段字段，尾部以大垫片保证缓冲不小于
 * 驱动实际写入尺寸（limits + sparseProperties 合计 < 768B）*/
typedef struct VkPhysicalDeviceProperties
{
    uint32_t apiVersion, driverVersion, vendorID, deviceID;
    VkPhysicalDeviceType deviceType;
    char deviceName[VK_MAX_PHYSICAL_DEVICE_NAME_SIZE];
    uint8_t pipelineCacheUUID[VK_UUID_SIZE];
    uint8_t tail[768];
} VkPhysicalDeviceProperties;

typedef struct VkMemoryType { VkFlags propertyFlags; uint32_t heapIndex; } VkMemoryType;
typedef struct VkMemoryHeap { VkDeviceSize size; VkFlags flags; } VkMemoryHeap;

typedef struct VkPhysicalDeviceMemoryProperties
{
    uint32_t memoryTypeCount; VkMemoryType memoryTypes[VK_MAX_MEMORY_TYPES];
    uint32_t memoryHeapCount; VkMemoryHeap memoryHeaps[VK_MAX_MEMORY_HEAPS];
} VkPhysicalDeviceMemoryProperties;

typedef struct VkQueueFamilyProperties
{
    VkFlags queueFlags; uint32_t queueCount;
    uint32_t timestampValidBits; VkExtent3D minImageTransferGranularity;
} VkQueueFamilyProperties;

typedef struct VkFormatProperties
{
    VkFlags linearTilingFeatures, optimalTilingFeatures, bufferFeatures;
} VkFormatProperties;

typedef struct VkMemoryRequirements
{
    VkDeviceSize size, alignment; uint32_t memoryTypeBits;
} VkMemoryRequirements;

typedef struct VkCommandPoolCreateInfo
{
    VkStructureType sType; const void* pNext; VkFlags flags; uint32_t queueFamilyIndex;
} VkCommandPoolCreateInfo;

typedef struct VkCommandBufferAllocateInfo
{
    VkStructureType sType; const void* pNext;
    VkCommandPool commandPool; VkCommandBufferLevel level; uint32_t commandBufferCount;
} VkCommandBufferAllocateInfo;

typedef struct VkCommandBufferBeginInfo
{
    VkStructureType sType; const void* pNext; VkFlags flags; const void* pInheritanceInfo;
} VkCommandBufferBeginInfo;

typedef struct VkSubmitInfo
{
    VkStructureType sType; const void* pNext;
    uint32_t waitSemaphoreCount; const VkFence* pWaitSemaphores; const VkFlags* pWaitDstStageMask;
    uint32_t commandBufferCount; const VkCommandBuffer* pCommandBuffers;
    uint32_t signalSemaphoreCount; const VkFence* pSignalSemaphores;
} VkSubmitInfo;

typedef union VkClearValue
{
    float color[4];
    struct { float depth; uint32_t stencil; } depthStencil;
} VkClearValue;

typedef struct VkRenderPassBeginInfo
{
    VkStructureType sType; const void* pNext;
    VkRenderPass renderPass; VkFramebuffer framebuffer;
    VkRect2D renderArea;
    uint32_t clearValueCount; const VkClearValue* pClearValues;
} VkRenderPassBeginInfo;

typedef struct VkClearRect
{
    VkRect2D rect; uint32_t baseArrayLayer, layerCount;
} VkClearRect;

typedef struct VkClearAttachment
{
    VkFlags aspectMask; uint32_t colorAttachment; VkClearValue clearValue;
} VkClearAttachment;

typedef struct VkMemoryAllocateInfo
{
    VkStructureType sType; const void* pNext;
    VkDeviceSize allocationSize; uint32_t memoryTypeIndex;
} VkMemoryAllocateInfo;

typedef struct VkMappedMemoryRange
{
    VkStructureType sType; const void* pNext;
    VkDeviceMemory memory; VkDeviceSize offset, size;
} VkMappedMemoryRange;

typedef struct VkImageSubresourceRange
{
    VkFlags aspectMask; uint32_t baseMipLevel, levelCount, baseArrayLayer, layerCount;
} VkImageSubresourceRange;

typedef struct VkImageSubresourceLayers
{
    VkFlags aspectMask; uint32_t mipLevel, baseArrayLayer, layerCount;
} VkImageSubresourceLayers;

typedef struct VkImageMemoryBarrier
{
    VkStructureType sType; const void* pNext;
    VkFlags srcAccessMask, dstAccessMask;
    VkImageLayout oldLayout, newLayout;
    uint32_t srcQueueFamilyIndex, dstQueueFamilyIndex;
    VkImage image; VkImageSubresourceRange subresourceRange;
} VkImageMemoryBarrier;

typedef struct VkBufferCreateInfo
{
    VkStructureType sType; const void* pNext; VkFlags flags;
    VkDeviceSize size; VkFlags usage; VkSharingMode sharingMode;
    uint32_t queueFamilyIndexCount; const uint32_t* pQueueFamilyIndices;
} VkBufferCreateInfo;

typedef struct VkBufferImageCopy
{
    VkDeviceSize bufferOffset; uint32_t bufferRowLength, bufferImageHeight;
    VkImageSubresourceLayers imageSubresource; VkOffset3D imageOffset; VkExtent3D imageExtent;
} VkBufferImageCopy;

typedef struct VkBufferCopy
{
    VkDeviceSize srcOffset, dstOffset, size;
} VkBufferCopy;

typedef struct VkImageCreateInfo
{
    VkStructureType sType; const void* pNext; VkFlags flags;
    int32_t imageType; VkFormat format; VkExtent3D extent;
    uint32_t mipLevels, arrayLayers; int32_t samples; VkImageTiling tiling;
    VkFlags usage; VkSharingMode sharingMode;
    uint32_t queueFamilyIndexCount; const uint32_t* pQueueFamilyIndices;
    VkImageLayout initialLayout;
} VkImageCreateInfo;

typedef struct VkComponentMapping { int32_t r, g, b, a; } VkComponentMapping;

typedef struct VkImageViewCreateInfo
{
    VkStructureType sType; const void* pNext; VkFlags flags;
    VkImage image; VkImageViewType viewType; VkFormat format;
    VkComponentMapping components; VkImageSubresourceRange subresourceRange;
} VkImageViewCreateInfo;

typedef struct VkFramebufferCreateInfo
{
    VkStructureType sType; const void* pNext; VkFlags flags;
    VkRenderPass renderPass; uint32_t attachmentCount; const VkImageView* pAttachments;
    uint32_t width, height, layers;
} VkFramebufferCreateInfo;

typedef struct VkAttachmentDescription
{
    VkFlags flags; VkFormat format; int32_t samples;
    VkAttachmentLoadOp loadOp; VkAttachmentStoreOp storeOp;
    VkAttachmentLoadOp stencilLoadOp; VkAttachmentStoreOp stencilStoreOp;
    VkImageLayout initialLayout, finalLayout;
} VkAttachmentDescription;

typedef struct VkAttachmentReference { uint32_t attachment; VkImageLayout layout; } VkAttachmentReference;

typedef struct VkSubpassDescription
{
    VkFlags flags; VkPipelineBindPoint pipelineBindPoint;
    uint32_t inputAttachmentCount; const VkAttachmentReference* pInputAttachments;
    uint32_t colorAttachmentCount; const VkAttachmentReference* pColorAttachments;
    const VkAttachmentReference* pResolveAttachments;
    const VkAttachmentReference* pDepthStencilAttachment;
    uint32_t preserveAttachmentCount; const uint32_t* pPreserveAttachments;
} VkSubpassDescription;

typedef struct VkRenderPassCreateInfo
{
    VkStructureType sType; const void* pNext; VkFlags flags;
    uint32_t attachmentCount; const VkAttachmentDescription* pAttachments;
    uint32_t subpassCount; const VkSubpassDescription* pSubpasses;
    uint32_t dependencyCount; const void* pDependencies;
} VkRenderPassCreateInfo;

typedef struct VkShaderModuleCreateInfo
{
    VkStructureType sType; const void* pNext; VkFlags flags;
    size_t codeSize; const uint32_t* pCode;
} VkShaderModuleCreateInfo;

typedef struct VkSpecializationInfo
{
    uint32_t mapEntryCount; const void* pMapEntries;
    size_t dataSize; const void* pData;
} VkSpecializationInfo;

typedef struct VkPipelineShaderStageCreateInfo
{
    VkStructureType sType; const void* pNext; VkFlags flags;
    VkShaderStageFlagBits stage; VkShaderModule module;
    const char* pName; const VkSpecializationInfo* pSpecializationInfo;
} VkPipelineShaderStageCreateInfo;

typedef struct VkVertexInputBindingDescription
{
    uint32_t binding, stride; VkVertexInputRate inputRate;
} VkVertexInputBindingDescription;

typedef struct VkVertexInputAttributeDescription
{
    uint32_t location, binding; VkFormat format; uint32_t offset;
} VkVertexInputAttributeDescription;

typedef struct VkPipelineVertexInputStateCreateInfo
{
    VkStructureType sType; const void* pNext; VkFlags flags;
    uint32_t vertexBindingDescriptionCount; const VkVertexInputBindingDescription* pVertexBindingDescriptions;
    uint32_t vertexAttributeDescriptionCount; const VkVertexInputAttributeDescription* pVertexAttributeDescriptions;
} VkPipelineVertexInputStateCreateInfo;

typedef struct VkPipelineInputAssemblyStateCreateInfo
{
    VkStructureType sType; const void* pNext; VkFlags flags;
    VkPrimitiveTopology topology; VkBool32 primitiveRestartEnable;
} VkPipelineInputAssemblyStateCreateInfo;

typedef struct VkPipelineViewportStateCreateInfo
{
    VkStructureType sType; const void* pNext; VkFlags flags;
    uint32_t viewportCount; const VkViewport* pViewports;
    uint32_t scissorCount; const VkRect2D* pScissors;
} VkPipelineViewportStateCreateInfo;

typedef struct VkPipelineRasterizationStateCreateInfo
{
    VkStructureType sType; const void* pNext; VkFlags flags;
    VkBool32 depthClampEnable, rasterizerDiscardEnable;
    VkPolygonMode polygonMode; VkCullModeFlags cullMode; VkFrontFace frontFace;
    VkBool32 depthBiasEnable;
    float depthBiasConstantFactor, depthBiasClamp, depthBiasSlopeFactor, lineWidth;
} VkPipelineRasterizationStateCreateInfo;

typedef struct VkPipelineMultisampleStateCreateInfo
{
    VkStructureType sType; const void* pNext; VkFlags flags;
    int32_t rasterizationSamples; VkBool32 sampleShadingEnable; float minSampleShading;
    const uint32_t* pSampleMask; VkBool32 alphaToCoverageEnable, alphaToOneEnable;
} VkPipelineMultisampleStateCreateInfo;

typedef struct VkStencilOpState
{
    int32_t failOp, passOp, depthFailOp, compareOp;
    uint32_t compareMask, writeMask, reference;
} VkStencilOpState;

typedef struct VkPipelineDepthStencilStateCreateInfo
{
    VkStructureType sType; const void* pNext; VkFlags flags;
    VkBool32 depthTestEnable, depthWriteEnable; VkCompareOp depthCompareOp;
    VkBool32 depthBoundsTestEnable, stencilTestEnable;
    VkStencilOpState front, back;
    float minDepthBounds, maxDepthBounds;
} VkPipelineDepthStencilStateCreateInfo;

typedef struct VkPipelineColorBlendAttachmentState
{
    VkBool32 blendEnable;
    VkBlendFactor srcColorBlendFactor, dstColorBlendFactor; VkBlendOp colorBlendOp;
    VkBlendFactor srcAlphaBlendFactor, dstAlphaBlendFactor; VkBlendOp alphaBlendOp;
    VkFlags colorWriteMask;
} VkPipelineColorBlendAttachmentState;

typedef struct VkPipelineColorBlendStateCreateInfo
{
    VkStructureType sType; const void* pNext; VkFlags flags;
    VkBool32 logicOpEnable; int32_t logicOp;
    uint32_t attachmentCount; const VkPipelineColorBlendAttachmentState* pAttachments;
    float blendConstants[4];
} VkPipelineColorBlendStateCreateInfo;

typedef struct VkPipelineDynamicStateCreateInfo
{
    VkStructureType sType; const void* pNext; VkFlags flags;
    uint32_t dynamicStateCount; const VkDynamicState* pDynamicStates;
} VkPipelineDynamicStateCreateInfo;

typedef struct VkGraphicsPipelineCreateInfo
{
    VkStructureType sType; const void* pNext; VkFlags flags;
    uint32_t stageCount; const VkPipelineShaderStageCreateInfo* pStages;
    const VkPipelineVertexInputStateCreateInfo* pVertexInputState;
    const VkPipelineInputAssemblyStateCreateInfo* pInputAssemblyState;
    const void* pTessellationState;
    const VkPipelineViewportStateCreateInfo* pViewportState;
    const VkPipelineRasterizationStateCreateInfo* pRasterizationState;
    const VkPipelineMultisampleStateCreateInfo* pMultisampleState;
    const VkPipelineDepthStencilStateCreateInfo* pDepthStencilState;
    const VkPipelineColorBlendStateCreateInfo* pColorBlendState;
    const VkPipelineDynamicStateCreateInfo* pDynamicState;
    VkPipelineLayout layout; VkRenderPass renderPass; uint32_t subpass;
    VkPipeline basePipelineHandle; int32_t basePipelineIndex;
} VkGraphicsPipelineCreateInfo;

typedef struct VkPushConstantRange
{
    VkShaderStageFlagBits stageFlags; uint32_t offset, size;
} VkPushConstantRange;

typedef struct VkPipelineLayoutCreateInfo
{
    VkStructureType sType; const void* pNext; VkFlags flags;
    uint32_t setLayoutCount; const VkDescriptorSetLayout* pSetLayouts;
    uint32_t pushConstantRangeCount; const VkPushConstantRange* pPushConstantRanges;
} VkPipelineLayoutCreateInfo;

typedef struct VkSamplerCreateInfo
{
    VkStructureType sType; const void* pNext; VkFlags flags;
    VkFilter magFilter, minFilter; VkSamplerMipmapMode mipmapMode;
    VkSamplerAddressMode addressModeU, addressModeV, addressModeW;
    float mipLodBias; VkBool32 anisotropyEnable; float maxAnisotropy;
    VkBool32 compareEnable; VkCompareOp compareOp;
    float minLod, maxLod; int32_t borderColor;
    VkBool32 unnormalizedCoordinates;
} VkSamplerCreateInfo;

typedef struct VkDescriptorSetLayoutBinding
{
    uint32_t binding; VkDescriptorType descriptorType; uint32_t descriptorCount;
    VkShaderStageFlagBits stageFlags; const VkSampler* pImmutableSamplers;
} VkDescriptorSetLayoutBinding;

typedef struct VkDescriptorSetLayoutCreateInfo
{
    VkStructureType sType; const void* pNext; VkFlags flags;
    uint32_t bindingCount; const VkDescriptorSetLayoutBinding* pBindings;
} VkDescriptorSetLayoutCreateInfo;

typedef struct VkDescriptorPoolSize
{
    VkDescriptorType type; uint32_t descriptorCount;
} VkDescriptorPoolSize;

typedef struct VkDescriptorPoolCreateInfo
{
    VkStructureType sType; const void* pNext; VkFlags flags;
    uint32_t maxSets; uint32_t poolSizeCount; const VkDescriptorPoolSize* pPoolSizes;
} VkDescriptorPoolCreateInfo;

typedef struct VkDescriptorSetAllocateInfo
{
    VkStructureType sType; const void* pNext;
    VkDescriptorPool descriptorPool;
    uint32_t descriptorSetCount; const VkDescriptorSetLayout* pSetLayouts;
} VkDescriptorSetAllocateInfo;

typedef struct VkDescriptorBufferInfo
{
    VkBuffer buffer; VkDeviceSize offset, range;
} VkDescriptorBufferInfo;

typedef struct VkDescriptorImageInfo
{
    VkSampler sampler; VkImageView imageView; VkImageLayout imageLayout;
} VkDescriptorImageInfo;

typedef struct VkWriteDescriptorSet
{
    VkStructureType sType; const void* pNext;
    VkDescriptorSet dstSet; uint32_t dstBinding, dstArrayElement, descriptorCount;
    VkDescriptorType descriptorType;
    const VkDescriptorImageInfo* pImageInfo;
    const VkDescriptorBufferInfo* pBufferInfo;
    const void* pTexelBufferView;
} VkWriteDescriptorSet;

/* ===================================================================== */
/* 函数指针（运行期 vkGetInstanceProcAddr 解析）                            */
/* ===================================================================== */
typedef void* (WINAPI *PFN_vkGetInstanceProcAddr)(VkInstance, const char*);

typedef VkResult (WINAPI *PFN_vkCreateInstance)(const VkInstanceCreateInfo*, const void*, VkInstance*);
typedef VkResult (WINAPI *PFN_vkEnumeratePhysicalDevices)(VkInstance, uint32_t*, VkPhysicalDevice*);
typedef void     (WINAPI *PFN_vkGetPhysicalDeviceProperties)(VkPhysicalDevice, VkPhysicalDeviceProperties*);
typedef void     (WINAPI *PFN_vkGetPhysicalDeviceQueueFamilyProperties)(VkPhysicalDevice, uint32_t*, VkQueueFamilyProperties*);
typedef void     (WINAPI *PFN_vkGetPhysicalDeviceMemoryProperties)(VkPhysicalDevice, VkPhysicalDeviceMemoryProperties*);
typedef void     (WINAPI *PFN_vkGetPhysicalDeviceFormatProperties)(VkPhysicalDevice, VkFormat, VkFormatProperties*);
typedef VkResult (WINAPI *PFN_vkCreateDevice)(VkPhysicalDevice, const VkDeviceCreateInfo*, const void*, VkDevice*);
typedef void     (WINAPI *PFN_vkDestroyInstance)(VkInstance, const void*);
typedef void     (WINAPI *PFN_vkDestroyDevice)(VkDevice, const void*);
typedef void     (WINAPI *PFN_vkGetDeviceQueue)(VkDevice, uint32_t, uint32_t, VkQueue*);
typedef VkResult (WINAPI *PFN_vkCreateCommandPool)(VkDevice, const VkCommandPoolCreateInfo*, const void*, VkCommandPool*);
typedef void     (WINAPI *PFN_vkDestroyCommandPool)(VkDevice, VkCommandPool, const void*);
typedef VkResult (WINAPI *PFN_vkAllocateCommandBuffers)(VkDevice, const VkCommandBufferAllocateInfo*, VkCommandBuffer*);
typedef VkResult (WINAPI *PFN_vkResetCommandBuffer)(VkCommandBuffer, VkFlags);
typedef VkResult (WINAPI *PFN_vkBeginCommandBuffer)(VkCommandBuffer, const VkCommandBufferBeginInfo*);
typedef VkResult (WINAPI *PFN_vkEndCommandBuffer)(VkCommandBuffer);
typedef VkResult (WINAPI *PFN_vkQueueSubmit)(VkQueue, uint32_t, const VkSubmitInfo*, VkFence);
typedef VkResult (WINAPI *PFN_vkQueueWaitIdle)(VkQueue);
typedef VkResult (WINAPI *PFN_vkDeviceWaitIdle)(VkDevice);
typedef VkResult (WINAPI *PFN_vkCreateBuffer)(VkDevice, const VkBufferCreateInfo*, const void*, VkBuffer*);
typedef void     (WINAPI *PFN_vkDestroyBuffer)(VkDevice, VkBuffer, const void*);
typedef VkResult (WINAPI *PFN_vkCreateImage)(VkDevice, const VkImageCreateInfo*, const void*, VkImage*);
typedef void     (WINAPI *PFN_vkDestroyImage)(VkDevice, VkImage, const void*);
typedef VkResult (WINAPI *PFN_vkAllocateMemory)(VkDevice, const VkMemoryAllocateInfo*, const void*, VkDeviceMemory*);
typedef void     (WINAPI *PFN_vkFreeMemory)(VkDevice, VkDeviceMemory, const void*);
typedef VkResult (WINAPI *PFN_vkMapMemory)(VkDevice, VkDeviceMemory, VkDeviceSize, VkDeviceSize, VkFlags, void**);
typedef void     (WINAPI *PFN_vkUnmapMemory)(VkDevice, VkDeviceMemory);
typedef VkResult (WINAPI *PFN_vkFlushMappedMemoryRanges)(VkDevice, uint32_t, const VkMappedMemoryRange*);
typedef VkResult (WINAPI *PFN_vkBindBufferMemory)(VkDevice, VkBuffer, VkDeviceMemory, VkDeviceSize);
typedef VkResult (WINAPI *PFN_vkBindImageMemory)(VkDevice, VkImage, VkDeviceMemory, VkDeviceSize);
typedef void     (WINAPI *PFN_vkGetBufferMemoryRequirements)(VkDevice, VkBuffer, VkMemoryRequirements*);
typedef void     (WINAPI *PFN_vkGetImageMemoryRequirements)(VkDevice, VkImage, VkMemoryRequirements*);
typedef VkResult (WINAPI *PFN_vkCreateImageView)(VkDevice, const VkImageViewCreateInfo*, const void*, VkImageView*);
typedef void     (WINAPI *PFN_vkDestroyImageView)(VkDevice, VkImageView, const void*);
typedef VkResult (WINAPI *PFN_vkCreateRenderPass)(VkDevice, const VkRenderPassCreateInfo*, const void*, VkRenderPass*);
typedef void     (WINAPI *PFN_vkDestroyRenderPass)(VkDevice, VkRenderPass, const void*);
typedef VkResult (WINAPI *PFN_vkCreateFramebuffer)(VkDevice, const VkFramebufferCreateInfo*, const void*, VkFramebuffer*);
typedef void     (WINAPI *PFN_vkDestroyFramebuffer)(VkDevice, VkFramebuffer, const void*);
typedef VkResult (WINAPI *PFN_vkCreateShaderModule)(VkDevice, const VkShaderModuleCreateInfo*, const void*, VkShaderModule*);
typedef void     (WINAPI *PFN_vkDestroyShaderModule)(VkDevice, VkShaderModule, const void*);
typedef VkResult (WINAPI *PFN_vkCreateDescriptorSetLayout)(VkDevice, const VkDescriptorSetLayoutCreateInfo*, const void*, VkDescriptorSetLayout*);
typedef void     (WINAPI *PFN_vkDestroyDescriptorSetLayout)(VkDevice, VkDescriptorSetLayout, const void*);
typedef VkResult (WINAPI *PFN_vkCreatePipelineLayout)(VkDevice, const VkPipelineLayoutCreateInfo*, const void*, VkPipelineLayout*);
typedef void     (WINAPI *PFN_vkDestroyPipelineLayout)(VkDevice, VkPipelineLayout, const void*);
typedef VkResult (WINAPI *PFN_vkCreateGraphicsPipelines)(VkDevice, VkPipelineCache, uint32_t, const VkGraphicsPipelineCreateInfo*, const void*, VkPipeline*);
typedef void     (WINAPI *PFN_vkDestroyPipeline)(VkDevice, VkPipeline, const void*);
typedef VkResult (WINAPI *PFN_vkCreateSampler)(VkDevice, const VkSamplerCreateInfo*, const void*, VkSampler*);
typedef void     (WINAPI *PFN_vkDestroySampler)(VkDevice, VkSampler, const void*);
typedef VkResult (WINAPI *PFN_vkCreateDescriptorPool)(VkDevice, const VkDescriptorPoolCreateInfo*, const void*, VkDescriptorPool*);
typedef void     (WINAPI *PFN_vkDestroyDescriptorPool)(VkDevice, VkDescriptorPool, const void*);
typedef VkResult (WINAPI *PFN_vkAllocateDescriptorSets)(VkDevice, const VkDescriptorSetAllocateInfo*, VkDescriptorSet*);
typedef void     (WINAPI *PFN_vkFreeDescriptorSets)(VkDevice, VkDescriptorPool, uint32_t, const VkDescriptorSet*);
typedef void     (WINAPI *PFN_vkUpdateDescriptorSets)(VkDevice, uint32_t, const VkWriteDescriptorSet*, uint32_t, const void*);
typedef void     (WINAPI *PFN_vkCmdBeginRenderPass)(VkCommandBuffer, const VkRenderPassBeginInfo*, VkSubpassContents);
typedef void     (WINAPI *PFN_vkCmdEndRenderPass)(VkCommandBuffer);
typedef void     (WINAPI *PFN_vkCmdSetViewport)(VkCommandBuffer, uint32_t, uint32_t, const VkViewport*);
typedef void     (WINAPI *PFN_vkCmdSetScissor)(VkCommandBuffer, uint32_t, uint32_t, const VkRect2D*);
typedef void     (WINAPI *PFN_vkCmdBindPipeline)(VkCommandBuffer, VkPipelineBindPoint, VkPipeline);
typedef void     (WINAPI *PFN_vkCmdPushConstants)(VkCommandBuffer, VkPipelineLayout, VkShaderStageFlagBits, uint32_t, uint32_t, const void*);
typedef void     (WINAPI *PFN_vkCmdBindDescriptorSets)(VkCommandBuffer, VkPipelineBindPoint, VkPipelineLayout, uint32_t, uint32_t, const VkDescriptorSet*, uint32_t, const uint32_t*);
typedef void     (WINAPI *PFN_vkCmdBindVertexBuffers)(VkCommandBuffer, uint32_t, uint32_t, const VkBuffer*, const VkDeviceSize*);
typedef void     (WINAPI *PFN_vkCmdDraw)(VkCommandBuffer, uint32_t, uint32_t, uint32_t, uint32_t);
typedef void     (WINAPI *PFN_vkCmdClearAttachments)(VkCommandBuffer, uint32_t, const VkClearAttachment*, uint32_t, const VkClearRect*);
typedef void     (WINAPI *PFN_vkCmdPipelineBarrier)(VkCommandBuffer, VkFlags, VkFlags, VkFlags, uint32_t, const void*, uint32_t, const void*, uint32_t, const VkImageMemoryBarrier*);
typedef void     (WINAPI *PFN_vkCmdCopyBuffer)(VkCommandBuffer, VkBuffer, VkBuffer, uint32_t, const VkBufferCopy*);
typedef void     (WINAPI *PFN_vkCmdCopyBufferToImage)(VkCommandBuffer, VkBuffer, VkImage, VkImageLayout, uint32_t, const VkBufferImageCopy*);
typedef void     (WINAPI *PFN_vkCmdCopyImageToBuffer)(VkCommandBuffer, VkImage, VkImageLayout, VkBuffer, uint32_t, const VkBufferImageCopy*);

#define VKPROC_LIST(X)                                                     \
    X(vkCreateInstance)              X(vkEnumeratePhysicalDevices)         \
    X(vkGetPhysicalDeviceProperties) X(vkGetPhysicalDeviceQueueFamilyProperties) \
    X(vkGetPhysicalDeviceMemoryProperties) X(vkGetPhysicalDeviceFormatProperties) \
    X(vkCreateDevice)               X(vkDestroyInstance)                  \
    X(vkDestroyDevice)              X(vkGetDeviceQueue)                    \
    X(vkCreateCommandPool)          X(vkDestroyCommandPool)               \
    X(vkAllocateCommandBuffers)     X(vkResetCommandBuffer)               \
    X(vkBeginCommandBuffer)         X(vkEndCommandBuffer)                  \
    X(vkQueueSubmit)                X(vkQueueWaitIdle)  X(vkDeviceWaitIdle) \
    X(vkCreateBuffer)               X(vkDestroyBuffer)                     \
    X(vkCreateImage)                X(vkDestroyImage)                      \
    X(vkAllocateMemory)             X(vkFreeMemory)                         \
    X(vkMapMemory)                  X(vkUnmapMemory)                       \
    X(vkFlushMappedMemoryRanges)    X(vkBindBufferMemory)                  \
    X(vkBindImageMemory)            X(vkGetBufferMemoryRequirements)       \
    X(vkGetImageMemoryRequirements) X(vkCreateImageView) X(vkDestroyImageView) \
    X(vkCreateRenderPass)           X(vkDestroyRenderPass)                  \
    X(vkCreateFramebuffer)          X(vkDestroyFramebuffer)                \
    X(vkCreateShaderModule)         X(vkDestroyShaderModule)                \
    X(vkCreateDescriptorSetLayout)  X(vkDestroyDescriptorSetLayout)        \
    X(vkCreatePipelineLayout)       X(vkDestroyPipelineLayout)              \
    X(vkCreateGraphicsPipelines)    X(vkDestroyPipeline)                    \
    X(vkCreateSampler)              X(vkDestroySampler)                     \
    X(vkCreateDescriptorPool)       X(vkDestroyDescriptorPool)              \
    X(vkAllocateDescriptorSets)     X(vkFreeDescriptorSets)                 \
    X(vkUpdateDescriptorSets)                                              \
    X(vkCmdBeginRenderPass)         X(vkCmdEndRenderPass)                  \
    X(vkCmdSetViewport)             X(vkCmdSetScissor)                     \
    X(vkCmdBindPipeline)            X(vkCmdPushConstants)                  \
    X(vkCmdBindDescriptorSets)      X(vkCmdBindVertexBuffers)              \
    X(vkCmdDraw)                    X(vkCmdClearAttachments)                \
    X(vkCmdPipelineBarrier)         X(vkCmdCopyBuffer)                      \
    X(vkCmdCopyBufferToImage)       X(vkCmdCopyImageToBuffer)

#define VKPROC_DECL(name) static PFN_##name p_##name = NULL;
VKPROC_LIST(VKPROC_DECL)
#undef VKPROC_DECL

static HMODULE s_hvk = NULL;
static PFN_vkGetInstanceProcAddr pfnEntry = NULL;

/* ===================================================================== */
/* 后端私有状态                                                           */
/* ===================================================================== */
struct SlrRhiTarget
{
    int w, h, has_depth;
    VkImage color;      VkDeviceMemory color_mem;  VkImageView color_view;
    VkImage depth;      VkDeviceMemory depth_mem;  VkImageView depth_view;
    VkFramebuffer fb;                     /* rp_depth / rp_color 匹配      */
    VkDescriptorSet set_sampler;         /* post/blit 采样本目标颜色      */
    uint32_t layout;                      /* 颜色附件当前布局（跟踪）      */
};

typedef struct
{
    VkImage img; VkDeviceMemory mem; VkImageView view;
    VkDescriptorSet set_sampler;          /* DSL_SAMPLER（v1 TEX/blit/post）*/
    VkDescriptorSet set_pipe_tex;         /* DSL_PIPE_TEX（PTEX）           */
} VkTexture;

static VkInstance       s_inst = NULL;
static VkPhysicalDevice s_phys = NULL;
static VkDevice         s_dev = NULL;
static VkQueue          s_queue = NULL;
static uint32_t         s_qfamily = 0;
static VkCommandPool    s_pool = NULL;
static VkCommandBuffer  s_cmd = NULL;
static VkPhysicalDeviceMemoryProperties s_memprops;
static VkFormat         s_depth_fmt = (VkFormat)VK_FORMAT_D24_UNORM_S8_UINT;
static int             s_depth_stencil = 1;
static char            s_devname[128] = "unknown";
static uint32_t         s_api_version = 0;

/* 共享资源 */
static VkRenderPass        s_rp_depth = NULL;   /* 颜色+深度，CLEAR 载入       */
static VkRenderPass        s_rp_depth_nc = NULL;/* 颜色+深度，LOAD 载入（续画） */
static VkRenderPass        s_rp_color = NULL;   /* 仅颜色，DONT_CARE（全屏覆写）*/
static VkSampler           s_sampler = NULL;
static VkDescriptorPool    s_descpool = NULL;
static VkDescriptorSetLayout s_dsl_pipe_flat = NULL;  /* b0 PerDraw UBO        */
static VkDescriptorSetLayout s_dsl_pipe_tex = NULL;   /* b0 UBO + b1 sampler   */
static VkDescriptorSetLayout s_dsl_sampler = NULL;    /* b0 sampler            */
static VkDescriptorSet     s_set_perdraw = NULL;
static VkBuffer            s_ubo_draw = NULL;
static VkDeviceMemory      s_ubo_draw_mem = NULL;
static void*               s_ubo_draw_ptr = NULL;
static int                s_ubo_coherent = 1;
static VkShaderModule      s_shaders[9];
static VkPipelineLayout    s_pl_layouts[8];
static VkPipeline          s_vk_pipes[8];
static VkBuffer            s_vb[4];
static VkDeviceMemory      s_vb_mem[4];
/* 动态网格（mesh id = 4+slot）：HOST_VISIBLE 持久映射顶点缓冲，
 * mesh_upload 直接 memcpy（免中转 copy / 免队列提交，帧间安全）*/
static VkBuffer            s_vb_custom[SLR_CUSTOM_MESHES];
static VkDeviceMemory      s_vb_custom_mem[SLR_CUSTOM_MESHES];
static void*               s_vb_custom_ptr[SLR_CUSTOM_MESHES];
static VkDeviceSize        s_vb_custom_cap[SLR_CUSTOM_MESHES];
static uint32_t            s_vb_custom_count[SLR_CUSTOM_MESHES];
static int                 s_vb_custom_coh[SLR_CUSTOM_MESHES];
static VkBuffer            s_upload_buf = NULL;   /* 纹理上传中转（按需增长） */
static VkDeviceMemory      s_upload_mem = NULL;
static void*               s_upload_ptr = NULL;
static VkDeviceSize        s_upload_size = 0;
static int                 s_upload_coherent = 1;
static VkBuffer            s_rdbuf = NULL;        /* 回读中转（按需重建）     */
static VkDeviceMemory      s_rd_mem = NULL;
static void*               s_rd_ptr = NULL;
static VkDeviceSize        s_rd_size = 0;

/* 管线槽位（含不透明/透明变体）*/
enum
{
    VKP_PFLAT_O = 0, VKP_PFLAT_T, VKP_PTEX_O, VKP_PTEX_T,
    VKP_V1_FLAT, VKP_V1_TEX, VKP_BLIT, VKP_POST, VKP_COUNT
};

/* 记录状态（即时风格分段提交）*/
static int              s_recording = 0;
static int              s_pass_open = 0;
static SlrRhiTarget* s_pass_t = NULL;
static int              s_trans = 0;

/* 描述符槽表（VkTexture 的 PTEX set；管线层帧级写槽/选当前绑定）*/
static VkDescriptorSet s_desc_set[SLR_DESC_TEX_SLOTS];
static VkDescriptorSet s_cur_tex_set = NULL;

static CRITICAL_SECTION s_lock;
static int              s_lock_init = 0;

/* ===================================================================== */
/* 小工具                                                                 */
/* ===================================================================== */
static int vk_check(VkResult r, const char* what)
{
    if (r == VK_SUCCESS) return 1;
    {
        char msg[160];
        _snprintf(msg, sizeof(msg) - 1, "%s failed (VkResult=%d)", what, (int)r);
        msg[sizeof(msg) - 1] = 0;
        set_error_detail(SLR_E_BACKEND, msg);
    }
    return 0;
}

static uint32_t vk_find_memory(uint32_t type_bits, uint32_t props)
{
    uint32_t i;
    for (i = 0; i < s_memprops.memoryTypeCount; i++)
    {
        if ((type_bits & (1u << i)) &&
            (s_memprops.memoryTypes[i].propertyFlags & props) == props)
            return i;
    }
    return 0xFFFFFFFFu;
}

static void vk_flush_mem(VkDeviceMemory mem, VkDeviceSize off, VkDeviceSize size, int coherent)
{
    VkMappedMemoryRange r;
    if (coherent) return;
    r.sType = VK_STRUCTURE_TYPE_MAPPED_MEMORY_RANGE;
    r.pNext = NULL;
    r.memory = mem;
    r.offset = off;
    r.size = size;
    p_vkFlushMappedMemoryRanges(s_dev, 1, &r);
}

/* 建缓冲：props 含 HOST_VISIBLE 时输出持久映射指针 */
static int vk_make_buffer(VkBuffer* buf, VkDeviceMemory* mem, VkDeviceSize size,
                         uint32_t usage, uint32_t props, void** mapped, int* coherent)
{
    VkBufferCreateInfo bi;
    VkMemoryRequirements req;
    VkMemoryAllocateInfo ai;
    uint32_t type;
    memset(&bi, 0, sizeof(bi));
    bi.sType = VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO;
    bi.size = size;
    bi.usage = usage;
    bi.sharingMode = (VkSharingMode)VK_SHARING_MODE_EXCLUSIVE;
    if (!vk_check(p_vkCreateBuffer(s_dev, &bi, NULL, buf), "vkCreateBuffer")) return 0;
    p_vkGetBufferMemoryRequirements(s_dev, *buf, &req);
    type = vk_find_memory(req.memoryTypeBits, props);
    if (type == 0xFFFFFFFFu)
    {
        p_vkDestroyBuffer(s_dev, *buf, NULL); *buf = NULL;
        set_error_detail(SLR_E_MEMORY, "no compatible memory type for buffer");
        return 0;
    }
    memset(&ai, 0, sizeof(ai));
    ai.sType = VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO;
    ai.allocationSize = req.size;
    ai.memoryTypeIndex = type;
    if (!vk_check(p_vkAllocateMemory(s_dev, &ai, NULL, mem), "vkAllocateMemory(buffer)"))
    {
        p_vkDestroyBuffer(s_dev, *buf, NULL); *buf = NULL;
        return 0;
    }
    if (!vk_check(p_vkBindBufferMemory(s_dev, *buf, *mem, 0), "vkBindBufferMemory"))
    {
        p_vkFreeMemory(s_dev, *mem, NULL); *mem = NULL;
        p_vkDestroyBuffer(s_dev, *buf, NULL); *buf = NULL;
        return 0;
    }
    if (props & VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT)
    {
        void* ptr = NULL;
        if (!vk_check(p_vkMapMemory(s_dev, *mem, 0, size, 0, &ptr), "vkMapMemory"))
        {
            p_vkFreeMemory(s_dev, *mem, NULL); *mem = NULL;
            p_vkDestroyBuffer(s_dev, *buf, NULL); *buf = NULL;
            return 0;
        }
        if (mapped) *mapped = ptr;
        if (coherent)
            *coherent = (s_memprops.memoryTypes[type].propertyFlags &
                         VK_MEMORY_PROPERTY_HOST_COHERENT_BIT) ? 1 : 0;
    }
    return 1;
}

/* 建图像（2D RGBA8 / 深度），设备本地内存 */
static int vk_make_image(VkImage* img, VkDeviceMemory* mem, VkImageView* view,
                         uint32_t w, uint32_t h, VkFormat fmt, uint32_t usage, int is_depth)
{
    VkImageCreateInfo ii;
    VkMemoryRequirements req;
    VkMemoryAllocateInfo ai;
    VkImageViewCreateInfo vi;
    uint32_t type;
    uint32_t aspect = is_depth
        ? (uint32_t)(VK_IMAGE_ASPECT_DEPTH_BIT | (s_depth_stencil ? VK_IMAGE_ASPECT_STENCIL_BIT : 0))
        : (uint32_t)VK_IMAGE_ASPECT_COLOR_BIT;

    memset(&ii, 0, sizeof(ii));
    ii.sType = VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO;
    ii.imageType = 0; /* VK_IMAGE_TYPE_2D */
    ii.format = fmt;
    ii.extent.width = w; ii.extent.height = h; ii.extent.depth = 1;
    ii.mipLevels = 1; ii.arrayLayers = 1;
    ii.samples = 1; /* VK_SAMPLE_COUNT_1_BIT */
    ii.tiling = (VkImageTiling)VK_IMAGE_TILING_OPTIMAL;
    ii.usage = usage;
    ii.sharingMode = (VkSharingMode)VK_SHARING_MODE_EXCLUSIVE;
    ii.initialLayout = (VkImageLayout)VK_IMAGE_LAYOUT_UNDEFINED;
    if (!vk_check(p_vkCreateImage(s_dev, &ii, NULL, img), "vkCreateImage")) return 0;
    p_vkGetImageMemoryRequirements(s_dev, *img, &req);
    type = vk_find_memory(req.memoryTypeBits, VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT);
    if (type == 0xFFFFFFFFu)
        type = vk_find_memory(req.memoryTypeBits, 0);
    if (type == 0xFFFFFFFFu)
    {
        p_vkDestroyImage(s_dev, *img, NULL); *img = NULL;
        set_error_detail(SLR_E_MEMORY, "no compatible memory type for image");
        return 0;
    }
    memset(&ai, 0, sizeof(ai));
    ai.sType = VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO;
    ai.allocationSize = req.size;
    ai.memoryTypeIndex = type;
    if (!vk_check(p_vkAllocateMemory(s_dev, &ai, NULL, mem), "vkAllocateMemory(image)"))
    {
        p_vkDestroyImage(s_dev, *img, NULL); *img = NULL;
        return 0;
    }
    if (!vk_check(p_vkBindImageMemory(s_dev, *img, *mem, 0), "vkBindImageMemory"))
    {
        p_vkFreeMemory(s_dev, *mem, NULL); *mem = NULL;
        p_vkDestroyImage(s_dev, *img, NULL); *img = NULL;
        return 0;
    }
    memset(&vi, 0, sizeof(vi));
    vi.sType = VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO;
    vi.image = *img;
    vi.viewType = (VkImageViewType)VK_IMAGE_VIEW_TYPE_2D;
    vi.format = fmt;
    vi.subresourceRange.aspectMask = aspect;
    vi.subresourceRange.baseMipLevel = 0;
    vi.subresourceRange.levelCount = 1;
    vi.subresourceRange.baseArrayLayer = 0;
    vi.subresourceRange.layerCount = 1;
    if (!vk_check(p_vkCreateImageView(s_dev, &vi, NULL, view), "vkCreateImageView"))
    {
        p_vkFreeMemory(s_dev, *mem, NULL); *mem = NULL;
        p_vkDestroyImage(s_dev, *img, NULL); *img = NULL;
        return 0;
    }
    return 1;
}

static void vk_destroy_buffer(VkBuffer* buf, VkDeviceMemory* mem, void** mapped)
{
    if (*mapped) { p_vkUnmapMemory(s_dev, *mem); *mapped = NULL; }
    if (*mem)  { p_vkFreeMemory(s_dev, *mem, NULL); *mem = NULL; }
    if (*buf)  { p_vkDestroyBuffer(s_dev, *buf, NULL); *buf = NULL; }
}

static void vk_destroy_image(VkImage* img, VkDeviceMemory* mem, VkImageView* view)
{
    if (*view) { p_vkDestroyImageView(s_dev, *view, NULL); *view = NULL; }
    if (*mem)  { p_vkFreeMemory(s_dev, *mem, NULL); *mem = NULL; }
    if (*img)  { p_vkDestroyImage(s_dev, *img, NULL); *img = NULL; }
}

/* ---- 描述符集 ---- */
static int vk_alloc_sets(VkDescriptorSet* sets, uint32_t count, VkDescriptorSetLayout layout)
{
    VkDescriptorSetAllocateInfo ai;
    uint32_t i;
    memset(&ai, 0, sizeof(ai));
    ai.sType = VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO;
    ai.descriptorPool = s_descpool;
    ai.descriptorSetCount = count;
    ai.pSetLayouts = &layout;
    for (i = 0; i < count; i++) sets[i] = NULL;
    if (!vk_check(p_vkAllocateDescriptorSets(s_dev, &ai, sets), "vkAllocateDescriptorSets"))
        return 0;
    return 1;
}

static void vk_write_sampler_set(VkDescriptorSet set, VkImageView view)
{
    VkDescriptorImageInfo ii;
    VkWriteDescriptorSet w;
    memset(&ii, 0, sizeof(ii));
    ii.sampler = s_sampler;
    ii.imageView = view;
    ii.imageLayout = (VkImageLayout)VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL;
    memset(&w, 0, sizeof(w));
    w.sType = VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET;
    w.dstSet = set;
    w.dstBinding = 0;
    w.descriptorCount = 1;
    w.descriptorType = (VkDescriptorType)VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER;
    w.pImageInfo = &ii;
    p_vkUpdateDescriptorSets(s_dev, 1, &w, 0, NULL);
}

static void vk_write_perdraw_set(VkDescriptorSet set)
{
    VkDescriptorBufferInfo bi;
    VkWriteDescriptorSet w;
    memset(&bi, 0, sizeof(bi));
    bi.buffer = s_ubo_draw;
    bi.offset = 0;
    bi.range = sizeof(SlrPerDraw);
    memset(&w, 0, sizeof(w));
    w.sType = VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET;
    w.dstSet = set;
    w.dstBinding = 0;
    w.descriptorCount = 1;
    w.descriptorType = (VkDescriptorType)VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER;
    w.pBufferInfo = &bi;
    p_vkUpdateDescriptorSets(s_dev, 1, &w, 0, NULL);
}

/* PTEX 集合：b0 PerDraw UBO + b1 采样器 */
static void vk_write_pipe_tex_set(VkDescriptorSet set, VkImageView view)
{
    VkDescriptorBufferInfo bi;
    VkDescriptorImageInfo ii;
    VkWriteDescriptorSet w[2];
    memset(&bi, 0, sizeof(bi));
    bi.buffer = s_ubo_draw;
    bi.offset = 0;
    bi.range = sizeof(SlrPerDraw);
    memset(&ii, 0, sizeof(ii));
    ii.sampler = s_sampler;
    ii.imageView = view;
    ii.imageLayout = (VkImageLayout)VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL;
    memset(w, 0, sizeof(w));
    w[0].sType = VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET;
    w[0].dstSet = set; w[0].dstBinding = 0; w[0].descriptorCount = 1;
    w[0].descriptorType = (VkDescriptorType)VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER;
    w[0].pBufferInfo = &bi;
    w[1].sType = VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET;
    w[1].dstSet = set; w[1].dstBinding = 1; w[1].descriptorCount = 1;
    w[1].descriptorType = (VkDescriptorType)VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER;
    w[1].pImageInfo = &ii;
    p_vkUpdateDescriptorSets(s_dev, 2, w, 0, NULL);
}

/* ---- 命令段收尾 / 提交 ---- */
static int vk_ensure_recording(void)
{
    VkCommandBufferBeginInfo bi;
    if (s_recording) return 1;
    memset(&bi, 0, sizeof(bi));
    bi.sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO;
    if (!vk_check(p_vkBeginCommandBuffer(s_cmd, &bi), "vkBeginCommandBuffer")) return 0;
    s_recording = 1;
    return 1;
}

static void vk_flush_pending(void)
{
    if (!s_recording) return;
    if (s_pass_open)
    {
        p_vkCmdEndRenderPass(s_cmd);
        s_pass_open = 0;
        s_pass_t = NULL;
    }
    if (p_vkEndCommandBuffer(s_cmd) == VK_SUCCESS)
    {
        VkSubmitInfo si;
        memset(&si, 0, sizeof(si));
        si.sType = VK_STRUCTURE_TYPE_SUBMIT_INFO;
        si.commandBufferCount = 1;
        si.pCommandBuffers = &s_cmd;
        p_vkQueueSubmit(s_queue, 1, &si, (VkFence)NULL);
        p_vkQueueWaitIdle(s_queue);
    }
    p_vkResetCommandBuffer(s_cmd, 0);
    s_recording = 0;
}

/* 独立小段：录制 -> 提交 -> 等待（texture_create / readback 用）*/
static int vk_submit_now(void)
{
    VkSubmitInfo si;
    if (s_pass_open) return 0;
    if (!vk_check(p_vkEndCommandBuffer(s_cmd), "vkEndCommandBuffer")) return 0;
    memset(&si, 0, sizeof(si));
    si.sType = VK_STRUCTURE_TYPE_SUBMIT_INFO;
    si.commandBufferCount = 1;
    si.pCommandBuffers = &s_cmd;
    if (!vk_check(p_vkQueueSubmit(s_queue, 1, &si, (VkFence)NULL), "vkQueueSubmit")) return 0;
    if (!vk_check(p_vkQueueWaitIdle(s_queue), "vkQueueWaitIdle")) return 0;
    p_vkResetCommandBuffer(s_cmd, 0);
    s_recording = 0;
    return 1;
}

/* ---- 布局转换屏障 ---- */
static void vk_barrier_image(VkImage img, uint32_t old_layout, uint32_t new_layout,
                            uint32_t src_stage, uint32_t src_access,
                            uint32_t dst_stage, uint32_t dst_access)
{
    VkImageMemoryBarrier b;
    memset(&b, 0, sizeof(b));
    b.sType = VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER;
    b.srcAccessMask = src_access;
    b.dstAccessMask = dst_access;
    b.oldLayout = (VkImageLayout)old_layout;
    b.newLayout = (VkImageLayout)new_layout;
    b.srcQueueFamilyIndex = 0xFFFFFFFFu;
    b.dstQueueFamilyIndex = 0xFFFFFFFFu;
    b.image = img;
    b.subresourceRange.aspectMask = VK_IMAGE_ASPECT_COLOR_BIT;
    b.subresourceRange.levelCount = 1;
    b.subresourceRange.layerCount = 1;
    p_vkCmdPipelineBarrier(s_cmd, src_stage, dst_stage, 0, 0, NULL, 0, NULL, 1, &b);
}

/* 渲染目标颜色布局转换 + 记账 */
static void vk_transition_target(SlrRhiTarget* t, uint32_t new_layout)
{
    if (t->layout == new_layout) return;
    if (t->layout == VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL ||
        t->layout == VK_IMAGE_LAYOUT_UNDEFINED)
        vk_barrier_image(t->color, t->layout, new_layout,
                         VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT,
                         VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT,
                         new_layout == VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL
                             ? VK_PIPELINE_STAGE_TRANSFER_BIT
                             : VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT,
                         new_layout == VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL
                             ? VK_ACCESS_TRANSFER_READ_BIT
                             : VK_ACCESS_SHADER_READ_BIT);
    else
        vk_barrier_image(t->color, t->layout, new_layout,
                         VK_PIPELINE_STAGE_TRANSFER_BIT, VK_ACCESS_TRANSFER_READ_BIT,
                         new_layout == VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL
                             ? VK_PIPELINE_STAGE_TRANSFER_BIT
                             : VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT,
                         new_layout == VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL
                             ? VK_ACCESS_TRANSFER_READ_BIT
                             : VK_ACCESS_SHADER_READ_BIT);
    t->layout = new_layout;
}

/* ---- pass 开启 ---- */
static void vk_full_vp_scissor(int w, int h)
{
    VkViewport vp;
    VkRect2D rc;
    memset(&vp, 0, sizeof(vp));
    vp.width = (float)w; vp.height = (float)h;
    vp.maxDepth = 1.0f;
    p_vkCmdSetViewport(s_cmd, 0, 1, &vp);
    memset(&rc, 0, sizeof(rc));
    rc.extent.width = (uint32_t)w;
    rc.extent.height = (uint32_t)h;
    p_vkCmdSetScissor(s_cmd, 0, 1, &rc);
}

/* clear != NULL：rp_depth 全幅清（颜色 + 深度 1.0）
 * clear == NULL：带深度目标走 rp_depth_nc（LOAD 续画，等价 GL 重绑 FBO），
 *                 无深度目标走 rp_color；回读态先转回 COLOR_ATTACHMENT。 */
static void vk_open_pass(SlrRhiTarget* t, int w, int h, const float* clear)
{
    VkRenderPassBeginInfo bi;
    VkClearValue cv[2];

    if (!clear && t->layout == VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL)
    {
        /* 续画前把回读态转回渲染目标态（rp_*_nc 的 initialLayout 约定）*/
        vk_barrier_image(t->color, VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL,
                         VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,
                         VK_PIPELINE_STAGE_TRANSFER_BIT, VK_ACCESS_TRANSFER_READ_BIT,
                         VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT,
                         VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT);
        t->layout = VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL;
    }

    memset(&bi, 0, sizeof(bi));
    bi.sType = VK_STRUCTURE_TYPE_RENDER_PASS_BEGIN_INFO;
    bi.framebuffer = t->fb;
    bi.renderArea.extent.width = (uint32_t)w;
    bi.renderArea.extent.height = (uint32_t)h;
    if (clear)
    {
        bi.renderPass = s_rp_depth;
        cv[0].color[0] = clear[0]; cv[0].color[1] = clear[1];
        cv[0].color[2] = clear[2]; cv[0].color[3] = clear[3];
        cv[1].depthStencil.depth = 1.0f;
        cv[1].depthStencil.stencil = 0;
        bi.clearValueCount = 2;
        bi.pClearValues = cv;
    }
    else
    {
        bi.renderPass = t->has_depth ? s_rp_depth_nc : s_rp_color;
        bi.clearValueCount = 0;
        bi.pClearValues = NULL;
    }
    p_vkCmdBeginRenderPass(s_cmd, &bi, (VkSubpassContents)VK_SUBPASS_CONTENTS_INLINE);
    s_pass_open = 1;
    s_pass_t = t;
    t->layout = VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL;
    vk_full_vp_scissor(w, h);
}

/* ===================================================================== */
/* 着色器模块 / 管线                                                       */
/* ===================================================================== */
static int vk_make_shader_module(VkShaderModule* out, const unsigned char* code, uint32_t size)
{
    VkShaderModuleCreateInfo si;
    memset(&si, 0, sizeof(si));
    si.sType = VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO;
    si.codeSize = size;
    si.pCode = (const uint32_t*)code;
    if (!vk_check(p_vkCreateShaderModule(s_dev, &si, NULL, out), "vkCreateShaderModule"))
        return 0;
    return 1;
}

static int vk_make_pipeline_layout(VkPipelineLayout* out,
                                  VkDescriptorSetLayout dsl, int has_set,
                                  uint32_t pc_stages, uint32_t pc_offset, uint32_t pc_size)
{
    VkPipelineLayoutCreateInfo pi;
    VkPushConstantRange pc;
    memset(&pi, 0, sizeof(pi));
    pi.sType = VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO;
    if (has_set) { pi.setLayoutCount = 1; pi.pSetLayouts = &dsl; }
    if (pc_size)
    {
        memset(&pc, 0, sizeof(pc));
        pc.stageFlags = (VkShaderStageFlagBits)pc_stages;
        pc.offset = pc_offset;
        pc.size = pc_size;
        pi.pushConstantRangeCount = 1;
        pi.pPushConstantRanges = &pc;
    }
    if (!vk_check(p_vkCreatePipelineLayout(s_dev, &pi, NULL, out), "vkCreatePipelineLayout"))
        return 0;
    return 1;
}

static int vk_make_gfx_pipeline(VkPipeline* out, VkRenderPass rp, VkPipelineLayout layout,
                                VkShaderModule vs, VkShaderModule fs,
                                int depth_test, int depth_write, int blend)
{
    VkPipelineShaderStageCreateInfo stages[2];
    VkVertexInputBindingDescription bind;
    VkVertexInputAttributeDescription attrs[2];
    VkPipelineVertexInputStateCreateInfo vi;
    VkPipelineInputAssemblyStateCreateInfo ia;
    VkPipelineViewportStateCreateInfo vp;
    VkPipelineRasterizationStateCreateInfo rs;
    VkPipelineMultisampleStateCreateInfo ms;
    VkPipelineDepthStencilStateCreateInfo ds;
    VkPipelineColorBlendAttachmentState cba;
    VkPipelineColorBlendStateCreateInfo cb;
    VkDynamicState dyn[2];
    VkPipelineDynamicStateCreateInfo dy;
    VkGraphicsPipelineCreateInfo gi;

    memset(stages, 0, sizeof(stages));
    stages[0].sType = VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO;
    stages[0].stage = (VkShaderStageFlagBits)VK_SHADER_STAGE_VERTEX_BIT;
    stages[0].module = vs;
    stages[0].pName = "main";
    stages[1].sType = VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO;
    stages[1].stage = (VkShaderStageFlagBits)VK_SHADER_STAGE_FRAGMENT_BIT;
    stages[1].module = fs;
    stages[1].pName = "main";

    bind.binding = 0; bind.stride = 16; bind.inputRate = (VkVertexInputRate)VK_VERTEX_INPUT_RATE_VERTEX;
    attrs[0].location = 0; attrs[0].binding = 0; attrs[0].offset = 0;
    attrs[0].format = (VkFormat)VK_FORMAT_R32G32_SFLOAT;   /* pos2 */
    attrs[1].location = 1; attrs[1].binding = 0; attrs[1].offset = 8;
    attrs[1].format = (VkFormat)VK_FORMAT_R32G32_SFLOAT;   /* uv2  */

    memset(&vi, 0, sizeof(vi));
    vi.sType = VK_STRUCTURE_TYPE_PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO;
    vi.vertexBindingDescriptionCount = 1;
    vi.pVertexBindingDescriptions = &bind;
    vi.vertexAttributeDescriptionCount = 2;
    vi.pVertexAttributeDescriptions = attrs;

    memset(&ia, 0, sizeof(ia));
    ia.sType = VK_STRUCTURE_TYPE_PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO;
    ia.topology = (VkPrimitiveTopology)VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST;

    memset(&vp, 0, sizeof(vp));
    vp.sType = VK_STRUCTURE_TYPE_PIPELINE_VIEWPORT_STATE_CREATE_INFO;
    vp.viewportCount = 1;
    vp.scissorCount = 1;

    memset(&rs, 0, sizeof(rs));
    rs.sType = VK_STRUCTURE_TYPE_PIPELINE_RASTERIZATION_STATE_CREATE_INFO;
    rs.polygonMode = (VkPolygonMode)VK_POLYGON_MODE_FILL;
    rs.cullMode = (VkCullModeFlags)VK_CULL_MODE_NONE;
    rs.frontFace = (VkFrontFace)VK_FRONT_FACE_COUNTER_CLOCKWISE;
    rs.lineWidth = 1.0f;

    memset(&ms, 0, sizeof(ms));
    ms.sType = VK_STRUCTURE_TYPE_PIPELINE_MULTISAMPLE_STATE_CREATE_INFO;
    ms.rasterizationSamples = 1;

    memset(&ds, 0, sizeof(ds));
    ds.sType = VK_STRUCTURE_TYPE_PIPELINE_DEPTH_STENCIL_STATE_CREATE_INFO;
    ds.depthTestEnable = depth_test ? VK_TRUE : VK_FALSE;
    ds.depthWriteEnable = depth_write ? VK_TRUE : VK_FALSE;
    ds.depthCompareOp = (VkCompareOp)VK_COMPARE_OP_LESS;

    memset(&cba, 0, sizeof(cba));
    cba.blendEnable = blend ? VK_TRUE : VK_FALSE;
    cba.srcColorBlendFactor = (VkBlendFactor)VK_BLEND_FACTOR_SRC_ALPHA;
    cba.dstColorBlendFactor = (VkBlendFactor)VK_BLEND_FACTOR_ONE_MINUS_SRC_ALPHA;
    cba.colorBlendOp = (VkBlendOp)VK_BLEND_OP_ADD;
    cba.srcAlphaBlendFactor = (VkBlendFactor)VK_BLEND_FACTOR_SRC_ALPHA;
    cba.dstAlphaBlendFactor = (VkBlendFactor)VK_BLEND_FACTOR_ONE_MINUS_SRC_ALPHA;
    cba.alphaBlendOp = (VkBlendOp)VK_BLEND_OP_ADD;
    cba.colorWriteMask = VK_COLOR_COMPONENT_RGBA;

    memset(&cb, 0, sizeof(cb));
    cb.sType = VK_STRUCTURE_TYPE_PIPELINE_COLOR_BLEND_STATE_CREATE_INFO;
    cb.attachmentCount = 1;
    cb.pAttachments = &cba;

    dyn[0] = (VkDynamicState)VK_DYNAMIC_STATE_VIEWPORT;
    dyn[1] = (VkDynamicState)VK_DYNAMIC_STATE_SCISSOR;
    memset(&dy, 0, sizeof(dy));
    dy.sType = VK_STRUCTURE_TYPE_PIPELINE_DYNAMIC_STATE_CREATE_INFO;
    dy.dynamicStateCount = 2;
    dy.pDynamicStates = dyn;

    memset(&gi, 0, sizeof(gi));
    gi.sType = VK_STRUCTURE_TYPE_GRAPHICS_PIPELINE_CREATE_INFO;
    gi.stageCount = 2;
    gi.pStages = stages;
    gi.pVertexInputState = &vi;
    gi.pInputAssemblyState = &ia;
    gi.pViewportState = &vp;
    gi.pRasterizationState = &rs;
    gi.pMultisampleState = &ms;
    gi.pDepthStencilState = &ds;
    gi.pColorBlendState = &cb;
    gi.pDynamicState = &dy;
    gi.layout = layout;
    gi.renderPass = rp;
    gi.subpass = 0;

    if (!vk_check(p_vkCreateGraphicsPipelines(s_dev, NULL, 1, &gi, NULL, out),
                  "vkCreateGraphicsPipelines"))
        return 0;
    return 1;
}

/* ---- render pass：style 0=全幅清(CLEAR/UNDEFINED) 1=续画(LOAD/现布局)
 *      2=仅颜色全屏覆写(DONT_CARE/UNDEFINED) 3=仅颜色全幅清(CLEAR/UNDEFINED) ---- */
static int vk_make_render_pass(VkRenderPass* out, int with_depth, int style)
{
    VkAttachmentDescription att[2];
    VkAttachmentReference cref, dref;
    VkSubpassDescription sub;
    VkRenderPassCreateInfo ri;
    uint32_t count = with_depth ? 2 : 1;
    int keep = (style == 1);
    VkAttachmentLoadOp color_load = keep ? (VkAttachmentLoadOp)VK_ATTACHMENT_LOAD_OP_LOAD
        : (style == 2) ? (VkAttachmentLoadOp)VK_ATTACHMENT_LOAD_OP_DONT_CARE
        : (VkAttachmentLoadOp)VK_ATTACHMENT_LOAD_OP_CLEAR;

    memset(att, 0, sizeof(att));
    /* 颜色 */
    att[0].format = (VkFormat)VK_FORMAT_R8G8B8A8_UNORM;
    att[0].samples = 1;
    att[0].loadOp = color_load;
    att[0].storeOp = (VkAttachmentStoreOp)VK_ATTACHMENT_STORE_OP_STORE;
    att[0].stencilLoadOp = att[0].loadOp;
    att[0].stencilStoreOp = att[0].storeOp;
    att[0].initialLayout = (VkImageLayout)(keep ? VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL
                                                : VK_IMAGE_LAYOUT_UNDEFINED);
    att[0].finalLayout = (VkImageLayout)VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL;
    if (with_depth)
    {
        /* 深度 */
        att[1].format = s_depth_fmt;
        att[1].samples = 1;
        att[1].loadOp = keep ? (VkAttachmentLoadOp)VK_ATTACHMENT_LOAD_OP_LOAD
                             : (VkAttachmentLoadOp)VK_ATTACHMENT_LOAD_OP_CLEAR;
        att[1].storeOp = (VkAttachmentStoreOp)VK_ATTACHMENT_STORE_OP_STORE;
        att[1].stencilLoadOp = att[1].loadOp;
        att[1].stencilStoreOp = att[1].storeOp;
        att[1].initialLayout = (VkImageLayout)(keep ? VK_IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL
                                                    : VK_IMAGE_LAYOUT_UNDEFINED);
        att[1].finalLayout = (VkImageLayout)VK_IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL;
    }

    memset(&cref, 0, sizeof(cref));
    cref.attachment = 0;
    cref.layout = (VkImageLayout)VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL;
    memset(&dref, 0, sizeof(dref));
    dref.attachment = 1;
    dref.layout = (VkImageLayout)VK_IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL;

    memset(&sub, 0, sizeof(sub));
    sub.pipelineBindPoint = (VkPipelineBindPoint)VK_PIPELINE_BIND_POINT_GRAPHICS;
    sub.colorAttachmentCount = 1;
    sub.pColorAttachments = &cref;
    sub.pDepthStencilAttachment = with_depth ? &dref : NULL;

    memset(&ri, 0, sizeof(ri));
    ri.sType = VK_STRUCTURE_TYPE_RENDER_PASS_CREATE_INFO;
    ri.attachmentCount = count;
    ri.pAttachments = att;
    ri.subpassCount = 1;
    ri.pSubpasses = &sub;
    if (!vk_check(p_vkCreateRenderPass(s_dev, &ri, NULL, out), "vkCreateRenderPass"))
        return 0;
    return 1;
}

/* 确保上传中转缓冲至少 need 字节（HOST_VISIBLE + COHERENT，持久映射）*/
static int vk_ensure_upload(VkDeviceSize need)
{
    if (s_upload_buf && s_upload_size >= need) return 1;
    vk_destroy_buffer(&s_upload_buf, &s_upload_mem, &s_upload_ptr);
    s_upload_size = 0;
    if (!vk_make_buffer(&s_upload_buf, &s_upload_mem, need, 0x00000001, /* TRANSFER_SRC */
                        VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | VK_MEMORY_PROPERTY_HOST_COHERENT_BIT,
                        &s_upload_ptr, &s_upload_coherent))
        return 0;
    s_upload_size = need;
    return 1;
}

/* ===================================================================== */
/* 共享资源构建（设备成功后一次）                                          */
/* ===================================================================== */
static int vk_make_shared(void)
{
    static const float tri[] = {          /* 与 GL/D3D11 后端逐字节一致 */
        -0.5f, -0.35f, 0.0f, 0.0f,
         0.5f, -0.35f, 1.0f, 0.0f,
         0.0f,  0.65f, 0.5f, 1.0f,
    };
    static const float quad[] = {
        -0.5f, -0.5f, 0.0f, 0.0f,
         0.5f, -0.5f, 1.0f, 0.0f,
         0.5f,  0.5f, 1.0f, 1.0f,
        -0.5f, -0.5f, 0.0f, 0.0f,
         0.5f,  0.5f, 1.0f, 1.0f,
        -0.5f,  0.5f, 0.0f, 1.0f,
    };
    static const float fs_tri[] = {       /* D3D 版 V 翻转（RT 行序差异）*/
        -1.0f, -1.0f, 0.0f, 1.0f,
         3.0f, -1.0f, 2.0f, 1.0f,
        -1.0f,  3.0f, 0.0f, -1.0f,
    };
    static const float ctx_tri[] = {
        -0.8f, -0.6f, 0.0f, 0.0f,
         0.8f, -0.6f, 1.0f, 0.0f,
         0.0f,  0.9f, 0.5f, 1.0f,
    };
    const float* datas[4] = { tri, quad, fs_tri, ctx_tri };
    const VkDeviceSize counts[4] = { 3, 6, 3, 3 };
    VkDeviceSize total = 0;
    int i;
    VkSamplerCreateInfo sinfo;
    VkDescriptorPoolCreateInfo pi;
    VkDescriptorPoolSize psizes[2];
    VkDescriptorSetLayoutBinding binds[2];
    VkDescriptorSetLayoutCreateInfo di;
    VkDeviceSize upneed;

    memset(s_shaders, 0, sizeof(s_shaders));
    memset(s_pl_layouts, 0, sizeof(s_pl_layouts));
    memset(s_vk_pipes, 0, sizeof(s_vk_pipes));
    memset(s_vb, 0, sizeof(s_vb));
    memset(s_vb_mem, 0, sizeof(s_vb_mem));
    memset(s_vb_custom, 0, sizeof(s_vb_custom));
    memset(s_vb_custom_mem, 0, sizeof(s_vb_custom_mem));
    memset(s_vb_custom_ptr, 0, sizeof(s_vb_custom_ptr));
    memset(s_vb_custom_cap, 0, sizeof(s_vb_custom_cap));
    memset(s_vb_custom_count, 0, sizeof(s_vb_custom_count));

    /* ---- render pass（管线与 framebuffer 依赖）----
     * style 0 = 全幅清（begin_scene / v1_clear）
     * style 1 = 续画 LOAD（相机段 / v1 追加绘制）
     * style 2 = 仅颜色全屏覆写（post / blit）*/
    if (!vk_make_render_pass(&s_rp_depth, 1, 0)) return 0;
    if (!vk_make_render_pass(&s_rp_depth_nc, 1, 1)) return 0;
    if (!vk_make_render_pass(&s_rp_color, 0, 2)) return 0;

    /* ---- 采样器：线性 + CLAMP_TO_EDGE（与 GL/D3D11 一致）---- */
    memset(&sinfo, 0, sizeof(sinfo));
    sinfo.sType = VK_STRUCTURE_TYPE_SAMPLER_CREATE_INFO;
    sinfo.magFilter = (VkFilter)VK_FILTER_LINEAR;
    sinfo.minFilter = (VkFilter)VK_FILTER_LINEAR;
    sinfo.mipmapMode = (VkSamplerMipmapMode)VK_SAMPLER_MIPMAP_MODE_NEAREST;
    sinfo.addressModeU = (VkSamplerAddressMode)VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_EDGE;
    sinfo.addressModeV = (VkSamplerAddressMode)VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_EDGE;
    sinfo.addressModeW = (VkSamplerAddressMode)VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_EDGE;
    sinfo.maxLod = 1.0f;
    if (!vk_check(p_vkCreateSampler(s_dev, &sinfo, NULL, &s_sampler), "vkCreateSampler"))
        return 0;

    /* ---- 描述符池 ---- */
    memset(&pi, 0, sizeof(pi));
    pi.sType = VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO;
    pi.flags = VK_DESCRIPTOR_POOL_CREATE_FREE_DESCRIPTOR_SET_BIT;
    pi.maxSets = 512;
    psizes[0].type = (VkDescriptorType)VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER;
    psizes[0].descriptorCount = 256;
    psizes[1].type = (VkDescriptorType)VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER;
    psizes[1].descriptorCount = 512;
    pi.poolSizeCount = 2;
    pi.pPoolSizes = psizes;
    if (!vk_check(p_vkCreateDescriptorPool(s_dev, &pi, NULL, &s_descpool), "vkCreateDescriptorPool"))
        return 0;

    /* ---- 描述符布局 ×3 ---- */
    memset(&di, 0, sizeof(di));
    di.sType = VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO;
    memset(binds, 0, sizeof(binds));
    binds[0].binding = 0;
    binds[0].descriptorType = (VkDescriptorType)VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER;
    binds[0].descriptorCount = 1;
    binds[0].stageFlags = (VkShaderStageFlagBits)(VK_SHADER_STAGE_VERTEX_BIT | VK_SHADER_STAGE_FRAGMENT_BIT);
    di.bindingCount = 1;
    di.pBindings = binds;
    if (!vk_check(p_vkCreateDescriptorSetLayout(s_dev, &di, NULL, &s_dsl_pipe_flat),
                  "vkCreateDescriptorSetLayout(pipe_flat)"))
        return 0;
    binds[1].binding = 1;
    binds[1].descriptorType = (VkDescriptorType)VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER;
    binds[1].descriptorCount = 1;
    binds[1].stageFlags = (VkShaderStageFlagBits)VK_SHADER_STAGE_FRAGMENT_BIT;
    di.bindingCount = 2;
    if (!vk_check(p_vkCreateDescriptorSetLayout(s_dev, &di, NULL, &s_dsl_pipe_tex),
                  "vkCreateDescriptorSetLayout(pipe_tex)"))
        return 0;
    memset(binds, 0, sizeof(binds));
    binds[0].binding = 0;
    binds[0].descriptorType = (VkDescriptorType)VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER;
    binds[0].descriptorCount = 1;
    binds[0].stageFlags = (VkShaderStageFlagBits)VK_SHADER_STAGE_FRAGMENT_BIT;
    di.bindingCount = 1;
    di.pBindings = binds;
    if (!vk_check(p_vkCreateDescriptorSetLayout(s_dev, &di, NULL, &s_dsl_sampler),
                  "vkCreateDescriptorSetLayout(sampler)"))
        return 0;

    /* ---- PerDraw UBO（持久映射，0x10 = UNIFORM_BUFFER usage）+ PFLAT 描述符集 ---- */
    if (!vk_make_buffer(&s_ubo_draw, &s_ubo_draw_mem, sizeof(SlrPerDraw), 0x10,
                        VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | VK_MEMORY_PROPERTY_HOST_COHERENT_BIT,
                        &s_ubo_draw_ptr, &s_ubo_coherent))
        return 0;
    if (!vk_alloc_sets(&s_set_perdraw, 1, s_dsl_pipe_flat)) return 0;
    vk_write_perdraw_set(s_set_perdraw);

    /* ---- 上传中转（网格 + 后续纹理上传）---- */
    total = 0;
    for (i = 0; i < 4; i++) total += counts[i] * 16;
    upneed = total > 65536 ? total : 65536;
    if (!vk_ensure_upload(upneed)) return 0;

    /* ---- 网格 ×4（设备本地，经中转一次性上传）---- */
    {
        VkDeviceSize off = 0;
        for (i = 0; i < 4; i++)
        {
            VkDeviceSize size = counts[i] * 16;
            VkBufferCreateInfo vbi;
            VkMemoryRequirements req;
            VkMemoryAllocateInfo mai;
            uint32_t type;
            void* mapped = NULL;
            memset(&vbi, 0, sizeof(vbi));
            vbi.sType = VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO;
            vbi.size = size;
            vbi.usage = 0x80; /* VK_BUFFER_USAGE_VERTEX_BUFFER_BIT */
            if (!vk_check(p_vkCreateBuffer(s_dev, &vbi, NULL, &s_vb[i]), "vkCreateBuffer(mesh)"))
                return 0;
            p_vkGetBufferMemoryRequirements(s_dev, s_vb[i], &req);
            type = vk_find_memory(req.memoryTypeBits, VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT);
            if (type == 0xFFFFFFFFu) type = vk_find_memory(req.memoryTypeBits, 0);
            memset(&mai, 0, sizeof(mai));
            mai.sType = VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO;
            mai.allocationSize = req.size;
            mai.memoryTypeIndex = type;
            if (!vk_check(p_vkAllocateMemory(s_dev, &mai, NULL, &s_vb_mem[i]), "vkAllocateMemory(mesh)"))
                return 0;
            if (!vk_check(p_vkBindBufferMemory(s_dev, s_vb[i], s_vb_mem[i], 0), "vkBindBufferMemory(mesh)"))
                return 0;
            /* CPU -> 中转 -> GPU（一段命令，一次性提交）*/
            memcpy((char*)s_upload_ptr + off, datas[i], (size_t)size);
            off += size;
        }
        vk_flush_mem(s_upload_mem, 0, total, s_upload_coherent);
        if (!vk_ensure_recording()) return 0;
        off = 0;
        for (i = 0; i < 4; i++)
        {
            VkBufferCopy cp;
            memset(&cp, 0, sizeof(cp));
            cp.srcOffset = off;
            cp.dstOffset = 0;
            cp.size = counts[i] * 16;
            p_vkCmdCopyBuffer(s_cmd, s_upload_buf, s_vb[i], 1, &cp);
            off += cp.size;
        }
        if (!vk_submit_now()) return 0;
    }

    /* ---- 着色器模块 ×9 ---- */
    if (!vk_make_shader_module(&s_shaders[0], SLR_VK_SPV_VS_SCENE, SLR_VK_SPV_VS_SCENE_SIZE)) return 0;
    if (!vk_make_shader_module(&s_shaders[1], SLR_VK_SPV_FS_FLAT, SLR_VK_SPV_FS_FLAT_SIZE)) return 0;
    if (!vk_make_shader_module(&s_shaders[2], SLR_VK_SPV_FS_TEX, SLR_VK_SPV_FS_TEX_SIZE)) return 0;
    if (!vk_make_shader_module(&s_shaders[3], SLR_VK_SPV_VS_PSCENE, SLR_VK_SPV_VS_PSCENE_SIZE)) return 0;
    if (!vk_make_shader_module(&s_shaders[4], SLR_VK_SPV_FS_PFLAT, SLR_VK_SPV_FS_PFLAT_SIZE)) return 0;
    if (!vk_make_shader_module(&s_shaders[5], SLR_VK_SPV_FS_PTEX, SLR_VK_SPV_FS_PTEX_SIZE)) return 0;
    if (!vk_make_shader_module(&s_shaders[6], SLR_VK_SPV_VS_FULL, SLR_VK_SPV_VS_FULL_SIZE)) return 0;
    if (!vk_make_shader_module(&s_shaders[7], SLR_VK_SPV_FS_BLIT, SLR_VK_SPV_FS_BLIT_SIZE)) return 0;
    if (!vk_make_shader_module(&s_shaders[8], SLR_VK_SPV_FS_POST, SLR_VK_SPV_FS_POST_SIZE)) return 0;

    /* ---- 管线布局 ×6 ---- */
    if (!vk_make_pipeline_layout(&s_pl_layouts[VKP_PFLAT_O], s_dsl_pipe_flat, 1,
                                 VK_SHADER_STAGE_VERTEX_BIT | VK_SHADER_STAGE_FRAGMENT_BIT, 0, 4))
        return 0;
    s_pl_layouts[VKP_PFLAT_T] = s_pl_layouts[VKP_PFLAT_O];
    if (!vk_make_pipeline_layout(&s_pl_layouts[VKP_PTEX_O], s_dsl_pipe_tex, 1,
                                 VK_SHADER_STAGE_VERTEX_BIT | VK_SHADER_STAGE_FRAGMENT_BIT, 0, 4))
        return 0;
    s_pl_layouts[VKP_PTEX_T] = s_pl_layouts[VKP_PTEX_O];
    if (!vk_make_pipeline_layout(&s_pl_layouts[VKP_V1_FLAT], NULL, 0,
                                 VK_SHADER_STAGE_VERTEX_BIT | VK_SHADER_STAGE_FRAGMENT_BIT, 0, 80))
        return 0;
    if (!vk_make_pipeline_layout(&s_pl_layouts[VKP_V1_TEX], s_dsl_sampler, 1,
                                 VK_SHADER_STAGE_VERTEX_BIT | VK_SHADER_STAGE_FRAGMENT_BIT, 0, 80))
        return 0;
    if (!vk_make_pipeline_layout(&s_pl_layouts[VKP_BLIT], s_dsl_sampler, 1, 0, 0, 0)) return 0;
    if (!vk_make_pipeline_layout(&s_pl_layouts[VKP_POST], s_dsl_sampler, 1,
                                 VK_SHADER_STAGE_FRAGMENT_BIT, 0, 16))
        return 0;

    /* ---- 管线 ×8（绘制类带深度；post/blit 无深度）---- */
    if (!vk_make_gfx_pipeline(&s_vk_pipes[VKP_PFLAT_O], s_rp_depth, s_pl_layouts[VKP_PFLAT_O],
                              s_shaders[3], s_shaders[4], 1, 1, 0)) return 0;
    if (!vk_make_gfx_pipeline(&s_vk_pipes[VKP_PFLAT_T], s_rp_depth, s_pl_layouts[VKP_PFLAT_T],
                              s_shaders[3], s_shaders[4], 1, 0, 1)) return 0;
    if (!vk_make_gfx_pipeline(&s_vk_pipes[VKP_PTEX_O], s_rp_depth, s_pl_layouts[VKP_PTEX_O],
                              s_shaders[3], s_shaders[5], 1, 1, 0)) return 0;
    if (!vk_make_gfx_pipeline(&s_vk_pipes[VKP_PTEX_T], s_rp_depth, s_pl_layouts[VKP_PTEX_T],
                              s_shaders[3], s_shaders[5], 1, 0, 1)) return 0;
    if (!vk_make_gfx_pipeline(&s_vk_pipes[VKP_V1_FLAT], s_rp_depth, s_pl_layouts[VKP_V1_FLAT],
                              s_shaders[0], s_shaders[1], 0, 0, 0)) return 0;
    if (!vk_make_gfx_pipeline(&s_vk_pipes[VKP_V1_TEX], s_rp_depth, s_pl_layouts[VKP_V1_TEX],
                              s_shaders[0], s_shaders[2], 0, 0, 0)) return 0;
    if (!vk_make_gfx_pipeline(&s_vk_pipes[VKP_BLIT], s_rp_color, s_pl_layouts[VKP_BLIT],
                              s_shaders[6], s_shaders[7], 0, 0, 0)) return 0;
    if (!vk_make_gfx_pipeline(&s_vk_pipes[VKP_POST], s_rp_color, s_pl_layouts[VKP_POST],
                              s_shaders[6], s_shaders[8], 0, 0, 0)) return 0;
    return 1;
}

static void vk_free_shared(void)
{
    int i;
    vk_flush_pending();
    if (s_rdbuf) vk_destroy_buffer(&s_rdbuf, &s_rd_mem, &s_rd_ptr);
    s_rd_size = 0;
    if (s_upload_buf) vk_destroy_buffer(&s_upload_buf, &s_upload_mem, &s_upload_ptr);
    s_upload_size = 0;
    for (i = 0; i < VKP_COUNT; i++)
    {
        if (s_vk_pipes[i]) { p_vkDestroyPipeline(s_dev, s_vk_pipes[i], NULL); s_vk_pipes[i] = NULL; }
    }
    /* 布局别名：PFLAT_T / PTEX_T 与 O 变体同一对象，先清引用防重复销毁 */
    s_pl_layouts[VKP_PFLAT_T] = NULL;
    s_pl_layouts[VKP_PTEX_T] = NULL;
    for (i = 0; i < 8; i++)
    {
        if (s_pl_layouts[i]) { p_vkDestroyPipelineLayout(s_dev, s_pl_layouts[i], NULL); s_pl_layouts[i] = NULL; }
    }
    for (i = 0; i < 9; i++)
    {
        if (s_shaders[i]) { p_vkDestroyShaderModule(s_dev, s_shaders[i], NULL); s_shaders[i] = NULL; }
    }
    for (i = 0; i < 4; i++)
    {
        if (s_vb[i]) { p_vkDestroyBuffer(s_dev, s_vb[i], NULL); s_vb[i] = NULL; }
        if (s_vb_mem[i]) { p_vkFreeMemory(s_dev, s_vb_mem[i], NULL); s_vb_mem[i] = NULL; }
    }
    for (i = 0; i < SLR_CUSTOM_MESHES; i++)
    {
        vk_destroy_buffer(&s_vb_custom[i], &s_vb_custom_mem[i], &s_vb_custom_ptr[i]);
        s_vb_custom_cap[i] = 0;
        s_vb_custom_count[i] = 0;
    }
    if (s_set_perdraw) { p_vkFreeDescriptorSets(s_dev, s_descpool, 1, &s_set_perdraw); s_set_perdraw = NULL; }
    /* 描述符槽表清空（纹理 set 已随纹理销毁释放，防悬空句柄）*/
    memset(s_desc_set, 0, sizeof(s_desc_set));
    s_cur_tex_set = NULL;
    if (s_ubo_draw) vk_destroy_buffer(&s_ubo_draw, &s_ubo_draw_mem, &s_ubo_draw_ptr);
    if (s_dsl_pipe_flat) { p_vkDestroyDescriptorSetLayout(s_dev, s_dsl_pipe_flat, NULL); s_dsl_pipe_flat = NULL; }
    if (s_dsl_pipe_tex) { p_vkDestroyDescriptorSetLayout(s_dev, s_dsl_pipe_tex, NULL); s_dsl_pipe_tex = NULL; }
    if (s_dsl_sampler) { p_vkDestroyDescriptorSetLayout(s_dev, s_dsl_sampler, NULL); s_dsl_sampler = NULL; }
    if (s_descpool) { p_vkDestroyDescriptorPool(s_dev, s_descpool, NULL); s_descpool = NULL; }
    if (s_sampler) { p_vkDestroySampler(s_dev, s_sampler, NULL); s_sampler = NULL; }
    if (s_rp_depth) { p_vkDestroyRenderPass(s_dev, s_rp_depth, NULL); s_rp_depth = NULL; }
    if (s_rp_depth_nc) { p_vkDestroyRenderPass(s_dev, s_rp_depth_nc, NULL); s_rp_depth_nc = NULL; }
    if (s_rp_color) { p_vkDestroyRenderPass(s_dev, s_rp_color, NULL); s_rp_color = NULL; }
}

/* ===================================================================== */
/* 渲染目标 / 纹理                                                         */
/* ===================================================================== */
static SlrRhiTarget* vk_target_create(int w, int h, int with_depth)
{
    SlrRhiTarget* t;
    VkFramebufferCreateInfo fi;
    VkImageView views[2];

    vk_flush_pending();
    t = (SlrRhiTarget*)malloc(sizeof(SlrRhiTarget));
    if (!t) { set_error(SLR_E_MEMORY); return NULL; }
    memset(t, 0, sizeof(*t));
    t->w = w; t->h = h;
    t->has_depth = with_depth ? 1 : 0;
    t->layout = VK_IMAGE_LAYOUT_UNDEFINED;

    if (!vk_make_image(&t->color, &t->color_mem, &t->color_view,
                       (uint32_t)w, (uint32_t)h, (VkFormat)VK_FORMAT_R8G8B8A8_UNORM,
                       VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT | VK_IMAGE_USAGE_SAMPLED_BIT |
                       VK_IMAGE_USAGE_TRANSFER_SRC_BIT, 0))
        goto fail;
    if (with_depth)
    {
        if (!vk_make_image(&t->depth, &t->depth_mem, &t->depth_view,
                           (uint32_t)w, (uint32_t)h, s_depth_fmt,
                           VK_IMAGE_USAGE_DEPTH_STENCIL_ATTACHMENT_BIT, 1))
            goto fail;
    }

    memset(&fi, 0, sizeof(fi));
    fi.sType = VK_STRUCTURE_TYPE_FRAMEBUFFER_CREATE_INFO;
    if (with_depth)
    {
        views[0] = t->color_view;
        views[1] = t->depth_view;
        fi.renderPass = s_rp_depth;
        fi.attachmentCount = 2;
        fi.pAttachments = views;
    }
    else
    {
        views[0] = t->color_view;
        fi.renderPass = s_rp_color;
        fi.attachmentCount = 1;
        fi.pAttachments = views;
    }
    fi.width = (uint32_t)w;
    fi.height = (uint32_t)h;
    fi.layers = 1;
    if (!vk_check(p_vkCreateFramebuffer(s_dev, &fi, NULL, &t->fb), "vkCreateFramebuffer"))
        goto fail;

    if (!vk_alloc_sets(&t->set_sampler, 1, s_dsl_sampler)) goto fail;
    vk_write_sampler_set(t->set_sampler, t->color_view);
    return t;

fail:
    if (t->set_sampler) p_vkFreeDescriptorSets(s_dev, s_descpool, 1, &t->set_sampler);
    if (t->fb) p_vkDestroyFramebuffer(s_dev, t->fb, NULL);
    vk_destroy_image(&t->depth, &t->depth_mem, &t->depth_view);
    vk_destroy_image(&t->color, &t->color_mem, &t->color_view);
    free(t);
    set_error_detail(SLR_E_FBO, "Vulkan render target creation failed");
    return NULL;
}

static void vk_target_destroy(SlrRhiTarget* t)
{
    if (!t) return;
    vk_flush_pending();
    if (t->set_sampler) p_vkFreeDescriptorSets(s_dev, s_descpool, 1, &t->set_sampler);
    if (t->fb) p_vkDestroyFramebuffer(s_dev, t->fb, NULL);
    vk_destroy_image(&t->depth, &t->depth_mem, &t->depth_view);
    vk_destroy_image(&t->color, &t->color_mem, &t->color_view);
    free(t);
}

/* rgba 首行 = 图像底部（sl_texture.c 已统一翻转）：
 * VK 纹理行 0 = 首数据行，采样 v=0 -> 首行，与 GL t=0 / D3D v=0 语义一致 */
static void* vk_texture_create(int w, int h, const unsigned char* rgba)
{
    VkTexture* t;
    VkDeviceSize need = (VkDeviceSize)w * h * 4;
    VkBufferImageCopy cp;

    vk_flush_pending();
    t = (VkTexture*)malloc(sizeof(VkTexture));
    if (!t) { set_error(SLR_E_MEMORY); return NULL; }
    memset(t, 0, sizeof(*t));

    if (!vk_make_image(&t->img, &t->mem, &t->view,
                       (uint32_t)w, (uint32_t)h, (VkFormat)VK_FORMAT_R8G8B8A8_UNORM,
                       VK_IMAGE_USAGE_SAMPLED_BIT | VK_IMAGE_USAGE_TRANSFER_DST_BIT, 0))
        goto fail;

    if (!vk_ensure_upload(need)) goto fail;
    memcpy(s_upload_ptr, rgba, (size_t)need);
    vk_flush_mem(s_upload_mem, 0, need, s_upload_coherent);

    if (!vk_ensure_recording()) goto fail;
    vk_barrier_image(t->img, VK_IMAGE_LAYOUT_UNDEFINED, VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
                     VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT, 0,
                     VK_PIPELINE_STAGE_TRANSFER_BIT, VK_ACCESS_TRANSFER_WRITE_BIT);
    memset(&cp, 0, sizeof(cp));
    cp.imageSubresource.aspectMask = VK_IMAGE_ASPECT_COLOR_BIT;
    cp.imageSubresource.layerCount = 1;
    cp.imageExtent.width = (uint32_t)w;
    cp.imageExtent.height = (uint32_t)h;
    cp.imageExtent.depth = 1;
    p_vkCmdCopyBufferToImage(s_cmd, s_upload_buf, t->img,
                             (VkImageLayout)VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, 1, &cp);
    vk_barrier_image(t->img, VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
                     VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL,
                     VK_PIPELINE_STAGE_TRANSFER_BIT, VK_ACCESS_TRANSFER_WRITE_BIT,
                     VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT, VK_ACCESS_SHADER_READ_BIT);
    if (!vk_submit_now()) goto fail;

    if (!vk_alloc_sets(&t->set_sampler, 1, s_dsl_sampler)) goto fail;
    vk_write_sampler_set(t->set_sampler, t->view);
    if (!vk_alloc_sets(&t->set_pipe_tex, 1, s_dsl_pipe_tex)) goto fail;
    vk_write_pipe_tex_set(t->set_pipe_tex, t->view);
    return t;

fail:
    if (t->set_sampler) p_vkFreeDescriptorSets(s_dev, s_descpool, 1, &t->set_sampler);
    if (t->set_pipe_tex) p_vkFreeDescriptorSets(s_dev, s_descpool, 1, &t->set_pipe_tex);
    vk_destroy_image(&t->img, &t->mem, &t->view);
    free(t);
    set_error_detail(SLR_E_TEXTURE, "Vulkan texture creation failed");
    return NULL;
}

static void vk_texture_destroy(void* tex)
{
    VkTexture* t = (VkTexture*)tex;
    if (!t) return;
    vk_flush_pending();
    if (t->set_sampler) p_vkFreeDescriptorSets(s_dev, s_descpool, 1, &t->set_sampler);
    if (t->set_pipe_tex) p_vkFreeDescriptorSets(s_dev, s_descpool, 1, &t->set_pipe_tex);
    vk_destroy_image(&t->img, &t->mem, &t->view);
    free(t);
}

/* ===================================================================== */
/* 管线 pass                                                              */
/* ===================================================================== */
/* 阶段 1：整幅清（render pass 载入清）+ 不透明初始状态 */
static void vk_begin_scene(SlrRhiTarget* t, int w, int h, const float* clear)
{
    vk_flush_pending();
    if (!vk_ensure_recording()) return;
    vk_open_pass(t, w, h, clear);
    s_trans = 0;
}

/* 阶段 7/9 逐相机：视口（GL 左下原点 -> VK 顶部原点换算，同 D3D11）+
 * 矩形级局部清（vkCmdClearAttachments 不受 scissor 限制，正合相机清屏）*/
static void vk_camera_begin(SlrRhiTarget* t, int x, int y, int w, int h,
                            int target_h, int clear_flags, const float* clear)
{
    VkViewport vp;
    VkRect2D rc;
    VkClearAttachment catt[2];
    VkClearRect crc;
    int nc = 0;
    uint32_t top_y = (uint32_t)(target_h - (y + h));

    if (!s_pass_open || s_pass_t != t)
    {
        vk_flush_pending();
        if (!vk_ensure_recording()) return;
        vk_open_pass(t, w, h, NULL);
    }
    memset(&vp, 0, sizeof(vp));
    vp.x = (float)x;
    vp.y = (float)top_y;
    vp.width = (float)w;
    vp.height = (float)h;
    vp.maxDepth = 1.0f;
    p_vkCmdSetViewport(s_cmd, 0, 1, &vp);
    memset(&rc, 0, sizeof(rc));
    rc.offset.x = x;
    rc.offset.y = (int32_t)top_y;
    rc.extent.width = (uint32_t)w;
    rc.extent.height = (uint32_t)h;
    p_vkCmdSetScissor(s_cmd, 0, 1, &rc);

    if (clear_flags & SLR_CLEAR_COLOR)
    {
        memset(&catt[nc], 0, sizeof(catt[nc]));
        catt[nc].aspectMask = VK_IMAGE_ASPECT_COLOR_BIT;
        catt[nc].colorAttachment = 0;
        catt[nc].clearValue.color[0] = clear[0];
        catt[nc].clearValue.color[1] = clear[1];
        catt[nc].clearValue.color[2] = clear[2];
        catt[nc].clearValue.color[3] = clear[3];
        nc++;
    }
    if ((clear_flags & SLR_CLEAR_DEPTH) && t->has_depth)
    {
        memset(&catt[nc], 0, sizeof(catt[nc]));
        catt[nc].aspectMask = VK_IMAGE_ASPECT_DEPTH_BIT |
                              (s_depth_stencil ? VK_IMAGE_ASPECT_STENCIL_BIT : 0);
        catt[nc].clearValue.depthStencil.depth = 1.0f;
        catt[nc].clearValue.depthStencil.stencil = 0;
        nc++;
    }
    if (nc > 0)
    {
        memset(&crc, 0, sizeof(crc));
        crc.rect = rc;
        crc.baseArrayLayer = 0;
        crc.layerCount = 1;
        p_vkCmdClearAttachments(s_cmd, (uint32_t)nc, catt, 1, &crc);
    }
}

static void vk_set_state(int transparent)
{
    s_trans = transparent ? 1 : 0;
}

static void vk_upload_perdraw(const void* data, int bytes)
{
    if (!s_ubo_draw_ptr) return;
    memcpy(s_ubo_draw_ptr, data, (size_t)bytes);
    vk_flush_mem(s_ubo_draw_mem, 0, (VkDeviceSize)bytes, s_ubo_coherent);
}

/* 帧级光照块：VK 后端暂不消费（SPIR-V 固化于 sl_rhi_vk_shaders.h，
 * 未包含光照消费逻辑；接入需重生成 SPIR-V + descriptor set 布局扩展）。
 * 空实现保持 vtable 对齐：设置光照在 VK 上无效果但不报错；默认路径
 * （无光照 + ambient=1）输出与旧版逐字节一致，同效果测试不受影响。 */
static void vk_upload_lights(const void* data, int bytes)
{
    (void)data;
    (void)bytes;
}

/* ── 描述符表（descriptor set 槽表，VK 原生形态）──────────────────────
 * desc_write_tex 写槽（槽内容 = VkTexture 的 PTEX descriptor set，
 * 管线层帧级填充），desc_bind_tex 选当前绑定的 set——绑定与绘制分离，
 * draw_item 只携带整数索引不碰资源指针，与 DX11 PSSetShaderResources
 * 机制对齐（VK 的 vkCmdBindDescriptorSets 本身就是该语义）。
 * 槽表/当前绑定声明于后端私有状态区（vk_free_shared 前向引用）。 */
static int vk_desc_write_tex(int slot, void* tex)
{
    if (slot < 0 || slot >= SLR_DESC_TEX_SLOTS) return 0;
    s_desc_set[slot] = tex ? ((VkTexture*)tex)->set_pipe_tex : NULL;
    return 1;
}

static void vk_desc_bind_tex(int slot)
{
    s_cur_tex_set = (slot >= 0 && slot < SLR_DESC_TEX_SLOTS)
                  ? s_desc_set[slot] : NULL;
}

static void vk_draw_item(int prog, int slot, int mesh)
{
    int idx;
    VkDescriptorSet set;
    VkDeviceSize off = 0;
    VkBuffer vb;
    uint32_t count;
    uint32_t obj = (uint32_t)slot;

    if (!s_pass_open)
    {
        set_error(SLR_E_STATE);
        return;
    }
    if (prog == SLR_PROG_PFLAT || prog == SLR_PROG_PHONG_FLAT
        || (prog >= SLR_PROG_GEN_BASE && ((prog - SLR_PROG_GEN_BASE) & 1)))
    {
        /* Phong 新槽与 v3.5 固化槽（FLAT 变体 = 奇数下标）降级映射到
         * PFLAT 管线：VK SPIR-V 固化未含光照/高光/新效果，绘制不报错
         * 仅无该效果（管线侧 C 层/阴影仍一致工作）*/
        idx = s_trans ? VKP_PFLAT_T : VKP_PFLAT_O;
        set = s_set_perdraw;
    }
    else if (prog == SLR_PROG_PTEX || prog == SLR_PROG_PHONG_TEX
        || (prog >= SLR_PROG_GEN_BASE && !((prog - SLR_PROG_GEN_BASE) & 1)))
    {
        if (!s_cur_tex_set) { set_error(SLR_E_TEXTURE); return; }
        idx = s_trans ? VKP_PTEX_T : VKP_PTEX_O;
        set = s_cur_tex_set;
    }
    else
    {
        set_error(SLR_E_STATE);
        return;
    }
    /* mesh 0..3 静态网格；4..4+SLR_CUSTOM_MESHES-1 动态网格 */
    if (mesh >= 4)
    {
        int c = mesh - 4;
        if (c >= SLR_CUSTOM_MESHES || !s_vb_custom[c]) return; /* 未上传/越界跳过 */
        vb = s_vb_custom[c];
        count = s_vb_custom_count[c];
    }
    else
    {
        if (mesh < 0 || mesh > 3) return;
        vb = s_vb[mesh];
        count = (mesh == 1) ? 6 : 3;
    }
    p_vkCmdBindPipeline(s_cmd, (VkPipelineBindPoint)VK_PIPELINE_BIND_POINT_GRAPHICS, s_vk_pipes[idx]);
    p_vkCmdPushConstants(s_cmd, s_pl_layouts[idx],
                        (VkShaderStageFlagBits)(VK_SHADER_STAGE_VERTEX_BIT | VK_SHADER_STAGE_FRAGMENT_BIT),
                        0, 4, &obj);
    p_vkCmdBindDescriptorSets(s_cmd, (VkPipelineBindPoint)VK_PIPELINE_BIND_POINT_GRAPHICS,
                              s_pl_layouts[idx], 0, 1, &set, 0, NULL);
    p_vkCmdBindVertexBuffers(s_cmd, 0, 1, &vb, &off);
    p_vkCmdDraw(s_cmd, count, 1, 0, 0);
}

/* 动态网格上传（三角形列表 pos2+uv2，stride 16B）：容量不足时重建
 * HOST_VISIBLE 顶点缓冲，之后持久映射指针直接 memcpy（非 COHERENT
 * 时手动 flush）。上帧提交已 QueueWaitIdle，此处无需同步队列。 */
static int vk_mesh_upload(int slot, const float* verts, int vert_count)
{
    VkDeviceSize bytes, cap;

    if (slot < 0 || slot >= SLR_CUSTOM_MESHES || !verts ||
        vert_count <= 0 || vert_count > SLR_CUSTOM_MAX_VERTS)
    {
        set_error(SLR_E_BAD_PARAM);
        return 0;
    }
    bytes = (VkDeviceSize)vert_count * 16;
    cap = (bytes + 0xFF) & ~(VkDeviceSize)0xFF;   /* 256B 对齐减少重建次数 */
    if (!s_vb_custom[slot] || s_vb_custom_cap[slot] < bytes)
    {
        vk_destroy_buffer(&s_vb_custom[slot], &s_vb_custom_mem[slot],
                          &s_vb_custom_ptr[slot]);
        s_vb_custom_cap[slot] = 0;
        if (!vk_make_buffer(&s_vb_custom[slot], &s_vb_custom_mem[slot], cap,
                            0x80, /* VK_BUFFER_USAGE_VERTEX_BUFFER_BIT */
                            VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | VK_MEMORY_PROPERTY_HOST_COHERENT_BIT,
                            &s_vb_custom_ptr[slot], &s_vb_custom_coh[slot]))
            return 0;
        s_vb_custom_cap[slot] = cap;
    }
    memcpy(s_vb_custom_ptr[slot], verts, (size_t)bytes);
    if (!s_vb_custom_coh[slot])
        vk_flush_mem(s_vb_custom_mem[slot], 0, bytes, 0);
    s_vb_custom_count[slot] = (uint32_t)vert_count;
    return 1;
}

/* 全屏 pass（post / blit 共用）：flush 前段 -> 采样屏障 -> 自含 pass */
static void vk_full_pass(SlrRhiTarget* dst, SlrRhiTarget* src, int w, int h,
                         int enabled, float bright, float sat, float vig)
{
    int idx = enabled ? VKP_POST : VKP_BLIT;
    VkDescriptorSet set;
    VkDeviceSize off = 0;
    float fx[4];

    vk_flush_pending();
    if (!vk_ensure_recording()) return;
    vk_transition_target(src, VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL);
    vk_open_pass(dst, w, h, NULL);
    p_vkCmdBindPipeline(s_cmd, (VkPipelineBindPoint)VK_PIPELINE_BIND_POINT_GRAPHICS, s_vk_pipes[idx]);
    if (enabled)
    {
        fx[0] = bright; fx[1] = sat; fx[2] = vig; fx[3] = 0.0f;
        p_vkCmdPushConstants(s_cmd, s_pl_layouts[idx],
                             (VkShaderStageFlagBits)VK_SHADER_STAGE_FRAGMENT_BIT, 0, 16, fx);
    }
    set = src->set_sampler;
    p_vkCmdBindDescriptorSets(s_cmd, (VkPipelineBindPoint)VK_PIPELINE_BIND_POINT_GRAPHICS,
                              s_pl_layouts[idx], 0, 1, &set, 0, NULL);
    p_vkCmdBindVertexBuffers(s_cmd, 0, 1, &s_vb[2], &off);
    p_vkCmdDraw(s_cmd, 3, 1, 0, 0);
    p_vkCmdEndRenderPass(s_cmd);
    s_pass_open = 0;
    s_pass_t = NULL;
    dst->layout = VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL;
}

static void vk_post_process(SlrRhiTarget* dst, SlrRhiTarget* src, int w, int h,
                            int enabled, float bright, float sat, float vig)
{
    vk_full_pass(dst, src, w, h, enabled, bright, sat, vig);
}

static void vk_blit(SlrRhiTarget* dst, SlrRhiTarget* src, int w, int h)
{
    vk_full_pass(dst, src, w, h, 0, 0.0f, 0.0f, 0.0f);
}

/* 阶段 13：回读（行 0 = 图像顶部，紧密行距，直接 memcpy）*/
static void vk_readback(SlrRhiTarget* t, int w, int h, int64_t dst_ptr)
{
    unsigned char* buf = (unsigned char*)(intptr_t)dst_ptr;
    VkDeviceSize need = (VkDeviceSize)w * h * 4;
    VkBufferImageCopy cp;

    vk_flush_pending();
    if (s_rd_size < need)
    {
        if (s_rdbuf) vk_destroy_buffer(&s_rdbuf, &s_rd_mem, &s_rd_ptr);
        s_rd_size = 0;
        if (!vk_make_buffer(&s_rdbuf, &s_rd_mem, need, 0x00000002 /* TRANSFER_DST */,
                            VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | VK_MEMORY_PROPERTY_HOST_COHERENT_BIT,
                            &s_rd_ptr, NULL))
            return;
        s_rd_size = need;
    }
    if (!vk_ensure_recording()) return;
    vk_transition_target(t, VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL);
    memset(&cp, 0, sizeof(cp));
    cp.imageSubresource.aspectMask = VK_IMAGE_ASPECT_COLOR_BIT;
    cp.imageSubresource.layerCount = 1;
    cp.imageExtent.width = (uint32_t)w;
    cp.imageExtent.height = (uint32_t)h;
    cp.imageExtent.depth = 1;
    p_vkCmdCopyImageToBuffer(s_cmd, t->color,
                             (VkImageLayout)VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL,
                             s_rdbuf, 1, &cp);
    if (!vk_submit_now()) return;
    memcpy(buf, s_rd_ptr, (size_t)need);
}

/* ===================================================================== */
/* v1 直连 pass                                                           */
/* ===================================================================== */
static void vk_v1_clear(SlrRhiTarget* t, int w, int h, const float* clear)
{
    vk_flush_pending();
    if (!vk_ensure_recording()) return;
    vk_open_pass(t, w, h, clear);
}

static void vk_v1_draw(SlrRhiTarget* t, int w, int h,
                       int prog, const float* mvp, const float* color, void* tex)
{
    int idx;
    VkDescriptorSet set;
    VkDeviceSize off = 0;
    struct { float m[16]; float c[4]; } pc;

    if (prog != SLR_PROG_FLAT && prog != SLR_PROG_TEX)
    {
        set_error(SLR_E_STATE);
        return;
    }
    if (!s_pass_open || s_pass_t != t)
    {
        vk_flush_pending();
        if (!vk_ensure_recording()) return;
        vk_open_pass(t, w, h, NULL);
    }
    idx = (prog == SLR_PROG_TEX && tex) ? VKP_V1_TEX : VKP_V1_FLAT;
    memcpy(pc.m, mvp, sizeof(pc.m));
    memcpy(pc.c, color, sizeof(pc.c));
    p_vkCmdBindPipeline(s_cmd, (VkPipelineBindPoint)VK_PIPELINE_BIND_POINT_GRAPHICS, s_vk_pipes[idx]);
    p_vkCmdPushConstants(s_cmd, s_pl_layouts[idx],
                         (VkShaderStageFlagBits)(VK_SHADER_STAGE_VERTEX_BIT | VK_SHADER_STAGE_FRAGMENT_BIT),
                         0, sizeof(pc), &pc);
    if (idx == VKP_V1_TEX)
    {
        set = ((VkTexture*)tex)->set_sampler;
        p_vkCmdBindDescriptorSets(s_cmd, (VkPipelineBindPoint)VK_PIPELINE_BIND_POINT_GRAPHICS,
                                  s_pl_layouts[idx], 0, 1, &set, 0, NULL);
    }
    p_vkCmdBindVertexBuffers(s_cmd, 0, 1, &s_vb[3], &off);
    p_vkCmdDraw(s_cmd, 3, 1, 0, 0);
}

/* ===================================================================== */
/* 初始化 / 销毁                                                           */
/* ===================================================================== */
static int vk_load_procs(void)
{
    int missing = 0;
#define LOAD_VK(name) \
    do { \
        p_##name = (PFN_##name)pfnEntry(s_inst, #name); \
        if (!p_##name) missing++; \
    } while (0);
    VKPROC_LIST(LOAD_VK)
#undef LOAD_VK
    if (missing)
    {
        char msg[64];
        _snprintf(msg, sizeof(msg) - 1, "Vulkan proc resolution missing %d symbols", missing);
        msg[sizeof(msg) - 1] = 0;
        set_error_detail(SLR_E_BACKEND, msg);
        return 0;
    }
    return 1;
}

static int vk_init(void)
{
    VkApplicationInfo app;
    VkInstanceCreateInfo ici;
    VkResult r;
    uint32_t count = 0, i;
    VkPhysicalDevice* devs = NULL;
    VkPhysicalDeviceProperties props;
    VkFormatProperties fp;
    VkQueueFamilyProperties* fams = NULL;
    float prio = 1.0f;
    VkDeviceQueueCreateInfo qci;
    VkDeviceCreateInfo dci;
    VkCommandPoolCreateInfo cpi;
    VkCommandBufferAllocateInfo cai;

    /* 1) vulkan-1.dll + 入口 */
    s_hvk = LoadLibraryA("vulkan-1.dll");
    if (!s_hvk)
    {
        set_error_detail(SLR_E_BACKEND, "vulkan-1.dll load failed");
        return 0;
    }
    pfnEntry = (PFN_vkGetInstanceProcAddr)GetProcAddress(s_hvk, "vkGetInstanceProcAddr");
    if (!pfnEntry)
    {
        set_error_detail(SLR_E_BACKEND, "vkGetInstanceProcAddr not found");
        return 0;
    }

    /* 2) instance（离屏：无扩展、无校验层）*/
    memset(&app, 0, sizeof(app));
    app.sType = VK_STRUCTURE_TYPE_APPLICATION_INFO;
    app.pApplicationName = "SLangRender";
    app.applicationVersion = 1;
    app.pEngineName = "SLangRender RHI";
    app.engineVersion = 1;
    app.apiVersion = VK_API_VERSION_1_0;
    memset(&ici, 0, sizeof(ici));
    ici.sType = VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO;
    ici.pApplicationInfo = &app;
    r = pfnEntry(NULL, "vkCreateInstance") != NULL
        ? ((PFN_vkCreateInstance)pfnEntry(NULL, "vkCreateInstance"))(&ici, NULL, &s_inst)
        : VK_ERROR_INITIALIZATION_FAILED;
    if (r != VK_SUCCESS)
    {
        set_error_detail(SLR_E_BACKEND, "vkCreateInstance failed (no Vulkan ICD?)");
        return 0;
    }

    /* 3) 全量函数解析 */
    if (!vk_load_procs()) return 0;

    /* 4) 物理设备：首个带图形队列族的 */
    if (p_vkEnumeratePhysicalDevices(s_inst, &count, NULL) != VK_SUCCESS || count == 0)
    {
        set_error_detail(SLR_E_BACKEND, "no Vulkan physical device");
        return 0;
    }
    devs = (VkPhysicalDevice*)malloc(sizeof(VkPhysicalDevice) * count);
    if (!devs) { set_error(SLR_E_MEMORY); return 0; }
    if (p_vkEnumeratePhysicalDevices(s_inst, &count, devs) != VK_SUCCESS) { free(devs); return 0; }
    for (i = 0; i < count; i++)
    {
        uint32_t fc = 0, j;
        p_vkGetPhysicalDeviceQueueFamilyProperties(devs[i], &fc, NULL);
        if (fc == 0) continue;
        fams = (VkQueueFamilyProperties*)malloc(sizeof(VkQueueFamilyProperties) * fc);
        if (!fams) break;
        p_vkGetPhysicalDeviceQueueFamilyProperties(devs[i], &fc, fams);
        for (j = 0; j < fc; j++)
        {
            if (fams[j].queueFlags & VK_QUEUE_GRAPHICS_BIT)
            {
                s_phys = devs[i];
                s_qfamily = j;
                break;
            }
        }
        free(fams); fams = NULL;
        if (s_phys) break;
    }
    free(devs);
    if (!s_phys)
    {
        set_error_detail(SLR_E_BACKEND, "no Vulkan graphics queue family");
        return 0;
    }

    /* 5) 设备信息 / 内存属性 / 深度格式 */
    memset(&props, 0, sizeof(props));
    p_vkGetPhysicalDeviceProperties(s_phys, &props);
    _snprintf(s_devname, sizeof(s_devname) - 1, "%s", props.deviceName);
    s_devname[sizeof(s_devname) - 1] = 0;
    s_api_version = props.apiVersion;
    p_vkGetPhysicalDeviceMemoryProperties(s_phys, &s_memprops);

    memset(&fp, 0, sizeof(fp));
    p_vkGetPhysicalDeviceFormatProperties(s_phys, (VkFormat)VK_FORMAT_D24_UNORM_S8_UINT, &fp);
    if (fp.optimalTilingFeatures & VK_FORMAT_FEATURE_DEPTH_STENCIL_ATTACHMENT_BIT)
    {
        s_depth_fmt = (VkFormat)VK_FORMAT_D24_UNORM_S8_UINT;
        s_depth_stencil = 1;
    }
    else
    {
        memset(&fp, 0, sizeof(fp));
        p_vkGetPhysicalDeviceFormatProperties(s_phys, (VkFormat)VK_FORMAT_D32_SFLOAT, &fp);
        if (fp.optimalTilingFeatures & VK_FORMAT_FEATURE_DEPTH_STENCIL_ATTACHMENT_BIT)
        {
            s_depth_fmt = (VkFormat)VK_FORMAT_D32_SFLOAT;
            s_depth_stencil = 0;
        }
        else
        {
            set_error_detail(SLR_E_BACKEND, "no supported depth format (D24S8/D32)");
            return 0;
        }
    }

    /* 6) 逻辑设备 + 图形队列 */
    memset(&qci, 0, sizeof(qci));
    qci.sType = VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO;
    qci.queueFamilyIndex = s_qfamily;
    qci.queueCount = 1;
    qci.pQueuePriorities = &prio;
    memset(&dci, 0, sizeof(dci));
    dci.sType = VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO;
    dci.queueCreateInfoCount = 1;
    dci.pQueueCreateInfos = &qci;
    if (!vk_check(p_vkCreateDevice(s_phys, &dci, NULL, &s_dev), "vkCreateDevice")) return 0;
    p_vkGetDeviceQueue(s_dev, s_qfamily, 0, &s_queue);

    /* 7) 命令池 + 主命令缓冲 */
    memset(&cpi, 0, sizeof(cpi));
    cpi.sType = VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO;
    cpi.flags = VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT;
    cpi.queueFamilyIndex = s_qfamily;
    if (!vk_check(p_vkCreateCommandPool(s_dev, &cpi, NULL, &s_pool), "vkCreateCommandPool")) return 0;
    memset(&cai, 0, sizeof(cai));
    cai.sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO;
    cai.commandPool = s_pool;
    cai.level = (VkCommandBufferLevel)VK_COMMAND_BUFFER_LEVEL_PRIMARY;
    cai.commandBufferCount = 1;
    if (!vk_check(p_vkAllocateCommandBuffers(s_dev, &cai, &s_cmd), "vkAllocateCommandBuffers")) return 0;

    if (!s_lock_init)
    {
        InitializeCriticalSection(&s_lock);
        s_lock_init = 1;
    }
    return 1;
}

static void vk_shutdown(void)
{
    if (s_dev) p_vkDeviceWaitIdle(s_dev);
    if (s_pool) { p_vkDestroyCommandPool(s_dev, s_pool, NULL); s_pool = NULL; }
    s_cmd = NULL;
    s_recording = 0;
    s_pass_open = 0;
    s_pass_t = NULL;
    if (s_dev) { p_vkDestroyDevice(s_dev, NULL); s_dev = NULL; }
    if (s_inst) { p_vkDestroyInstance(s_inst, NULL); s_inst = NULL; }
    s_phys = NULL;
    s_queue = NULL;
    if (s_hvk) { FreeLibrary(s_hvk); s_hvk = NULL; }
    pfnEntry = NULL;
    if (s_lock_init) { DeleteCriticalSection(&s_lock); s_lock_init = 0; }
}

static void vk_info(char* renderer, int rcap, char* version, int vcap)
{
    uint32_t major = (s_api_version >> 22) & 0x7F;
    uint32_t minor = (s_api_version >> 12) & 0x3FF;
    uint32_t patch = s_api_version & 0xFFF;
    _snprintf(renderer, (size_t)rcap - 1, "Vulkan (%s)", s_devname);
    renderer[rcap - 1] = 0;
    _snprintf(version, (size_t)vcap - 1, "Vulkan %u.%u.%u", major, minor, patch);
    version[vcap - 1] = 0;
}

static int vk_enter(void)
{
    EnterCriticalSection(&s_lock);
    return 1;
}

static void vk_exit(void) { LeaveCriticalSection(&s_lock); }

/* ===================================================================== */
/* vtable                                                                 */
/* ===================================================================== */
static const SlrRhi s_rhi_vk =
{
    "vk",
    vk_init,
    vk_shutdown,
    vk_info,
    vk_enter,
    vk_exit,
    vk_make_shared,
    vk_free_shared,
    vk_target_create,
    vk_target_destroy,
    vk_texture_create,
    vk_texture_destroy,
    vk_mesh_upload,
    vk_begin_scene,
    vk_camera_begin,
    vk_set_state,
    vk_upload_perdraw,
    vk_draw_item,
    vk_post_process,
    vk_blit,
    vk_readback,
    vk_v1_clear,
    vk_v1_draw,
    vk_desc_write_tex,
    vk_desc_bind_tex,
    vk_upload_lights,
};

const SlrRhi* slr_rhi_vk(void) { return &s_rhi_vk; }
