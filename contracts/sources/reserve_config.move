/// parameters for a Reserve.
module suilend::reserve_config {
    use std::vector::{Self};
    use suilend::decimal::{Decimal, Self, add, sub, mul, div, ge, le};
    use sui::tx_context::{TxContext};
    use sui::bag::{Self, Bag};

    #[test_only]
    use sui::test_scenario::{Self};

    const EInvalidReserveConfig: u64 = 0;
    const EInvalidUtil: u64 = 1;

    struct ReserveConfig has store {
        // risk params
        open_ltv_pct: u8,
        close_ltv_pct: u8,
        borrow_weight_bps: u64,
        deposit_limit: u64,
        borrow_limit: u64,
        liquidation_bonus_bps: u64,

        // interest params
        interest_rate_utils: vector<u8>,
        // in basis points
        interest_rate_aprs: vector<u64>,

        // fees
        borrow_fee_bps: u64,
        spread_fee_bps: u64,
        liquidation_fee_bps: u64,

        additional_fields: Bag
    }

    struct ReserveConfigBuilder has store {
        fields: Bag
    }

    public fun create_reserve_config(
        open_ltv_pct: u8, 
        close_ltv_pct: u8, 
        borrow_weight_bps: u64, 
        deposit_limit: u64, 
        borrow_limit: u64, 
        liquidation_bonus_bps: u64,
        borrow_fee_bps: u64, 
        spread_fee_bps: u64, 
        liquidation_fee_bps: u64, 
        interest_rate_utils: vector<u8>,
        interest_rate_aprs: vector<u64>,
        ctx: &mut TxContext
    ): ReserveConfig {
        let config = ReserveConfig {
            open_ltv_pct,
            close_ltv_pct,
            borrow_weight_bps,
            deposit_limit,
            borrow_limit,
            liquidation_bonus_bps,
            interest_rate_utils,
            interest_rate_aprs,
            borrow_fee_bps,
            spread_fee_bps,
            liquidation_fee_bps,
            additional_fields: bag::new(ctx)
        };

        validate_reserve_config(&config);
        config
    }

    fun validate_reserve_config(config: &ReserveConfig) {
        assert!(config.open_ltv_pct <= 100, EInvalidReserveConfig);
        assert!(config.close_ltv_pct <= 100, EInvalidReserveConfig);
        assert!(config.open_ltv_pct <= config.close_ltv_pct, EInvalidReserveConfig);

        assert!(config.borrow_weight_bps >= 10_000, EInvalidReserveConfig);
        assert!(config.liquidation_bonus_bps <= 2_000, EInvalidReserveConfig);

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

    public fun open_ltv(config: &ReserveConfig): Decimal {
        decimal::from_percent(config.open_ltv_pct)
    }

    public fun close_ltv(config: &ReserveConfig): Decimal {
        decimal::from_percent(config.close_ltv_pct)
    }

    public fun borrow_weight(config: &ReserveConfig): Decimal {
        decimal::from_bps(config.borrow_weight_bps)
    }

    public fun deposit_limit(config: &ReserveConfig): u64 {
        config.deposit_limit
    }

    public fun borrow_limit(config: &ReserveConfig): u64 {
        config.borrow_limit
    }

    public fun liquidation_bonus(config: &ReserveConfig): Decimal {
        decimal::from_bps(config.liquidation_bonus_bps)
    }

    public fun borrow_fee(config: &ReserveConfig): Decimal {
        decimal::from_bps(config.borrow_fee_bps)
    }

    public fun liquidation_fee(config: &ReserveConfig): Decimal {
        decimal::from_bps(config.liquidation_fee_bps)
    }

    public fun spread_fee(config: &ReserveConfig): Decimal {
        decimal::from_bps(config.spread_fee_bps)
    }

    public fun calculate_apr(config: &ReserveConfig, cur_util: Decimal): Decimal {
        assert!(le(cur_util, decimal::from(1)), EInvalidUtil);

        let length = vector::length(&config.interest_rate_utils);

        let i = 1;
        while (i < length) {
            let left_util = decimal::from_percent(*vector::borrow(&config.interest_rate_utils, i - 1));
            let right_util = decimal::from_percent(*vector::borrow(&config.interest_rate_utils, i));

            if (ge(cur_util, left_util) && le(cur_util, right_util)) {
                let left_apr = decimal::from_bps(*vector::borrow(&config.interest_rate_aprs, i - 1));
                let right_apr = decimal::from_bps(*vector::borrow(&config.interest_rate_aprs, i));

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

    public fun destroy(config: ReserveConfig) {
        let ReserveConfig { 
            open_ltv_pct: _,
            close_ltv_pct: _,
            borrow_weight_bps: _,
            deposit_limit: _,
            borrow_limit: _,
            liquidation_bonus_bps: _,
            interest_rate_utils: _,
            interest_rate_aprs: _,
            borrow_fee_bps: _,
            spread_fee_bps: _,
            liquidation_fee_bps: _,
            additional_fields
        } = config;

        bag::destroy_empty(additional_fields);
    }

    public fun from(config: &ReserveConfig, ctx: &mut TxContext): ReserveConfigBuilder {
        let builder = ReserveConfigBuilder { fields: bag::new(ctx) };
        set_open_ltv_pct(&mut builder, config.open_ltv_pct);
        set_close_ltv_pct(&mut builder, config.close_ltv_pct);
        set_borrow_weight_bps(&mut builder, config.borrow_weight_bps);
        set_deposit_limit(&mut builder, config.deposit_limit);
        set_borrow_limit(&mut builder, config.borrow_limit);
        set_liquidation_bonus_bps(&mut builder, config.liquidation_bonus_bps);

        set_interest_rate_utils(&mut builder, config.interest_rate_utils);
        set_interest_rate_aprs(&mut builder, config.interest_rate_aprs);

        set_borrow_fee_bps(&mut builder, config.borrow_fee_bps);
        set_spread_fee_bps(&mut builder, config.spread_fee_bps);
        set_liquidation_fee_bps(&mut builder, config.liquidation_fee_bps);

        builder
    }
    
    fun set<K: copy + drop + store, V: store + drop>(builder : &mut ReserveConfigBuilder, field: K, value: V) {
        if (bag::contains(&builder.fields, field)) {
            let val: &mut V = bag::borrow_mut(&mut builder.fields, field);
            *val = value;
        } else {
            bag::add(&mut builder.fields, field, value);
        }
    }

    public fun set_open_ltv_pct(builder: &mut ReserveConfigBuilder, open_ltv_pct: u8) {
        set(builder, b"open_ltv_pct", open_ltv_pct);
    }

    public fun set_close_ltv_pct(builder: &mut ReserveConfigBuilder, close_ltv_pct: u8) {
        set(builder, b"close_ltv_pct", close_ltv_pct);
    }

    public fun set_borrow_weight_bps(builder: &mut ReserveConfigBuilder, borrow_weight_bps: u64) {
        set(builder, b"borrow_weight_bps", borrow_weight_bps);
    }

    public fun set_deposit_limit(builder: &mut ReserveConfigBuilder, deposit_limit: u64) {
        set(builder, b"deposit_limit", deposit_limit);
    }

    public fun set_borrow_limit(builder: &mut ReserveConfigBuilder, borrow_limit: u64) {
        set(builder, b"borrow_limit", borrow_limit);
    }

    public fun set_liquidation_bonus_bps(builder: &mut ReserveConfigBuilder, liquidation_bonus_bps: u64) {
        set(builder, b"liquidation_bonus_bps", liquidation_bonus_bps);
    }

    public fun set_interest_rate_utils(builder: &mut ReserveConfigBuilder, interest_rate_utils: vector<u8>) {
        set(builder, b"interest_rate_utils", interest_rate_utils);
    }

    public fun set_interest_rate_aprs(builder: &mut ReserveConfigBuilder, interest_rate_aprs: vector<u64>) {
        set(builder, b"interest_rate_aprs", interest_rate_aprs);
    }

    public fun set_borrow_fee_bps(builder: &mut ReserveConfigBuilder, borrow_fee_bps: u64) {
        set(builder, b"borrow_fee_bps", borrow_fee_bps);
    }

    public fun set_spread_fee_bps(builder: &mut ReserveConfigBuilder, spread_fee_bps: u64) {
        set(builder, b"spread_fee_bps", spread_fee_bps);
    }

    public fun set_liquidation_fee_bps(builder: &mut ReserveConfigBuilder, liquidation_fee_bps: u64) {
        set(builder, b"liquidation_fee_bps", liquidation_fee_bps);
    }

    public fun build(builder: ReserveConfigBuilder, tx_context: &mut TxContext): ReserveConfig {
        let config = create_reserve_config(
            bag::remove(&mut builder.fields, b"open_ltv_pct"),
            bag::remove(&mut builder.fields, b"close_ltv_pct"),
            bag::remove(&mut builder.fields, b"borrow_weight_bps"),
            bag::remove(&mut builder.fields, b"deposit_limit"),
            bag::remove(&mut builder.fields, b"borrow_limit"),
            bag::remove(&mut builder.fields, b"liquidation_bonus_bps"),
            bag::remove(&mut builder.fields, b"borrow_fee_bps"),
            bag::remove(&mut builder.fields, b"spread_fee_bps"),
            bag::remove(&mut builder.fields, b"liquidation_fee_bps"),
            bag::remove(&mut builder.fields, b"interest_rate_utils"),
            bag::remove(&mut builder.fields, b"interest_rate_aprs"),
            tx_context
        );

        let ReserveConfigBuilder { fields } = builder;
        bag::destroy_empty(fields);
        config
    }


    // === Tests ==
    #[test_only]
    public fun default_reserve_config(): ReserveConfig {
        let owner = @0x26;
        let scenario = test_scenario::begin(owner);
        
        let config = create_reserve_config(
            // open ltv pct
            50,
            // close ltv pct
            80,
            // borrow weight bps
            10_000,
            // deposit_limit
            18_446_744_073_709_551_615u64,
            // borrow_limit
            18_446_744_073_709_551_615u64,
            // liquidation bonus pct
            10,
            // borrow fee bps
            0,
            // spread fee bps
            0,
            // liquidation fee bps
            5000,
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
                vector::push_back(&mut v, 1);
                v
            },
            test_scenario::ctx(&mut scenario)
        );

        test_scenario::end(scenario);

        config
    }

    // TODO tests for validate_utils_and_aprs

    #[test]
    fun test_calculate_apr() {
        let config = example_reserve_config();
        config.interest_rate_utils = {
            let v = vector::empty();
            vector::push_back(&mut v, 0);
            vector::push_back(&mut v, 10);
            vector::push_back(&mut v, 100);
            v
        };
        config.interest_rate_aprs = {
            let v = vector::empty();
            vector::push_back(&mut v, 0);
            vector::push_back(&mut v, 10000);
            vector::push_back(&mut v, 100000);
            v
        };

        assert!(calculate_apr(&config, decimal::from_percent(0)) == decimal::from(0), 0);
        assert!(calculate_apr(&config, decimal::from_percent(5)) == decimal::from_percent(50), 0);
        assert!(calculate_apr(&config, decimal::from_percent(10)) == decimal::from_percent(100), 0);
        assert!(calculate_apr(&config, decimal::from_percent(55)) == decimal::from_percent_u64(550), 0);
        assert!(calculate_apr(&config, decimal::from_percent(100)) == decimal::from_percent_u64(1000), 0);

        destroy(config);
    }

    #[test]
    fun test_valid_reserve_config() {

        let owner = @0x26;
        let scenario = test_scenario::begin(owner);

        let utils = vector::empty();
        vector::push_back(&mut utils, 0);
        vector::push_back(&mut utils, 100);

        let aprs = vector::empty();
        vector::push_back(&mut aprs, 0);
        vector::push_back(&mut aprs, 100);

        let config = create_reserve_config(
            10,
            10,
            10_000,
            1,
            1,
            5,
            10,
            2000,
            3000,
            utils,
            aprs,
            test_scenario::ctx(&mut scenario)
        );


        destroy(config);
        test_scenario::end(scenario);
    }

    // TODO: there are so many other invalid states to test
    #[test]
    #[expected_failure(abort_code = EInvalidReserveConfig)]
    fun test_invalid_reserve_config() {
        let owner = @0x26;
        let scenario = test_scenario::begin(owner);

        let config = create_reserve_config(
            // open ltv pct
            10,
            // close ltv pct
            9,
            // borrow weight bps
            10_000,
            // deposit_limit
            1,
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
                vector::push_back(&mut v, 100);
                v
            },
            test_scenario::ctx(&mut scenario)
        );

        destroy(config);
        test_scenario::end(scenario);
    }

    #[test_only]
    fun example_reserve_config(): ReserveConfig {
        let owner = @0x26;
        let scenario = test_scenario::begin(owner);

        let config = create_reserve_config(
            // open ltv pct
            10,
            // close ltv pct
            10,
            // borrow weight bps
            10_000,
            // deposit_limit
            1,
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

        test_scenario::end(scenario);
        config
    }

}
