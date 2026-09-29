Terminals '(' ')' '[' ']' ',' '->' 'x' typename fixed_typename ufixed_typename 'indexed' letters digits 'expecting selector' 'expecting type'.
Nonterminals dispatch selector nontrivial_selector comma_delimited_types type_with_subscripts type_index_name array_subscripts tuple array_subscript identifier  identifier_parts identifier_part type typespec.
Rootsymbol dispatch.
%% Expect 3 shift/reduce conflicts:
%%   1. `dispatch` rules allow both a bare `tuple` and a `nontrivial_selector`
%%      that begins with a `typespec` (which can also be a tuple), making this
%%      ambiguity structural rather than a bug.
%%   2-3. After `fixed_typename` / `ufixed_typename` with lookahead `digits`,
%%      the parser can either shift toward `type -> fixed_typename digits 'x'
%%      digits` (the explicit-M/N fixed-point form) or reduce
%%      `identifier_part -> fixed_typename` to start an identifier. Yecc
%%      defaults to shift, which is the desired behavior in `'expecting
%%      type'` dispatch mode — `fixed128x18` parses as a type and routes to
%%      the `ABI.Parser.reject_unsupported!/1` walker. In no-prefix dispatch
%%      mode (used by `ABI.FunctionSelector.decode/1` for full selectors),
%%      the LALR state only reaches the identifier path, so function names
%%      like `fixed128(uint256)` and `fixed128x18(uint256)` still parse
%%      cleanly as identifiers.
Expect 3.

dispatch -> 'expecting type' type_with_subscripts : {type, '$2'}.
dispatch -> 'expecting selector' selector : {selector, '$2'}.
dispatch -> tuple : {selector, #{function => nil, types => lists:map(fun wrap_type/1, ['$1']), returns => nil}}.
dispatch -> nontrivial_selector : {selector, '$1'}.

selector -> typespec : #{function => nil, types => '$1', returns => nil}.
selector -> nontrivial_selector : '$1'.

nontrivial_selector -> typespec '->' type : #{function => nil, types => '$1', returns => '$3'}.
nontrivial_selector -> identifier typespec : #{function => '$1', types => '$2', returns => nil}.
nontrivial_selector -> identifier typespec '->' type : #{function => '$1', types => '$2', returns => '$4'}.

typespec -> '(' ')' : [].
typespec -> '(' comma_delimited_types ')' : '$2'.

tuple -> '(' ')' : {tuple, []}.
tuple -> '(' comma_delimited_types ')' : {tuple, lists:map(fun get_type/1, '$2')}.

comma_delimited_types -> type_index_name : ['$1'].
comma_delimited_types -> type_index_name ',' comma_delimited_types : ['$1' | '$3'].

identifier -> identifier_parts : iolist_to_binary('$1').

identifier_parts -> identifier_part : ['$1'].
identifier_parts -> identifier_part identifier_parts : ['$1' | '$2'].

identifier_part -> typename : v('$1').
identifier_part -> fixed_typename : v('$1').
identifier_part -> ufixed_typename : v('$1').
identifier_part -> 'x' : v('$1').
identifier_part -> letters : v('$1').
identifier_part -> digits : v('$1').

type_index_name -> type_with_subscripts : #{type => '$1'}.
type_index_name -> type_with_subscripts 'indexed' : #{type => '$1', indexed => true}.
type_index_name -> type_with_subscripts 'indexed' identifier : #{type => '$1', name => '$3', indexed => true}.
type_index_name -> type_with_subscripts identifier : #{type => '$1', name => '$2'}.

type_with_subscripts -> type : '$1'.
type_with_subscripts -> type array_subscripts : with_subscripts('$1', '$2').

array_subscripts -> array_subscript : ['$1'].
array_subscripts -> array_subscript array_subscripts : ['$1' | '$2'].

array_subscript -> '[' ']' : variable.
array_subscript -> '[' digits ']' : list_to_integer(v('$2')).

type -> typename :
  plain_type(list_to_atom(v('$1'))).
type -> typename digits :
  juxt_type(list_to_atom(v('$1')), list_to_integer(v('$2'))).
type -> fixed_typename :
  plain_type(fixed).
type -> fixed_typename digits 'x' digits :
  double_juxt_type(fixed, 'x', list_to_integer(v('$2')), list_to_integer(v('$4'))).
type -> ufixed_typename :
  plain_type(ufixed).
type -> ufixed_typename digits 'x' digits :
  double_juxt_type(ufixed, 'x', list_to_integer(v('$2')), list_to_integer(v('$4'))).
type -> tuple : '$1'.


Erlang code.

v({_Token, _Line, Value}) -> Value.

plain_type(address) -> address;
plain_type(bool) -> bool;
plain_type(function) -> function;
plain_type(string) -> string;
plain_type(bytes) -> bytes;
plain_type(int) -> juxt_type(int, 256);
plain_type(uint) -> juxt_type(uint, 256);
plain_type(fixed) -> double_juxt_type(fixed, 'x', 128, 18);
plain_type(ufixed) -> double_juxt_type(ufixed, 'x', 128, 18).

with_subscripts(Type, []) -> Type;
with_subscripts(Type, [H | T]) -> with_subscripts(with_subscript(Type, H), T).

with_subscript(Type, variable) -> {array, Type};
with_subscript(Type, N) when is_integer(N), N >= 0 -> {array, Type, N}.

juxt_type(int, M) when M > 0, M =< 256, (M rem 8) =:= 0 -> {int, M};
juxt_type(uint, M) when M > 0, M =< 256, (M rem 8) =:= 0 -> {uint, M};
juxt_type(bytes, M) when M > 0, M =< 32 -> {bytes, M}.

double_juxt_type(fixed, 'x', M, N) when M >= 0, M =< 256, (M rem 8) =:= 0, N > 0, N =< 80 -> {fixed, M, N};
double_juxt_type(ufixed, 'x', M, N) when M >= 0, M =< 256, (M rem 8) =:= 0, N > 0, N =< 80 -> {ufixed, M, N}.

wrap_type(T) -> #{type => T}.

get_type(T) -> wrap_type(maps:get(type, T)).
