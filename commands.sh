# get gas
curl --location --request POST 'http://127.0.0.1:9123/gas' \
--header 'Content-Type: application/json' \
--data-raw '{
    "FixedAmountRequest": {
        "recipient": "0x4f3446baf9ca583b920e81924b94883b64addc2a2671963b546aaef77f79a28b"
    }
}'

# deploy package
sui client publish --gas-budget 100000000 .

curl --location --request POST 'https://fullnode.mainnet.sui.io:443' \
--header 'Content-Type: application/json' \
--data-raw '{
  "jsonrpc": "2.0",
  "id": 1,
  "method": "suix_getOwnedObjects",
  "params": [
    "0x3f5f0fcc52e8d0478627a23d62c8993b46013ded746295e225bbee54d6d7d4ca"
  ]
}'

curl --location --request POST 'https://fullnode.mainnet.sui.io:443' \
--header 'Content-Type: application/json' \
--data-raw '{
  "jsonrpc": "2.0",
  "id": 1,
  "method": "suix_getDynamicFields",
  "params": [
    "0x814bf15ce7c92e611db36affb6ff664ff284af8d614330b8bceb8bff660e9a47"
  ]
}'

curl --location --request POST 'https://fullnode.mainnet.sui.io:443' \
--header 'Content-Type: application/json' \
--data-raw '{
  "jsonrpc": "2.0",
  "id": 1,
  "method": "suix_getObject",
  "params": [
    "0x7330cd2015b5e0b24163fb1177bb3c6b707469ed2835f71ed8f6621d5c2f3b12"
  ]
}'
