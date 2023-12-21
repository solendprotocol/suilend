module suilend::obligation {
    use sui::object::{Self, ID, UID};
    use sui::balance::{Self, Balance};
    use suilend::decimal::{Decimal, Self};
    use std::vector::{Self};
    use sui::bag::{Self, Bag};
    use sui::tx_context::{Self, TxContext};
    use suilend::reserve::{Self, Reserve, CToken};

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

    public(friend) fun deposit<P, T>(
        obligation: &mut Obligation<P>,
        reserve_id: u64,
        ctokens: Balance<CToken<P, T>>,
    ) {
        let deposit = find_or_add_deposit(obligation, reserve_id);
        deposit.deposited_ctoken_amount = deposit.deposited_ctoken_amount + balance::value(&ctokens);
        add_to_balance_bag(obligation, ctokens);
    }

    // used to index into the balance bag
    struct Key<phantom T> has copy, drop, store {}

    fun add_to_balance_bag<P, T>(
        obligation: &mut Obligation<P>,
        ctokens: Balance<T>,
    ) {
        if(bag::contains(&obligation.balances, Key<T>{})) {
            let deposit = bag::borrow_mut(&mut obligation.balances, Key<T>{});
            balance::join(deposit, ctokens);
        } else {
            bag::add(&mut obligation.balances, Key<T>{}, ctokens);
        };
    }

    fun find_or_add_deposit<P>(
        obligation: &mut Obligation<P>,
        reserve_id: u64,
    ): &mut Deposit<P> {
        let i = 0;
        while (i < vector::length(&obligation.deposits)) {
            let deposit = vector::borrow_mut(&mut obligation.deposits, i);
            if (deposit.reserve_id == reserve_id) {
                return deposit
            };

            i = i + 1;
        };

        let deposit = Deposit<P> {
            reserve_id: reserve_id,
            deposited_ctoken_amount: 0,
            market_value: decimal::from(0)
        };

        vector::push_back(&mut obligation.deposits, deposit);
        let length = vector::length(&obligation.deposits);
        vector::borrow_mut(&mut obligation.deposits, length - 1)
    }

}