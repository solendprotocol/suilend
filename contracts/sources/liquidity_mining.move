/// A farmer farms incentives to receive rewards proportional to their stake in the pool.
module suilend::liquidity_mining {
    use suilend::decimal::{Self, Decimal, add, sub, mul, div, floor};
    use sui::object::{Self, ID, UID};
    use sui::math::{Self};
    use sui::clock::{Self, Clock};
    use sui::tx_context::{TxContext};
    use std::vector::{Self};
    use sui::balance::{Self, Balance};
    use sui::bag::{Self, Bag};
    use std::type_name::{Self, TypeName};
    use std::option::{Self, Option};

    // === Errors ===
    const EIdMismatch: u64 = 0;
    const EInvalidTime: u64 = 1;
    const EInvalidType: u64 = 2;
    const EMaxConcurrentIncentivesViolated: u64 = 3;
    const ENotAllRewardsClaimed: u64 = 4;
    const EIncentivePeriodNotOver: u64 = 5;
    const EIncentiveManagerNotUpdated: u64 = 6;
    const EFarmerNotUpdated: u64 = 7;

    // === Constants ===
    const MAX_REWARDS: u64 = 5;

    // === Friends ===
    friend suilend::lending_market;
    friend suilend::obligation;

    /// This struct manages all incentives for a given stake pool.
    struct IncentiveManager has key, store {
        id: UID,

        total_weight: u64,
        incentives: vector<Option<Incentive>>,

        last_update_time_ms: u64,
        num_incentives: u64,
    }

    struct Incentive has store {
        incentive_manager_id: ID,
        incentive_id: u64,

        coin_type: TypeName,

        start_time_ms: u64,
        end_time_ms: u64,

        total_rewards: u64,
        allocated_rewards: Decimal,

        cumulative_rewards_per_weight: Decimal,

        num_farmers: u64,

        additional_fields: Bag
    }

    // == Dynamic Field Keys
    struct RewardBalance<phantom T> has copy, store, drop {}

    struct Farmer has store {
        incentive_manager_id: ID,
        weight: u64,

        rewards: vector<Option<Reward>>,
        last_update_time_ms: u64,
    }

    struct Reward has store {
        incentive_id: u64,

        accumulated_rewards: Decimal,
        cumulative_rewards_per_weight: Decimal,
    }

    // === Public-View Functions ===
    public fun incentive_manager_id(farmer: &Farmer): ID {
        farmer.incentive_manager_id
    }

    // === Public-Mutative Functions ===
    public fun new_incentive_manager(ctx: &mut TxContext): IncentiveManager {
        IncentiveManager {
            id: object::new(ctx),
            total_weight: 0,
            incentives: {
                let v = vector::empty();
                let i = 0;
                while (i < MAX_REWARDS) {
                    vector::push_back(&mut v, option::none());
                    i = i + 1;
                };
                v
            },
            last_update_time_ms: 0,
            num_incentives: 0,
        }
    }

    public fun add_incentive<T>(
        incentive_manager: &mut IncentiveManager,
        rewards: Balance<T>,
        start_time_ms: u64,
        end_time_ms: u64,
        clock: &Clock, 
        ctx: &mut TxContext
    ) {
        let start_time_ms = math::max(start_time_ms, clock::timestamp_ms(clock));
        assert!(start_time_ms < end_time_ms, EInvalidTime);

        let incentive = Incentive {
            incentive_manager_id: object::id(incentive_manager),
            incentive_id: incentive_manager.num_incentives,
            coin_type: type_name::get<T>(),
            start_time_ms,
            end_time_ms,
            total_rewards: balance::value(&rewards),
            allocated_rewards: decimal::from(0),
            cumulative_rewards_per_weight: decimal::from(0),
            num_farmers: 0,
            additional_fields: {
                let bag = bag::new(ctx);
                bag::add(&mut bag, RewardBalance<T> {}, rewards);
                bag
            }
        };

        let i = find_available_index(incentive_manager);
        assert!(i < MAX_REWARDS, EMaxConcurrentIncentivesViolated);

        let optional_incentive = vector::borrow_mut(&mut incentive_manager.incentives, i);
        option::fill(optional_incentive, incentive);

        incentive_manager.num_incentives = incentive_manager.num_incentives + 1;
    }

    /// Close incentive campaign, claim dust amounts of rewards, and destroy object.
    /// This can only be called if the incentive period is over and all rewards have been claimed.
    public fun close_incentive<T>(
        incentive_manager: 
        &mut IncentiveManager, 
        index: u64, 
        clock: &Clock
    ): Balance<T> {
        let optional_incentive = vector::borrow_mut(&mut incentive_manager.incentives, index);
        let Incentive {
            incentive_manager_id: _, 
            incentive_id: _, 
            coin_type: _, 
            start_time_ms: _, 
            end_time_ms, 
            total_rewards: _, 
            allocated_rewards: _,
            cumulative_rewards_per_weight: _, 
            num_farmers, 
            additional_fields,
        } = option::extract(optional_incentive);

        let cur_time_ms = clock::timestamp_ms(clock);

        assert!(cur_time_ms >= end_time_ms, EIncentivePeriodNotOver);
        assert!(num_farmers == 0, ENotAllRewardsClaimed);

        let reward_balance: Balance<T> = bag::remove(
            &mut additional_fields,
            RewardBalance<T> {}
        );

        bag::destroy_empty(additional_fields);

        reward_balance
    }

    /// Cancel incentive campaign and claim unallocated rewards. Effectively sets the 
    /// end time of the incentive campaign to the current time.
    public fun cancel_incentive<T>(
        incentive_manager: &mut IncentiveManager,
        index: u64,
        clock: &Clock
    ): Balance<T> {
        update_incentive_manager(incentive_manager, clock);

        let incentive = option::borrow_mut(vector::borrow_mut(&mut incentive_manager.incentives, index));
        let cur_time_ms = clock::timestamp_ms(clock);

        incentive.end_time_ms = cur_time_ms;

        let unallocated_rewards = floor(sub(
            decimal::from(incentive.total_rewards),
            incentive.allocated_rewards
        ));

        let reward_balance: &mut Balance<T> = bag::borrow_mut(
            &mut incentive.additional_fields,
            RewardBalance<T> {}
        );

        balance::split(reward_balance, unallocated_rewards)
    }

    public fun update_incentive_manager(incentive_manager: &mut IncentiveManager, clock: &Clock) {
        if (incentive_manager.total_weight == 0) {
            return
        };

        let cur_time_ms = clock::timestamp_ms(clock);

        let i = 0;
        while (i < vector::length(&incentive_manager.incentives)) {
            let optional_incentive = vector::borrow_mut(&mut incentive_manager.incentives, i);
            if (option::is_none(optional_incentive)) {
                i = i + 1;
                continue
            };

            let incentive = option::borrow_mut(optional_incentive);
            if (cur_time_ms < incentive.start_time_ms || 
                incentive_manager.last_update_time_ms >= incentive.end_time_ms) {
                i = i + 1;
                continue
            };

            let time_passed_ms = math::min(cur_time_ms, incentive.end_time_ms) - 
                math::max(incentive.start_time_ms, incentive_manager.last_update_time_ms);

            let unlocked_rewards = div(
                mul(
                    decimal::from(incentive.total_rewards),
                    decimal::from(time_passed_ms)
                ),
                decimal::from(incentive.end_time_ms - incentive.start_time_ms)
            );
            incentive.allocated_rewards = add(incentive.allocated_rewards, unlocked_rewards);

            incentive.cumulative_rewards_per_weight = add(
                incentive.cumulative_rewards_per_weight,
                div(
                    unlocked_rewards,
                    decimal::from(incentive_manager.total_weight)
                )
            );

            i = i + 1;
        };

        incentive_manager.last_update_time_ms = cur_time_ms;
    }

    public fun update_farmer(incentive_manager: &mut IncentiveManager, farmer: &mut Farmer, clock: &Clock) {
        assert!(object::id(incentive_manager) == farmer.incentive_manager_id, EIdMismatch);

        let cur_time_ms = clock::timestamp_ms(clock);
        assert!(incentive_manager.last_update_time_ms == cur_time_ms, EIncentiveManagerNotUpdated);

        let i = 0;
        while (i < vector::length(&incentive_manager.incentives)) {
            let optional_incentive = vector::borrow_mut(&mut incentive_manager.incentives, i);
            if (option::is_none(optional_incentive)) {
                i = i + 1;
                continue
            };

            let incentive = option::borrow_mut(optional_incentive);

            let optional_reward = vector::borrow_mut(&mut farmer.rewards, i);
            if (option::is_none(optional_reward)) {
                if (cur_time_ms < incentive.end_time_ms) {
                    option::fill(
                        optional_reward, 
                        Reward {
                            incentive_id: incentive.incentive_id,
                            accumulated_rewards: decimal::from(0),
                            cumulative_rewards_per_weight: incentive.cumulative_rewards_per_weight
                        }
                    );

                    incentive.num_farmers = incentive.num_farmers + 1;
                };
            }
            else {
                let reward = option::borrow_mut(optional_reward);
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

        farmer.last_update_time_ms = cur_time_ms;
    }

    // === Public-Friend functions
    /// Create a new farmer object with zero weight.
    public(friend) fun new_farmer(
        incentive_manager: &mut IncentiveManager,
        clock: &Clock,
    ): Farmer {
        assert!(incentive_manager.last_update_time_ms == clock::timestamp_ms(clock), EIncentiveManagerNotUpdated);

        let farmer = Farmer {
            incentive_manager_id: object::id(incentive_manager),
            weight: 0,
            rewards: {
                let v = vector::empty();
                let i = 0;
                while (i < MAX_REWARDS) {
                    vector::push_back(&mut v, option::none());
                    i = i + 1;
                };

                v
            },
            last_update_time_ms: clock::timestamp_ms(clock),
        };

        // needed to populate the rewards vector
        update_farmer(incentive_manager, &mut farmer, clock);

        farmer
    }

    public(friend) fun change_farmer_weight(
        incentive_manager: &mut IncentiveManager, 
        farmer: &mut Farmer, 
        new_weight: u64, 
        clock: &Clock
    ) {
        assert!(object::id(incentive_manager) == farmer.incentive_manager_id, EIdMismatch);
        assert!(incentive_manager.last_update_time_ms == clock::timestamp_ms(clock), EIncentiveManagerNotUpdated);
        assert!(farmer.last_update_time_ms == clock::timestamp_ms(clock), EFarmerNotUpdated);

        incentive_manager.total_weight = incentive_manager.total_weight - farmer.weight + new_weight;
        farmer.weight = new_weight;
    }

    public(friend) fun claim_rewards<T>(
        incentive_manager: &mut IncentiveManager, 
        farmer: &mut Farmer, 
        clock: &Clock, 
        index: u64
    ): Balance<T> {
        assert!(object::id(incentive_manager) == farmer.incentive_manager_id, EIdMismatch);
        assert!(incentive_manager.last_update_time_ms == clock::timestamp_ms(clock), EIncentiveManagerNotUpdated);
        assert!(farmer.last_update_time_ms == clock::timestamp_ms(clock), EFarmerNotUpdated);

        let incentive = option::borrow_mut(vector::borrow_mut(&mut incentive_manager.incentives, index));
        assert!(incentive.coin_type == type_name::get<T>(), EInvalidType);

        let optional_reward = vector::borrow_mut(&mut farmer.rewards, index);
        let reward = option::borrow_mut(optional_reward);

        let claimable_rewards = floor(reward.accumulated_rewards);

        reward.accumulated_rewards = sub(reward.accumulated_rewards, decimal::from(claimable_rewards));
        let reward_balance: &mut Balance<T> = bag::borrow_mut(
            &mut incentive.additional_fields,
            RewardBalance<T> {}
        );

        if (clock::timestamp_ms(clock) >= incentive.end_time_ms) {
            let Reward { 
                incentive_id: _, 
                accumulated_rewards: _, 
                cumulative_rewards_per_weight: _ 
            } = option::extract(optional_reward);

            incentive.num_farmers = incentive.num_farmers - 1;
        };

        balance::split(reward_balance, claimable_rewards)
    }

    // === Private Functions ===
    fun find_available_index(incentive_manager: &IncentiveManager): u64 {
        let i = 0;
        while (i < vector::length(&incentive_manager.incentives)) {
            let optional_incentive = vector::borrow(&incentive_manager.incentives, i);
            if (option::is_none(optional_incentive)) {
                return i
            };

            i = i + 1;
        };

        i
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

        let farmer_1 = new_farmer(&mut incentive_manager, &clock);
        change_farmer_weight(&mut incentive_manager, &mut farmer_1, 100, &clock);
        std::debug::print(&farmer_1);

        // at this point, farmer 1 has earned 50 dollars
        clock::set_for_testing(&mut clock, 5 * 1000);
        update_incentive_manager(&mut incentive_manager, &clock);
        update_farmer(&mut incentive_manager, &mut farmer_1, &clock);
        {
            let usdc = claim_rewards<USDC>(&mut incentive_manager, &mut farmer_1, &clock, 0);
            std::debug::print(&usdc);
            assert!(balance::value(&usdc) == 25 * 1_000_000, 0);
            sui::test_utils::destroy(usdc);
        };

        let farmer_2 = new_farmer(&mut incentive_manager, &clock);
        change_farmer_weight(&mut incentive_manager, &mut farmer_2, 400, &clock);

        clock::set_for_testing(&mut clock, 10 * 1000);
        update_incentive_manager(&mut incentive_manager, &clock);
        update_farmer(&mut incentive_manager, &mut farmer_1, &clock);
        update_farmer(&mut incentive_manager, &mut farmer_2, &clock);
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

        change_farmer_weight(&mut incentive_manager, &mut farmer_1, 250, &clock);
        change_farmer_weight(&mut incentive_manager, &mut farmer_2, 250, &clock);

        clock::set_for_testing(&mut clock, 20 * 1000);
        update_incentive_manager(&mut incentive_manager, &clock);
        update_farmer(&mut incentive_manager, &mut farmer_1, &clock);
        update_farmer(&mut incentive_manager, &mut farmer_2, &clock);
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
        add_incentive(&mut incentive_manager, sui, 10 * 1000, 20 * 1000, &clock, ctx);

        let farmer_1 = new_farmer(&mut incentive_manager, &clock);
        change_farmer_weight(&mut incentive_manager, &mut farmer_1, 100, &clock);

        clock::set_for_testing(&mut clock, 15 * 1000);
        update_incentive_manager(&mut incentive_manager, &clock);
        let farmer_2 = new_farmer(&mut incentive_manager, &clock);
        change_farmer_weight(&mut incentive_manager, &mut farmer_2, 100, &clock);

        clock::set_for_testing(&mut clock, 30 * 1000);
        update_incentive_manager(&mut incentive_manager, &clock);
        update_farmer(&mut incentive_manager, &mut farmer_1, &clock);
        update_farmer(&mut incentive_manager, &mut farmer_2, &clock);
        {
            let usdc = claim_rewards<USDC>(&mut incentive_manager, &mut farmer_1, &clock, 0);
            assert!(balance::value(&usdc) == 87_500_000, 0);
            sui::test_utils::destroy(usdc);
        };
        {
            let sui = claim_rewards<SUI>(&mut incentive_manager, &mut farmer_1, &clock, 1);
            assert!(balance::value(&sui) == 75 * 1_000_000, 0);
            sui::test_utils::destroy(sui);
        };

        {
            let usdc = claim_rewards<USDC>(&mut incentive_manager, &mut farmer_2, &clock, 0);
            assert!(balance::value(&usdc) == 12_500_000, 0);
            sui::test_utils::destroy(usdc);
        };
        {
            let sui = claim_rewards<SUI>(&mut incentive_manager, &mut farmer_2, &clock, 1);
            assert!(balance::value(&sui) == 25 * 1_000_000, 0);
            sui::test_utils::destroy(sui);
        };

        std::debug::print(&farmer_1);
        std::debug::print(&farmer_2);
        std::debug::print(&incentive_manager);

        sui::test_utils::destroy(clock);
        sui::test_utils::destroy(incentive_manager);
        sui::test_utils::destroy(farmer_1);
        sui::test_utils::destroy(farmer_2);
        test_scenario::end(scenario);

    }

    #[test]
    fun test_incentive_manager_cancel_and_close() {
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

        let farmer_1 = new_farmer(&mut incentive_manager, &clock);
        change_farmer_weight(&mut incentive_manager, &mut farmer_1, 100, &clock);

        clock::set_for_testing(&mut clock, 10 * 1000);
        update_incentive_manager(&mut incentive_manager, &clock);

        let unallocated_rewards = cancel_incentive<USDC>(&mut incentive_manager, 0, &clock);
        std::debug::print(&incentive_manager);
        assert!(balance::value(&unallocated_rewards) == 50 * 1_000_000, 0);

        clock::set_for_testing(&mut clock, 15 * 1000);
        update_incentive_manager(&mut incentive_manager, &clock);
        update_farmer(&mut incentive_manager, &mut farmer_1, &clock);
        let farmer_rewards = claim_rewards<USDC>(&mut incentive_manager, &mut farmer_1, &clock, 0);
        assert!(balance::value(&farmer_rewards) == 50 * 1_000_000, 0);

        let dust_rewards = close_incentive<USDC>(&mut incentive_manager, 0, &clock);
        assert!(balance::value(&dust_rewards) == 0, 0);

        std::debug::print(&incentive_manager);

        sui::test_utils::destroy(unallocated_rewards);
        sui::test_utils::destroy(farmer_rewards);
        sui::test_utils::destroy(dust_rewards);
        sui::test_utils::destroy(clock);
        sui::test_utils::destroy(incentive_manager);
        sui::test_utils::destroy(farmer_1);
        test_scenario::end(scenario);
    }
}
