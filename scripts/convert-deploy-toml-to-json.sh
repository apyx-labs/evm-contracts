#!/bin/env bash

NETWORK=$1

cat "deploy/${NETWORK}.toml" | tomlq '
  .'${NETWORK}' as $net |
  {
    contracts: (
      $net.address 
      | to_entries 
      | map(select(.key | endswith("_address"))) 
      | map(
          (.key | sub("_address$"; "")) as $name 
          | {
              key: $name, 
              value: {
                address: .value, 
                block: $net.uint[$name + "_block"]
              }
            }
        ) 
      | from_entries
    )
  }'