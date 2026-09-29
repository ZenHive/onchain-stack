Definitions.

INT        = [0-9]+
LETTERS    = [a-zA-Z_]+
WHITESPACE = [\s\t\n\r]
TYPES      = uint|int|address|bool|bytes|function|string

Rules.

indexed       : {token, {'indexed',         TokenLine, TokenChars}}.
fixed         : {token, {fixed_typename,    TokenLine, TokenChars}}.
ufixed        : {token, {ufixed_typename,   TokenLine, TokenChars}}.
{TYPES}       : {token, {typename,          TokenLine, TokenChars}}.
x             : {token, {'x',               TokenLine, TokenChars}}.
{INT}         : {token, {digits,            TokenLine, TokenChars}}.
{LETTERS}     : {token, {letters,           TokenLine, TokenChars}}.
\[            : {token, {'[',               TokenLine}}.
\]            : {token, {']',               TokenLine}}.
\(            : {token, {'(',               TokenLine}}.
\)            : {token, {')',               TokenLine}}.
,             : {token, {',',               TokenLine}}.
->            : {token, {'->',              TokenLine}}.
{WHITESPACE}+ : skip_token.

Erlang code.
