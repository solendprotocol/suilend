module suilend::lending_market {
    use sui::object::{Self, ID, UID};
    use sui::object_bag::{Self, ObjectBag};
    use sui::bag::{Self, Bag};
    use sui::clock::{Clock};
    use sui::types;
    use sui::tx_context::{Self, TxContext};
    use sui::transfer;
    use suilend::reserve::{Self, Reserve, ReserveTreasury, ReserveConfig, CToken};
    use std::vector::{Self};
    use std::debug::{Self};
    use std::string::{Self};
    use suilend::decimal::{Self, Decimal};
    use suilend::obligation::{Self, Obligation};
    use sui::coin::{Self, Coin};

    /* errors */
    const ENotAOneTimeWitness: u64 = 0;

    struct LendingMarket<phantom P> has key {
        id: UID,

        reserves: vector<Reserve<P>>,
        reserve_treasuries: Bag,

        obligations: ObjectBag,
    }

    struct LendingMarketOwnerCap<phantom P> has key {
        id: UID
    }

    struct ObligationOwnerCap<phantom P> has key, store {
        id: UID,
        obligation_id: ID
    }

    // used to store ReserveTreasury objects in the Bag
    struct Name<phantom P> has copy, drop, store {}

    public entry fun create_lending_market<P: drop>(
        witness: P, 
        ctx: &mut TxContext
    ) {
        assert!(types::is_one_time_witness(&witness), ENotAOneTimeWitness);

        let lending_market = LendingMarket<P> {
            id: object::new(ctx),
            reserves: vector::empty(),
            reserve_treasuries: bag::new(ctx),
            obligations: object_bag::new(ctx),
        };
        
        transfer::share_object(lending_market);
        transfer::transfer(
            LendingMarketOwnerCap<P> { id: object::new(ctx) }, 
            tx_context::sender(ctx)
        );
    }

    public entry fun add_reserve<P, T>(
        _: &LendingMarketOwnerCap<P>, 
        lending_market: &mut LendingMarket<P>, 
        // scaled by 10^18
        price: u256,
        config: ReserveConfig,
        clock: &Clock,
        _ctx: &mut TxContext
    ) {

        let reserve_id = vector::length(&lending_market.reserves);
        let (reserve, reserve_treasury) = reserve::create_reserve<P, T>(config, price, clock, reserve_id);

        vector::push_back(&mut lending_market.reserves, reserve);
        bag::add(&mut lending_market.reserve_treasuries, Name<T> {}, reserve_treasury);
        debug::print(&reserve_id);
    }

    public entry fun create_obligation<P>(
        lending_market: &mut LendingMarket<P>, 
        ctx: &mut TxContext
    ) {
        let obligation = obligation::create_obligation<P>(tx_context::sender(ctx), ctx);
        transfer::transfer(
            ObligationOwnerCap<P> { id: object::new(ctx), obligation_id: object::id(&obligation) }, 
            tx_context::sender(ctx)
        );

        object_bag::add(&mut lending_market.obligations, object::id(&obligation), obligation);
    }

    public entry fun deposit_liquidity_and_mint_ctokens<P, T>(
        lending_market: &mut LendingMarket<P>, 
        clock: &Clock,
        deposit: Coin<T>,
        ctx: &mut TxContext
    ) {
        let reserve_treasury: &mut ReserveTreasury<P, T> = bag::borrow_mut(
            &mut lending_market.reserve_treasuries, 
            Name<T> {}
        );
        let reserve: &mut Reserve<P> = vector::borrow_mut(
            &mut lending_market.reserves, 
            reserve::reserve_id(reserve_treasury)
        );

        let ctoken_balance = reserve::deposit_liquidity_and_mint_ctokens<P, T>(
            reserve, 
            reserve_treasury, 
            coin::into_balance(deposit),
            clock, 
        );

        let ctokens = coin::from_balance(ctoken_balance, ctx);
        transfer::public_transfer(ctokens, tx_context::sender(ctx));
    }

    public entry fun deposit_ctokens_into_obligation<P, T>(
        lending_market: &mut LendingMarket<P>, 
        obligation_owner_cap: &ObligationOwnerCap<P>,
        deposit: Coin<CToken<P, T>>,
        _ctx: &mut TxContext
    ) {
        let obligation = object_bag::borrow_mut(
            &mut lending_market.obligations, 
            obligation_owner_cap.obligation_id
        );

        let reserve_treasury: &mut ReserveTreasury<P, T> = bag::borrow_mut(
            &mut lending_market.reserve_treasuries, 
            Name<T> {}
        );

        obligation::deposit<P, T>(
            obligation, 
            reserve::reserve_id(reserve_treasury),
            coin::into_balance(deposit), 
        );
    }
}