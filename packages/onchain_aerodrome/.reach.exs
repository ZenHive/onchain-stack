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
  deps: [
    forbidden: [
      {:types, :analytics},
      {:types, :read},
      {:types, :write},
      {:types, :bindings},
      {:base, :types},
      {:base, :analytics},
      {:base, :read},
      {:base, :write},
      {:base, :bindings},
      {:bindings, :types},
      {:bindings, :analytics},
      {:bindings, :read},
      {:bindings, :write},
      {:analytics, :read},
      {:analytics, :write},
      {:read, :write}
    ]
  ],
  smells: [strict: true]
]
