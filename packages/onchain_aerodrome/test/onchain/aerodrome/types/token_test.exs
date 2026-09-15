defmodule Onchain.Aerodrome.Types.TokenTest do
  use ExUnit.Case, async: true

  alias Onchain.Aerodrome.Types.Token
  alias Onchain.Aerodrome.TypesCase

  @token_fixtures ~w(lp_sugar.tokens token_sugar.tokens)

  describe "from_raw/1" do
    test "maps a positional fixture row one to one" do
      row = first_row("lp_sugar.tokens")
      token = Token.from_raw(row)

      assert %Token{} = token
      TypesCase.assert_one_to_one(Token, {"lp_sugar.json", "tokens"}, row, token)
      TypesCase.refute_floats(token)
      assert is_integer(token.account_balance)
      assert is_boolean(token.listed)
      assert is_boolean(token.emerging)
    end

    test "decodes tokens rows from both lp_sugar and token_sugar fixtures" do
      for id <- @token_fixtures, row <- TypesCase.decode_rows(id) do
        token = Token.from_raw(row)
        assert %Token{} = token
        TypesCase.refute_floats(token)
      end
    end

    test "raises FunctionClauseError on a tuple of the wrong size" do
      assert_raise FunctionClauseError, fn -> Token.from_raw({}) end
    end
  end

  defp first_row(id), do: id |> TypesCase.decode_rows() |> hd()
end
