module suilend::lending_market {
    use sui::object::{Self, ID, UID};
    use sui::object_bag::{Self, ObjectBag};
    use sui::bag::{Self, Bag};
    use sui::clock::{Clock};
    use sui::types;
    use sui::tx_context::{Self, TxContext};
    use sui::transfer;
    use suilend::reserve::{Self, Reserve, ReserveConfig, CToken};
    use std::vector::{Self};
    use std::debug::{Self};
    use suilend::obligation::{Self, Obligation};
    use sui::coin::{Self, Coin, CoinMetadata};
    use sui::balance::{Self, Balance, Supply};
    use pyth::price_info::{PriceInfoObject};

    /* errors */
    const ENotAOneTimeWitness: u64 = 0;
    const EObligationNotHealthy: u64 = 1;

    struct LendingMarket<phantom P> has key {
        id: UID,

        reserves: vector<Reserve<P>>,
        obligations: ObjectBag,
        balances: Bag,
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

    struct Balances<phantom P, phantom T> has store {
        reserve_id: u64,
        available_amount: Balance<T>,
        ctoken_supply: Supply<CToken<P, T>>,
        deposited_ctokens: Balance<CToken<P, T>>
    }

    // used to store Balance objects in the Bag
    struct Name<phantom P> has copy, drop, store {}

    public fun create_lending_market<P: drop>(
        witness: P, 
        ctx: &mut TxContext
    ): LendingMarketOwnerCap<P> {
        assert!(types::is_one_time_witness(&witness), ENotAOneTimeWitness);

        let lending_market = LendingMarket<P> {
            id: object::new(ctx),
            reserves: vector::empty(),
            obligations: object_bag::new(ctx),
            balances: bag::new(ctx),
        };
        
        transfer::share_object(lending_market);

        LendingMarketOwnerCap<P> { id: object::new(ctx) }
    }

    public fun add_reserve<P, T>(
        _: &LendingMarketOwnerCap<P>, 
        lending_market: &mut LendingMarket<P>, 
        price_info: &PriceInfoObject,
        config: ReserveConfig,
        coin_metadata: &CoinMetadata<T>,
        clock: &Clock,
        _ctx: &mut TxContext
    ) {

        let reserve_id = vector::length(&lending_market.reserves);
        let (reserve, ctoken_supply) = reserve::create_reserve<P, T>(
            config, 
            coin_metadata, 
            price_info, 
            clock, 
            reserve_id
        );

        vector::push_back(&mut lending_market.reserves, reserve);
        bag::add(
            &mut lending_market.balances, 
            Name<T> {}, 
            Balances<P, T> {
                reserve_id,
                available_amount: balance::zero(),
                ctoken_supply,
                deposited_ctokens: balance::zero()
            }
        );
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
        let (reserve, balances) = get_reserve_mut<P, T>(lending_market);

        let ctoken_amount = reserve::deposit_liquidity_and_mint_ctokens<P>(
            reserve, 
            coin::value(&deposit), 
            clock, 
        );

        let ctoken_balance = balance::increase_supply(&mut balances.ctoken_supply, ctoken_amount);

        balance::join(&mut balances.available_amount, coin::into_balance(deposit));

        coin::from_balance(ctoken_balance, ctx)
    }

    public fun redeem_ctokens_and_withdraw_liquidity<P, T>(
        lending_market: &mut LendingMarket<P>, 
        clock: &Clock,
        ctokens: Coin<CToken<P, T>>,
        ctx: &mut TxContext
    ): Coin<T> {
        let (reserve, balances) = get_reserve_mut<P, T>(lending_market);

        let liquidity_amount = reserve::redeem_ctokens<P>(
            reserve, 
            coin::value(&ctokens), 
            clock, 
        );

        balance::decrease_supply(&mut balances.ctoken_supply, coin::into_balance(ctokens));
        coin::from_balance(balance::split(&mut balances.available_amount, liquidity_amount), ctx)
    }


    public fun deposit_ctokens_into_obligation<P, T>(
        lending_market: &mut LendingMarket<P>, 
        obligation_owner_cap: &ObligationOwnerCap<P>,
        deposit: Coin<CToken<P, T>>,
        _ctx: &mut TxContext
    ) {
        let balances: &mut Balances<P, T> = bag::borrow_mut(&mut lending_market.balances, Name<T> {});
        let reserve = vector::borrow(&lending_market.reserves, balances.reserve_id);
        let obligation = object_bag::borrow_mut(
            &mut lending_market.obligations, 
            obligation_owner_cap.obligation_id
        );

        obligation::deposit<P, T>(
            obligation, 
            reserve,
            coin::value(&deposit)
        );

        balance::join(&mut balances.deposited_ctokens, coin::into_balance(deposit));
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

        let balances: &mut Balances<P, T> = bag::borrow_mut(&mut lending_market.balances, Name<T> {});
        let reserve = vector::borrow_mut(&mut lending_market.reserves, balances.reserve_id);

        reserve::borrow_liquidity<P>(
            reserve, 
            clock,
            amount
        );

        obligation::borrow<P, T>(
            refreshed_ticket, 
            obligation, 
            reserve, 
            clock, 
            amount
        );

        coin::from_balance(balance::split(&mut balances.available_amount, amount), ctx)
    }

    public fun withdraw_ctokens<P, T>(
        lending_market: &mut LendingMarket<P>,
        obligation_owner_cap: &ObligationOwnerCap<P>,
        clock: &Clock,
        amount: u64,
        ctx: &mut TxContext
    ): Coin<CToken<P, T>> {
        let obligation = object_bag::borrow_mut(
            &mut lending_market.obligations, 
            obligation_owner_cap.obligation_id
        );
        let refreshed_ticket = obligation::refresh<P>(obligation, &mut lending_market.reserves, clock);

        let balances: &mut Balances<P, T> = bag::borrow_mut(&mut lending_market.balances, Name<T> {});
        let reserve = vector::borrow_mut(&mut lending_market.reserves, balances.reserve_id);

        obligation::withdraw<P, T>(
            refreshed_ticket, 
            obligation, 
            reserve, 
            clock, 
            amount
        );

        coin::from_balance(balance::split(&mut balances.deposited_ctokens, amount), ctx)
    }

    fun get_reserve<P, T>(
        lending_market: &LendingMarket<P>,
    ): (&Reserve<P>, &Balances<P, T>) {
        let balances: &Balances<P, T> = bag::borrow(
            &lending_market.balances, 
            Name<T> {}
        );

        let reserve = vector::borrow(
            &lending_market.reserves, 
            balances.reserve_id
        );

        (reserve, balances)
    }

    fun get_reserve_mut<P, T>(
        lending_market: &mut LendingMarket<P>,
    ): (&mut Reserve<P>, &mut Balances<P, T>) {
        let balances: &mut Balances<P, T> = bag::borrow_mut(
            &mut lending_market.balances, 
            Name<T> {}
        );

        let reserve = vector::borrow_mut(
            &mut lending_market.reserves, 
            balances.reserve_id
        );

        (reserve, balances)
    }

    fun get_obligation_mut<P>(
        lending_market: &mut LendingMarket<P>,
        obligation_id: ID
    ): &mut Obligation<P> {
        object_bag::borrow_mut(
            &mut lending_market.obligations, 
            obligation_id
        )
    }

    public fun liquidate<P, Repay, Withdraw>(
        lending_market: &mut LendingMarket<P>,
        obligation_id: ID,
        clock: &Clock,
        repay_coins: Coin<Repay>,
        ctx: &mut TxContext
    ): (Coin<Repay>, Coin<CToken<P, Withdraw>>) {
        let obligation: Obligation<P> = object_bag::remove(
            &mut lending_market.obligations, 
            obligation_id
        );

        let refreshed_ticket = obligation::refresh<P>(&mut obligation, &mut lending_market.reserves, clock);

        let (repay_reserve, _) = get_reserve<P, Repay>(lending_market);
        let (withdraw_reserve, _) = get_reserve<P, Withdraw>(lending_market);

        let (withdraw_ctoken_amount, required_repay_amount) = obligation::liquidate<P>(
            refreshed_ticket, 
            &mut obligation, 
            repay_reserve, 
            withdraw_reserve, 
            clock, 
            coin::value(&repay_coins)
        );

        object_bag::add(&mut lending_market.obligations, object::id(&obligation), obligation);

        {
            let (repay_reserve, repay_balances) = get_reserve_mut<P, Repay>(lending_market);

            reserve::repay_liquidity<P>(
                repay_reserve, 
                clock, 
                required_repay_amount
            );

            let required_repay_coins = coin::split(&mut repay_coins, required_repay_amount, ctx);
            balance::join(&mut repay_balances.available_amount, coin::into_balance(required_repay_coins));
        };

        let (_, withdraw_balances) = get_reserve_mut<P, Withdraw>(lending_market);
        let withdraw_ctokens_balance = balance::split(
            &mut withdraw_balances.deposited_ctokens, 
            withdraw_ctoken_amount
        );

        (repay_coins, coin::from_balance(withdraw_ctokens_balance, ctx))
    }

    public fun repay<P, T>(
        lending_market: &mut LendingMarket<P>,
        obligation_id: ID,
        clock: &Clock,
        repay_coins: Coin<T>,
        _ctx: &mut TxContext
    ) {
        let obligation = object_bag::borrow_mut(
            &mut lending_market.obligations, 
            obligation_id
        );
        let balances: &mut Balances<P, T> = bag::borrow_mut(&mut lending_market.balances, Name<T> {});
        let reserve = vector::borrow_mut(&mut lending_market.reserves, balances.reserve_id);

        obligation::repay<P>(
            obligation, 
            reserve, 
            coin::value(&repay_coins)
        );

        reserve::repay_liquidity<P>(
            reserve, 
            clock, 
            coin::value(&repay_coins)
        );

        balance::join(&mut balances.available_amount, coin::into_balance(repay_coins));
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
