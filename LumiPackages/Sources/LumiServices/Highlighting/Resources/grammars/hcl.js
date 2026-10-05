// highlight.js v11 language grammar: HCL2 / Terraform / Nomad (.tf, .tfvars, .hcl, .nomad).
// Lumi karar 111 — hljs.registerLanguage('hcl'), highlight.min.js'ten sonra değerlendirilir.
hljs.registerLanguage('hcl', function (hljs) {
  const IDENT = /[A-Za-z_][\w-]*/;
  const EXPR = []; // expression modes; filled below (SUBST refers to it recursively)

  const SUBST = {
    scope: 'subst',
    begin: /[$%]\{~?/,
    end: /~?\}/,
    contains: EXPR
  };
  const ESCAPED_INTERP = { begin: /\$\$\{|%%\{/, relevance: 0 };
  const STRING = {
    scope: 'string',
    begin: /"/,
    end: /"/,
    contains: [hljs.BACKSLASH_ESCAPE, ESCAPED_INTERP, SUBST]
  };
  const HEREDOC = {
    scope: 'string',
    begin: /<<-?[ \t]*([A-Za-z_]\w*)[ \t]*$/,
    end: /^[ \t]*([A-Za-z_]\w*)[ \t]*$/,
    'on:begin': (m, resp) => { resp.data.heredocId = m[1]; },
    'on:end': (m, resp) => { if (resp.data.heredocId !== m[1]) resp.ignoreMatch(); },
    contains: [ESCAPED_INTERP, SUBST]
  };
  const NUMBER = {
    scope: 'number',
    begin: /\b\d+(?:\.\d+)?(?:[eE][+-]?\d+)?\b/,
    relevance: 0
  };
  const ROOT_VAR = {
    scope: 'variable',
    begin: /\b(?:var|local|module|data|each|count|self)\b(?=\.)/
  };
  const ROOT_BUILTIN = {
    scope: 'built_in',
    begin: /\b(?:path|terraform)\b(?=\.)/
  };
  const PROPERTY = {
    scope: 'property',
    begin: /(?<=[\w\]]\.)[A-Za-z_][\w-]*/,
    relevance: 0
  };
  const TYPE = {
    scope: 'type',
    variants: [
      { begin: /\b(?:string|number|bool|any)\b/ },
      { begin: /\b(?:list|map|set|object|tuple|optional)\b(?=\()/ }
    ]
  };
  const FUNCTION = {
    scope: 'built_in',
    begin: /\b[a-z][a-z0-9_]*(?=\()/,
    relevance: 0
  };
  const ATTR = {
    scope: 'attr',
    variants: [
      { begin: /\b[A-Za-z_][\w-]*(?=[ \t]*=(?![=>]))/ },
      { begin: /"[^"\n$%]*"(?=[ \t]*=(?![=>]))/ }
    ],
    relevance: 0
  };
  const KEYWORD = { scope: 'keyword', begin: /\b(?:for|in|if|else|endif|endfor)\b/, relevance: 0 };
  const LITERAL = { scope: 'literal', begin: /\b(?:true|false|null)\b/, relevance: 0 };
  const OPERATOR = {
    scope: 'operator',
    begin: /=>|\.\.\.|[-+*\/%!<>=&|?:]+/,
    relevance: 0
  };
  const PUNCT = { scope: 'punctuation', begin: /[()\[\],.]/, relevance: 0 };
  const BRACES = {
    begin: /\{/,
    end: /\}/,
    beginScope: 'punctuation',
    endScope: 'punctuation',
    contains: EXPR
  };
  const STRAY_BRACE = { scope: 'punctuation', begin: /\}/, relevance: 0 };

  // Block header: `resource "type" "name" {`, `locals {`, `ingress {`
  const BLOCK_LABELED = {
    begin: [/^[ \t]*/, IDENT, /[ \t]+/, /"[^"\n]*"/, /[ \t]*/, /(?:"[^"\n]*")?/, /(?=[ \t]*\{)/],
    beginScope: { 2: 'keyword', 4: 'title.class', 6: 'title.function' }
  };
  const BLOCK_BARE = {
    begin: [/^[ \t]*/, IDENT, /(?=[ \t]*\{)/],
    beginScope: { 2: 'keyword' }
  };

  EXPR.push(
    BLOCK_LABELED,
    BLOCK_BARE,
    hljs.HASH_COMMENT_MODE,
    hljs.C_LINE_COMMENT_MODE,
    hljs.C_BLOCK_COMMENT_MODE,
    HEREDOC,
    STRING,
    KEYWORD,
    LITERAL,
    ROOT_VAR,
    ROOT_BUILTIN,
    PROPERTY,
    TYPE,
    FUNCTION,
    ATTR,
    NUMBER,
    OPERATOR,
    BRACES,
    PUNCT
  );

  return {
    name: 'HCL',
    aliases: ['tf', 'tfvars', 'terraform', 'nomad', 'hcl2'],
    contains: EXPR.concat([STRAY_BRACE])
  };
});
