// fixed point decimal representation
module suilend::decimal {
    // 1e18
    const WAD: u256 = 1000000000000000000;

    struct Decimal has copy, store, drop {
        value: u256
    }

    public fun from(v: u64): Decimal {
        Decimal {
            value: (v as u256) * WAD
        }
    }

    public fun from_percent(v: u8): Decimal {
        Decimal {
            value: (v as u256) * WAD / 100
        }
    }

    public fun from_percent_u64(v: u64): Decimal {
        Decimal {
            value: (v as u256) * WAD / 100
        }
    }

    public fun from_bps(v: u64): Decimal {
        Decimal {
            value: (v as u256) * WAD / 10_000
        }
    }

    public fun from_scaled_val(v: u256): Decimal {
        Decimal {
            value: v
        }
    }

    public fun to_scaled_val(v: Decimal): u256 {
        v.value
    }

    public fun add(a: Decimal, b: Decimal): Decimal {
        Decimal {
            value: a.value + b.value
        }
    }

    public fun sub(a: Decimal, b: Decimal): Decimal {
        Decimal {
            value: a.value - b.value
        }
    }

    public fun mul(a: Decimal, b: Decimal): Decimal {
        Decimal {
            value: (a.value * b.value) / WAD
        }
    }

    public fun div(a: Decimal, b: Decimal): Decimal {
        Decimal {
            value: (a.value * WAD) / b.value
        }
    }

    // TODO: optimize this
    public fun pow(b: Decimal, e: u64): Decimal {
        let i = 0;
        let product = from(1);

        while (i < e) {
            product = mul(product, b);
            i = i + 1;
        };

        product
    }

    public fun floor(a: Decimal): u64 {
        ((a.value / WAD) as u64)
    }

    public fun ceil(a: Decimal): u64 {
        (((a.value + WAD - 1) / WAD) as u64)
    }

    public fun eq(a: Decimal, b: Decimal): bool {
        a.value == b.value
    }

    public fun ge(a: Decimal, b: Decimal): bool {
        a.value >= b.value
    }

    public fun gt(a: Decimal, b: Decimal): bool {
        a.value > b.value
    }

    public fun le(a: Decimal, b: Decimal): bool {
        a.value <= b.value
    }

    public fun lt(a: Decimal, b: Decimal): bool {
        a.value < b.value
    }

    public fun min(a: Decimal, b: Decimal): Decimal {
        if (a.value < b.value) {
            a
        } else {
            b
        }
    }

    public fun max(a: Decimal, b: Decimal): Decimal {
        if (a.value > b.value) {
            a
        } else {
            b
        }
    }
}

#[test_only]
module suilend::decimal_tests {
    use suilend::decimal::{Self, add, pow};

    #[test]
    fun test_add() {
        let a = decimal::from(1);
        let b = decimal::from(2);
        assert!(add(a, b) == decimal::from(3), 0);
    }

    #[test]
    fun test_pow() {
        assert!(pow(decimal::from(5), 4) == decimal::from(625), 0);
    }
}
