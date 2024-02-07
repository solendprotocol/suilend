module suilend::lending_market {
    use sui::object::{Self, ID, UID};
    use suilend::rate_limiter::{Self, RateLimiter};
    use sui::event::{Self};
    use suilend::decimal::{Self};
    use sui::object_table::{Self, ObjectTable};
    use sui::bag::{Self, Bag};
    use sui::clock::{Self, Clock};
    use sui::types;
    use sui::tx_context::{Self, TxContext};
    use sui::transfer;
    use suilend::reserve::{Self, Reserve, CToken};
    use suilend::reserve_config::{ReserveConfig};
    use std::vector::{Self};
    use suilend::obligation::{Self, Obligation};
    use sui::coin::{Self, Coin, CoinMetadata};
    use sui::balance::{Self, Balance, Supply};
    use pyth::price_info::{PriceInfoObject};

    #[test_only]
    use std::debug::{Self};

    const CURRENT_VERSION: u64 = 1;

    /* errors */
    const ENotAOneTimeWitness: u64 = 0;
    const EObligationNotHealthy: u64 = 1;
    const EIncorrectVersion: u64 = 2;
    const ETooSmall: u64 = 3;

    /* Events */
    struct MintEvent<phantom P, phantom T> has drop, copy {
        in_liquidity_amount: u64,
        out_ctoken_amount: u64,
        caller: address
    }

    struct RedeemEvent<phantom P, phantom T> has drop, copy {
        in_ctoken_amount: u64,
        out_liquidity_amount: u64,
        caller: address
    }

    struct DepositEvent<phantom P, phantom T> has drop, copy {
        ctoken_amount: u64,
        obligation_id: ID,
        caller: address
    }

    struct WithdrawEvent<phantom P, phantom T> has drop, copy {
        ctoken_amount: u64,
        obligation_id: ID,
        caller: address
    }

    struct BorrowEvent<phantom P, phantom T> has drop, copy {
        liquidity_amount: u64,
        obligation_id: ID,
        caller: address
    }

    struct RepayEvent<phantom P, phantom T> has drop, copy {
        liquidity_amount: u64,
        obligation_id: ID,
        caller: address
    }

    struct LiquidateEvent<phantom P, phantom RepayType, phantom WithdrawType> has drop, copy {
        repay_amount: u64,
        withdraw_amount: u64,
        obligation_id: ID,
        caller: address,
    }

    struct LendingMarket<phantom P> has key {
        id: UID,
        version: u64,

        reserves: vector<Reserve<P>>,
        obligations: ObjectTable<ID, Obligation<P>>,
        balances: Bag,

        // window duration is in seconds
        rate_limiter: RateLimiter
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
        deposited_ctokens: Balance<CToken<P, T>>,
        fees: Balance<T>,
        ctoken_fees: Balance<CToken<P, T>>,
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
            version: CURRENT_VERSION,
            reserves: vector::empty(),
            obligations: object_table::new(ctx),
            balances: bag::new(ctx),
            rate_limiter: rate_limiter::new(rate_limiter::new_config(1, 18_446_744_073_709_551_615), 0)
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
        ctx: &mut TxContext
    ) {
        assert!(lending_market.version == CURRENT_VERSION, EIncorrectVersion);

        let reserve_id = vector::length(&lending_market.reserves);
        let (reserve, ctoken_supply) = reserve::create_reserve<P, T>(
            config, 
            coin_metadata, 
            price_info, 
            clock, 
            ctx
        );

        vector::push_back(&mut lending_market.reserves, reserve);
        bag::add(
            &mut lending_market.balances, 
            Name<T> {}, 
            Balances<P, T> {
                reserve_id,
                available_amount: balance::zero(),
                ctoken_supply,
                deposited_ctokens: balance::zero(),
                fees: balance::zero(),
                ctoken_fees: balance::zero(),
            }
        );
    }

    public fun update_reserve_config<P, T>(
        _: &LendingMarketOwnerCap<P>, 
        lending_market: &mut LendingMarket<P>, 
        config: ReserveConfig,
    ) {
        assert!(lending_market.version == CURRENT_VERSION, EIncorrectVersion);

        let (reserve, _) = get_reserve_mut<P, T>(lending_market);
        reserve::update_reserve_config<P>(reserve, config);
    }

    public fun refresh_reserve_price<P, T>(
        lending_market: &mut LendingMarket<P>, 
        clock: &Clock,
        price_info: &PriceInfoObject,
    ) {
        assert!(lending_market.version == CURRENT_VERSION, EIncorrectVersion);

        let (reserve, _) = get_reserve_mut<P, T>(lending_market);
        reserve::update_price<P>(reserve, clock, price_info);
    }

    public fun create_obligation<P>(
        lending_market: &mut LendingMarket<P>, 
        ctx: &mut TxContext
    ): ObligationOwnerCap<P> {
        assert!(lending_market.version == CURRENT_VERSION, EIncorrectVersion);

        let obligation = obligation::create_obligation<P>(tx_context::sender(ctx), ctx);
        let cap = ObligationOwnerCap<P> { 
            id: object::new(ctx), 
            obligation_id: object::id(&obligation) 
        };

        object_table::add(&mut lending_market.obligations, object::id(&obligation), obligation);

        cap
    }

    public fun deposit_liquidity_and_mint_ctokens<P, T>(
        lending_market: &mut LendingMarket<P>, 
        clock: &Clock,
        deposit: Coin<T>,
        ctx: &mut TxContext
    ): Coin<CToken<P, T>> {
        assert!(lending_market.version == CURRENT_VERSION, EIncorrectVersion);
        assert!(coin::value(&deposit) > 0, ETooSmall);

        let (reserve, balances) = get_reserve_mut<P, T>(lending_market);

        reserve::compound_interest(reserve, clock);
        let ctoken_amount = reserve::deposit_liquidity_and_mint_ctokens<P>(
            reserve, 
            coin::value(&deposit)
        );

        assert!(ctoken_amount > 0, ETooSmall);

        event::emit(MintEvent<P, T> {
            in_liquidity_amount: coin::value(&deposit),
            out_ctoken_amount: ctoken_amount,
            caller: tx_context::sender(ctx)
        });

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
        assert!(lending_market.version == CURRENT_VERSION, EIncorrectVersion);
        assert!(coin::value(&ctokens) > 0, ETooSmall);

        let (reserve, balances) = get_reserve_mut<P, T>(lending_market);

        reserve::compound_interest(reserve, clock);
        let liquidity_amount = reserve::redeem_ctokens<P>(
            reserve, 
            coin::value(&ctokens)
        );

        assert!(liquidity_amount > 0, ETooSmall);

        event::emit(RedeemEvent<P, T> {
            in_ctoken_amount: coin::value(&ctokens),
            out_liquidity_amount: liquidity_amount,
            caller: tx_context::sender(ctx)
        });

        balance::decrease_supply(&mut balances.ctoken_supply, coin::into_balance(ctokens));
        coin::from_balance(balance::split(&mut balances.available_amount, liquidity_amount), ctx)
    }


    public fun deposit_ctokens_into_obligation<P, T>(
        lending_market: &mut LendingMarket<P>, 
        obligation_owner_cap: &ObligationOwnerCap<P>,
        deposit: Coin<CToken<P, T>>,
        ctx: &mut TxContext
    ) {
        assert!(lending_market.version == CURRENT_VERSION, EIncorrectVersion);
        assert!(coin::value(&deposit) > 0, ETooSmall);

        let balances: &mut Balances<P, T> = bag::borrow_mut(&mut lending_market.balances, Name<T> {});
        let reserve = vector::borrow(&lending_market.reserves, balances.reserve_id);
        let obligation = object_table::borrow_mut(
            &mut lending_market.obligations, 
            obligation_owner_cap.obligation_id
        );

        obligation::deposit<P>(
            obligation, 
            reserve,
            coin::value(&deposit)
        );

        event::emit(DepositEvent<P, T> {
            ctoken_amount: coin::value(&deposit),
            obligation_id: obligation_owner_cap.obligation_id,
            caller: tx_context::sender(ctx)
        });

        balance::join(&mut balances.deposited_ctokens, coin::into_balance(deposit));

    }

    public fun borrow<P, T>(
        lending_market: &mut LendingMarket<P>,
        obligation_owner_cap: &ObligationOwnerCap<P>,
        clock: &Clock,
        amount: u64,
        ctx: &mut TxContext
    ): Coin<T> {
        assert!(lending_market.version == CURRENT_VERSION, EIncorrectVersion);
        assert!(amount > 0, ETooSmall);

        let obligation = object_table::borrow_mut(
            &mut lending_market.obligations, 
            obligation_owner_cap.obligation_id
        );
        obligation::refresh<P>(obligation, &mut lending_market.reserves, clock);

        let balances: &mut Balances<P, T> = bag::borrow_mut(&mut lending_market.balances, Name<T> {});
        let reserve = vector::borrow_mut(&mut lending_market.reserves, balances.reserve_id);

        reserve::compound_interest(reserve, clock);
        reserve::assert_price_is_fresh(reserve, clock);

        let borrow_fee = reserve::calculate_borrow_fee<P>(reserve, amount);

        reserve::borrow_liquidity<P>(reserve, amount + borrow_fee);
        obligation::borrow<P>(obligation, reserve, amount + borrow_fee);

        let borrow_value = reserve::market_value_upper_bound(reserve, decimal::from(amount + borrow_fee));
        rate_limiter::process_qty(
            &mut lending_market.rate_limiter, 
            clock::timestamp_ms(clock) / 1000,
            borrow_value
        );

        event::emit(BorrowEvent<P, T> {
            liquidity_amount: amount + borrow_fee,
            obligation_id: obligation_owner_cap.obligation_id,
            caller: tx_context::sender(ctx)
        });

        let fee_balance = balance::split(&mut balances.available_amount, borrow_fee);
        balance::join(&mut balances.fees, fee_balance);

        let receive_balance = balance::split(&mut balances.available_amount, amount);
        coin::from_balance(receive_balance, ctx)
    }

    public fun withdraw_ctokens<P, T>(
        lending_market: &mut LendingMarket<P>,
        obligation_owner_cap: &ObligationOwnerCap<P>,
        clock: &Clock,
        amount: u64,
        ctx: &mut TxContext
    ): Coin<CToken<P, T>> {
        assert!(lending_market.version == CURRENT_VERSION, EIncorrectVersion);
        assert!(amount > 0, ETooSmall);

        let obligation = object_table::borrow_mut(
            &mut lending_market.obligations, 
            obligation_owner_cap.obligation_id
        );
        obligation::refresh<P>(obligation, &mut lending_market.reserves, clock);

        let balances: &mut Balances<P, T> = bag::borrow_mut(&mut lending_market.balances, Name<T> {});
        let reserve = vector::borrow_mut(&mut lending_market.reserves, balances.reserve_id);

        obligation::withdraw<P>(obligation, reserve, amount);

        let withdraw_value = reserve::ctoken_market_value_upper_bound(reserve, amount);
        rate_limiter::process_qty(
            &mut lending_market.rate_limiter, 
            clock::timestamp_ms(clock) / 1000,
            withdraw_value
        );

        event::emit(WithdrawEvent<P, T> {
            ctoken_amount: amount,
            obligation_id: obligation_owner_cap.obligation_id,
            caller: tx_context::sender(ctx)
        });

        coin::from_balance(balance::split(&mut balances.deposited_ctokens, amount), ctx)
    }

    public fun liquidate<P, Repay, Withdraw>(
        lending_market: &mut LendingMarket<P>,
        obligation_id: ID,
        clock: &Clock,
        repay_coins: Coin<Repay>,
        ctx: &mut TxContext
    ): (Coin<Repay>, Coin<CToken<P, Withdraw>>) {
        assert!(lending_market.version == CURRENT_VERSION, EIncorrectVersion);
        assert!(coin::value(&repay_coins) > 0, ETooSmall);

        let obligation: Obligation<P> = object_table::remove(
            &mut lending_market.obligations, 
            obligation_id
        );

        obligation::refresh<P>(&mut obligation, &mut lending_market.reserves, clock);

        let (repay_reserve, _) = get_reserve<P, Repay>(lending_market);
        let (withdraw_reserve, _) = get_reserve<P, Withdraw>(lending_market);

        let (withdraw_ctoken_amount, required_repay_amount) = obligation::liquidate<P>(
            &mut obligation, 
            repay_reserve, 
            withdraw_reserve, 
            coin::value(&repay_coins)
        );

        assert!(withdraw_ctoken_amount > 0, ETooSmall);
        assert!(required_repay_amount > 0, ETooSmall);

        let liquidation_fee_amount = reserve::calculate_liquidation_fee<P>(
            withdraw_reserve, 
            withdraw_ctoken_amount
        );

        object_table::add(&mut lending_market.obligations, object::id(&obligation), obligation);

        {
            let (repay_reserve, repay_balances) = get_reserve_mut<P, Repay>(lending_market);

            reserve::repay_liquidity<P>(repay_reserve, required_repay_amount);

            let required_repay_coins = coin::split(&mut repay_coins, required_repay_amount, ctx);
            balance::join(&mut repay_balances.available_amount, coin::into_balance(required_repay_coins));
        };

        let (_, withdraw_balances) = get_reserve_mut<P, Withdraw>(lending_market);

        let withdraw_ctokens_balance = balance::split(
            &mut withdraw_balances.deposited_ctokens, 
            withdraw_ctoken_amount
        );

        let fee_balance = balance::split(
            &mut withdraw_ctokens_balance,
            liquidation_fee_amount
        );

        balance::join(&mut withdraw_balances.ctoken_fees, fee_balance);

        event::emit(LiquidateEvent<P, Repay, Withdraw> {
            repay_amount: required_repay_amount,
            withdraw_amount: withdraw_ctoken_amount,
            obligation_id,
            caller: tx_context::sender(ctx)
        });

        (repay_coins, coin::from_balance(withdraw_ctokens_balance, ctx))
    }

    public fun repay<P, T>(
        lending_market: &mut LendingMarket<P>,
        obligation_id: ID,
        clock: &Clock,
        repay_coins: Coin<T>,
        ctx: &mut TxContext
    ) {
        assert!(lending_market.version == CURRENT_VERSION, EIncorrectVersion);

        let obligation = object_table::borrow_mut(
            &mut lending_market.obligations, 
            obligation_id
        );
        let balances: &mut Balances<P, T> = bag::borrow_mut(&mut lending_market.balances, Name<T> {});
        let reserve = vector::borrow_mut(&mut lending_market.reserves, balances.reserve_id);

        reserve::compound_interest(reserve, clock);
        reserve::repay_liquidity<P>(reserve, coin::value(&repay_coins));

        obligation::repay<P>(
            obligation, 
            reserve, 
            decimal::from(coin::value(&repay_coins))
        );

        event::emit(RepayEvent<P, T> {
            liquidity_amount: coin::value(&repay_coins),
            obligation_id,
            caller: tx_context::sender(ctx)
        });

        balance::join(&mut balances.available_amount, coin::into_balance(repay_coins));
    }

    // TODO: do we want a separate fee collector address? instead of using the owner
    public fun claim_fees<P, T>(
        _: &LendingMarketOwnerCap<P>,
        lending_market: &mut LendingMarket<P>,
        ctx: &mut TxContext
    ): (Coin<CToken<P, T>>, Coin<T>) {
        assert!(lending_market.version == CURRENT_VERSION, EIncorrectVersion);

        let (reserve, balances) = get_reserve_mut<P, T>(lending_market);

        let claimed_spread_fees_amount = reserve::claim_spread_fees<P>(reserve);
        let claimed_spread_fees = balance::split(&mut balances.available_amount, claimed_spread_fees_amount);

        let fee_balance = balance::withdraw_all(&mut balances.fees);
        balance::join(&mut fee_balance, claimed_spread_fees);

        let ctoken_fee_balance = balance::withdraw_all(&mut balances.ctoken_fees);

        (
            coin::from_balance(ctoken_fee_balance, ctx),
            coin::from_balance(fee_balance, ctx)
        )

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

    #[test_only]
    public fun print_obligation<P>(
        lending_market: &LendingMarket<P>,
        obligation_id: ID
    ) {
        let obligation: &Obligation<P> = object_table::borrow(
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
