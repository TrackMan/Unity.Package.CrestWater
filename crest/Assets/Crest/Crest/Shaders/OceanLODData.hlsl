// Crest Ocean System

// This file is subject to the MIT License as seen in the root of this folder structure (LICENSE)

// Ocean LOD data - data, samplers and functions associated with LODs

// Conversions for world space from/to UV space. All these should *not* be clamped otherwise they'll break fullscreen triangles.
float2 LD_WorldToUV(in float2 i_samplePos, in float2 i_centerPos, in float i_res, in float i_texelSize)
{
	return (i_samplePos - i_centerPos) / (i_texelSize * i_res) + 0.5;
}

float3 WorldToUV(in float2 i_samplePos, in uint i_sliceIndex) {
	const float2 result = LD_WorldToUV(
		i_samplePos,
		_LD_Pos_Scale[i_sliceIndex].xy,
		_LD_Params[i_sliceIndex].y,
		_LD_Params[i_sliceIndex].x
	);
	return float3(result, i_sliceIndex);
}

float3 WorldToUV_BiggerLod(in float2 i_samplePos, in uint i_sliceIndex_BiggerLod) {
	const float2 result = LD_WorldToUV(
		i_samplePos, _LD_Pos_Scale[i_sliceIndex_BiggerLod].xy,
		_LD_Params[i_sliceIndex_BiggerLod].y,
		_LD_Params[i_sliceIndex_BiggerLod].x
	);
	return float3(result, i_sliceIndex_BiggerLod);
}

float3 WorldToUV_Source(in float2 i_samplePos, in uint i_sliceIndex_Source) {
	const float2 result = LD_WorldToUV(
		i_samplePos,
		_LD_Pos_Scale_Source[i_sliceIndex_Source].xy,
		_LD_Params_Source[i_sliceIndex_Source].y,
		_LD_Params_Source[i_sliceIndex_Source].x
	);
	return float3(result, i_sliceIndex_Source);
}


float2 LD_UVToWorld(in float2 i_uv, in float2 i_centerPos, in float i_res, in float i_texelSize)
{
	return i_texelSize * i_res * (i_uv - 0.5) + i_centerPos;
}

float2 UVToWorld(in float2 i_uv, in float i_sliceIndex) { return LD_UVToWorld(i_uv, _LD_Pos_Scale[i_sliceIndex].xy, _LD_Params[i_sliceIndex].y, _LD_Params[i_sliceIndex].x); }

// Shortcuts if _LD_SliceIndex is set
float3 WorldToUV(in float2 i_samplePos) { return WorldToUV(i_samplePos, _LD_SliceIndex); }
float3 WorldToUV_BiggerLod(in float2 i_samplePos) { return WorldToUV_BiggerLod(i_samplePos, _LD_SliceIndex + 1); }
float2 UVToWorld(in float2 i_uv) { return UVToWorld(i_uv, _LD_SliceIndex); }

// Convert compute shader id to uv texture coordinates
float2 IDtoUV(in float2 i_id, in float i_width, in float i_height)
{
	return (i_id + 0.5) / float2(i_width, i_height);
}


// Sampling functions
void SampleDisplacements(in Texture2DArray i_dispSampler, in float3 i_uv_slice, in float i_wt, inout float3 io_worldPos, inout half io_sss)
{
	const half4 data = i_dispSampler.SampleLevel(LODData_linear_clamp_sampler, i_uv_slice, 0.0);
	io_worldPos += i_wt * data.xyz;
	io_sss += i_wt * data.a;
}

void SampleDisplacementsNormals(in Texture2DArray i_dispSampler, in float3 i_uv_slice, in float i_wt, in float i_invRes, in float i_texelSize, inout float3 io_worldPos, inout half2 io_nxz, inout half io_sss)
{
	const half4 data = i_dispSampler.SampleLevel(LODData_linear_clamp_sampler, i_uv_slice, 0.0);
	io_sss += i_wt * data.a;
	const half3 disp = data.xyz;
	io_worldPos += i_wt * disp;

	float3 n; {
		float3 dd = float3(i_invRes, 0.0, i_texelSize);
		half3 disp_x = dd.zyy + i_dispSampler.SampleLevel(LODData_linear_clamp_sampler, i_uv_slice + float3(dd.xy, 0.0), dd.y).xyz;
		half3 disp_z = dd.yyz + i_dispSampler.SampleLevel(LODData_linear_clamp_sampler, i_uv_slice + float3(dd.yx, 0.0), dd.y).xyz;
		n = normalize(cross(disp_z - disp, disp_x - disp));
	}
	io_nxz += i_wt * n.xz;
}

void SampleFoam(in Texture2DArray i_oceanFoamSampler, in float3 i_uv_slice, in float i_wt, inout half io_foam)
{
	io_foam += i_wt * i_oceanFoamSampler.SampleLevel(LODData_linear_clamp_sampler, i_uv_slice, 0.0).x;
}

void SampleFlow(in Texture2DArray i_oceanFlowSampler, in float3 i_uv_slice, in float i_wt, inout half2 io_flow)
{
	io_flow += i_wt * i_oceanFlowSampler.SampleLevel(LODData_linear_clamp_sampler, i_uv_slice, 0.0).xy;
}

void SampleSeaDepth(in Texture2DArray i_oceanDepthSampler, in float3 i_uv_slice, in float i_wt, inout half io_oceanDepth)
{
	io_oceanDepth += i_wt * (i_oceanDepthSampler.SampleLevel(LODData_linear_clamp_sampler, i_uv_slice, 0.0).x - CREST_OCEAN_DEPTH_BASELINE);
}

void SampleClip(in Texture2DArray i_oceanClipSurfaceSampler, in float3 i_uv_slice, in float i_wt, inout half io_clipValue)
{
	io_clipValue += i_wt * (i_oceanClipSurfaceSampler.SampleLevel(LODData_linear_clamp_sampler, i_uv_slice, 0.0).x);
}

void SampleShadow(in Texture2DArray i_oceanShadowSampler, in float3 i_uv_slice, in float i_wt, inout half2 io_shadow)
{
	io_shadow += i_wt * i_oceanShadowSampler.SampleLevel(LODData_linear_clamp_sampler, i_uv_slice, 0.0).xy;
}

#define SampleLod(i_lodTextureArray, i_uv_slice) (i_lodTextureArray.SampleLevel(LODData_linear_clamp_sampler, i_uv_slice, 0.0))
#define SampleLodLevel(i_lodTextureArray, i_uv_slice, mips) (i_lodTextureArray.SampleLevel(LODData_linear_clamp_sampler, i_uv_slice, mips))

void PosToSliceIndices(const float2 worldXZ, const float meshScaleLerp, const float minSlice, out uint slice0, out uint slice1, out float lodAlpha)
{
	const float2 offsetFromCenter = abs(worldXZ - _OceanCenterPosWorld.xz);
	const float taxicab = max(offsetFromCenter.x, offsetFromCenter.y);
	const float radius0 = _LD_Pos_Scale[0].z;
	const float sliceNumber = clamp(log2(taxicab / radius0), minSlice, _SliceCount - 1.0);

	lodAlpha = frac(sliceNumber);
	slice0 = (uint)sliceNumber;
	slice1 = slice0 + 1;

	// lod alpha is remapped to ensure patches weld together properly. patches can vary significantly in shape (with
	// strips added and removed), and this variance depends on the base density of the mesh, as this defines the strip width.
	// using .15 as black and .85 as white should work for base mesh density as low as 16.
	const float BLACK_POINT = 0.15, WHITE_POINT = 0.85;
	lodAlpha = saturate((lodAlpha - BLACK_POINT) / (WHITE_POINT - BLACK_POINT));

	if (slice0 == 0)
	{
		// blend out lod0 when viewpoint gains altitude
		lodAlpha = min(lodAlpha + meshScaleLerp, 1.0);
	}
}
