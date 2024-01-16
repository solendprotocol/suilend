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
    use std::option::{Option, Self};
    use suilend::decimal::{Self, Decimal};
    use suilend::obligation::{Self, Obligation};
    use sui::coin::{Self, Coin, CoinMetadata};
    use sui::balance::{Self, Balance};
    use pyth::price_info::{Self, PriceInfoObject};
    use pyth::price_feed::{Self, PriceFeed};

    /* errors */
    const ENotAOneTimeWitness: u64 = 0;
    const EObligationNotHealthy: u64 = 1;

    struct LendingMarket<phantom P> has key {
        id: UID,

        reserves: vector<Reserve<P>>,
        reserve_treasuries: Bag,

        obligations: ObjectBag,
    }

    struct LendingMarketOwnerCap<phantom P> has key, store {
        id: UID
    }

    struct ObligationOwnerCap<phantom P> has key, store {
        id: UID,
        obligation_id: ID
    }

    public fun obligation_id<P>(cap: &ObligationOwnerCap<P>): ID {
        cap.obligation_id
    }

    // used to store ReserveTreasury objects in the Bag
    struct Name<phantom P> has copy, drop, store {}

    public fun create_lending_market<P: drop>(
        witness: P, 
        ctx: &mut TxContext
    ): LendingMarketOwnerCap<P> {
        assert!(types::is_one_time_witness(&witness), ENotAOneTimeWitness);

        let lending_market = LendingMarket<P> {
            id: object::new(ctx),
            reserves: vector::empty(),
            reserve_treasuries: bag::new(ctx),
            obligations: object_bag::new(ctx),
        };
        
        transfer::share_object(lending_market);

        LendingMarketOwnerCap<P> { id: object::new(ctx) }
    }

    public fun add_reserve<P, T>(
        _: &LendingMarketOwnerCap<P>, 
        lending_market: &mut LendingMarket<P>, 
        priceInfo: &PriceInfoObject,
        config: ReserveConfig,
        coin_metadata: &CoinMetadata<T>,
        clock: &Clock,
        _ctx: &mut TxContext
    ) {

        let reserve_id = vector::length(&lending_market.reserves);
        let (reserve, reserve_treasury) = reserve::create_reserve<P, T>(
            config, 
            coin_metadata, 
            priceInfo, 
            clock, 
            reserve_id
        );

        vector::push_back(&mut lending_market.reserves, reserve);
        bag::add(&mut lending_market.reserve_treasuries, Name<T> {}, reserve_treasury);
    }

    public fun update_reserve_config<P, T>(
        _: &LendingMarketOwnerCap<P>, 
        lending_market: &mut LendingMarket<P>, 
        config: ReserveConfig,
        _ctx: &mut TxContext
    ) {
        let (reserve, _) = get_reserve_mut<P, T>(lending_market);
        reserve::update_reserve_config<P>(reserve, config);
    }

    public fun refresh_reserve_price<P>(
        lending_market: &mut LendingMarket<P>, 
        reserve_id: u64,
        clock: &Clock,
        price_info: &PriceInfoObject,
        _ctx: &mut TxContext
    ) {
        let reserve = vector::borrow_mut(
            &mut lending_market.reserves, 
            reserve_id
        );
        reserve::update_price<P>(reserve, clock, price_info);
    }

    #[test_only]
    public fun update_price_for_testing<P, T>(
        _: &LendingMarketOwnerCap<P>, 
        lending_market: &mut LendingMarket<P>, 
        clock: &Clock,
        price: u256,
        _ctx: &mut TxContext
    ) {
        let (reserve, _) = get_reserve_mut<P, T>(lending_market);
        reserve::update_price_for_testing<P>(reserve, clock, price);
    }

    public fun create_obligation<P>(
        lending_market: &mut LendingMarket<P>, 
        ctx: &mut TxContext
    ): ObligationOwnerCap<P> {
        let obligation = obligation::create_obligation<P>(tx_context::sender(ctx), ctx);
        let cap = ObligationOwnerCap<P> { 
            id: object::new(ctx), 
            obligation_id: object::id(&obligation) 
        };
        object_bag::add(&mut lending_market.obligations, object::id(&obligation), obligation);

        cap
    }

    public fun deposit_liquidity_and_mint_ctokens<P, T>(
        lending_market: &mut LendingMarket<P>, 
        clock: &Clock,
        deposit: Coin<T>,
        ctx: &mut TxContext
    ): Coin<CToken<P, T>> {
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

        coin::from_balance(ctoken_balance, ctx)
    }

    public fun deposit_ctokens_into_obligation<P, T>(
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

    fun find_obligation<P>(
        lending_market: &mut LendingMarket<P>, 
        obligation_owner_cap: &ObligationOwnerCap<P>
    ): &mut Obligation<P> {
        object_bag::borrow_mut(
            &mut lending_market.obligations, 
            obligation_owner_cap.obligation_id
        )
    }

    fun find_reserve<P, T>(
        lending_market: &mut LendingMarket<P>, 
    ): (&mut Reserve<P>, &mut ReserveTreasury<P, T>) {
        let reserve_treasury: &mut ReserveTreasury<P, T> = bag::borrow_mut(
            &mut lending_market.reserve_treasuries, 
            Name<T> {}
        );
        let reserve: &mut Reserve<P> = vector::borrow_mut(
            &mut lending_market.reserves, 
            reserve::reserve_id(reserve_treasury)
        );

        (reserve, reserve_treasury)
    }

    public fun borrow<P, T>(
        lending_market: &mut LendingMarket<P>,
        obligation_owner_cap: &ObligationOwnerCap<P>,
        clock: &Clock,
        amount: u64,
        ctx: &mut TxContext
    ): Coin<T> {
        let obligation = object_bag::borrow_mut(
            &mut lending_market.obligations, 
            obligation_owner_cap.obligation_id
        );

        let refreshed_ticket = obligation::refresh<P>(obligation, &mut lending_market.reserves, clock);

        let reserve_treasury: &mut ReserveTreasury<P, T> = bag::borrow_mut(
            &mut lending_market.reserve_treasuries, 
            Name<T> {}
        );

        let reserve = vector::borrow_mut(
            &mut lending_market.reserves, 
            reserve::reserve_id(reserve_treasury)
        );

        let liquidity = reserve::borrow_liquidity<P, T>(
            reserve, 
            reserve_treasury, 
            clock,
            amount
        );

        obligation::borrow<P, T>(
            refreshed_ticket, 
            obligation, 
            reserve, 
            reserve::reserve_id(reserve_treasury), 
            clock, 
            amount
        );

        coin::from_balance(liquidity, ctx)
    }

    public fun withdraw<P, T>(
        lending_market: &mut LendingMarket<P>,
        obligation_owner_cap: &ObligationOwnerCap<P>,
        clock: &Clock,
        amount: u64,
        ctx: &mut TxContext
    ): Coin<T> {
        let obligation = object_bag::borrow_mut(
            &mut lending_market.obligations, 
            obligation_owner_cap.obligation_id
        );

        let refreshed_ticket = obligation::refresh<P>(obligation, &mut lending_market.reserves, clock);

        let reserve_treasury: &mut ReserveTreasury<P, T> = bag::borrow_mut(
            &mut lending_market.reserve_treasuries, 
            Name<T> {}
        );

        let reserve = vector::borrow_mut(
            &mut lending_market.reserves, 
            reserve::reserve_id(reserve_treasury)
        );

        let ctokens = obligation::withdraw<P, T>(
            refreshed_ticket, 
            obligation, 
            reserve, 
            reserve::reserve_id(reserve_treasury), 
            clock, 
            amount
        );

        let tokens = reserve::redeem_ctokens<P, T>(reserve, reserve_treasury, ctokens, clock);

        coin::from_balance(tokens, ctx)
    }

    fun get_reserve<P, T>(
        lending_market: &LendingMarket<P>,
    ): (&Reserve<P>, &ReserveTreasury<P, T>) {
        let reserve_treasury: &ReserveTreasury<P, T> = bag::borrow(
            &lending_market.reserve_treasuries, 
            Name<T> {}
        );

        let reserve = vector::borrow(
            &lending_market.reserves, 
            reserve::reserve_id(reserve_treasury)
        );

        (reserve, reserve_treasury)
    }

    fun get_reserve_mut<P, T>(
        lending_market: &mut LendingMarket<P>,
    ): (&mut Reserve<P>, &mut ReserveTreasury<P, T>) {
        let reserve_treasury: &mut ReserveTreasury<P, T> = bag::borrow_mut(
            &mut lending_market.reserve_treasuries, 
            Name<T> {}
        );

        let reserve = vector::borrow_mut(
            &mut lending_market.reserves, 
            reserve::reserve_id(reserve_treasury)
        );

        (reserve, reserve_treasury)
    }

    public fun liquidate<P, Repay, Withdraw>(
        lending_market: &mut LendingMarket<P>,
        obligation_id: ID,
        clock: &Clock,
        repay_amount: Coin<Repay>,
        ctx: &mut TxContext
    ): (Coin<Repay>, Coin<Withdraw>) {
        let obligation: Obligation<P> = object_bag::remove(
            &mut lending_market.obligations, 
            obligation_id
        );

        let refreshed_ticket = obligation::refresh<P>(&mut obligation, &mut lending_market.reserves, clock);

        let (repay_reserve, repay_reserve_treasury) = get_reserve<P, Repay>(lending_market);
        let (withdraw_reserve, withdraw_reserve_treasury) = get_reserve<P, Withdraw>(lending_market);

        let repay_balance = coin::into_balance(repay_amount);

        let (withdraw_ctoken_balance, required_repay_amount) = obligation::liquidate<P, Repay, Withdraw>(
            refreshed_ticket, 
            &mut obligation, 
            repay_reserve, 
            reserve::reserve_id(repay_reserve_treasury), 
            withdraw_reserve, 
            reserve::reserve_id(withdraw_reserve_treasury), 
            clock, 
            &repay_balance
        );

        // send required_repay_amount to reserve, send rest back to user
        let required_repay_balance = balance::split(
            &mut repay_balance, 
            required_repay_amount
        );

        {
            let (repay_reserve, repay_reserve_treasury) = get_reserve_mut<P, Repay>(lending_market);
            reserve::repay_liquidity<P, Repay>(
                repay_reserve, 
                repay_reserve_treasury, 
                clock, 
                required_repay_balance
            );
        };

        let (withdraw_reserve, withdraw_reserve_treasury) = get_reserve_mut<P, Withdraw>(lending_market);
        let withdraw_balance = reserve::redeem_ctokens<P, Withdraw>(
            withdraw_reserve, 
            withdraw_reserve_treasury, 
            withdraw_ctoken_balance, 
            clock,
        );
        debug::print(&7);
        let ratio = reserve::ctoken_ratio(withdraw_reserve);
        debug::print(&ratio);
        debug::print(&withdraw_balance);

        object_bag::add(&mut lending_market.obligations, object::id(&obligation), obligation);

        (coin::from_balance(repay_balance, ctx), coin::from_balance(withdraw_balance, ctx))
    }

    public fun repay<P, T>(
        lending_market: &mut LendingMarket<P>,
        obligation_id: ID,
        clock: &Clock,
        amount: Coin<T>,
        _ctx: &mut TxContext
    ) {
        let obligation = object_bag::borrow_mut(
            &mut lending_market.obligations, 
            obligation_id
        );

        let reserve_treasury: &mut ReserveTreasury<P, T> = bag::borrow_mut(
            &mut lending_market.reserve_treasuries, 
            Name<T> {}
        );

        let reserve = vector::borrow_mut(
            &mut lending_market.reserves, 
            reserve::reserve_id(reserve_treasury)
        );

        obligation::repay<P>(
            obligation, 
            reserve, 
            reserve::reserve_id(reserve_treasury), 
            coin::value(&amount)
        );

        reserve::repay_liquidity<P, T>(
            reserve, 
            reserve_treasury, 
            clock, 
            coin::into_balance(amount)
        );
    }

    #[test_only]
    public fun print_obligation<P>(
        lending_market: &LendingMarket<P>,
        obligation_id: ID
    ) {
        let obligation: &Obligation<P> = object_bag::borrow(
            &lending_market.obligations, 
            obligation_id
        );

        debug::print(obligation);
    }

    #[test_only]
    public fun destroy_for_testing<P>(obligation_owner_cap: ObligationOwnerCap<P>) {
        let ObligationOwnerCap { id, obligation_id: _ } = obligation_owner_cap;
        object::delete(id);
    }

    #[test_only]
    public fun destroy_lending_market_owner_cap_for_testing<P>(lending_market_owner_cap: LendingMarketOwnerCap<P>) {
        let LendingMarketOwnerCap { id } = lending_market_owner_cap;
        object::delete(id);
    }
}