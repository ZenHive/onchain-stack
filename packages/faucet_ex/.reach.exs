# Reach architecture policy — drives `mix reach.check --arch` / `--smells`.
[
  layers: [
    sources: "Faucet.Source.*",
    support: "Faucet.Test.*",
    core: "Faucet.*"
  ],
  deps: [
    forbidden: [
      # The loop knows only the behaviour, never a concrete adapter.
      {:core, :sources},
      {:core, :support},
      {:sources, :support}
    ]
  ],
  # `--smells` is advisory unless strict is set; this makes it gate.
  smells: [strict: true]
]
