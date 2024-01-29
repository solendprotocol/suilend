module suilend::reserve {
    use sui::balance::{Self, Supply};
    use sui::event::{Self};
    use suilend::oracles::{Self};
    use suilend::decimal::{Decimal, Self, add, sub, mul, div, eq, floor, pow, le, ceil};
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
        liquidation_fee
    };

    friend suilend::lending_market;
    friend suilend::obligation;

    struct CToken<phantom P, phantom T> has drop {}

    /* constants */
    const PRICE_STALENESS_THRESHOLD_S: u64 = 0;

    /* errors */
    const EPriceStale: u64 = 0;
    const EPriceIdentifierMismatch: u64 = 1;
    const EDepositLimitExceeded: u64 = 2;
    const EBorrowLimitExceeded: u64 = 3;

    /* events */
    struct InterestUpdateEvent<phantom P> has drop, copy {
        reserve_id: u64,
        cumulative_borrow_rate: Decimal,
        available_amount: u64,
        borrowed_amount: Decimal,
        ctoken_supply: u64,
        timestamp_s: u64
    }

    struct Reserve<phantom P> has store {
        id: u64,

        config: ReserveConfig,
        mint_decimals: u8,

        // oracles
        price_identifier: PriceIdentifier,

        price: Decimal,
        price_last_update_timestamp_s: u64,

        available_amount: u64,
        ctoken_supply: u64,
        borrowed_amount: Decimal,

        cumulative_borrow_rate: Decimal,
        interest_last_update_timestamp_s: u64,

        fees_accumulated: Decimal
    }

    public(friend) fun create_reserve<P, T>(
        config: ReserveConfig, 
        coin_metadata: &CoinMetadata<T>,
        price_info_obj: &PriceInfoObject, 
        clock: &Clock, 
        reserve_id: u64,
    ): (Reserve<P>, Supply<CToken<P, T>>) {

        let (price_decimal, price_identifier) = oracles::get_pyth_price_and_identifier(price_info_obj);

        (
            Reserve {
                id: reserve_id,
                config,
                mint_decimals: coin::get_decimals(coin_metadata),
                price_identifier,
                price: price_decimal,
                price_last_update_timestamp_s: clock::timestamp_ms(clock) / 1000,
                available_amount: 0,
                ctoken_supply: 0,
                borrowed_amount: decimal::from(0),
                cumulative_borrow_rate: decimal::from(1),
                interest_last_update_timestamp_s: clock::timestamp_ms(clock) / 1000,
                fees_accumulated: decimal::from(0)
            },
            balance::create_supply(CToken<P, T> {})
        )
    }

    public fun id<P>(reserve: &Reserve<P>): u64 {
        reserve.id
    }

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


    public fun cumulative_borrow_rate<P>(reserve: &Reserve<P>): Decimal {
        reserve.cumulative_borrow_rate
    }

    public fun total_supply<P>(reserve: &Reserve<P>): Decimal {
        add(
            decimal::from(reserve.available_amount),
            reserve.borrowed_amount
        )
    }

    public fun calculate_utilization_rate<P>(reserve: &Reserve<P>): Decimal {
        let total_supply = total_supply(reserve);
        if (eq(total_supply, decimal::from(0))) {
            decimal::from(0)
        }
        else {
            div(reserve.borrowed_amount, total_supply)
        }
    }

    // always greater than or equal to one
    public fun ctoken_ratio<P>(reserve: &Reserve<P>): Decimal {
        let total_supply = total_supply(reserve);

        if (eq(total_supply, decimal::from(0))) {
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
        &reserve.config
    }

    public(friend) fun update_reserve_config<P>(
        reserve: &mut Reserve<P>, 
        config: ReserveConfig, 
    ) {
        reserve.config = config;
    }

    public fun update_price<P>(
        reserve: &mut Reserve<P>, 
        clock: &Clock,
        price_info_obj: &PriceInfoObject
    ) {
        let (price_decimal, price_identifier) = oracles::get_pyth_price_and_identifier(price_info_obj);
        assert!(price_identifier == reserve.price_identifier, EPriceIdentifierMismatch);

        reserve.price = price_decimal;
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
        let additional_borrow_rate = pow(
            add(
                decimal::from(1),
                div(
                    calculate_apr(&reserve.config, utilization_rate),
                    decimal::from(365 * 24 * 60 * 60)
                )
            ),
            time_elapsed_s
        );

        reserve.cumulative_borrow_rate = mul(
            reserve.cumulative_borrow_rate,
            additional_borrow_rate
        );

        reserve.borrowed_amount = mul(
            reserve.borrowed_amount,
            additional_borrow_rate
        );

        reserve.interest_last_update_timestamp_s = cur_time_s;

        event::emit(InterestUpdateEvent<P> {
            reserve_id: reserve.id,
            cumulative_borrow_rate: reserve.cumulative_borrow_rate,
            available_amount: reserve.available_amount,
            borrowed_amount: reserve.borrowed_amount,
            ctoken_supply: reserve.ctoken_supply,
            timestamp_s: cur_time_s
        });
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
            le(total_supply(reserve), decimal::from(deposit_limit(&reserve.config))), 
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

        liquidity_amount
    }

    public fun calculate_borrow_fee<P>(
        reserve: &Reserve<P>,
        borrow_amount: u64
    ): u64 {
        ceil(mul(decimal::from(borrow_amount), borrow_fee(&reserve.config)))
    }

    public fun calculate_liquidation_fee<P>(
        reserve: &Reserve<P>,
        withdraw_amount: u64
    ): u64 {
        ceil(mul(decimal::from(withdraw_amount), liquidation_fee(&reserve.config)))
    }

    public(friend) fun borrow_liquidity<P>(
        reserve: &mut Reserve<P>, 
        liquidity_amount: u64
    ) {
        reserve.available_amount = reserve.available_amount - liquidity_amount;
        reserve.borrowed_amount = add(reserve.borrowed_amount, decimal::from(liquidity_amount));

        assert!(
            le(reserve.borrowed_amount, decimal::from(borrow_limit(&reserve.config))), 
            EBorrowLimitExceeded 
        );
    }

    public(friend) fun repay_liquidity<P>(
        reserve: &mut Reserve<P>, 
        repay_amount: u64
    ) {
        reserve.available_amount = reserve.available_amount + repay_amount;
        reserve.borrowed_amount = sub(reserve.borrowed_amount, decimal::from(repay_amount));
    }

    #[test_only]
    fun example_reserve_config(): ReserveConfig {
        reserve_config::create_reserve_config(
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
            }
        )
    }

    #[test_only]
    public fun update_price_for_testing<P>(
        reserve: &mut Reserve<P>, 
        clock: &Clock,
        price_decimal: Decimal
    ) {
        reserve.price = price_decimal;
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

        let reserve = Reserve<TEST_USDC> {
            id: 0,
            config: example_reserve_config(),
            mint_decimals: 9,
            price_identifier: example_price_identifier(),
            price: decimal::from(1),
            price_last_update_timestamp_s: 0,
            available_amount: 500,
            ctoken_supply: 200,
            borrowed_amount: decimal::from(500),
            cumulative_borrow_rate: decimal::from(1),
            interest_last_update_timestamp_s: 0,
            fees_accumulated: decimal::from(0)
        };

        assert!(id(&reserve) == 0, 0);

        assert!(market_value(&reserve, decimal::from(10_000_000_000)) == decimal::from(10), 0);
        assert!(ctoken_market_value(&reserve, 10_000_000_000) == decimal::from(50), 0);
        assert!(cumulative_borrow_rate(&reserve) == decimal::from(1), 0);
        assert!(total_supply(&reserve) == decimal::from(1000), 0);
        assert!(calculate_utilization_rate(&reserve) == decimal::from_percent(50), 0);
        assert!(ctoken_ratio(&reserve) == decimal::from(5), 0);
        destroy_for_testing(reserve);

    }

    #[test]
    fun test_compound_interest() {
        use suilend::test_usdc::{TEST_USDC};
        use sui::test_scenario::{Self};

        let owner = @0x26;
        let scenario = test_scenario::begin(owner);

        let reserve = Reserve<TEST_USDC> {
            id: 0,
            config: example_reserve_config(),
            mint_decimals: 9,
            price_identifier: example_price_identifier(),
            price: decimal::from(1),
            price_last_update_timestamp_s: 0,
            available_amount: 500,
            ctoken_supply: 200,
            borrowed_amount: decimal::from(500),
            cumulative_borrow_rate: decimal::from(1),
            interest_last_update_timestamp_s: 0,
            fees_accumulated: decimal::from(0)
        };

        let clock = clock::create_for_testing(test_scenario::ctx(&mut scenario));
        clock::set_for_testing(&mut clock, 1000); 

        compound_interest(&mut reserve, &clock);

        assert!(cumulative_borrow_rate(&reserve) == decimal::from_bps(10_050), 0);
        assert!(reserve.borrowed_amount == add(decimal::from(500), decimal::from_percent(250)), 0);
        assert!(reserve.interest_last_update_timestamp_s == 1, 0);

        // test idempotency

        compound_interest(&mut reserve, &clock);

        assert!(cumulative_borrow_rate(&reserve) == decimal::from_bps(10_050), 0);
        assert!(reserve.borrowed_amount == add(decimal::from(500), decimal::from_percent(250)), 0);
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
            id: 0,
            config: example_reserve_config(),
            mint_decimals: 9,
            price_identifier: example_price_identifier(),
            price: decimal::from(1),
            price_last_update_timestamp_s: 0,
            available_amount: 500,
            ctoken_supply: 200,
            borrowed_amount: decimal::from(500),
            cumulative_borrow_rate: decimal::from(1),
            interest_last_update_timestamp_s: 1,
            fees_accumulated: decimal::from(0)
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
            }
        );

        let reserve = Reserve<TEST_USDC> {
            id: 0,
            config,
            mint_decimals: 9,
            price_identifier: example_price_identifier(),
            price: decimal::from(1),
            price_last_update_timestamp_s: 0,
            available_amount: 500,
            ctoken_supply: 200,
            borrowed_amount: decimal::from(500),
            cumulative_borrow_rate: decimal::from(1),
            interest_last_update_timestamp_s: 1,
            fees_accumulated: decimal::from(0)
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
            id: 0,
            config: example_reserve_config(),
            mint_decimals: 9,
            price_identifier: example_price_identifier(),
            price: decimal::from(1),
            price_last_update_timestamp_s: 0,
            available_amount: 500,
            ctoken_supply: 200,
            borrowed_amount: decimal::from(500),
            cumulative_borrow_rate: decimal::from(1),
            interest_last_update_timestamp_s: 1,
            fees_accumulated: decimal::from(0)
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
            id: 0,
            config: example_reserve_config(),
            mint_decimals: 9,
            price_identifier: example_price_identifier(),
            price: decimal::from(1),
            price_last_update_timestamp_s: 0,
            available_amount: 500,
            ctoken_supply: 200,
            borrowed_amount: decimal::from(500),
            cumulative_borrow_rate: decimal::from(1),
            interest_last_update_timestamp_s: 1,
            fees_accumulated: decimal::from(0)
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
            }
        );

        let reserve = Reserve<TEST_USDC> {
            id: 0,
            config,
            mint_decimals: 9,
            price_identifier: example_price_identifier(),
            price: decimal::from(1),
            price_last_update_timestamp_s: 0,
            available_amount: 500,
            ctoken_supply: 200,
            borrowed_amount: decimal::from(500),
            cumulative_borrow_rate: decimal::from(1),
            interest_last_update_timestamp_s: 1,
            fees_accumulated: decimal::from(0)
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
            id: 0,
            config: example_reserve_config(),
            mint_decimals: 9,
            price_identifier: example_price_identifier(),
            price: decimal::from(1),
            price_last_update_timestamp_s: 0,
            available_amount: 500,
            ctoken_supply: 200,
            borrowed_amount: decimal::from(500),
            cumulative_borrow_rate: decimal::from(1),
            interest_last_update_timestamp_s: 1,
            fees_accumulated: decimal::from(0)
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
    public fun create_for_testing<P>(
        id: u64,
        config: ReserveConfig,
        mint_decimals: u8,
        price: Decimal,
        price_last_update_timestamp_s: u64,
        available_amount: u64,
        ctoken_supply: u64,
        borrowed_amount: Decimal,
        cumulative_borrow_rate: Decimal,
        interest_last_update_timestamp_s: u64,
    ): Reserve<P> {
        Reserve<P> {
            id,
            config,
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
            price_last_update_timestamp_s,
            available_amount,
            ctoken_supply,
            borrowed_amount,
            cumulative_borrow_rate,
            interest_last_update_timestamp_s,
            fees_accumulated: decimal::from(0)
        }
    }


    #[test_only]
    public fun destroy_for_testing<P>(reserve: Reserve<P>) {
         let Reserve {
            id: _,
            config: _,
            mint_decimals: _,
            price_identifier: _,
            price: _,
            price_last_update_timestamp_s: _,
            available_amount: _,
            ctoken_supply: _,
            borrowed_amount: _,
            cumulative_borrow_rate: _,
            interest_last_update_timestamp_s: _,
            fees_accumulated: _
        } = reserve;
    }
}
