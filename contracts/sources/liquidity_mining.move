/// A farmer farms incentives to receive rewards proportional to their stake in the pool.
module suilend::liquidity_mining {
    use suilend::decimal::{Self, Decimal, add, sub, mul, div, floor};
    use sui::object::{Self, ID, UID};
    use sui::math::{Self};
    use sui::clock::{Self, Clock};
    use sui::tx_context::{Self, TxContext};
    use std::vector::{Self};
    use sui::balance::{Self, Balance};
    use sui::bag::{Self, Bag};
    use std::type_name::{Self, TypeName};
    use sui::vec_map::{Self, VecMap};

    // === Errors ===
    const EIdMismatch: u64 = 0;
    const EInvalidTime: u64 = 1;
    const EInvalidType: u64 = 2;

    /// This struct manages all incentives for a given stake pool.
    struct IncentiveManager has key, store {
        id: UID,

        total_weight: u64,
        incentives: vector<Incentive>,

        last_update_time_ms: u64,
        num_incentives: u64,
    }

    struct Incentive has store {
        incentive_manager_id: ID,
        incentive_id: u64,

        coin_type: TypeName,

        start_time_ms: u64,
        reward_distribution_period_ms: u64,
        total_rewards: u64,

        cumulative_rewards_per_weight: Decimal,

        num_farmers: u64,

        additional_fields: Bag
    }

    // == Dynamic Field Keys
    struct RewardBalance<phantom T> has copy, store, drop {}

    struct Farmer has store {
        incentive_manager_id: ID,
        weight: u64,

        rewards: VecMap<u64, Reward>,
    }

    struct Reward has store {
        incentive_id: u64,

        accumulated_rewards: Decimal,
        cumulative_rewards_per_weight: Decimal,
    }

    public fun new_incentive_manager(ctx: &mut TxContext): IncentiveManager {
        IncentiveManager {
            id: object::new(ctx),
            total_weight: 0,
            incentives: vector::empty(),
            last_update_time_ms: 0,
            num_incentives: 0,
        }
    }

    public fun add_incentive<T>(
        incentive_manager: &mut IncentiveManager,
        rewards: Balance<T>,
        start_time_ms: u64,
        // eg if 100, then the rewards are distributed over 100 milliseconds
        reward_distribution_period_ms: u64, 
        clock: &Clock, 
        ctx: &mut TxContext
    ) {
        let incentive = Incentive {
            incentive_manager_id: object::id(incentive_manager),
            incentive_id: incentive_manager.num_incentives,
            coin_type: type_name::get<T>(),
            start_time_ms: math::max(start_time_ms, clock::timestamp_ms(clock)),
            reward_distribution_period_ms,
            total_rewards: balance::value(&rewards),
            cumulative_rewards_per_weight: decimal::from(0),
            num_farmers: 0,
            additional_fields: {
                let bag = bag::new(ctx);
                bag::add(&mut bag, RewardBalance<T> {}, rewards);
                bag
            }
        };

        vector::push_back(&mut incentive_manager.incentives, incentive);
        incentive_manager.num_incentives = incentive_manager.num_incentives + 1;
    }

    public fun new_farmer(
        incentive_manager: &mut IncentiveManager,
        weight: u64,
        clock: &Clock,
    ): Farmer {
        let farmer = Farmer {
            incentive_manager_id: object::id(incentive_manager),
            weight: 0,
            rewards: vec_map::empty(),
        };

        increase_farmer_weight(incentive_manager, &mut farmer, weight, clock);
        farmer
    }

    public fun increase_farmer_weight(
        incentive_manager: &mut IncentiveManager, 
        farmer: &mut Farmer, 
        delta: u64, 
        clock: &Clock
    ) {
        assert!(object::id(incentive_manager) == farmer.incentive_manager_id, EIdMismatch);
        update_farmer(incentive_manager, farmer, clock);

        farmer.weight = farmer.weight + delta;
        incentive_manager.total_weight = incentive_manager.total_weight + delta;
    }

    public fun decrease_farmer_weight(
        incentive_manager: &mut IncentiveManager, 
        farmer: &mut Farmer, 
        delta: u64, 
        clock: &Clock
    ) {
        assert!(object::id(incentive_manager) == farmer.incentive_manager_id, EIdMismatch);
        update_farmer(incentive_manager, farmer, clock);

        farmer.weight = farmer.weight - delta;
        incentive_manager.total_weight = incentive_manager.total_weight - delta;
    }

    fun update_incentive_manager(incentive_manager: &mut IncentiveManager, clock: &Clock) {
        if (incentive_manager.total_weight == 0) {
            return
        };

        let cur_time_ms = clock::timestamp_ms(clock);

        let i = 0;
        while (i < vector::length(&incentive_manager.incentives)) {
            let incentive = vector::borrow_mut(&mut incentive_manager.incentives, i);
            if (cur_time_ms < incentive.start_time_ms) {
                i = i + 1;
                continue
            };

            let end_time_ms = incentive.start_time_ms + incentive.reward_distribution_period_ms;
            if (incentive_manager.last_update_time_ms <= end_time_ms) {
                let time_passed_ms = math::min(cur_time_ms, end_time_ms) - math::max(incentive.start_time_ms, incentive_manager.last_update_time_ms);
                if (time_passed_ms == 0) {
                    i = i + 1;
                    continue
                };

                incentive.cumulative_rewards_per_weight = add(
                    incentive.cumulative_rewards_per_weight,
                    div(
                        mul(
                            decimal::from(incentive.total_rewards),
                            decimal::from(time_passed_ms)
                        ),
                        mul(
                            decimal::from(incentive.reward_distribution_period_ms),
                            decimal::from(incentive_manager.total_weight)
                        )
                    )
                );
            };

            i = i + 1;
        };


        incentive_manager.last_update_time_ms = cur_time_ms;
    }

    fun update_farmer(incentive_manager: &mut IncentiveManager, farmer: &mut Farmer, clock: &Clock) {
        assert!(object::id(incentive_manager) == farmer.incentive_manager_id, EIdMismatch);

        update_incentive_manager(incentive_manager, clock);
        let cur_time_ms = clock::timestamp_ms(clock);

        let i = 0;
        while (i < vector::length(&incentive_manager.incentives)) {
            let incentive = vector::borrow_mut(&mut incentive_manager.incentives, i);

            if (!vec_map::contains(&farmer.rewards, &incentive.incentive_id)) {
                if (cur_time_ms < incentive.start_time_ms + incentive.reward_distribution_period_ms) {
                    vec_map::insert(&mut farmer.rewards, incentive.incentive_id, Reward {
                        incentive_id: incentive.incentive_id,
                        accumulated_rewards: decimal::from(0),
                        cumulative_rewards_per_weight: incentive.cumulative_rewards_per_weight
                    });

                    incentive.num_farmers = incentive.num_farmers + 1;
                };
            }
            else {
                let reward = vec_map::get_mut(&mut farmer.rewards, &incentive.incentive_id);
                let new_rewards = mul(
                    sub(
                        incentive.cumulative_rewards_per_weight,
                        reward.cumulative_rewards_per_weight
                    ),
                    decimal::from(farmer.weight),
                );

                reward.accumulated_rewards = add(reward.accumulated_rewards, new_rewards);
                reward.cumulative_rewards_per_weight = incentive.cumulative_rewards_per_weight;
            };

            i = i + 1;
        };
    }

    fun claim_rewards<T>(
        incentive_manager: &mut IncentiveManager, 
        farmer: &mut Farmer, 
        clock: &Clock, 
        incentive_id: u64
    ): Balance<T> {
        update_farmer(incentive_manager, farmer, clock);

        let incentive = vector::borrow_mut(&mut incentive_manager.incentives, incentive_id);
        assert!(incentive.coin_type == type_name::get<T>(), EInvalidType);

        let reward = vec_map::get_mut(&mut farmer.rewards, &incentive_id);
        let claimable_rewards = floor(reward.accumulated_rewards);

        reward.accumulated_rewards = sub(reward.accumulated_rewards, decimal::from(claimable_rewards));
        let reward_balance: &mut Balance<T> = bag::borrow_mut(
            &mut incentive.additional_fields,
            RewardBalance<T> {}
        );

        balance::split(reward_balance, claimable_rewards)
    }

    #[test_only]
    struct USDC has drop {}

    #[test_only]
    struct SUI has drop {}

    #[test]
    fun test_incentive_manager_basic() {
        use sui::test_scenario::{Self};
        use sui::balance::{Self};

        let owner = @0x26;
        let scenario = test_scenario::begin(owner);
        let ctx = test_scenario::ctx(&mut scenario);

        let clock = clock::create_for_testing(ctx);
        clock::set_for_testing(&mut clock, 0); 

        let incentive_manager = new_incentive_manager(ctx);
        let usdc = balance::create_for_testing<USDC>(100 * 1_000_000);
        add_incentive(&mut incentive_manager, usdc, 0, 20 * 1000, &clock, ctx);

        let farmer_1 = new_farmer(&mut incentive_manager, 100, &clock);
        std::debug::print(&farmer_1);

        // at this point, farmer 1 has earned 50 dollars
        clock::set_for_testing(&mut clock, 5 * 1000);
        update_farmer(&mut incentive_manager, &mut farmer_1, &clock);
        {
            let usdc = claim_rewards<USDC>(&mut incentive_manager, &mut farmer_1, &clock, 0);
            std::debug::print(&usdc);
            assert!(balance::value(&usdc) == 25 * 1_000_000, 0);
            sui::test_utils::destroy(usdc);
        };

        let farmer_2 = new_farmer(&mut incentive_manager, 400, &clock);

        clock::set_for_testing(&mut clock, 10 * 1000);
        {
            let usdc = claim_rewards<USDC>(&mut incentive_manager, &mut farmer_1, &clock, 0);
            std::debug::print(&usdc);
            assert!(balance::value(&usdc) == 5 * 1_000_000, 0);
            sui::test_utils::destroy(usdc);
        };
        {
            let usdc = claim_rewards<USDC>(&mut incentive_manager, &mut farmer_2, &clock, 0);
            std::debug::print(&usdc);
            assert!(balance::value(&usdc) == 20 * 1_000_000, 0);
            sui::test_utils::destroy(usdc);
        };

        increase_farmer_weight(&mut incentive_manager, &mut farmer_1, 150, &clock);
        decrease_farmer_weight(&mut incentive_manager, &mut farmer_2, 150, &clock);

        clock::set_for_testing(&mut clock, 20 * 1000);
        {
            let usdc = claim_rewards<USDC>(&mut incentive_manager, &mut farmer_1, &clock, 0);
            std::debug::print(&usdc);
            assert!(balance::value(&usdc) == 25 * 1_000_000, 0);
            sui::test_utils::destroy(usdc);
        };
        {
            let usdc = claim_rewards<USDC>(&mut incentive_manager, &mut farmer_2, &clock, 0);
            std::debug::print(&usdc);
            assert!(balance::value(&usdc) == 25 * 1_000_000, 0);
            sui::test_utils::destroy(usdc);
        };

        sui::test_utils::destroy(clock);
        sui::test_utils::destroy(incentive_manager);
        sui::test_utils::destroy(farmer_1);
        sui::test_utils::destroy(farmer_2);
        test_scenario::end(scenario);
    }

    #[test]
    fun test_incentive_manager_multiple_rewards() {
        use sui::test_scenario::{Self};
        use sui::balance::{Self};

        let owner = @0x26;
        let scenario = test_scenario::begin(owner);
        let ctx = test_scenario::ctx(&mut scenario);

        let clock = clock::create_for_testing(ctx);
        clock::set_for_testing(&mut clock, 0); 

        let incentive_manager = new_incentive_manager(ctx);
        let usdc = balance::create_for_testing<USDC>(100 * 1_000_000);
        add_incentive(&mut incentive_manager, usdc, 0, 20 * 1000, &clock, ctx);

        let sui = balance::create_for_testing<SUI>(100 * 1_000_000);
        add_incentive(&mut incentive_manager, sui, 10 * 1000, 10 * 1000, &clock, ctx);

        let farmer_1 = new_farmer(&mut incentive_manager, 100, &clock);

        clock::set_for_testing(&mut clock, 15 * 1000);
        let farmer_2 = new_farmer(&mut incentive_manager, 100, &clock);

        clock::set_for_testing(&mut clock, 30 * 1000);
        {
            let usdc = claim_rewards<USDC>(&mut incentive_manager, &mut farmer_1, &clock, 0);
            std::debug::print(&usdc);
            assert!(balance::value(&usdc) == 87_500_000, 0);
            sui::test_utils::destroy(usdc);
        };
        {
            let sui = claim_rewards<SUI>(&mut incentive_manager, &mut farmer_1, &clock, 1);
            std::debug::print(&sui);
            assert!(balance::value(&sui) == 75 * 1_000_000, 0);
            sui::test_utils::destroy(sui);
        };

        {
            let usdc = claim_rewards<USDC>(&mut incentive_manager, &mut farmer_2, &clock, 0);
            std::debug::print(&usdc);
            assert!(balance::value(&usdc) == 12_500_000, 0);
            sui::test_utils::destroy(usdc);
        };
        {
            let sui = claim_rewards<SUI>(&mut incentive_manager, &mut farmer_2, &clock, 1);
            std::debug::print(&sui);
            assert!(balance::value(&sui) == 25 * 1_000_000, 0);
            sui::test_utils::destroy(sui);
        };

        sui::test_utils::destroy(clock);
        sui::test_utils::destroy(incentive_manager);
        sui::test_utils::destroy(farmer_1);
        sui::test_utils::destroy(farmer_2);
        test_scenario::end(scenario);

    }
}
