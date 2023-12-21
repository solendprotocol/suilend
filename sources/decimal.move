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

    public fun from_scaled_val(v: u256): Decimal {
        Decimal {
            value: v
        }
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

    public fun floor(a: Decimal): u64 {
        ((a.value / WAD) as u64)
    }

    public fun ceil_to_u64(a: Decimal): u64 {
        (((a.value + WAD - 1) / WAD) as u64)
    }

    public fun eq(a: Decimal, b: Decimal): bool {
        a.value == b.value
    }
}

#[test_only]
module suilend::decimal_tests {
    use suilend::decimal::{Self, add};

    #[test]
    fun test_add() {
        let a = decimal::from(1);
        let b = decimal::from(2);
        assert!(add(a, b) == decimal::from(3), 0);
    }
}
