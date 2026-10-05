// HLSL / Cg grammar for highlight.js v11 (Unity .hlsl/.cginc/.compute, DirectX .fx/.usf).
// Lumi karar 111 — loaded after highlight.min.js, before shaderlab.js (which embeds it).
hljs.registerLanguage('hlsl', function (hljs) {
  var SCALARS = ['bool', 'int', 'uint', 'dword', 'half', 'float', 'double', 'fixed',
    'min16float', 'min10float', 'min16int', 'min12int', 'min16uint',
    'int16_t', 'uint16_t', 'int64_t', 'uint64_t', 'float16_t', 'float32_t', 'float64_t'];

  var vectorTypes = [];
  SCALARS.forEach(function (s) {
    vectorTypes.push(s);
    for (var n = 1; n <= 4; n++) {
      vectorTypes.push(s + n);
      for (var m = 1; m <= 4; m++) vectorTypes.push(s + n + 'x' + m);
    }
  });

  var RESOURCE_TYPES = [
    'void', 'string', 'matrix', 'vector', 'snorm', 'unorm',
    'sampler', 'sampler1D', 'sampler2D', 'sampler3D', 'samplerCUBE', 'samplerRECT',
    'sampler2D_float', 'sampler2D_half', 'sampler2DShadow', 'sampler_state',
    'SamplerState', 'SamplerComparisonState',
    'Texture', 'Texture1D', 'Texture1DArray', 'Texture2D', 'Texture2DArray', 'Texture2DMS',
    'Texture2DMSArray', 'Texture3D', 'TextureCube', 'TextureCubeArray',
    'RWTexture1D', 'RWTexture1DArray', 'RWTexture2D', 'RWTexture2DArray', 'RWTexture3D',
    'RasterizerOrderedTexture2D', 'FeedbackTexture2D',
    'Buffer', 'RWBuffer', 'StructuredBuffer', 'RWStructuredBuffer',
    'AppendStructuredBuffer', 'ConsumeStructuredBuffer',
    'ByteAddressBuffer', 'RWByteAddressBuffer', 'ConstantBuffer',
    'InputPatch', 'OutputPatch', 'PointStream', 'LineStream', 'TriangleStream',
    'RaytracingAccelerationStructure', 'RayDesc', 'BuiltInTriangleIntersectionAttributes'
  ];

  var KEYWORDS = [
    'break', 'continue', 'discard', 'do', 'else', 'for', 'if', 'return', 'switch', 'case',
    'default', 'while', 'struct', 'class', 'interface', 'namespace', 'cbuffer', 'tbuffer',
    'typedef', 'const', 'static', 'uniform', 'volatile', 'inline', 'in', 'out', 'inout',
    'extern', 'shared', 'groupshared', 'precise', 'nointerpolation', 'linear', 'centroid',
    'noperspective', 'sample', 'register', 'packoffset', 'row_major', 'column_major',
    'globallycoherent', 'point', 'line', 'triangle', 'lineadj', 'triangleadj', 'export',
    'technique', 'technique10', 'technique11', 'pass', 'compile', 'template', 'typename',
    'sizeof', 'unsigned', 'payload', 'vertices', 'indices', 'primitives'
  ];

  var INTRINSICS = [
    'abort', 'abs', 'acos', 'all', 'AllMemoryBarrier', 'AllMemoryBarrierWithGroupSync', 'any',
    'asdouble', 'asfloat', 'asin', 'asint', 'asuint', 'atan', 'atan2', 'ceil', 'clamp', 'clip',
    'cos', 'cosh', 'countbits', 'cross', 'D3DCOLORtoUBYTE4', 'ddx', 'ddx_coarse', 'ddx_fine',
    'ddy', 'ddy_coarse', 'ddy_fine', 'degrees', 'determinant', 'DeviceMemoryBarrier',
    'DeviceMemoryBarrierWithGroupSync', 'distance', 'dot', 'dst', 'errorf', 'EvaluateAttributeAtCentroid',
    'EvaluateAttributeAtSample', 'EvaluateAttributeSnapped', 'exp', 'exp2', 'f16tof32', 'f32tof16',
    'faceforward', 'firstbithigh', 'firstbitlow', 'floor', 'fma', 'fmod', 'frac', 'frexp', 'fwidth',
    'GetRenderTargetSampleCount', 'GetRenderTargetSamplePosition', 'GroupMemoryBarrier',
    'GroupMemoryBarrierWithGroupSync', 'InterlockedAdd', 'InterlockedAnd', 'InterlockedCompareExchange',
    'InterlockedCompareStore', 'InterlockedExchange', 'InterlockedMax', 'InterlockedMin',
    'InterlockedOr', 'InterlockedXor', 'isfinite', 'isinf', 'isnan', 'ldexp', 'length', 'lerp', 'lit',
    'log', 'log10', 'log2', 'mad', 'max', 'min', 'modf', 'msad4', 'mul', 'noise', 'normalize', 'pow',
    'printf', 'Process2DQuadTessFactorsAvg', 'ProcessIsolineTessFactors', 'ProcessQuadTessFactorsAvg',
    'ProcessTriTessFactorsAvg', 'radians', 'rcp', 'reflect', 'refract', 'reversebits', 'round',
    'rsqrt', 'saturate', 'sign', 'sin', 'sincos', 'sinh', 'smoothstep', 'sqrt', 'step', 'tan', 'tanh',
    'tex1D', 'tex1Dbias', 'tex1Dgrad', 'tex1Dlod', 'tex1Dproj', 'tex2D', 'tex2Dbias', 'tex2Dgrad',
    'tex2Dlod', 'tex2Dproj', 'tex3D', 'tex3Dbias', 'tex3Dgrad', 'tex3Dlod', 'tex3Dproj', 'texCUBE',
    'texCUBEbias', 'texCUBEgrad', 'texCUBElod', 'texCUBEproj', 'transpose', 'trunc',
    'WaveActiveAllTrue', 'WaveActiveAnyTrue', 'WaveActiveSum', 'WaveActiveMax', 'WaveActiveMin',
    'WaveGetLaneIndex', 'WaveGetLaneCount', 'WaveIsFirstLane', 'WaveReadLaneFirst', 'WaveReadLaneAt',
    'TraceRay', 'ReportHit', 'AcceptHitAndEndSearch', 'IgnoreHit', 'DispatchRaysIndex', 'DispatchRaysDimensions',
    // Unity built-in pipeline helpers (UnityCG.cginc)
    'UnityObjectToClipPos', 'UnityObjectToViewPos', 'UnityObjectToWorldNormal', 'UnityObjectToWorldDir',
    'UnityWorldToClipPos', 'UnityWorldToViewPos', 'UnityWorldSpaceViewDir', 'UnityWorldSpaceLightDir',
    'WorldSpaceViewDir', 'ObjSpaceViewDir', 'WorldSpaceLightDir', 'ShadeSH9', 'UnpackNormal',
    'UnpackScaleNormal', 'UnpackNormalScale', 'ComputeScreenPos', 'ComputeGrabScreenPos',
    'LinearEyeDepth', 'Linear01Depth', 'DecodeHDR', 'GammaToLinearSpace', 'LinearToGammaSpace',
    'Luminance', 'EncodeFloatRGBA', 'DecodeFloatRGBA', 'TRANSFORM_TEX', 'LIGHT_ATTENUATION',
    'SHADOW_ATTENUATION', 'TRANSFER_SHADOW', 'SHADOW_COORDS', 'LIGHTING_COORDS', 'TRANSFER_VERTEX_TO_FRAGMENT',
    'V2F_SHADOW_CASTER', 'TRANSFER_SHADOW_CASTER_NORMALOFFSET', 'SHADOW_CASTER_FRAGMENT',
    // Unity SRP core / URP helpers
    'TransformObjectToHClip', 'TransformObjectToWorld', 'TransformWorldToHClip', 'TransformWorldToView',
    'TransformObjectToWorldNormal', 'TransformObjectToWorldDir', 'TransformWorldToObject',
    'GetVertexPositionInputs', 'GetVertexNormalInputs', 'GetWorldSpaceViewDir', 'GetWorldSpaceNormalizeViewDir',
    'GetCameraPositionWS', 'GetMainLight', 'GetAdditionalLight', 'GetAdditionalLightsCount',
    'GetShadowCoord', 'TransformWorldToShadowCoord', 'MainLightRealtimeShadow', 'SampleSH', 'SampleSHVertex',
    'SampleSHPixel', 'UniversalFragmentPBR', 'UniversalFragmentBlinnPhong', 'InitializeStandardLitSurfaceData',
    'SampleAlbedoAlpha', 'SampleNormal', 'SampleEmission', 'MixFog', 'ComputeFogFactor',
    'AlphaDiscard', 'SafeNormalize', 'SampleSceneDepth', 'SampleSceneColor', 'LinearDepthToEyeDepth',
    'GetNormalizedScreenSpaceUV', 'ComputeNormalizedDeviceCoordinatesWithZ', 'PackNormalOctQuadEncode',
    'SAMPLE_TEXTURE2D', 'SAMPLE_TEXTURE2D_LOD', 'SAMPLE_TEXTURE2D_BIAS', 'SAMPLE_TEXTURE2D_GRAD',
    'SAMPLE_TEXTURE2D_ARRAY', 'SAMPLE_TEXTURE2D_ARRAY_LOD', 'SAMPLE_TEXTURE2D_X', 'SAMPLE_TEXTURE3D',
    'SAMPLE_TEXTURE3D_LOD', 'SAMPLE_TEXTURECUBE', 'SAMPLE_TEXTURECUBE_LOD', 'SAMPLE_DEPTH_TEXTURE',
    'SAMPLE_DEPTH_TEXTURE_LOD', 'LOAD_TEXTURE2D', 'LOAD_TEXTURE2D_LOD', 'LOAD_TEXTURE2D_X',
    'TEXTURE2D', 'TEXTURE2D_ARRAY', 'TEXTURE2D_SHADOW', 'TEXTURE3D', 'TEXTURECUBE', 'TEXTURE2D_FLOAT',
    'SAMPLER', 'SAMPLER_CMP', 'TEXTURE2D_PARAM', 'TEXTURE2D_ARGS', 'CBUFFER_START', 'CBUFFER_END',
    'TEXTURE2D_SAMPLER2D', 'SAMPLE_TEXTURE2D_SAMPLER', 'TEXTURE2D_X', 'TEXTURECUBE_ARRAY', 'ZERO_INITIALIZE', 'real', 'real2', 'real3',
    'real4', 'real3x3', 'real4x4',
    // Unity built-in variables
    '_Time', '_SinTime', '_CosTime', 'unity_DeltaTime', '_WorldSpaceCameraPos', '_ProjectionParams',
    '_ScreenParams', '_ZBufferParams', 'unity_OrthoParams', '_WorldSpaceLightPos0', '_LightColor0',
    'unity_ObjectToWorld', 'unity_WorldToObject', 'unity_CameraProjection', 'unity_MatrixVP',
    '_MainLightPosition', '_MainLightColor', '_CameraDepthTexture', '_CameraOpaqueTexture', '_GlobalMipBias'
  ];

  // Control-flow words that look like `word name(` and must not become a function definition.
  var NOT_DECL = '(?!(?:return|else|if|for|while|switch|do|case|new|discard)\\b)';
  var IDENT = /[A-Za-z_]\w*/;

  var SEMANTIC = /(?:SV_[A-Za-z]+\d*|(?:POSITIONT|POSITION|NORMAL|TANGENT|BINORMAL|COLOR|TEXCOORD|BLENDWEIGHT|BLENDINDICES|PSIZE|FOG|DEPTH|TESSFACTOR|VFACE|VPOS|INTERNALTESSPOS)\d*)\b/;

  var PREPROCESSOR = {
    scope: 'meta',
    begin: /^[ \t]*#[ \t]*[a-zA-Z_]\w*/,
    end: /$/,
    relevance: 0,
    contains: [
      { begin: /\\\n/, relevance: 0 }, // line continuation
      { scope: 'string', begin: /"/, end: /"/, illegal: null, contains: [hljs.BACKSLASH_ESCAPE] },
      { scope: 'string', begin: /<[^>\n]+>/ },
      hljs.C_LINE_COMMENT_MODE,
      hljs.C_BLOCK_COMMENT_MODE
    ]
  };

  var ATTRIBUTE = {
    scope: 'meta',
    begin: /\[\s*(?:numthreads|unroll|loop|branch|flatten|fastopt|allow_uav_condition|call|forcecase|maxvertexcount|domain|partitioning|outputtopology|outputcontrolpoints|patchconstantfunc|maxtessfactor|earlydepthstencil|instance|RootSignature|shader|WaveSize|NodeLaunch|NodeDispatchGrid|NumThreads)\b/,
    end: /\]/,
    relevance: 2,
    contains: [
      hljs.QUOTE_STRING_MODE,
      { scope: 'number', begin: /\b\d+\b/, relevance: 0 }
    ]
  };

  var NUMBER = {
    scope: 'number',
    relevance: 0,
    match: /\b0[xX][\da-fA-F]+[uUlL]*|(?:\b\d+(?:\.\d*)?|\.\d+)(?:[eE][-+]?\d+)?[fFhHlLuU]*/
  };

  var SEMANTIC_MODE = {
    match: [/:/, /[ \t]*/, SEMANTIC],
    scope: { 3: 'meta' },
    relevance: 2
  };

  var TYPE_DECL = {
    match: [/\b(?:struct|cbuffer|tbuffer|class|interface|namespace)\b/, /\s+/, IDENT],
    scope: { 1: 'keyword', 3: 'title.class' }
  };

  var FUNCTION_DECL = {
    match: [new RegExp('\\b' + NOT_DECL + '[A-Za-z_]\\w*(?:<[\\w \\t,]*>)?'), /[ \t]+/,
      new RegExp(NOT_DECL + '[A-Za-z_]\\w*'), /(?=\s*\()/],
    scope: { 1: 'type', 3: 'title.function' }
  };

  return {
    name: 'HLSL',
    aliases: ['hlsli', 'cginc', 'compute', 'fx', 'fxh', 'usf', 'ush'],
    keywords: {
      keyword: KEYWORDS,
      type: RESOURCE_TYPES.concat(vectorTypes),
      built_in: INTRINSICS,
      literal: ['true', 'false', 'NULL']
    },
    contains: [
      hljs.C_LINE_COMMENT_MODE,
      hljs.C_BLOCK_COMMENT_MODE,
      PREPROCESSOR,
      { scope: 'string', begin: /"/, end: /"/, contains: [hljs.BACKSLASH_ESCAPE] },
      ATTRIBUTE,
      SEMANTIC_MODE,
      TYPE_DECL,
      FUNCTION_DECL,
      { scope: 'built_in', match: /\bUNITY_[A-Z0-9_]+\b/, relevance: 0 },
      NUMBER
    ]
  };
});
