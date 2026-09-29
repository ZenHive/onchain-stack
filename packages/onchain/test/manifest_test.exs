defmodule Cartouche.ManifestTest do
  use ExUnit.Case, async: true

  alias Cartouche.Manifest

  describe "build/0" do
    test "returns a non-empty map with the descripex top-level keys" do
      manifest = Manifest.build()

      assert is_map(manifest)
      assert is_binary(manifest.version)
      assert is_binary(manifest.generated_at)
      assert is_list(manifest.modules)
      assert manifest.modules != []
    end

    test "mirrors the modules registered for Cartouche descripex discovery" do
      manifest_modules = MapSet.new(Manifest.build().modules, & &1.module)
      registered = MapSet.new(Cartouche.__descripex_modules__(), &inspect/1)

      assert MapSet.equal?(manifest_modules, registered)
    end
  end
end
