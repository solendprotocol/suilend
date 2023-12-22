#[test_only]
module suilend::test_usdc {
    use sui::coin::{Self, Coin, CoinMetadata};
    use std::vector::{Self};
    use std::option::{Self};
    use sui::tx_context::{Self, TxContext};
    use sui::transfer;

    struct TEST_USDC has drop {}

    public fun create_currency(ctx: &mut TxContext) {
        let (cap, metadata) = coin::create_currency(
            TEST_USDC {}, 
            6, 
            vector::empty(),
            vector::empty(),
            vector::empty(),
            option::none(),
            ctx
        );

        transfer::public_transfer(
            cap,
            tx_context::sender(ctx), 
        );
        transfer::public_transfer(
            metadata,
            tx_context::sender(ctx), 
        );
    }
}

#[test_only]
module suilend::test_sui {
    use sui::coin::{Self, Coin, CoinMetadata};
    use std::vector::{Self};
    use std::option::{Self};
    use sui::tx_context::{Self, TxContext};
    use sui::transfer;

    struct TEST_SUI has drop {}

    public fun create_currency(ctx: &mut TxContext) {
        let (cap, metadata) = coin::create_currency(
            TEST_SUI {}, 
            6, 
            vector::empty(),
            vector::empty(),
            vector::empty(),
            option::none(),
            ctx
        );

        transfer::public_transfer(
            cap,
            tx_context::sender(ctx), 
        );
        transfer::public_transfer(
            metadata,
            tx_context::sender(ctx), 
        );
    }
}