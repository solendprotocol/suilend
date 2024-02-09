module suilend::reserve {
    // === Imports ===
    use std::type_name::{Self, TypeName};
    use sui::tx_context::{TxContext};
    use sui::object::{Self, UID, ID};
    use suilend::cell::{Self, Cell};
    use std::option::{Self};
    use sui::event::{Self};
    use suilend::oracles::{Self};
    use suilend::decimal::{Decimal, Self, add, sub, mul, div, eq, floor, pow, le, ceil, min, max};
    use sui::clock::{Self, Clock};
    use sui::coin::{Self, CoinMetadata};
    use sui::math::{Self};
    use pyth::price_identifier::{PriceIdentifier};
    use pyth::price_info::{PriceInfoObject};
    use std::vector::{Self};
    use suilend::reserve_config::{
        Self, 
        ReserveConfig, 
        calculate_apr, 
        deposit_limit, 
        borrow_limit, 
        borrow_fee,
        liquidation_fee,
        spread_fee
    };

    #[test_only]
    use sui::test_scenario::{Self};

    // === Friends ===
    friend suilend::lending_market;
    friend suilend::obligation;

    // === Errors ===
    const EPriceStale: u64 = 0;
    const EPriceIdentifierMismatch: u64 = 1;
    const EDepositLimitExceeded: u64 = 2;
    const EBorrowLimitExceeded: u64 = 3;
    const EInvalidPrice: u64 = 4;
    const EMinAvailableAmountViolated: u64 = 5;

    // === Constants ===
    const PRICE_STALENESS_THRESHOLD_S: u64 = 0;
    // to prevent certain rounding bug attacks, we make sure that X amount of the underlying token_amount
    // can never be withdrawn or borrowed.
    const MIN_AVAILABLE_AMOUNT: u64 = 100; 

    // === Structs ===
    struct Reserve<phantom P> has key, store {
        id: UID,
        coin_type: TypeName,

        config: Cell<ReserveConfig>,
        mint_decimals: u8,

        // oracles
        price_identifier: PriceIdentifier,

        price: Decimal,
        smoothed_price: Decimal,
        price_last_update_timestamp_s: u64,

        available_amount: u64,
        ctoken_supply: u64,
        borrowed_amount: Decimal,

        cumulative_borrow_rate: Decimal,
        interest_last_update_timestamp_s: u64,

        unclaimed_spread_fees: Decimal
    }


    // === Events ===
    struct InterestUpdateEvent<phantom P> has drop, copy {
        reserve_id: ID,
        cumulative_borrow_rate: Decimal,
        available_amount: u64,
        borrowed_amount: Decimal,
        ctoken_supply: u64,
        timestamp_s: u64
    }

    // === Public-View Functions ===
    public fun coin_type<P>(reserve: &Reserve<P>): TypeName {
        reserve.coin_type
    }

    // make sure we are using the latest published price on sui
    public fun assert_price_is_fresh<P>(reserve: &Reserve<P>, clock: &Clock) {
        let cur_time_s = clock::timestamp_ms(clock) / 1000;
        assert!(
            cur_time_s - reserve.price_last_update_timestamp_s <= PRICE_STALENESS_THRESHOLD_S, 
            EPriceStale
        );
    }

    // if SUI = $1, this returns decimal::from(1).
    public fun price<P>(reserve: &Reserve<P>): Decimal {
        reserve.price
    }

    public fun price_lower_bound<P>(reserve: &Reserve<P>): Decimal {
        min(reserve.price, reserve.smoothed_price)
    }

    public fun price_upper_bound<P>(reserve: &Reserve<P>): Decimal {
        max(reserve.price, reserve.smoothed_price)
    }

    public fun market_value<P>(
        reserve: &Reserve<P>, 
        liquidity_amount: Decimal
    ): Decimal {
        div(
            mul(
                price(reserve),
                liquidity_amount
            ),
            decimal::from(math::pow(10, reserve.mint_decimals))
        )
    }

    public fun market_value_lower_bound<P>(
        reserve: &Reserve<P>, 
        liquidity_amount: Decimal
    ): Decimal {
        div(
            mul(
                price_lower_bound(reserve),
                liquidity_amount
            ),
            decimal::from(math::pow(10, reserve.mint_decimals))
        )
    }

    public fun market_value_upper_bound<P>(
        reserve: &Reserve<P>, 
        liquidity_amount: Decimal
    ): Decimal {
        div(
            mul(
                price_upper_bound(reserve),
                liquidity_amount
            ),
            decimal::from(math::pow(10, reserve.mint_decimals))
        )
    }

    public fun ctoken_market_value<P>(
        reserve: &Reserve<P>, 
        ctoken_amount: u64
    ): Decimal {
        // TODO should i floor here?
        let liquidity_amount = mul(
            decimal::from(ctoken_amount),
            ctoken_ratio(reserve)
        );

        market_value(reserve, liquidity_amount)
    }

    public fun ctoken_market_value_lower_bound<P>(
        reserve: &Reserve<P>, 
        ctoken_amount: u64
    ): Decimal {
        // TODO should i floor here?
        let liquidity_amount = mul(
            decimal::from(ctoken_amount),
            ctoken_ratio(reserve)
        );

        market_value_lower_bound(reserve, liquidity_amount)
    }

    public fun ctoken_market_value_upper_bound<P>(
        reserve: &Reserve<P>, 
        ctoken_amount: u64
    ): Decimal {
        // TODO should i floor here?
        let liquidity_amount = mul(
            decimal::from(ctoken_amount),
            ctoken_ratio(reserve)
        );

        market_value_upper_bound(reserve, liquidity_amount)
    }


    public fun cumulative_borrow_rate<P>(reserve: &Reserve<P>): Decimal {
        reserve.cumulative_borrow_rate
    }

    public fun total_supply<P>(reserve: &Reserve<P>): Decimal {
        // TODO: saturating sub here? might need to if we implement a socialized loss
        // mechanism
        sub(
            add(
                decimal::from(reserve.available_amount),
                reserve.borrowed_amount
            ),
            reserve.unclaimed_spread_fees
        )
    }

    public fun calculate_utilization_rate<P>(reserve: &Reserve<P>): Decimal {
        let total_supply_excluding_fees = add(
            decimal::from(reserve.available_amount),
            reserve.borrowed_amount
        );

        if (eq(total_supply_excluding_fees, decimal::from(0))) {
            decimal::from(0)
        }
        else {
            div(reserve.borrowed_amount, total_supply_excluding_fees)
        }
    }

    // always greater than or equal to one
    public fun ctoken_ratio<P>(reserve: &Reserve<P>): Decimal {
        let total_supply = total_supply(reserve);

        // this branch is only used once -- when the reserve is first initialized and has 
        // zero deposits. after that, borrows and redemptions won't let the ctoken supply fall 
        // below MIN_AVAILABLE_AMOUNT
        if (reserve.ctoken_supply == 0) {
            decimal::from(1)
        }
        else {
            div(
                total_supply,
                decimal::from(reserve.ctoken_supply)
            )
        }
    }

    public fun config<P>(reserve: &Reserve<P>): &ReserveConfig {
        cell::get(&reserve.config)
    }

    public fun calculate_borrow_fee<P>(
        reserve: &Reserve<P>,
        borrow_amount: u64
    ): u64 {
        ceil(mul(decimal::from(borrow_amount), borrow_fee(config(reserve))))
    }

    public fun calculate_liquidation_fee<P>(
        reserve: &Reserve<P>,
        withdraw_amount: u64
    ): u64 {
        ceil(mul(decimal::from(withdraw_amount), liquidation_fee(config(reserve))))
    }

    // === Public-Friend Functions
    public(friend) fun create_reserve<P, T>(
        config: ReserveConfig, 
        coin_metadata: &CoinMetadata<T>,
        price_info_obj: &PriceInfoObject, 
        clock: &Clock, 
        ctx: &mut TxContext
    ): Reserve<P> {

        let (price_decimal, smoothed_price_decimal, price_identifier) = oracles::get_pyth_price_and_identifier(price_info_obj, clock);
        assert!(option::is_some(&price_decimal), EInvalidPrice);

        Reserve {
            id: object::new(ctx),
            coin_type: type_name::get<T>(),
            config: cell::new(config),
            mint_decimals: coin::get_decimals(coin_metadata),
            price_identifier,
            price: option::extract(&mut price_decimal),
            smoothed_price: smoothed_price_decimal,
            price_last_update_timestamp_s: clock::timestamp_ms(clock) / 1000,
            available_amount: 0,
            ctoken_supply: 0,
            borrowed_amount: decimal::from(0),
            cumulative_borrow_rate: decimal::from(1),
            interest_last_update_timestamp_s: clock::timestamp_ms(clock) / 1000,
            unclaimed_spread_fees: decimal::from(0)
        }
    }

    public(friend) fun update_reserve_config<P>(
        reserve: &mut Reserve<P>, 
        config: ReserveConfig, 
    ) {
        let old = cell::set(&mut reserve.config, config);
        reserve_config::destroy(old);
    }

    public(friend) fun update_price<P>(
        reserve: &mut Reserve<P>, 
        clock: &Clock,
        price_info_obj: &PriceInfoObject
    ) {
        let (price_decimal, _, price_identifier) = oracles::get_pyth_price_and_identifier(price_info_obj, clock);
        assert!(price_identifier == reserve.price_identifier, EPriceIdentifierMismatch);
        assert!(option::is_some(&price_decimal), EInvalidPrice);

        reserve.price = option::extract(&mut price_decimal);
        reserve.price_last_update_timestamp_s = clock::timestamp_ms(clock) / 1000;
    }

    // compound interest every second
    public(friend) fun compound_interest<P>(reserve: &mut Reserve<P>, clock: &Clock) {
        let cur_time_s = clock::timestamp_ms(clock) / 1000;
        let time_elapsed_s = cur_time_s - reserve.interest_last_update_timestamp_s;
        if (time_elapsed_s == 0) {
            return
        };

        // I(t + n) = I(t) * (1 + apr()/SECONDS_IN_YEAR) ^ n
        let utilization_rate = calculate_utilization_rate(reserve);
        let compounded_borrow_rate = pow(
            add(
                decimal::from(1),
                div(
                    calculate_apr(config(reserve), utilization_rate),
                    decimal::from(365 * 24 * 60 * 60)
                )
            ),
            time_elapsed_s
        );

        reserve.cumulative_borrow_rate = mul(
            reserve.cumulative_borrow_rate,
            compounded_borrow_rate
        );

        let net_new_debt = mul(
            reserve.borrowed_amount,
            sub(compounded_borrow_rate, decimal::from(1))
        );

        reserve.unclaimed_spread_fees = add(
            reserve.unclaimed_spread_fees,
            mul(net_new_debt, spread_fee(config(reserve)))
        );

        reserve.borrowed_amount = add(
            reserve.borrowed_amount,
            net_new_debt 
        );

        reserve.interest_last_update_timestamp_s = cur_time_s;

        event::emit(InterestUpdateEvent<P> {
            reserve_id: object::uid_to_inner(&reserve.id),
            cumulative_borrow_rate: reserve.cumulative_borrow_rate,
            available_amount: reserve.available_amount,
            borrowed_amount: reserve.borrowed_amount,
            ctoken_supply: reserve.ctoken_supply,
            timestamp_s: cur_time_s
        });
    }

    public(friend) fun claim_spread_fees<P>(reserve: &mut Reserve<P>): u64 {
        let claimable_spread_fees = floor(min(
            decimal::from(reserve.available_amount),
            reserve.unclaimed_spread_fees
        ));

        reserve.available_amount = reserve.available_amount - claimable_spread_fees;
        reserve.unclaimed_spread_fees = sub(
            reserve.unclaimed_spread_fees,
            decimal::from(claimable_spread_fees)
        );

        claimable_spread_fees
    }

    public(friend) fun deposit_liquidity_and_mint_ctokens<P>(
        reserve: &mut Reserve<P>, 
        liquidity_amount: u64, 
    ): u64 {
        let ctoken_ratio = ctoken_ratio(reserve);

        let new_ctokens = floor(div(
            decimal::from(liquidity_amount),
            ctoken_ratio
        ));

        reserve.available_amount = reserve.available_amount + liquidity_amount;
        reserve.ctoken_supply = reserve.ctoken_supply + new_ctokens;

        assert!(
            le(total_supply(reserve), decimal::from(deposit_limit(config(reserve)))), 
            EDepositLimitExceeded
        );

        new_ctokens
    }

    public(friend) fun redeem_ctokens<P>(
        reserve: &mut Reserve<P>, 
        ctoken_amount: u64, 
    ): u64 {
        let ctoken_ratio = ctoken_ratio(reserve);

        let liquidity_amount = floor(mul(
            decimal::from(ctoken_amount),
            ctoken_ratio
        ));

        reserve.available_amount = reserve.available_amount - liquidity_amount;
        reserve.ctoken_supply = reserve.ctoken_supply - ctoken_amount;

        assert!(reserve.available_amount >= MIN_AVAILABLE_AMOUNT, EMinAvailableAmountViolated);

        liquidity_amount
    }

    public(friend) fun borrow_liquidity<P>(
        reserve: &mut Reserve<P>, 
        liquidity_amount: u64
    ) {
        reserve.available_amount = reserve.available_amount - liquidity_amount;
        reserve.borrowed_amount = add(reserve.borrowed_amount, decimal::from(liquidity_amount));

        assert!(
            le(reserve.borrowed_amount, decimal::from(borrow_limit(config(reserve)))), 
            EBorrowLimitExceeded 
        );

        assert!(reserve.available_amount >= MIN_AVAILABLE_AMOUNT, EMinAvailableAmountViolated);
    }

    public(friend) fun repay_liquidity<P>(
        reserve: &mut Reserve<P>, 
        repay_amount: u64
    ) {
        reserve.available_amount = reserve.available_amount + repay_amount;
        reserve.borrowed_amount = sub(reserve.borrowed_amount, decimal::from(repay_amount));
    }

    // === Test Functions ===
    #[test_only]
    fun example_reserve_config(): ReserveConfig {
        let owner = @0x26;
        let scenario = test_scenario::begin(owner);

        let config = reserve_config::create_reserve_config(
            // open ltv pct
            10,
            // close ltv pct
            10,
            // borrow weight bps
            10_000,
            // deposit_limit
            100_000,
            // borrow_limit
            100_000,
            // liquidation bonus pct
            5,
            // borrow fee bps
            10,
            // spread fee bps
            2000,
            // liquidation fee bps
            3000,
            // utils
            {
                let v = vector::empty();
                vector::push_back(&mut v, 0);
                vector::push_back(&mut v, 100);
                v
            },
            // aprs
            {
                let v = vector::empty();
                vector::push_back(&mut v, 0);
                vector::push_back(&mut v, 31536000);
                v
            },
            test_scenario::ctx(&mut scenario)
        );

        test_scenario::end(scenario);
        config
    }

    #[test_only]
    public fun update_price_for_testing<P>(
        reserve: &mut Reserve<P>, 
        clock: &Clock,
        price_decimal: Decimal,
        smoothed_price_decimal: Decimal
    ) {
        reserve.price = price_decimal;
        reserve.smoothed_price = smoothed_price_decimal;
        reserve.price_last_update_timestamp_s = clock::timestamp_ms(clock) / 1000;
    }

    #[test_only]
    use pyth::price_identifier::{Self};

    #[test_only]
    fun example_price_identifier(): PriceIdentifier {
        let v = vector::empty();
        let i = 0;
        while (i < 32) {
            vector::push_back(&mut v, i);
            i = i + 1;
        };

        price_identifier::from_byte_vec(v)
    }

    #[test]
    fun test_accessors() {
        use suilend::test_usdc::{TEST_USDC};
        let owner = @0x26;
        let scenario = test_scenario::begin(owner);

        let reserve = Reserve<TEST_USDC> {
            id: object::new(test_scenario::ctx(&mut scenario)),
            coin_type: type_name::get<TEST_USDC>(),
            config: cell::new(example_reserve_config()),
            mint_decimals: 9,
            price_identifier: example_price_identifier(),
            price: decimal::from(1),
            smoothed_price: decimal::from(2),
            price_last_update_timestamp_s: 0,
            available_amount: 500,
            ctoken_supply: 200,
            borrowed_amount: decimal::from(500),
            cumulative_borrow_rate: decimal::from(1),
            interest_last_update_timestamp_s: 0,
            unclaimed_spread_fees: decimal::from(0)
        };

        assert!(market_value(&reserve, decimal::from(10_000_000_000)) == decimal::from(10), 0);
        assert!(ctoken_market_value(&reserve, 10_000_000_000) == decimal::from(50), 0);
        assert!(cumulative_borrow_rate(&reserve) == decimal::from(1), 0);
        assert!(total_supply(&reserve) == decimal::from(1000), 0);
        assert!(calculate_utilization_rate(&reserve) == decimal::from_percent(50), 0);
        assert!(ctoken_ratio(&reserve) == decimal::from(5), 0);

        destroy_for_testing(reserve);
        test_scenario::end(scenario);
    }

    #[test]
    fun test_compound_interest() {
        use suilend::test_usdc::{TEST_USDC};
        use sui::test_scenario::{Self};

        let owner = @0x26;
        let scenario = test_scenario::begin(owner);

        let reserve = Reserve<TEST_USDC> {
            id: object::new(test_scenario::ctx(&mut scenario)),
            coin_type: type_name::get<TEST_USDC>(),
            config: cell::new(example_reserve_config()),
            mint_decimals: 9,
            price_identifier: example_price_identifier(),
            price: decimal::from(1),
            smoothed_price: decimal::from(1),
            price_last_update_timestamp_s: 0,
            available_amount: 500,
            ctoken_supply: 200,
            borrowed_amount: decimal::from(500),
            cumulative_borrow_rate: decimal::from(1),
            interest_last_update_timestamp_s: 0,
            unclaimed_spread_fees: decimal::from(0)
        };

        let clock = clock::create_for_testing(test_scenario::ctx(&mut scenario));
        clock::set_for_testing(&mut clock, 1000); 

        compound_interest(&mut reserve, &clock);

        assert!(cumulative_borrow_rate(&reserve) == decimal::from_bps(10_050), 0);
        assert!(reserve.borrowed_amount == add(decimal::from(500), decimal::from_percent(250)), 0);
        assert!(reserve.unclaimed_spread_fees == decimal::from_percent(50), 0);
        assert!(ctoken_ratio(&reserve) == decimal::from_percent_u64(501), 0);
        assert!(reserve.interest_last_update_timestamp_s == 1, 0);


        // test idempotency

        compound_interest(&mut reserve, &clock);

        assert!(cumulative_borrow_rate(&reserve) == decimal::from_bps(10_050), 0);
        assert!(reserve.borrowed_amount == add(decimal::from(500), decimal::from_percent(250)), 0);
        assert!(reserve.unclaimed_spread_fees == decimal::from_percent(50), 0);
        assert!(reserve.interest_last_update_timestamp_s == 1, 0);

        clock::destroy_for_testing(clock);
        destroy_for_testing(reserve);

        test_scenario::end(scenario);
    }

    #[test]
    fun test_deposit_happy() {
        use suilend::test_usdc::{TEST_USDC};
        use sui::test_scenario::{Self};

        let owner = @0x26;
        let scenario = test_scenario::begin(owner);

        let reserve = Reserve<TEST_USDC> {
            id: object::new(test_scenario::ctx(&mut scenario)),
            coin_type: type_name::get<TEST_USDC>(),
            config: cell::new(example_reserve_config()),
            mint_decimals: 9,
            price_identifier: example_price_identifier(),
            price: decimal::from(1),
            smoothed_price: decimal::from(1),
            price_last_update_timestamp_s: 0,
            available_amount: 500,
            ctoken_supply: 200,
            borrowed_amount: decimal::from(500),
            cumulative_borrow_rate: decimal::from(1),
            interest_last_update_timestamp_s: 1,
            unclaimed_spread_fees: decimal::from(0)
        };

        let ctoken_amount = deposit_liquidity_and_mint_ctokens(&mut reserve, 1000);
        assert!(ctoken_amount == 200, 0);
        assert!(reserve.available_amount == 1500, 0);
        assert!(reserve.ctoken_supply == 400, 0);

        destroy_for_testing(reserve);

        test_scenario::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = EDepositLimitExceeded)]
    fun test_deposit_fail() {
        use suilend::test_usdc::{TEST_USDC};
        use sui::test_scenario::{Self};

        let owner = @0x26;
        let scenario = test_scenario::begin(owner);

        let config = reserve_config::create_reserve_config(
            // open ltv pct
            10,
            // close ltv pct
            10,
            // borrow weight bps
            10_000,
            // deposit_limit
            1000,
            // borrow_limit
            1,
            // liquidation bonus pct
            5,
            // borrow fee bps
            10,
            // spread fee bps
            2000,
            // liquidation fee bps
            3000,
            // utils
            {
                let v = vector::empty();
                vector::push_back(&mut v, 0);
                vector::push_back(&mut v, 100);
                v
            },
            // aprs
            {
                let v = vector::empty();
                vector::push_back(&mut v, 0);
                vector::push_back(&mut v, 31536000);
                v
            },
            test_scenario::ctx(&mut scenario)
        );

        let reserve = Reserve<TEST_USDC> {
            id: object::new(test_scenario::ctx(&mut scenario)),
            coin_type: type_name::get<TEST_USDC>(),
            config: cell::new(config),
            mint_decimals: 9,
            price_identifier: example_price_identifier(),
            price: decimal::from(1),
            smoothed_price: decimal::from(1),
            price_last_update_timestamp_s: 0,
            available_amount: 500,
            ctoken_supply: 200,
            borrowed_amount: decimal::from(500),
            cumulative_borrow_rate: decimal::from(1),
            interest_last_update_timestamp_s: 1,
            unclaimed_spread_fees: decimal::from(0)
        };

        deposit_liquidity_and_mint_ctokens(&mut reserve, 1);

        destroy_for_testing(reserve);
        test_scenario::end(scenario);
    }

    #[test]
    fun test_redeem_happy() {
        use suilend::test_usdc::{TEST_USDC};
        use sui::test_scenario::{Self};

        let owner = @0x26;
        let scenario = test_scenario::begin(owner);

        let reserve = Reserve<TEST_USDC> {
            id: object::new(test_scenario::ctx(&mut scenario)),
            coin_type: type_name::get<TEST_USDC>(),
            config: cell::new(example_reserve_config()),
            mint_decimals: 9,
            price_identifier: example_price_identifier(),
            price: decimal::from(1),
            smoothed_price: decimal::from(1),
            price_last_update_timestamp_s: 0,
            available_amount: 500,
            ctoken_supply: 200,
            borrowed_amount: decimal::from(500),
            cumulative_borrow_rate: decimal::from(1),
            interest_last_update_timestamp_s: 1,
            unclaimed_spread_fees: decimal::from(0)
        };

        let ctoken_amount = deposit_liquidity_and_mint_ctokens(&mut reserve, 1000);

        let available_amount_old = reserve.available_amount;
        let ctoken_supply_old = reserve.ctoken_supply;

        let token_amount = redeem_ctokens(&mut reserve, ctoken_amount);

        assert!(token_amount == 1000, 0);
        assert!(reserve.available_amount == available_amount_old - 1000, 0);
        assert!(reserve.ctoken_supply == ctoken_supply_old - 200, 0);

        destroy_for_testing(reserve);

        test_scenario::end(scenario);
    }

    #[test]
    fun test_borrow_happy() {
        use suilend::test_usdc::{TEST_USDC};
        use sui::test_scenario::{Self};

        let owner = @0x26;
        let scenario = test_scenario::begin(owner);

        let reserve = Reserve<TEST_USDC> {
            id: object::new(test_scenario::ctx(&mut scenario)),
            coin_type: type_name::get<TEST_USDC>(),
            config: cell::new(example_reserve_config()),
            mint_decimals: 9,
            price_identifier: example_price_identifier(),
            price: decimal::from(1),
            smoothed_price: decimal::from(1),
            price_last_update_timestamp_s: 0,
            available_amount: 500,
            ctoken_supply: 200,
            borrowed_amount: decimal::from(500),
            cumulative_borrow_rate: decimal::from(1),
            interest_last_update_timestamp_s: 1,
            unclaimed_spread_fees: decimal::from(0)
        };

        borrow_liquidity(&mut reserve, 400);
        assert!(reserve.available_amount == 100, 0);
        assert!(reserve.borrowed_amount == decimal::from(900), 0);

        destroy_for_testing(reserve);

        test_scenario::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = EBorrowLimitExceeded)]
    fun test_borrow_fail() {
        use suilend::test_usdc::{TEST_USDC};
        use sui::test_scenario::{Self};

        let owner = @0x26;
        let scenario = test_scenario::begin(owner);

        let config = reserve_config::create_reserve_config(
            // open ltv pct
            10,
            // close ltv pct
            10,
            // borrow weight bps
            10_000,
            // deposit_limit
            1000,
            // borrow_limit
            500,
            // liquidation bonus pct
            5,
            // borrow fee bps
            10,
            // spread fee bps
            2000,
            // liquidation fee bps
            3000,
            // utils
            {
                let v = vector::empty();
                vector::push_back(&mut v, 0);
                vector::push_back(&mut v, 100);
                v
            },
            // aprs
            {
                let v = vector::empty();
                vector::push_back(&mut v, 0);
                vector::push_back(&mut v, 31536000);
                v
            },
            test_scenario::ctx(&mut scenario)
        );

        let reserve = Reserve<TEST_USDC> {
            id: object::new(test_scenario::ctx(&mut scenario)),
            coin_type: type_name::get<TEST_USDC>(),
            config: cell::new(config),
            mint_decimals: 9,
            price_identifier: example_price_identifier(),
            price: decimal::from(1),
            smoothed_price: decimal::from(1),
            price_last_update_timestamp_s: 0,
            available_amount: 500,
            ctoken_supply: 200,
            borrowed_amount: decimal::from(500),
            cumulative_borrow_rate: decimal::from(1),
            interest_last_update_timestamp_s: 1,
            unclaimed_spread_fees: decimal::from(0)
        };

        borrow_liquidity(&mut reserve, 1);
        destroy_for_testing(reserve);
        test_scenario::end(scenario);
    }

    #[test]
    fun test_repay_happy() {
        use suilend::test_usdc::{TEST_USDC};
        use sui::test_scenario::{Self};

        let owner = @0x26;
        let scenario = test_scenario::begin(owner);

        let reserve = Reserve<TEST_USDC> {
            id: object::new(test_scenario::ctx(&mut scenario)),
            coin_type: type_name::get<TEST_USDC>(),
            config: cell::new(example_reserve_config()),
            mint_decimals: 9,
            price_identifier: example_price_identifier(),
            price: decimal::from(1),
            smoothed_price: decimal::from(1),
            price_last_update_timestamp_s: 0,
            available_amount: 500,
            ctoken_supply: 200,
            borrowed_amount: decimal::from(500),
            cumulative_borrow_rate: decimal::from(1),
            interest_last_update_timestamp_s: 1,
            unclaimed_spread_fees: decimal::from(0)
        };

        borrow_liquidity(&mut reserve, 400);

        assert!(reserve.available_amount == 100, 0);
        assert!(reserve.borrowed_amount == decimal::from(900), 0);

        repay_liquidity(&mut reserve, 400);

        assert!(reserve.available_amount == 500, 0);
        assert!(reserve.borrowed_amount == decimal::from(500), 0);

        destroy_for_testing(reserve);

        test_scenario::end(scenario);
    }

    #[test_only]
    public fun create_for_testing<P, T>(
        config: ReserveConfig,
        mint_decimals: u8,
        price: Decimal,
        price_last_update_timestamp_s: u64,
        available_amount: u64,
        ctoken_supply: u64,
        borrowed_amount: Decimal,
        cumulative_borrow_rate: Decimal,
        interest_last_update_timestamp_s: u64,
        ctx: &mut TxContext
    ): Reserve<P> {
        let reserve = Reserve<P> {
            id: object::new(ctx),
            coin_type: type_name::get<T>(),
            config: cell::new(config),
            mint_decimals,
            price_identifier: {
                let v = vector::empty();
                let i = 0;
                while (i < 32) {
                    vector::push_back(&mut v, 0);
                    i = i + 1;
                };

                price_identifier::from_byte_vec(v)
            },
            price,
            smoothed_price: price,
            price_last_update_timestamp_s,
            available_amount,
            ctoken_supply,
            borrowed_amount,
            cumulative_borrow_rate,
            interest_last_update_timestamp_s,
            unclaimed_spread_fees: decimal::from(0)
        };

        reserve
    }


    #[test_only]
    public fun destroy_for_testing<P>(reserve: Reserve<P>) {
         let Reserve {
            id,
            coin_type: _,
            config,
            mint_decimals: _,
            price_identifier: _,
            price: _,
            smoothed_price: _,
            price_last_update_timestamp_s: _,
            available_amount: _,
            ctoken_supply: _,
            borrowed_amount: _,
            cumulative_borrow_rate: _,
            interest_last_update_timestamp_s: _,
            unclaimed_spread_fees: _
        } = reserve;

        object::delete(id);
        let config = cell::destroy(config);
        reserve_config::destroy(config);
    }
}
