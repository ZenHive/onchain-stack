[
  layers: [
    types: "Onchain.Aerodrome.Types.*",
    base: [
      "Onchain.Aerodrome.Contracts",
      "Onchain.Aerodrome.Epoch",
      "Onchain.Aerodrome.Math",
      "Onchain.Aerodrome.Math.*"
    ],
    bindings: "Onchain.Aerodrome.Bindings.*",
    analytics: "Onchain.Aerodrome.Analytics.*",
    read: "Onchain.Aerodrome.Sugar.*",
    write: "Onchain.Aerodrome.Write.*"
  ],
  # Mix.Tasks.* is intentionally outside the layer graph: fixture generators
  # must reach the network.
  deps: [
    mode: :allowlist,
    allowed: [
      types: [],
      base: [],
      bindings: [:types, :base],
      analytics: [:types, :base],
      read: [:types, :base, :bindings, :analytics],
      write: [:types, :base, :bindings, :analytics, :read]
    ]
  ],
  # Reach 2.8.2 reports :unknown even for a pure local helper call. An analytics
  # effects allowlist of [:pure, :exception] rejects that valid code; the
  # forbidden-call rules enforce the network boundary instead. Layer edges
  # alone cannot catch calls to these external, undeclared modules.
  calls: [
    forbidden: [
      {[
         "Onchain.Aerodrome.Analytics.*",
         "Onchain.Aerodrome.Types.*",
         "Onchain.Aerodrome.Math*",
         "Onchain.Aerodrome.Contracts",
         "Onchain.Aerodrome.Epoch"
       ], ["Onchain.RPC.*", "Onchain.Contract.*", "Onchain.Multicall.*", "Req.*", ":httpc.*"]}
    ]
  ],
  smells: [strict: true]
]
