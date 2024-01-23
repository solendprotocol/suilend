module suilend::reserve {
    use sui::balance::{Self, Supply};
    use suilend::oracles::{Self};
    use suilend::decimal::{Decimal, Self, add, sub, mul, div, eq, floor, ge, le};
    use sui::clock::{Self, Clock};
    use sui::coin::{Self, CoinMetadata};
    use sui::math::{Self};
    use std::debug;
    use pyth::price_identifier::{PriceIdentifier};
    use pyth::price_info::{PriceInfoObject};
    use std::vector::{Self};

    friend suilend::lending_market;
    friend suilend::obligation;

    struct CToken<phantom P, phantom T> has drop {}

    /* constants */
    const PRICE_STALENESS_THRESHOLD_S: u64 = 60;

    /* errors */
    const EPriceStale: u64 = 0;
    const EPriceIdentifierMismatch: u64 = 1;
    const EInvalidReserveConfig: u64 = 2;

    struct ReserveConfig has store, drop {
        // risk params
        open_ltv_pct: u8,
        close_ltv_pct: u8,
        borrow_weight_bps: u64,
        deposit_limit: u64,
        borrow_limit: u64,
        liquidation_bonus_pct: u8,

        // interest params
        interest_rate_utils: vector<u8>,
        interest_rate_aprs: vector<u64>,

        // fees
        borrow_fee_bps: u64,
        spread_fee_bps: u64,
        liquidation_fee_bps: u64,
    }

    public fun create_reserve_config(
        open_ltv_pct: u8, 
        close_ltv_pct: u8, 
        borrow_weight_bps: u64, 
        deposit_limit: u64, 
        borrow_limit: u64, 
        liquidation_bonus_pct: u8,
        borrow_fee_bps: u64, 
        spread_fee_bps: u64, 
        liquidation_fee_bps: u64, 
        interest_rate_utils: vector<u8>,
        interest_rate_aprs: vector<u64>,
    ): ReserveConfig {
        let config = ReserveConfig {
            open_ltv_pct,
            close_ltv_pct,
            borrow_weight_bps,
            deposit_limit,
            borrow_limit,
            liquidation_bonus_pct,
            interest_rate_utils,
            interest_rate_aprs,
            borrow_fee_bps,
            spread_fee_bps,
            liquidation_fee_bps,
        };

        validate_reserve_config(&config);
        config
    }

    fun validate_reserve_config(config: &ReserveConfig) {
        assert!(config.open_ltv_pct <= 100, EInvalidReserveConfig);
        assert!(config.close_ltv_pct <= 100, EInvalidReserveConfig);
        assert!(config.open_ltv_pct <= config.close_ltv_pct, EInvalidReserveConfig);

        assert!(config.borrow_weight_bps >= 10_000, EInvalidReserveConfig);
        assert!(config.liquidation_bonus_pct <= 20, EInvalidReserveConfig);

        assert!(config.borrow_fee_bps <= 10_000, EInvalidReserveConfig);
        assert!(config.spread_fee_bps <= 10_000, EInvalidReserveConfig);
        assert!(config.liquidation_fee_bps <= 10_000, EInvalidReserveConfig);

        validate_utils_and_aprs(&config.interest_rate_utils, &config.interest_rate_aprs);
    }

    fun validate_utils_and_aprs(utils: &vector<u8>, aprs: &vector<u64>) {
        assert!(vector::length(utils) >= 2, EInvalidReserveConfig);
        assert!(
            vector::length(utils) == vector::length(aprs), 
            EInvalidReserveConfig
        );

        let length = vector::length(utils);
        assert!(*vector::borrow(utils, 0) == 0, EInvalidReserveConfig);
        assert!(*vector::borrow(utils, length-1) == 100, EInvalidReserveConfig);

        // check that both vectors are strictly increasing
        let i = 1;
        while (i < length) {
            assert!(*vector::borrow(utils, i - 1) < *vector::borrow(utils, i), EInvalidReserveConfig);
            assert!(*vector::borrow(aprs, i - 1) < *vector::borrow(aprs, i), EInvalidReserveConfig);

            i = i + 1;
        }
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

    public fun id<P>(reserve: &Reserve<P>): u64 {
        reserve.id
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

    public(friend) fun update_reserve_config<P>(
        reserve: &mut Reserve<P>, 
        config: ReserveConfig, 
    ) {
        reserve.config = config;
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

    public fun calculate_apr<P>(reserve: &Reserve<P>): Decimal {
        let length = vector::length(&reserve.config.interest_rate_utils);

        let cur_util = calculate_utilization_rate(reserve);

        let i = 1;
        while (i < length) {
            let left_util = decimal::from_percent(*vector::borrow(&reserve.config.interest_rate_utils, i - 1));
            let right_util = decimal::from_percent(*vector::borrow(&reserve.config.interest_rate_utils, i));

            if (ge(cur_util, left_util) && le(cur_util, right_util)) {
                let left_apr = decimal::from_percent(*vector::borrow(&reserve.config.interest_rate_utils, i - 1));
                let right_apr = decimal::from_percent(*vector::borrow(&reserve.config.interest_rate_utils, i));

                let weight = div(
                    sub(cur_util, left_util),
                    sub(right_util, left_util)
                );

                let apr_diff = sub(right_apr, left_apr);
                return add(
                    left_apr,
                    mul(weight, apr_diff)
                )
            };

            i = i + 1;
        };

        // should never get here
        assert!(1 == 0, EInvalidReserveConfig);
        decimal::from(0)
    }

    public fun open_ltv<P>(reserve: &Reserve<P>): Decimal {
        decimal::from_percent(reserve.config.open_ltv_pct)
    }

    public fun close_ltv<P>(reserve: &Reserve<P>): Decimal {
        decimal::from_percent(reserve.config.close_ltv_pct)
    }

    public fun borrow_weight<P>(reserve: &Reserve<P>): Decimal {
        decimal::from_bps(reserve.config.borrow_weight_bps)
    }

    public fun liquidation_bonus<P>(reserve: &Reserve<P>): Decimal {
        decimal::from_percent(reserve.config.liquidation_bonus_pct)
    }

    // compound interest every second
    public(friend) fun compound_interest<P>(reserve: &mut Reserve<P>, clock: &Clock) {
        let cur_time_s = clock::timestamp_ms(clock) / 1000;
        let time_elapsed = decimal::from(cur_time_s - reserve.interest_last_update_timestamp_s);
        if (eq(time_elapsed, decimal::from(0))) {
            return
        };
        debug::print(&8);
        debug::print(&time_elapsed);

        // I(t + n) = I(t) * (1 + apr()/SECONDS_IN_YEAR) ^ n
        // since we don't have the pow() function, approximate with:
        // I(t + n) = I(t) * (1 + apr()/SECONDS_IN_YEAR * n)
        let additional_borrow_rate = add(
            decimal::from(1),
            mul(
                div(
                    calculate_apr(reserve),
                    decimal::from(365 * 24 * 60 * 60)
                ),
                time_elapsed
            )
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
    }

    // always greater than one
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

    public(friend) fun deposit_liquidity_and_mint_ctokens<P>(
        reserve: &mut Reserve<P>, 
        liquidity_amount: u64, 
        clock: &Clock,
    ): u64 {
        compound_interest(reserve, clock);

        let ctoken_ratio = ctoken_ratio(reserve);

        let new_ctokens = floor(div(
            decimal::from(liquidity_amount),
            ctoken_ratio
        ));

        // FIXME: check deposit limits

        reserve.available_amount = reserve.available_amount + liquidity_amount;
        reserve.ctoken_supply = reserve.ctoken_supply + new_ctokens;

        new_ctokens
    }

    public(friend) fun redeem_ctokens<P>(
        reserve: &mut Reserve<P>, 
        ctoken_amount: u64, 
        clock: &Clock,
    ): u64 {
        compound_interest(reserve, clock);

        let ctoken_ratio = ctoken_ratio(reserve);

        let liquidity_amount = floor(mul(
            decimal::from(ctoken_amount),
            ctoken_ratio
        ));

        reserve.available_amount = reserve.available_amount - liquidity_amount;
        reserve.ctoken_supply = reserve.ctoken_supply - ctoken_amount;

        liquidity_amount
    }

    public(friend) fun borrow_liquidity<P>(
        reserve: &mut Reserve<P>, 
        clock: &Clock,
        liquidity_amount: u64
    ) {
        compound_interest(reserve, clock);

        // FIXME: check borrow limits
        reserve.available_amount = reserve.available_amount - liquidity_amount;
        reserve.borrowed_amount = add(reserve.borrowed_amount, decimal::from(liquidity_amount));
    }

    public(friend) fun repay_liquidity<P>(
        reserve: &mut Reserve<P>, 
        clock: &Clock,
        repay_amount: u64
    ) {
        compound_interest(reserve, clock);

        reserve.available_amount = reserve.available_amount + repay_amount;
        reserve.borrowed_amount = sub(reserve.borrowed_amount, decimal::from(repay_amount));
    }
}
