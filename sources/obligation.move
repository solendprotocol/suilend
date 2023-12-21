module suilend::obligation {
    use sui::object::{Self, ID, UID};
    use sui::balance::{Self, Balance};
    use suilend::decimal::{Decimal, Self};
    use std::vector::{Self};
    use sui::bag::{Self, Bag};
    use sui::tx_context::{Self, TxContext};

    friend suilend::lending_market;

    struct Obligation<phantom P> has key, store {
        id: UID,
        owner: address,

        deposits: vector<Deposit<P>>,
        borrows: vector<Borrow<P>>,

        balances: Bag,

        // health stats
        deposited_value_usd: Decimal,
        unweighted_borrowed_value_usd: Decimal,
        weighted_borrowed_value_usd: Decimal,
        allowed_borrow_value_usd: Decimal,
        unhealthy_borrow_value_usd: Decimal
    }

    struct Deposit<phantom P> has store {
        reserve_id: u64,
        deposited_ctoken_amount: u64,
        market_value: Decimal,
    }

    struct Borrow<phantom P> has store {
        reserve_id: u64,
        borrowed_amount: u64,
        market_value: Decimal
    }

    public(friend) fun create_obligation<P>(owner: address, ctx: &mut TxContext): Obligation<P> {
        Obligation<P> {
            id: object::new(ctx),
            owner: owner,
            deposits: vector::empty(),
            borrows: vector::empty(),
            balances: bag::new(ctx),
            deposited_value_usd: decimal::from(0),
            unweighted_borrowed_value_usd: decimal::from(0),
            weighted_borrowed_value_usd: decimal::from(0),
            allowed_borrow_value_usd: decimal::from(0),
            unhealthy_borrow_value_usd: decimal::from(0)
        }
    }

}