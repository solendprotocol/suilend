#[test_only]
module suilend::mock_pyth {
    use pyth::price_info::{Self, PriceInfoObject};
    use pyth::price_feed::{Self};
    use pyth::price::{Self, Price};
    use pyth::price_identifier::{Self};
    use pyth::i64::{Self};
    use sui::tx_context::{TxContext};
    use std::vector::{Self};
    use sui::object::{Self, UID};
    use sui::bag::{Self, Bag};
    use sui::clock::{Clock, Self};

    struct PriceState has key {
        id: UID,
        price_objs: Bag
    }

    public fun init_state(ctx: &mut TxContext): PriceState {
        PriceState {
            id: object::new(ctx),
            price_objs: bag::new(ctx)
        }
    }

    public fun register<T>(state: &mut PriceState, ctx: &mut TxContext) {
        let v = vector::empty<u8>();
        vector::push_back(&mut v, (bag::length(&state.price_objs) as u8));

        let i = 1;
        while (i < 32) {
            vector::push_back(&mut v, 0);
            i = i + 1;
        };


        let price_info_obj = price_info::new_price_info_object_for_testing(
            price_info::new_price_info(
                0,
                0,
                price_feed::new(
                    price_identifier::from_byte_vec(v),
                    price::new(
                        i64::new(0, false),
                        0,
                        i64::new(0, false),
                        0
                    ),
                    price::new(
                        i64::new(0, false),
                        0,
                        i64::new(0, false),
                        0
                    )
                )
            ),
            ctx
        );

        bag::add(&mut state.price_objs, std::type_name::get<T>(), price_info_obj);
    }

    public fun get_price_obj<T>(state: &PriceState): &PriceInfoObject {
        bag::borrow(&state.price_objs, std::type_name::get<T>())
    }

    public fun update_price<T>(state: &mut PriceState, price: u64, expo: u8, clock: &Clock) {
        let price_info_obj = bag::borrow_mut(&mut state.price_objs, std::type_name::get<T>());
        let price_info = price_info::get_price_info_from_price_info_object(price_info_obj);

        let price = price::new(
            i64::new(price, false),
            0,
            i64::new((expo as u64), false),
            clock::timestamp_ms(clock) / 1000
        );

        price_info::update_price_info_object_for_testing(
            price_info_obj,
            &price_info::new_price_info(
                0,
                0,
                price_feed::new(
                    price_info::get_price_identifier(&price_info),
                    price,
                    price
                )
            )
        );
        
    }
}
