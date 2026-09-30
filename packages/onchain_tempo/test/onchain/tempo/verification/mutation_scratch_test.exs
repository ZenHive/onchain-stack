defmodule Onchain.Tempo.Verification.MutationScratchTest do
  use ExUnit.Case, async: false

  alias Onchain.Tempo.Verification.Campaign

  @moduletag :verification

  test "campaign refuses to run when a tracked patch target is dirty" do
    root = package_root()
    codec = Path.join(root, "lib/onchain/tempo/codec.ex")
    original = File.read!(codec)

    try do
      File.write!(codec, original <> "\n")
      assert_raise RuntimeError, ~r/refuses to run/, fn -> Campaign.run() end
    after
      File.write!(codec, original)
    end
  end

  defp package_root do
    Path.expand("../../../../", __DIR__)
  end
end
