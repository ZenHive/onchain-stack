defmodule Cartouche.VM.InvalidVmTest do
  use ExUnit.Case, async: true

  alias Cartouche.VM.InvalidVm

  describe "exception/1" do
    test "raises with the provided message" do
      exception =
        try do
          raise InvalidVm, "InvalidVm: :stack_underflow"
        rescue
          error in InvalidVm -> error
        end

      assert %InvalidVm{} = exception
      assert exception.message == "InvalidVm: :stack_underflow"
    end
  end
end
