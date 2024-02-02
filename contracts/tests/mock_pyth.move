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

    struct State has key {
        id: UID,
        num_feeds: u8
    }

    public fun init_state(ctx: &mut TxContext): State {
        State {
            id: object::new(ctx),
            num_feeds: 0
        }
    }

    #[test_only]
    public fun destroy_state(state: State) {
        let State { id, num_feeds: _ } = state;
        object::delete(id);
    }

    public fun create_price_info_obj(
        state: &mut State,
        ctx: &mut TxContext
    ): PriceInfoObject {
        state.num_feeds = state.num_feeds + 1;

        let v = vector::empty<u8>();
        vector::push_back(&mut v, state.num_feeds);

        let i = 1;
        while (i < 32) {
            vector::push_back(&mut v, 0);
            i = i + 1;
        };


        price_info::new_price_info_object_for_testing(
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
        )
    }

    public fun update_price(
        price_info_obj: &mut PriceInfoObject,
        price: Price
    ) {
        let price_info = price_info::get_price_info_from_price_info_object(price_info_obj);

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
