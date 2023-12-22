module suilend::reserve {
    use sui::object::{Self, ID, UID};
    use sui::balance::{Self, Balance, Supply};
    use sui::transfer;
    use sui::tx_context::{Self, TxContext};
    use suilend::decimal::{Decimal, Self, add, sub, mul, div, eq, floor};
    use std::vector::{Self};
    use sui::clock::{Self, Clock};
    use sui::coin::{Self, CoinMetadata};
    use sui::math::{Self, pow};

    friend suilend::lending_market;
    friend suilend::obligation;

    struct CToken<phantom P, phantom T> has drop {}

    /* constants */
    const PRICE_STALENESS_THRESHOLD_S: u64 = 60;

    /* errors */
    const EPriceStale: u64 = 0;

    // temporary price struct until we integrate with pyth
    struct Price has store {
        price: Decimal,
        last_update_timestamp_ms: u64
    }

    struct ReserveConfig has key, store {
        id: UID,

        // risk params
        open_ltv_pct: u8,
        close_ltv_pct: u8,
        borrow_weight_bps: u64,
        deposit_limit: u64,
        borrow_limit: u64,

        // fees
        borrow_fee_bps: u64,
        spread_fee_bps: u64,
        liquidation_fee_bps: u64,

        interest_rate: InterestRateModel
    }

    public entry fun create_reserve_config(
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
    ) {
        let config = ReserveConfig {
            id: object::new(ctx),
            open_ltv_pct,
            close_ltv_pct,
            borrow_weight_bps,
            deposit_limit,
            borrow_limit,
            borrow_fee_bps,
            spread_fee_bps,
            liquidation_fee_bps,
            interest_rate: InterestRateModel {
                utils: interest_rate_utils,
                aprs: interest_rate_aprs
            }
        };

        transfer::transfer(
            config,
            tx_context::sender(ctx)
        );
    }

    struct InterestRateModel has store {
        utils: vector<u8>,
        aprs: vector<u64>
    }

    struct Reserve<phantom P> has store {
        config: ReserveConfig,
        mint_decimals: u8,

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

    public(friend) fun create_reserve<P, T>(
        config: ReserveConfig, 
        coin_metadata: &CoinMetadata<T>,
        price: u256, 
        clock: &Clock, 
        reserve_id: u64,
    ): (Reserve<P>, ReserveTreasury<P, T>) {
        let reserve = Reserve {
            config,
            mint_decimals: coin::get_decimals(coin_metadata),
            price: decimal::from_scaled_val(price),
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

    public fun price<P>(reserve: &Reserve<P>, clock: &Clock): Decimal {
        let cur_time_s = clock::timestamp_ms(clock) / 1000;
        assert!(
            cur_time_s - reserve.price_last_update_timestamp_s <= PRICE_STALENESS_THRESHOLD_S, 
            EPriceStale
        );

        reserve.price
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

    public fun calculate_apr<P>(reserve: &Reserve<P>): Decimal {
        decimal::from_percent(5)
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

    // compound interest every second
    public(friend) fun compound_interest<P>(reserve: &mut Reserve<P>, clock: &Clock) {
        let cur_time_s = clock::timestamp_ms(clock) / 1000;
        let time_elapsed = decimal::from(cur_time_s - reserve.interest_last_update_timestamp_s);
        if (eq(time_elapsed, decimal::from(0))) {
            return
        };

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
        reserve.borrowed_amount = add(reserve.borrowed_amount, decimal::from(balance::value(&liquidity)));

        balance::join(&mut reserve_treasury.available_amount, liquidity);
    }
}