const zwindows = @import("zwindows");
const d3d12 = zwindows.d3d12;
const hrPanicOnFail = zwindows.hrPanicOnFail;
const MeshletResources = @import("meshlet_resources.zig").MeshletResources;
const Geometry = @import("geometry.zig").Geometry;
const Dx12State = @import("dx12_state.zig").Dx12State;

pub const MeshletPass = struct {
    root_signature: *d3d12.IRootSignature,
    pipeline: *d3d12.IPipelineState,
    resources: MeshletResources,

    pub fn init(dx12: *const Dx12State, geometry: *const Geometry) MeshletPass {
        const ms_cso = @embedFile("./shaders/main.ms.cso");
        const ps_cso = @embedFile("./shaders/main.ps.cso");

        var mesh_state_desc = d3d12.MESH_SHADER_PIPELINE_STATE_DESC.initDefault();
        mesh_state_desc.RTVFormats[0] = .R8G8B8A8_UNORM;
        mesh_state_desc.DepthStencilState = d3d12.DEPTH_STENCIL_DESC1.initDefault();
        mesh_state_desc.DSVFormat = .D32_FLOAT;
        mesh_state_desc.NumRenderTargets = 1;
        mesh_state_desc.MS = .{ .pShaderBytecode = ms_cso, .BytecodeLength = ms_cso.len };
        mesh_state_desc.PS = .{ .pShaderBytecode = ps_cso, .BytecodeLength = ps_cso.len };

        var stream = d3d12.PIPELINE_MESH_STATE_STREAM.init(mesh_state_desc);

        var root_signature: *d3d12.IRootSignature = undefined;
        hrPanicOnFail(dx12.device.CreateRootSignature(0, mesh_state_desc.MS.pShaderBytecode.?, mesh_state_desc.MS.BytecodeLength, &d3d12.IID_IRootSignature, @ptrCast(&root_signature)));

        var pipeline: *d3d12.IPipelineState = undefined;
        hrPanicOnFail(dx12.device.CreatePipelineState(&d3d12.PIPELINE_STATE_STREAM_DESC{ .SizeInBytes = @sizeOf(@TypeOf(stream)), .pPipelineStateSubobjectStream = @ptrCast(&stream) }, &d3d12.IID_IPipelineState, @ptrCast(&pipeline)));

        const resources = MeshletResources.init(geometry, dx12);

        return MeshletPass{
            .root_signature = root_signature,
            .pipeline = pipeline,
            .resources = resources,
        };
    }

    pub fn deinit(self: *MeshletPass) void {
        _ = self.pipeline.Release();
        _ = self.root_signature.Release();
        self.resources.deinit();
    }
};
