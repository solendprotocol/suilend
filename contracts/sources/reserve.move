module suilend::reserve {
    use sui::object::{Self, UID};
    use sui::balance::{Self, Balance, Supply};
    use sui::tx_context::{TxContext};
    use suilend::decimal::{Decimal, Self, add, sub, mul, div, eq, floor};
    use sui::clock::{Self, Clock};
    use sui::coin::{Self, CoinMetadata};
    use sui::math::{Self, pow};
    use std::option::{Self, Option};
    use std::debug;
    use pyth::price_info::{Self, PriceInfoObject};
    use pyth::price_feed::{Self};
    use pyth::price_identifier::{PriceIdentifier};
    use pyth::price::{Self};
    use pyth::i64::{Self};

    friend suilend::lending_market;
    friend suilend::obligation;

    struct CToken<phantom P, phantom T> has drop {}

    /* constants */
    const PRICE_STALENESS_THRESHOLD_S: u64 = 60;

    /* errors */
    const EPriceStale: u64 = 0;
    const EPriceIdentifierMismatch: u64 = 1;

    // temporary price struct until we integrate with pyth
    struct Price has store {
        price: Decimal,
        last_update_timestamp_ms: u64
    }

    struct ReserveConfig has store {
        id: UID,

        // risk params
        open_ltv_pct: u8,
        close_ltv_pct: u8,
        borrow_weight_bps: u64,
        deposit_limit: u64,
        borrow_limit: u64,
        liquidation_bonus_pct: u8,

        // fees
        borrow_fee_bps: u64,
        spread_fee_bps: u64,
        liquidation_fee_bps: u64,

        interest_rate: InterestRateModel
    }

    public fun create_reserve_config(
        open_ltv_pct: u8, 
        close_ltv_pct: u8, 
        borrow_weight_bps: u64, 
        deposit_limit: u64, 
        borrow_limit: u64, 
        borrow_fee_bps: u64, 
        spread_fee_bps: u64, 
        liquidation_fee_bps: u64, 
        interest_rate_utils: vector<u8>,
        interest_rate_aprs: vector<u64>,
        ctx: &mut TxContext, 
    ): ReserveConfig {
        ReserveConfig {
            id: object::new(ctx),
            open_ltv_pct,
            close_ltv_pct,
            borrow_weight_bps,
            deposit_limit,
            borrow_limit,
            liquidation_bonus_pct: 5,
            borrow_fee_bps,
            spread_fee_bps,
            liquidation_fee_bps,
            interest_rate: InterestRateModel {
                utils: interest_rate_utils,
                aprs: interest_rate_aprs
            }
        }
    }

    struct InterestRateModel has store, drop {
        utils: vector<u8>,
        aprs: vector<u64>
    }

    struct Reserve<phantom P> has store {
        config: Option<ReserveConfig>,
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

    // holds all the strongly typed stuff. Reserve intentionally doesn't have the coin type parameter.
    struct ReserveTreasury<phantom P, phantom T> has store {
        // reserve_treasury.reserve_id belongs to lending_market.reserves(reserve_treasury.reserve_id)
        reserve_id: u64,
        available_amount: Balance<T>,
        ctoken_supply: Supply<CToken<P, T>>
    }

    public fun reserve_id<P, T>(reserve_treasury: &ReserveTreasury<P, T>): u64 {
        reserve_treasury.reserve_id
    }

    fun get_pyth_price_and_identifier(price_info_obj: &PriceInfoObject): (Decimal, PriceIdentifier) {
        let price_info = price_info::get_price_info_from_price_info_object(price_info_obj);
        let price_feed = price_info::get_price_feed(&price_info);
        let price_identifier = price_feed::get_price_identifier(price_feed);
        let price = price_feed::get_price(price_feed);
        let mag = i64::get_magnitude_if_positive(&price::get_price(&price));
        let expo = price::get_expo(&price);

        // TODO: add staleness checks, confidence interval checks, etc

        let price_decimal = if (i64::get_is_negative(&expo)) {
            div(
                decimal::from(mag),
                decimal::from(math::pow(10, (i64::get_magnitude_if_negative(&expo) as u8)))
            )
        }
        else {
            mul(
                decimal::from(mag),
                decimal::from(math::pow(10, (i64::get_magnitude_if_positive(&expo) as u8)))
            )
        };

        (price_decimal, price_identifier)
    }

    public(friend) fun create_reserve<P, T>(
        config: ReserveConfig, 
        coin_metadata: &CoinMetadata<T>,
        price_info_obj: &PriceInfoObject, 
        clock: &Clock, 
        reserve_id: u64,
    ): (Reserve<P>, ReserveTreasury<P, T>) {

        let (price_decimal, price_identifier) = get_pyth_price_and_identifier(price_info_obj);

        let reserve = Reserve {
            config: option::some(config),
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
        };

        let reserve_treasury = ReserveTreasury {
            reserve_id,
            available_amount: balance::zero(),
            ctoken_supply: balance::create_supply(CToken<P, T> {})
        };

        (reserve, reserve_treasury)
    }

    public(friend) fun update_reserve_config<P>(
        reserve: &mut Reserve<P>, 
        config: ReserveConfig, 
    ) {
        let old_config = option::extract(&mut reserve.config);
        option::fill(&mut reserve.config, config);

        let ReserveConfig { 
            id, 
            open_ltv_pct: _, 
            close_ltv_pct: _, 
            borrow_weight_bps: _, 
            deposit_limit: _, 
            borrow_limit: _, 
            liquidation_bonus_pct: _,
            borrow_fee_bps: _,
            spread_fee_bps: _,
            liquidation_fee_bps: _,
            interest_rate: _
        } = old_config;
        object::delete(id);
    }

    public fun price<P>(reserve: &Reserve<P>, clock: &Clock): Decimal {
        let cur_time_s = clock::timestamp_ms(clock) / 1000;
        assert!(
            cur_time_s - reserve.price_last_update_timestamp_s <= PRICE_STALENESS_THRESHOLD_S, 
            EPriceStale
        );

        reserve.price
    }

    public fun update_price<P>(
        reserve: &mut Reserve<P>, 
        clock: &Clock,
        price_info_obj: &PriceInfoObject
    ) {
        let (price_decimal, price_identifier) = get_pyth_price_and_identifier(price_info_obj);
        assert!(price_identifier == reserve.price_identifier, EPriceIdentifierMismatch);

        reserve.price = price_decimal;
        reserve.price_last_update_timestamp_s = clock::timestamp_ms(clock) / 1000;
    }

    #[test_only]
    public fun update_price_for_testing<P>(
        reserve: &mut Reserve<P>, 
        clock: &Clock,
        price: u256, 
    ) {
        reserve.price = decimal::from_scaled_val(price);
        reserve.price_last_update_timestamp_s = clock::timestamp_ms(clock) / 1000;
    }

    public fun market_value<P>(
        reserve: &Reserve<P>, 
        clock: &Clock, 
        liquidity_amount: Decimal
    ): Decimal {
        div(
            mul(
                price(reserve, clock),
                liquidity_amount
            ),
            decimal::from(pow(10, reserve.mint_decimals))
        )
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

    public fun calculate_apr<P>(_reserve: &Reserve<P>): Decimal {
        decimal::from_percent(5)
    }

    public fun open_ltv<P>(reserve: &Reserve<P>): Decimal {
        decimal::from_percent(option::borrow(&reserve.config).open_ltv_pct)
    }

    public fun close_ltv<P>(reserve: &Reserve<P>): Decimal {
        decimal::from_percent(option::borrow(&reserve.config).close_ltv_pct)
    }

    public fun borrow_weight<P>(reserve: &Reserve<P>): Decimal {
        decimal::from_bps(option::borrow(&reserve.config).borrow_weight_bps)
    }

    public fun liquidation_bonus<P>(reserve: &Reserve<P>): Decimal {
        decimal::from_percent(option::borrow(&reserve.config).liquidation_bonus_pct)
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

    public(friend) fun deposit_liquidity_and_mint_ctokens<P, T>(
        reserve: &mut Reserve<P>, 
        reserve_treasury: &mut ReserveTreasury<P, T>, 
        liquidity: Balance<T>, 
        clock: &Clock,
    ): Balance<CToken<P, T>> {
        compound_interest(reserve, clock);

        let ctoken_ratio = ctoken_ratio(reserve);

        let new_ctokens = floor(div(
            decimal::from(balance::value(&liquidity)),
            ctoken_ratio
        ));

        // FIXME: check deposit limits

        reserve.available_amount = reserve.available_amount + balance::value(&liquidity);
        reserve.ctoken_supply = reserve.ctoken_supply + new_ctokens;

        balance::join(&mut reserve_treasury.available_amount, liquidity);
        balance::increase_supply(&mut reserve_treasury.ctoken_supply, new_ctokens)
    }

    public(friend) fun redeem_ctokens<P, T>(
        reserve: &mut Reserve<P>, 
        reserve_treasury: &mut ReserveTreasury<P, T>, 
        ctokens: Balance<CToken<P, T>>, 
        clock: &Clock,
    ): Balance<T> {
        compound_interest(reserve, clock);

        let ctoken_ratio = ctoken_ratio(reserve);

        let liquidity = floor(mul(
            decimal::from(balance::value(&ctokens)),
            ctoken_ratio
        ));

        reserve.available_amount = reserve.available_amount - liquidity;
        reserve.ctoken_supply = reserve.ctoken_supply - balance::value(&ctokens);

        balance::decrease_supply(&mut reserve_treasury.ctoken_supply, ctokens);
        balance::split(&mut reserve_treasury.available_amount, liquidity)
    }

    public(friend) fun borrow_liquidity<P, T>(
        reserve: &mut Reserve<P>, 
        reserve_treasury: &mut ReserveTreasury<P, T>, 
        clock: &Clock,
        liquidity_amount: u64
    ): Balance<T> {
        compound_interest(reserve, clock);

        // FIXME: check borrow limits
        reserve.available_amount = reserve.available_amount - liquidity_amount;
        reserve.borrowed_amount = add(reserve.borrowed_amount, decimal::from(liquidity_amount));

        balance::split(&mut reserve_treasury.available_amount, liquidity_amount)
    }

    public(friend) fun repay_liquidity<P, T>(
        reserve: &mut Reserve<P>, 
        reserve_treasury: &mut ReserveTreasury<P, T>, 
        clock: &Clock,
        liquidity: Balance<T>
    ) {
        compound_interest(reserve, clock);

        reserve.available_amount = reserve.available_amount + balance::value(&liquidity);
        reserve.borrowed_amount = sub(reserve.borrowed_amount, decimal::from(balance::value(&liquidity)));

        balance::join(&mut reserve_treasury.available_amount, liquidity);
    }
}