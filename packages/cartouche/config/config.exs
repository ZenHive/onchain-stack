import Config

# HTTP transport is Req (`Cartouche.HTTP` + each RPC module). Production needs no
# config — Req manages its own Finch pool (`Req.Finch`). To customise the pipeline
# (a tuned Finch pool, retries, proxies, telemetry, plugs), set a global keyword
# merged into every `Req.request/1` call:
#
#     config :cartouche, :req_options, finch: MyApp.Finch, retry: :transient
#
# Per-transport overrides are keyed by the calling module and take precedence over
# the global seam — used mainly to inject a stub in tests, e.g.
#
#     config :cartouche, Cartouche.RPC, plug: {Req.Test, Cartouche.RPC}

import_config "#{Mix.env()}.exs"
