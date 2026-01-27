#!/usr/bin/env sh

NETWORK=$1

yq -oj "deploy/${NETWORK}.toml" | jq '
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