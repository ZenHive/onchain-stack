defmodule Cartouche.Contract.BlockNumber do
  @moduledoc false

  use Onchain.Contract.Generator,
    artifact_file: Path.expand("../../../abi/BlockNumber.json", __DIR__)
end
