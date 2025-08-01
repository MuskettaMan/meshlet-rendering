const zwindows = @import("zwindows");
const d3d12 = zwindows.d3d12;
const hrPanicOnFail = zwindows.hrPanicOnFail;
const RasterResources = @import("raster_resources.zig").RasterResources;
const Geometry = @import("geometry.zig").Geometry;
const Dx12State = @import("dx12_state.zig").Dx12State;
const mesh_data = @import("mesh_data.zig");

pub const RasterPass = struct {
    root_signature: *d3d12.IRootSignature,
    pipeline: *d3d12.IPipelineState,
    resources: RasterResources,

    pub fn init(dx12: *const Dx12State, geometry: *const Geometry) RasterPass {
        const vs_cso = @embedFile("./shaders/main.vs.cso");
        const ps_cso = @embedFile("./shaders/main.ps.cso");

        const input_layout: [2]d3d12.INPUT_ELEMENT_DESC = .{
            d3d12.INPUT_ELEMENT_DESC.init("POSITION", 0, .R32G32B32_FLOAT, 0, @offsetOf(mesh_data.Vertex, "position"), .PER_VERTEX_DATA, 0),
            d3d12.INPUT_ELEMENT_DESC.init("NORMAL", 0, .R32G32B32_FLOAT, 0, @offsetOf(mesh_data.Vertex, "normal"), .PER_VERTEX_DATA, 0),
        };

        var pso_desc = d3d12.GRAPHICS_PIPELINE_STATE_DESC.initDefault();
        pso_desc.InputLayout = d3d12.INPUT_LAYOUT_DESC.init(&input_layout);
        pso_desc.VS = .{ .pShaderBytecode = vs_cso, .BytecodeLength = vs_cso.len };
        pso_desc.PS = .{ .pShaderBytecode = ps_cso, .BytecodeLength = ps_cso.len };
        pso_desc.PrimitiveTopologyType = .TRIANGLE;
        pso_desc.NumRenderTargets = 1;
        pso_desc.RTVFormats[0] = .R8G8B8A8_UNORM;
        pso_desc.DSVFormat = .D32_FLOAT;

        var root_signature: *d3d12.IRootSignature = undefined;
        hrPanicOnFail(dx12.device.CreateRootSignature(0, pso_desc.VS.pShaderBytecode.?, pso_desc.VS.BytecodeLength, &d3d12.IID_IRootSignature, @ptrCast(&root_signature)));

        var pipeline: *d3d12.IPipelineState = undefined;
        hrPanicOnFail(dx12.device.CreateGraphicsPipelineState(&pso_desc, &d3d12.IID_IPipelineState, @ptrCast(&pipeline)));

        const resources = RasterResources.init(geometry);

        return RasterPass{
            .root_signature = root_signature,
            .pipeline = pipeline,
            .resources = resources,
        };
    }

    pub fn deinit(self: *const RasterPass) void {
        _ = self.pipeline.Release();
        _ = self.root_signature.Release();
    }
};
