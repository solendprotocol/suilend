module suilend::oracles {
    use pyth::price_info::{Self, PriceInfoObject};
    use pyth::price_feed::{Self};
    use pyth::price_identifier::{PriceIdentifier};
    use pyth::price::{Self};
    use pyth::i64::{Self};
    use suilend::decimal::{Decimal, Self, mul, div};
    use sui::math::{Self};

    public fun get_pyth_price_and_identifier(price_info_obj: &PriceInfoObject): (Decimal, PriceIdentifier) {
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

}

