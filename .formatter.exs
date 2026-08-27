# Root project only. Each package under packages/ carries its own .formatter.exs
# and `mix format` run from a package directory uses that one, not this.
[
  inputs: ["mix.exs", ".formatter.exs", "{lib,shared}/**/*.{ex,exs}"],
  line_length: 120
]
