#[test_only]
module suilend::test_usdc {
    use sui::coin::{Self, TreasuryCap, CoinMetadata};
    use std::vector::{Self};
    use std::option::{Self};
    use sui::tx_context::{TxContext};

    struct TEST_USDC has drop {}

    #[test_only]
    public fun create_currency(ctx: &mut TxContext): (
        TreasuryCap<TEST_USDC>, 
        CoinMetadata<TEST_USDC>, 
    ) {
        coin::create_currency(
            TEST_USDC {}, 
            6, 
            vector::empty(),
            vector::empty(),
            vector::empty(),
            option::none(),
            ctx
        )
    }
}

#[test_only]
module suilend::test_sui {
    use sui::coin::{Self, TreasuryCap, CoinMetadata};
    use std::vector::{Self};
    use std::option::{Self};
    use sui::tx_context::{TxContext};

    struct TEST_SUI has drop {}

    #[test_only]
    public fun create_currency(ctx: &mut TxContext): (
        TreasuryCap<TEST_SUI>, 
        CoinMetadata<TEST_SUI>, 
    ) {
        coin::create_currency(
            TEST_SUI {}, 
            6, 
            vector::empty(),
            vector::empty(),
            vector::empty(),
            option::none(),
            ctx
        )
    }
}

