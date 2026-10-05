// Unity ShaderLab (.shader) grammar for highlight.js v11; program blocks delegate to hlsl/glsl.
// Lumi karar 111 — loaded after hlsl.js (CGPROGRAM/HLSLPROGRAM content uses subLanguage 'hlsl').
hljs.registerLanguage('shaderlab', function (hljs) {
  var KEYWORDS = [
    'Shader', 'Properties', 'SubShader', 'Pass', 'Tags', 'LOD', 'Cull', 'ZWrite', 'ZTest', 'ZClip',
    'Blend', 'BlendOp', 'ColorMask', 'ColorMaterial', 'Stencil', 'Fallback', 'CustomEditor',
    'CustomEditorForRenderPipeline', 'Name', 'UsePass', 'GrabPass', 'Category', 'Offset',
    'AlphaToMask', 'AlphaTest', 'Conservative', 'Dependency', 'PackageRequirements', 'Lighting',
    'Material', 'SeparateSpecular', 'SetTexture', 'Combine', 'ConstantColor', 'Fog', 'Mode',
    'Density', 'Range', 'BindChannels', 'Bind', 'Ref', 'ReadMask', 'WriteMask', 'Comp', 'Fail',
    'ZFail', 'CompFront', 'PassFront', 'FailFront', 'ZFailFront', 'CompBack', 'PassBack',
    'FailBack', 'ZFailBack', 'Diffuse', 'Ambient', 'Specular', 'Shininess', 'Emission'
  ];

  var LITERALS = [
    'On', 'Off', 'Back', 'Front', 'True', 'False', 'One', 'Zero', 'SrcColor', 'SrcAlpha', 'DstColor',
    'DstAlpha', 'OneMinusSrcColor', 'OneMinusSrcAlpha', 'OneMinusDstColor', 'OneMinusDstAlpha',
    'SrcAlphaSaturate', 'Less', 'Greater', 'LEqual', 'GEqual', 'Equal', 'NotEqual', 'Always', 'Never',
    'Keep', 'Replace', 'IncrSat', 'DecrSat', 'Invert', 'IncrWrap', 'DecrWrap', 'Add', 'Sub', 'RevSub',
    'Min', 'Max', 'LogicalClear', 'LogicalSet', 'LogicalCopy', 'LogicalNoop', 'LogicalInvert',
    'LogicalAnd', 'LogicalOr', 'LogicalXor', 'Multiply', 'Screen', 'Overlay', 'Darken', 'Lighten',
    'Previous', 'Primary', 'Texture', 'Constant', 'Double', 'Quad', 'Global', 'Linear', 'Exp', 'Exp2'
  ];

  // Block markers: begin marker, end marker, embedded language.
  function programBlock(beginMarker, endMarker, language) {
    return {
      begin: new RegExp('\\b' + beginMarker + '\\b'),
      end: new RegExp('\\b' + endMarker + '\\b'),
      beginScope: 'keyword',
      endScope: 'keyword',
      subLanguage: language,
      relevance: 10
    };
  }

  var PROPERTY_TYPE = {
    // `("Albedo", 2D)` — the display string followed by the property type.
    match: [/"[^"\n]*"/, /[ \t]*,[ \t]*/,
      /(?:2DArray|3DArray|CubeArray|2D|3D|Cube|Color|Vector|Float|Integer|Int|Range|Any)\b/],
    scope: { 1: 'string', 3: 'type' }
  };

  var PROPERTY_NAME = {
    scope: 'variable',
    match: /\b[A-Za-z_]\w*(?=[ \t]*\([ \t]*")/,
    relevance: 0
  };

  return {
    name: 'ShaderLab',
    aliases: ['shader'],
    case_insensitive: true,
    keywords: {
      keyword: KEYWORDS,
      literal: LITERALS
    },
    contains: [
      hljs.C_LINE_COMMENT_MODE,
      hljs.C_BLOCK_COMMENT_MODE,
      programBlock('CGPROGRAM', 'ENDCG', 'hlsl'),
      programBlock('CGINCLUDE', 'ENDCG', 'hlsl'),
      programBlock('HLSLPROGRAM', 'ENDHLSL', 'hlsl'),
      programBlock('HLSLINCLUDE', 'ENDHLSL', 'hlsl'),
      programBlock('GLSLPROGRAM', 'ENDGLSL', 'glsl'),
      programBlock('GLSLINCLUDE', 'ENDGLSL', 'glsl'),
      PROPERTY_TYPE,
      PROPERTY_NAME,
      { scope: 'variable', match: /\[[ \t]*_\w*[ \t]*\]/, relevance: 0 },
      { scope: 'meta', match: /\[[ \t]*[A-Za-z][^\]\n]{0,200}\]/, relevance: 0 },
      { scope: 'string', begin: /"/, end: /"/, contains: [hljs.BACKSLASH_ESCAPE] },
      hljs.C_NUMBER_MODE
    ]
  };
});
