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