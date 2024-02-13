module suilend::lending_market {
    // === Imports ===
    use sui::object::{Self, ID, UID};
    use suilend::rate_limiter::{Self, RateLimiter, RateLimiterConfig};
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
    use suilend::obligation::{Self, Obligation};
    use sui::coin::{Self, Coin, CoinMetadata};
    use sui::balance::{Self};
    use pyth::price_info::{PriceInfoObject};
    use std::type_name::{Self, TypeName};

    // === Errors ===
    const ENotAOneTimeWitness: u64 = 0;
    const EIncorrectVersion: u64 = 1;
    const ETooSmall: u64 = 2;

    // === Constants ===
    const CURRENT_VERSION: u64 = 1;

    // === Structs ===
    struct LendingMarket<phantom P> has key {
        id: UID,
        version: u64,

        reserves: ObjectTable<TypeName, Reserve<P>>,
        obligations: ObjectTable<ID, Obligation<P>>,
        balances: Bag,

        // window duration is in seconds
        rate_limiter: RateLimiter,
        fee_receiver: address
    }

    struct LendingMarketOwnerCap<phantom P> has key, store {
        id: UID,
        lending_market_id: ID
    }

    struct ObligationOwnerCap<phantom P> has key, store {
        id: UID,
        obligation_id: ID
    }

    // === Events ===
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

    // === Public-Mutative Functions ===
    public fun create_lending_market<P: drop>(
        witness: P, 
        fee_receiver: address,
        ctx: &mut TxContext
    ): (LendingMarketOwnerCap<P>, LendingMarket<P>) {
        assert!(types::is_one_time_witness(&witness), ENotAOneTimeWitness);

        let lending_market = LendingMarket<P> {
            id: object::new(ctx),
            version: CURRENT_VERSION,
            reserves: object_table::new(ctx),
            obligations: object_table::new(ctx),
            balances: bag::new(ctx),
            rate_limiter: rate_limiter::new(rate_limiter::new_config(1, 18_446_744_073_709_551_615), 0),
            fee_receiver
        };
        
        let owner_cap = LendingMarketOwnerCap<P> { 
            id: object::new(ctx), 
            lending_market_id: object::id(&lending_market) 
        };

        (owner_cap, lending_market)
    }

    public fun share_lending_market<P>(
        _: &LendingMarketOwnerCap<P>,
        lending_market: LendingMarket<P>, 
    ) {
        assert!(lending_market.version == CURRENT_VERSION, EIncorrectVersion);
        transfer::share_object(lending_market)
    }

    /// Cache the price from pyth onto the reserve object. this needs to be done for all
    /// relevant reserves used by an Obligation before any borrow/withdraw/liquidate can be performed.
    public fun refresh_reserve_price<P, T>(
        lending_market: &mut LendingMarket<P>, 
        clock: &Clock,
        price_info: &PriceInfoObject,
    ) {
        assert!(lending_market.version == CURRENT_VERSION, EIncorrectVersion);

        let reserve = object_table::borrow_mut(&mut lending_market.reserves, type_name::get<T>());
        reserve::update_price<P>(reserve, clock, price_info);
    }

    public fun create_obligation<P>(
        lending_market: &mut LendingMarket<P>, 
        ctx: &mut TxContext
    ): ObligationOwnerCap<P> {
        assert!(lending_market.version == CURRENT_VERSION, EIncorrectVersion);

        let obligation = obligation::create_obligation<P>(ctx);
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

        let reserve = object_table::borrow_mut(&mut lending_market.reserves, type_name::get<T>());
        reserve::compound_interest(reserve, clock);

        let deposit_amount = coin::value(&deposit);
        let ctokens = reserve::deposit_liquidity_and_mint_ctokens<P, T>(
            reserve, 
            coin::into_balance(deposit)
        );

        assert!(balance::value(&ctokens) > 0, ETooSmall);

        event::emit(MintEvent<P, T> {
            in_liquidity_amount: deposit_amount,
            out_ctoken_amount: balance::value(&ctokens),
            caller: tx_context::sender(ctx)
        });

        coin::from_balance(ctokens, ctx)
    }

    public fun redeem_ctokens_and_withdraw_liquidity<P, T>(
        lending_market: &mut LendingMarket<P>, 
        clock: &Clock,
        ctokens: Coin<CToken<P, T>>,
        ctx: &mut TxContext
    ): Coin<T> {
        assert!(lending_market.version == CURRENT_VERSION, EIncorrectVersion);
        assert!(coin::value(&ctokens) > 0, ETooSmall);

        let ctoken_amount = coin::value(&ctokens);
        let reserve = object_table::borrow_mut(&mut lending_market.reserves, type_name::get<T>());

        reserve::compound_interest(reserve, clock);
        let liquidity = reserve::redeem_ctokens<P, T>(
            reserve, 
            coin::into_balance(ctokens)
        );

        assert!(balance::value(&liquidity) > 0, ETooSmall);

        event::emit(RedeemEvent<P, T> {
            in_ctoken_amount: ctoken_amount,
            out_liquidity_amount: balance::value(&liquidity),
            caller: tx_context::sender(ctx)
        });

        coin::from_balance(liquidity, ctx)
    }


    public fun deposit_ctokens_into_obligation<P, T>(
        lending_market: &mut LendingMarket<P>, 
        obligation_owner_cap: &ObligationOwnerCap<P>,
        deposit: Coin<CToken<P, T>>,
        ctx: &mut TxContext
    ) {
        assert!(lending_market.version == CURRENT_VERSION, EIncorrectVersion);
        assert!(coin::value(&deposit) > 0, ETooSmall);

        let reserve = object_table::borrow_mut(&mut lending_market.reserves, type_name::get<T>());
        let obligation = object_table::borrow_mut(
            &mut lending_market.obligations, 
            obligation_owner_cap.obligation_id
        );

        event::emit(DepositEvent<P, T> {
            ctoken_amount: coin::value(&deposit),
            obligation_id: obligation_owner_cap.obligation_id,
            caller: tx_context::sender(ctx)
        });

        obligation::deposit<P>(
            obligation, 
            reserve,
            coin::value(&deposit)
        );
        reserve::deposit_ctokens<P, T>(reserve, coin::into_balance(deposit));
    }

    /// Borrow tokens of type T. A fee is charged.
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

        let reserve = object_table::borrow_mut(&mut lending_market.reserves, type_name::get<T>());

        reserve::compound_interest(reserve, clock);
        reserve::assert_price_is_fresh(reserve, clock);

        let (receive_balance, borrow_amount_with_fees) = reserve::borrow_liquidity<P, T>(reserve, amount);
        obligation::borrow<P>(obligation, reserve, borrow_amount_with_fees);

        let borrow_value = reserve::market_value_upper_bound(reserve, decimal::from(borrow_amount_with_fees));
        rate_limiter::process_qty(
            &mut lending_market.rate_limiter, 
            clock::timestamp_ms(clock) / 1000,
            borrow_value
        );

        event::emit(BorrowEvent<P, T> {
            liquidity_amount: borrow_amount_with_fees,
            obligation_id: obligation_owner_cap.obligation_id,
            caller: tx_context::sender(ctx)
        });

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

        let reserve = object_table::borrow_mut(&mut lending_market.reserves, type_name::get<T>());

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

        let ctoken_balance = reserve::withdraw_ctokens<P, T>(reserve, amount);
        coin::from_balance(ctoken_balance, ctx)
    }

    /// Liquidate an unhealthy obligation. Leftover repay coins are returned.
    public fun liquidate<P, Repay, Withdraw>(
        lending_market: &mut LendingMarket<P>,
        obligation_id: ID,
        clock: &Clock,
        repay_coins: &mut Coin<Repay>, // mut because we probably won't use all of it
        ctx: &mut TxContext
    ): Coin<CToken<P, Withdraw>> {
        assert!(lending_market.version == CURRENT_VERSION, EIncorrectVersion);
        assert!(coin::value(repay_coins) > 0, ETooSmall);

        let obligation = object_table::borrow_mut(
            &mut lending_market.obligations, 
            obligation_id
        );
        obligation::refresh<P>(obligation, &mut lending_market.reserves, clock);

        let repay_reserve = object_table::borrow(&lending_market.reserves, type_name::get<Repay>());
        let withdraw_reserve = object_table::borrow(&lending_market.reserves, type_name::get<Withdraw>());
        let (withdraw_ctoken_amount, required_repay_amount) = obligation::liquidate<P>(
            obligation, 
            repay_reserve, 
            withdraw_reserve, 
            coin::value(repay_coins)
        );

        assert!(withdraw_ctoken_amount > 0, ETooSmall);
        assert!(required_repay_amount > 0, ETooSmall);

        let required_repay_coins = coin::split(repay_coins, required_repay_amount, ctx);
        let repay_reserve = object_table::borrow_mut(&mut lending_market.reserves, type_name::get<Repay>());
        reserve::repay_liquidity<P, Repay>(repay_reserve, coin::into_balance(required_repay_coins));

        let withdraw_reserve = object_table::borrow_mut(&mut lending_market.reserves, type_name::get<Withdraw>());
        let ctokens = reserve::withdraw_ctokens<P, Withdraw>(withdraw_reserve, withdraw_ctoken_amount);
        reserve::deduct_liquidation_fee<P, Withdraw>(withdraw_reserve, &mut ctokens);

        event::emit(LiquidateEvent<P, Repay, Withdraw> {
            repay_amount: required_repay_amount,
            withdraw_amount: withdraw_ctoken_amount,
            obligation_id,
            caller: tx_context::sender(ctx)
        });

        coin::from_balance(ctokens, ctx)
    }

    public fun repay<P, T>(
        lending_market: &mut LendingMarket<P>,
        obligation_id: ID,
        clock: &Clock,
        repay_coins: Coin<T>,
        ctx: &mut TxContext
    ) {
        assert!(lending_market.version == CURRENT_VERSION, EIncorrectVersion);

        event::emit(RepayEvent<P, T> {
            liquidity_amount: coin::value(&repay_coins),
            obligation_id,
            caller: tx_context::sender(ctx)
        });

        let obligation = object_table::borrow_mut(
            &mut lending_market.obligations, 
            obligation_id
        );

        let reserve = object_table::borrow_mut(&mut lending_market.reserves, type_name::get<T>());

        reserve::compound_interest(reserve, clock);
        obligation::repay<P>(
            obligation, 
            reserve, 
            decimal::from(coin::value(&repay_coins))
        );

        reserve::repay_liquidity<P, T>(reserve, coin::into_balance(repay_coins));
    }


    // === Public-View Functions ===
    public fun obligation_id<P>(cap: &ObligationOwnerCap<P>): ID {
        cap.obligation_id
    }

    public fun reserve<P, T>(lending_market: &LendingMarket<P>): &Reserve<P> {
        object_table::borrow(&lending_market.reserves, type_name::get<T>())
    }

    public fun obligation<P>(lending_market: &LendingMarket<P>, obligation_id: ID): &Obligation<P> {
        object_table::borrow(&lending_market.obligations, obligation_id)
    }

    // === Admin Functions ===
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

        let reserve = reserve::create_reserve<P, T>(
            config, 
            coin_metadata, 
            price_info, 
            clock, 
            ctx
        );

        object_table::add(&mut lending_market.reserves, type_name::get<T>(), reserve);
    }

    public fun update_reserve_config<P, T>(
        _: &LendingMarketOwnerCap<P>, 
        lending_market: &mut LendingMarket<P>, 
        config: ReserveConfig,
    ) {
        assert!(lending_market.version == CURRENT_VERSION, EIncorrectVersion);

        let reserve = object_table::borrow_mut(&mut lending_market.reserves, type_name::get<T>());
        reserve::update_reserve_config<P>(reserve, config);
    }

    public fun update_rate_limiter_config<P>(
        _: &LendingMarketOwnerCap<P>, 
        lending_market: &mut LendingMarket<P>, 
        clock: &Clock,
        config: RateLimiterConfig,
    ) {
        assert!(lending_market.version == CURRENT_VERSION, EIncorrectVersion);
        lending_market.rate_limiter = rate_limiter::new(config, clock::timestamp_ms(clock) / 1000);
    }

    entry fun claim_fees<P, T>(
        lending_market: &mut LendingMarket<P>,
        ctx: &mut TxContext
    ) {
        assert!(lending_market.version == CURRENT_VERSION, EIncorrectVersion);

        let reserve = object_table::borrow_mut(&mut lending_market.reserves, type_name::get<T>());
        let (ctoken_fees, fees) = reserve::claim_fees<P, T>(reserve);

        transfer::public_transfer(coin::from_balance(ctoken_fees, ctx), lending_market.fee_receiver);
        transfer::public_transfer(coin::from_balance(fees, ctx), lending_market.fee_receiver);
    }

    // === Private Functions ===
    // === Test Functions ===
    #[test_only]
    public fun print_obligation<P>(
        lending_market: &LendingMarket<P>,
        obligation_id: ID
    ) {
        let obligation: &Obligation<P> = object_table::borrow(
            &lending_market.obligations, 
            obligation_id
        );

        std::debug::print(obligation);
    }

    #[test_only]
    public fun destroy_for_testing<P>(obligation_owner_cap: ObligationOwnerCap<P>) {
        let ObligationOwnerCap { id, obligation_id: _ } = obligation_owner_cap;
        object::delete(id);
    }

    #[test_only]
    public fun destroy_lending_market_owner_cap_for_testing<P>(lending_market_owner_cap: LendingMarketOwnerCap<P>) {
        let LendingMarketOwnerCap { id, lending_market_id: _ } = lending_market_owner_cap;
        object::delete(id);
    }

    #[test_only]
    struct LENDING_MARKET has drop {}

    #[test_only]
    use sui::test_scenario::{Self, Scenario};

    #[test]
    fun test_create_lending_market() {
        use sui::test_scenario::{Self};
        use sui::test_utils::{Self};

        let owner = @0x26;
        let scenario = test_scenario::begin(owner);

        let (owner_cap, lending_market) = create_lending_market(
            LENDING_MARKET {},
            owner,
            test_scenario::ctx(&mut scenario)
        );

        test_utils::destroy(owner_cap);
        test_utils::destroy(lending_market);
        test_scenario::end(scenario);
    }

    // #[test]
    // fun test_create_reserve() {
    //     use sui::test_scenario::{Self};
    //     use suilend::test_usdc::{Self, TEST_USDC};
    //     use suilend::reserve_config::{Self};
    //     use sui::test_utils::{Self};

    //     let owner = @0x26;
    //     let scenario = test_scenario::begin(owner);
    //     let clock = clock::create_for_testing(test_scenario::ctx(&mut scenario));
    //     let (usdc_cap, usdc_metadata) = test_usdc::create_currency(
    //         test_scenario::ctx(&mut scenario));

    //     let (owner_cap, lending_market) = create_lending_market(
    //         LENDING_MARKET {},
    //         test_scenario::ctx(&mut scenario)
    //     );

    //     add_reserve<LENDING_MARKET, TEST_USDC>(
    //         &owner_cap,
    //         &mut lending_market,
    //         &usdc_price_obj,
    //         reserve_config::default_reserve_config(),
    //         &usdc_metadata,
    //         &clock,
    //         test_scenario::ctx(&mut scenario)
    //     );

    //     test_utils::destroy(owner_cap);
    //     test_utils::destroy(lending_market);
    //     test_utils::destroy(clock);
    //     test_utils::destroy(usdc_price_obj);
    //     test_utils::destroy(usdc_metadata);
    //     test_utils::destroy(usdc_cap);
    //     test_scenario::end(scenario);
    // }

    #[test_only]
    use suilend::mock_pyth::{PriceState};

    #[test_only]
    struct State {
        clock: Clock,
        owner_cap: LendingMarketOwnerCap<LENDING_MARKET>,
        lending_market: LendingMarket<LENDING_MARKET>,
        prices: PriceState
    }

    #[test_only]
    struct ReserveArgs has store {
        config: ReserveConfig,
        initial_deposit: u64
    }

    #[test_only]
    fun setup(reserve_args: Bag, scenario: &mut Scenario): State {
        use suilend::test_usdc::{TEST_USDC};
        use suilend::test_sui::{TEST_SUI};
        use suilend::reserve_config::{Self};
        use sui::test_utils::{Self};
        use suilend::mock_pyth::{Self};
        use suilend::mock_metadata::{Self};
        use std::type_name::{Self};


        let clock = clock::create_for_testing(test_scenario::ctx(scenario));
        let metadata = mock_metadata::init_metadata(test_scenario::ctx(scenario));

        let (owner_cap, lending_market) = create_lending_market(
            LENDING_MARKET {},
            tx_context::sender(test_scenario::ctx(scenario)),
            test_scenario::ctx(scenario)
        );

        let prices = mock_pyth::init_state(test_scenario::ctx(scenario));
        mock_pyth::register<TEST_USDC>(&mut prices, test_scenario::ctx(scenario));
        mock_pyth::register<TEST_SUI>(&mut prices, test_scenario::ctx(scenario));

        add_reserve<LENDING_MARKET, TEST_USDC>(
            &owner_cap,
            &mut lending_market,
            mock_pyth::get_price_obj<TEST_USDC>(&prices),
            reserve_config::default_reserve_config(),
            mock_metadata::get<TEST_USDC>(&metadata),
            &clock,
            test_scenario::ctx(scenario)
        );

        add_reserve<LENDING_MARKET, TEST_SUI>(
            &owner_cap,
            &mut lending_market,
            mock_pyth::get_price_obj<TEST_SUI>(&prices),
            reserve_config::default_reserve_config(),
            mock_metadata::get<TEST_SUI>(&metadata),
            &clock,
            test_scenario::ctx(scenario)
        );

        if (bag::contains(&reserve_args, type_name::get<TEST_USDC>())) {
            let ReserveArgs { config, initial_deposit } = bag::remove(
                &mut reserve_args, 
                type_name::get<TEST_USDC>()
            );
            let coins = coin::mint_for_testing<TEST_USDC>(
                initial_deposit, 
                test_scenario::ctx(scenario)
            );

            let ctokens = deposit_liquidity_and_mint_ctokens<LENDING_MARKET, TEST_USDC>(
                &mut lending_market,
                &clock,
                coins,
                test_scenario::ctx(scenario)
            );

            update_reserve_config<LENDING_MARKET, TEST_USDC>(
                &owner_cap,
                &mut lending_market,
                config
            );

            test_utils::destroy(ctokens);
        };
        if (bag::contains(&reserve_args, type_name::get<TEST_SUI>())) {
            let ReserveArgs { config, initial_deposit } = bag::remove(
                &mut reserve_args, 
                type_name::get<TEST_SUI>()
            );
            let coins = coin::mint_for_testing<TEST_SUI>(
                initial_deposit, 
                test_scenario::ctx(scenario)
            );

            let ctokens = deposit_liquidity_and_mint_ctokens<LENDING_MARKET, TEST_SUI>(
                &mut lending_market,
                &clock,
                coins,
                test_scenario::ctx(scenario)
            );

            update_reserve_config<LENDING_MARKET, TEST_SUI>(
                &owner_cap,
                &mut lending_market,
                config
            );

            test_utils::destroy(ctokens);
        };

        test_utils::destroy(reserve_args);
        test_utils::destroy(metadata);

        return State {
            clock,
            owner_cap,
            lending_market,
            prices
        }
    }

    #[test]
    public fun test_deposit() {
        use sui::test_utils::{Self};
        use suilend::test_usdc::{TEST_USDC};
        use std::type_name::{Self};
        use suilend::reserve_config::{Self};

        let owner = @0x26;
        let scenario = test_scenario::begin(owner);
        let State { clock, owner_cap, lending_market, prices } = setup({
            let bag = bag::new(test_scenario::ctx(&mut scenario));
            bag::add(
                &mut bag, 
                type_name::get<TEST_USDC>(), 
                ReserveArgs {
                    config: reserve_config::default_reserve_config(),
                    initial_deposit: 100 * 1_000_000
                }
            );

            bag
        }, &mut scenario);

        let obligation_owner_cap = create_obligation(
            &mut lending_market,
            test_scenario::ctx(&mut scenario)
        );

        let coins = coin::mint_for_testing<TEST_USDC>(100 * 1_000_000, test_scenario::ctx(&mut scenario));

        let ctokens = deposit_liquidity_and_mint_ctokens<LENDING_MARKET, TEST_USDC>(
            &mut lending_market,
            &clock,
            coins,
            test_scenario::ctx(&mut scenario)
        );
        assert!(coin::value(&ctokens) == 100 * 1_000_000, 0);

        let usdc_reserve = reserve<LENDING_MARKET, TEST_USDC>(&lending_market);
        assert!(reserve::available_amount<LENDING_MARKET>(usdc_reserve) == 200 * 1_000_000, 0);

        deposit_ctokens_into_obligation<LENDING_MARKET, TEST_USDC>(
            &mut lending_market,
            &obligation_owner_cap,
            ctokens,
            test_scenario::ctx(&mut scenario)
        );

        let obligation = obligation(&lending_market, obligation_id(&obligation_owner_cap));
        assert!(obligation::deposited_ctoken_amount<LENDING_MARKET, TEST_USDC>(obligation) == 100 * 1_000_000, 0);


        // TODO test state

        test_utils::destroy(obligation_owner_cap);
        test_utils::destroy(owner_cap);
        test_utils::destroy(lending_market);
        test_utils::destroy(clock);
        test_utils::destroy(prices);
        test_scenario::end(scenario);
    }

    #[test]
    public fun test_redeem() {
        use sui::test_utils::{Self};
        use suilend::test_usdc::{TEST_USDC};
        use std::type_name::{Self};
        use suilend::reserve_config::{Self};

        let owner = @0x26;
        let scenario = test_scenario::begin(owner);
        let State { clock, owner_cap, lending_market, prices } = setup({
            let bag = bag::new(test_scenario::ctx(&mut scenario));
            bag::add(
                &mut bag, 
                type_name::get<TEST_USDC>(), 
                ReserveArgs {
                    config: reserve_config::default_reserve_config(),
                    initial_deposit: 100 * 1_000_000
                }
            );

            bag
        }, &mut scenario);

        let coins = coin::mint_for_testing<TEST_USDC>(100 * 1_000_000, test_scenario::ctx(&mut scenario));
        let ctokens = deposit_liquidity_and_mint_ctokens<LENDING_MARKET, TEST_USDC>(
            &mut lending_market,
            &clock,
            coins,
            test_scenario::ctx(&mut scenario)
        );
        assert!(coin::value(&ctokens) == 100 * 1_000_000, 0);

        let usdc_reserve = reserve<LENDING_MARKET, TEST_USDC>(&lending_market);
        let old_available_amount = reserve::available_amount<LENDING_MARKET>(usdc_reserve);

        let tokens = redeem_ctokens_and_withdraw_liquidity<LENDING_MARKET, TEST_USDC>(
            &mut lending_market,
            &clock,
            ctokens,
            test_scenario::ctx(&mut scenario)
        );
        assert!(coin::value(&tokens) == 100 * 1_000_000, 0);

        let usdc_reserve = reserve<LENDING_MARKET, TEST_USDC>(&lending_market);
        let new_available_amount = reserve::available_amount<LENDING_MARKET>(usdc_reserve);
        assert!(new_available_amount == old_available_amount - 100 * 1_000_000, 0);

        test_utils::destroy(tokens);
        test_utils::destroy(owner_cap);
        test_utils::destroy(lending_market);
        test_utils::destroy(clock);
        test_utils::destroy(prices);
        test_scenario::end(scenario);
    }


    #[test]
    public fun test_borrow_and_repay() {
        use sui::test_utils::{Self};
        use suilend::test_usdc::{TEST_USDC};
        use suilend::test_sui::{TEST_SUI};
        use suilend::mock_pyth::{Self};
        use suilend::reserve_config::{Self};

        use std::type_name::{Self};

        let owner = @0x26;
        let scenario = test_scenario::begin(owner);
        let State { clock, owner_cap, lending_market, prices } = setup({
            let bag = bag::new(test_scenario::ctx(&mut scenario));
            bag::add(
                &mut bag, 
                type_name::get<TEST_USDC>(), 
                ReserveArgs {
                    config: reserve_config::default_reserve_config(),
                    initial_deposit: 100 * 1_000_000
                }
            );
            bag::add(
                &mut bag, 
                type_name::get<TEST_SUI>(), 
                ReserveArgs {
                    config: {
                        let config = reserve_config::default_reserve_config();
                        let builder = reserve_config::from(
                            &config,
                            test_scenario::ctx(&mut scenario)
                        );

                        test_utils::destroy(config);

                        reserve_config::set_borrow_fee_bps(&mut builder, 10);
                        reserve_config::build(builder, test_scenario::ctx(&mut scenario))
                    },
                    initial_deposit: 100 * 1_000_000_000
                }
            );

            bag
        }, &mut scenario);

        clock::set_for_testing(&mut clock, 1 * 1000);

        // set reserve parameters and prices
        mock_pyth::update_price<TEST_USDC>(&mut prices, 1, 0, &clock); // $1
        mock_pyth::update_price<TEST_SUI>(&mut prices, 1, 1, &clock); // $10

        // create obligation
        let obligation_owner_cap = create_obligation(
            &mut lending_market,
            test_scenario::ctx(&mut scenario)
        );

        let coins = coin::mint_for_testing<TEST_USDC>(100 * 1_000_000, test_scenario::ctx(&mut scenario));
        let ctokens = deposit_liquidity_and_mint_ctokens<LENDING_MARKET, TEST_USDC>(
            &mut lending_market,
            &clock,
            coins,
            test_scenario::ctx(&mut scenario)
        );
        deposit_ctokens_into_obligation<LENDING_MARKET, TEST_USDC>(
            &mut lending_market,
            &obligation_owner_cap,
            ctokens,
            test_scenario::ctx(&mut scenario)
        );

        refresh_reserve_price<LENDING_MARKET, TEST_USDC>(
            &mut lending_market,
            &clock,
            mock_pyth::get_price_obj<TEST_USDC>(&prices)
        );
        refresh_reserve_price<LENDING_MARKET, TEST_SUI>(
            &mut lending_market,
            &clock,
            mock_pyth::get_price_obj<TEST_SUI>(&prices)
        );

        std::debug::print(&lending_market);
        let sui = borrow<LENDING_MARKET, TEST_SUI>(
            &mut lending_market,
            &obligation_owner_cap,
            &clock,
            1 * 1_000_000_000,
            test_scenario::ctx(&mut scenario)
        );

        assert!(coin::value(&sui) == 1 * 1_000_000_000, 0);

        // state checks
        let sui_reserve = reserve<LENDING_MARKET, TEST_SUI>(&lending_market);
        assert!(reserve::borrowed_amount<LENDING_MARKET>(sui_reserve) == decimal::from(1_001_000_000), 0);

        let obligation = obligation(&lending_market, obligation_id(&obligation_owner_cap));
        assert!(obligation::borrowed_amount<LENDING_MARKET, TEST_SUI>(obligation) == decimal::from(1_001_000_000), 0);

        repay<LENDING_MARKET, TEST_SUI>(
            &mut lending_market,
            obligation_id(&obligation_owner_cap),
            &clock,
            sui,
            test_scenario::ctx(&mut scenario)
        );

        let sui_reserve = reserve<LENDING_MARKET, TEST_SUI>(&lending_market);
        assert!(reserve::borrowed_amount<LENDING_MARKET>(sui_reserve) == decimal::from(1_000_000), 0);

        let obligation = obligation(&lending_market, obligation_id(&obligation_owner_cap));
        assert!(obligation::borrowed_amount<LENDING_MARKET, TEST_SUI>(obligation) == decimal::from(1_000_000), 0);

        test_scenario::next_tx(&mut scenario, owner);

        claim_fees<LENDING_MARKET, TEST_SUI>(
            &mut lending_market,
            test_scenario::ctx(&mut scenario)
        );

        test_scenario::next_tx(&mut scenario, owner);

        let fees: Coin<TEST_SUI> = test_scenario::take_from_address(&scenario, lending_market.fee_receiver);
        assert!(coin::value(&fees) == 1_000_000, 0);

        test_utils::destroy(fees);

        test_utils::destroy(obligation_owner_cap);
        test_utils::destroy(owner_cap);
        test_utils::destroy(lending_market);
        test_utils::destroy(clock);
        test_utils::destroy(prices);
        test_scenario::end(scenario);
    }

    #[test]
    public fun test_withdraw() {
        use sui::test_utils::{Self};
        use suilend::test_usdc::{TEST_USDC};
        use suilend::test_sui::{TEST_SUI};
        use suilend::mock_pyth::{Self};
        use suilend::reserve_config::{Self};

        use std::type_name::{Self};

        let owner = @0x26;
        let scenario = test_scenario::begin(owner);
        let State { clock, owner_cap, lending_market, prices } = setup({
            let bag = bag::new(test_scenario::ctx(&mut scenario));
            bag::add(
                &mut bag, 
                type_name::get<TEST_USDC>(), 
                ReserveArgs {
                    config: reserve_config::default_reserve_config(),
                    initial_deposit: 100 * 1_000_000
                }
            );
            bag::add(
                &mut bag, 
                type_name::get<TEST_SUI>(), 
                ReserveArgs {
                    config: reserve_config::default_reserve_config(),
                    initial_deposit: 100 * 1_000_000_000
                }
            );

            bag
        }, &mut scenario);

        clock::set_for_testing(&mut clock, 1 * 1000);

        // set reserve parameters and prices
        mock_pyth::update_price<TEST_USDC>(&mut prices, 1, 0, &clock); // $1
        mock_pyth::update_price<TEST_SUI>(&mut prices, 1, 1, &clock); // $10

        // create obligation
        let obligation_owner_cap = create_obligation(
            &mut lending_market,
            test_scenario::ctx(&mut scenario)
        );

        let coins = coin::mint_for_testing<TEST_USDC>(100 * 1_000_000, test_scenario::ctx(&mut scenario));
        let ctokens = deposit_liquidity_and_mint_ctokens<LENDING_MARKET, TEST_USDC>(
            &mut lending_market,
            &clock,
            coins,
            test_scenario::ctx(&mut scenario)
        );
        deposit_ctokens_into_obligation<LENDING_MARKET, TEST_USDC>(
            &mut lending_market,
            &obligation_owner_cap,
            ctokens,
            test_scenario::ctx(&mut scenario)
        );

        refresh_reserve_price<LENDING_MARKET, TEST_USDC>(
            &mut lending_market,
            &clock,
            mock_pyth::get_price_obj<TEST_USDC>(&prices)
        );
        refresh_reserve_price<LENDING_MARKET, TEST_SUI>(
            &mut lending_market,
            &clock,
            mock_pyth::get_price_obj<TEST_SUI>(&prices)
        );

        std::debug::print(&lending_market);
        let sui = borrow<LENDING_MARKET, TEST_SUI>(
            &mut lending_market,
            &obligation_owner_cap,
            &clock,
            2_500_000_000,
            test_scenario::ctx(&mut scenario)
        );


        let obligation = obligation(&lending_market, obligation_id(&obligation_owner_cap));
        let old_deposited_amount = obligation::deposited_ctoken_amount<LENDING_MARKET, TEST_USDC>(obligation);

        let usdc = withdraw_ctokens<LENDING_MARKET, TEST_USDC>(
            &mut lending_market,
            &obligation_owner_cap,
            &clock,
            50 * 1_000_000,
            test_scenario::ctx(&mut scenario)
        );

        let obligation = obligation(&lending_market, obligation_id(&obligation_owner_cap));
        let deposited_amount = obligation::deposited_ctoken_amount<LENDING_MARKET, TEST_USDC>(obligation);

        assert!(coin::value(&usdc) == 50_000_000, 0);
        assert!(deposited_amount == old_deposited_amount - 50 * 1_000_000, 0);

        test_utils::destroy(sui);
        test_utils::destroy(usdc);
        test_utils::destroy(obligation_owner_cap);
        test_utils::destroy(owner_cap);
        test_utils::destroy(lending_market);
        test_utils::destroy(clock);
        test_utils::destroy(prices);
        test_scenario::end(scenario);
    }

    #[test]
    public fun test_liquidate() {
        use sui::test_utils::{Self};
        use suilend::test_usdc::{TEST_USDC};
        use suilend::test_sui::{TEST_SUI};
        use suilend::mock_pyth::{Self};
        use suilend::reserve_config::{Self};
        use suilend::decimal::{sub};

        use std::type_name::{Self};

        let owner = @0x26;
        let scenario = test_scenario::begin(owner);
        let State { clock, owner_cap, lending_market, prices } = setup({
            let bag = bag::new(test_scenario::ctx(&mut scenario));
            bag::add(
                &mut bag, 
                type_name::get<TEST_USDC>(), 
                ReserveArgs {
                    config: reserve_config::default_reserve_config(),
                    initial_deposit: 100 * 1_000_000
                }
            );
            bag::add(
                &mut bag, 
                type_name::get<TEST_SUI>(), 
                ReserveArgs {
                    config: reserve_config::default_reserve_config(),
                    initial_deposit: 100 * 1_000_000_000
                }
            );

            bag
        }, &mut scenario);

        clock::set_for_testing(&mut clock, 1 * 1000);

        // set reserve parameters and prices
        mock_pyth::update_price<TEST_USDC>(&mut prices, 1, 0, &clock); // $1
        mock_pyth::update_price<TEST_SUI>(&mut prices, 1, 1, &clock); // $10

        // create obligation
        let obligation_owner_cap = create_obligation(
            &mut lending_market,
            test_scenario::ctx(&mut scenario)
        );

        let coins = coin::mint_for_testing<TEST_USDC>(100 * 1_000_000, test_scenario::ctx(&mut scenario));
        let ctokens = deposit_liquidity_and_mint_ctokens<LENDING_MARKET, TEST_USDC>(
            &mut lending_market,
            &clock,
            coins,
            test_scenario::ctx(&mut scenario)
        );
        deposit_ctokens_into_obligation<LENDING_MARKET, TEST_USDC>(
            &mut lending_market,
            &obligation_owner_cap,
            ctokens,
            test_scenario::ctx(&mut scenario)
        );

        refresh_reserve_price<LENDING_MARKET, TEST_USDC>(
            &mut lending_market,
            &clock,
            mock_pyth::get_price_obj<TEST_USDC>(&prices)
        );
        refresh_reserve_price<LENDING_MARKET, TEST_SUI>(
            &mut lending_market,
            &clock,
            mock_pyth::get_price_obj<TEST_SUI>(&prices)
        );

        let sui = borrow<LENDING_MARKET, TEST_SUI>(
            &mut lending_market,
            &obligation_owner_cap,
            &clock,
            5 * 1_000_000_000,
            test_scenario::ctx(&mut scenario)
        );
        test_utils::destroy(sui);

        // set the open and close ltvs of the usdc reserve to 0
        let usdc_reserve = reserve<LENDING_MARKET, TEST_USDC>(&lending_market);
        update_reserve_config<LENDING_MARKET, TEST_USDC>(
            &owner_cap,
            &mut lending_market,
            {
                let builder = reserve_config::from(
                    reserve::config(usdc_reserve), 
                    test_scenario::ctx(&mut scenario)
                );
                reserve_config::set_open_ltv_pct(&mut builder, 0);
                reserve_config::set_close_ltv_pct(&mut builder, 0);
                reserve_config::set_liquidation_bonus_bps(&mut builder, 1_000);

                reserve_config::build(builder, test_scenario::ctx(&mut scenario))
            }
        );

        let obligation = obligation(&lending_market, obligation_id(&obligation_owner_cap));

        let sui_reserve = reserve<LENDING_MARKET, TEST_SUI>(&lending_market);
        let old_reserve_borrowed_amount = reserve::borrowed_amount<LENDING_MARKET>(sui_reserve);

        let old_deposited_amount = obligation::deposited_ctoken_amount<LENDING_MARKET, TEST_USDC>(obligation);
        let old_borrowed_amount = obligation::borrowed_amount<LENDING_MARKET, TEST_SUI>(obligation);

        // liquidate the obligation
        let sui = coin::mint_for_testing<TEST_SUI>(5 * 1_000_000_000, test_scenario::ctx(&mut scenario));
        let usdc = liquidate<LENDING_MARKET, TEST_SUI, TEST_USDC>(
            &mut lending_market,
            obligation_id(&obligation_owner_cap),
            &clock,
            &mut sui,
            test_scenario::ctx(&mut scenario)
        );

        assert!(coin::value(&sui) == 4 * 1_000_000_000, 0);
        assert!(coin::value(&usdc) == 10 * 1_000_000 + 500_000, 0);

        let obligation = obligation(&lending_market, obligation_id(&obligation_owner_cap));

        let sui_reserve = reserve<LENDING_MARKET, TEST_SUI>(&lending_market);
        let reserve_borrowed_amount = reserve::borrowed_amount<LENDING_MARKET>(sui_reserve);

        let deposited_amount = obligation::deposited_ctoken_amount<LENDING_MARKET, TEST_USDC>(obligation);
        let borrowed_amount = obligation::borrowed_amount<LENDING_MARKET, TEST_SUI>(obligation);

        assert!(reserve_borrowed_amount == sub(old_reserve_borrowed_amount, decimal::from(1_000_000_000)), 0);
        assert!(borrowed_amount == sub(old_borrowed_amount, decimal::from(1_000_000_000)), 0);
        assert!(deposited_amount == old_deposited_amount - 11 * 1_000_000, 0);

        // claim fees
        test_scenario::next_tx(&mut scenario, owner);
        claim_fees<LENDING_MARKET, TEST_USDC>(
            &mut lending_market,
            test_scenario::ctx(&mut scenario)
        );

        test_scenario::next_tx(&mut scenario, owner);
        let ctoken_fees: Coin<CToken<LENDING_MARKET, TEST_USDC>> = test_scenario::take_from_address(
            &scenario, 
            lending_market.fee_receiver
        );
        assert!(coin::value(&ctoken_fees) == 500_000, 0);

        test_utils::destroy(ctoken_fees);
        test_utils::destroy(sui);
        test_utils::destroy(usdc);
        test_utils::destroy(obligation_owner_cap);
        test_utils::destroy(owner_cap);
        test_utils::destroy(lending_market);
        test_utils::destroy(clock);
        test_utils::destroy(prices);
        test_scenario::end(scenario);
    }
}
