# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Initial scaffold: contract address registry (`Onchain.Aerodrome.Contracts`)
  with Base addresses verified against `velodrome-finance/sugar` deployments
  and live `eth_call`, captured Sugar/factory ABIs in `priv/abis/`, and the
  `.reach.exs` layer contract.
