module suilend::cell {
    use std::option::{Self, Option};

    struct Cell<Element> has store {
        element: Option<Element>
    }

    public fun new<Element>(element: Element): Cell<Element> {
        Cell { element: option::some(element) }
    }

    public fun set<Element>(cell: &mut Cell<Element>, element: Element): Element {
        option::swap(&mut cell.element, element)
    }

    public fun get<Element>(cell: &Cell<Element>): &Element {
        option::borrow(&cell.element)
    }
    
    public fun get_mut<Element>(cell: &mut Cell<Element>): &mut Element {
        option::borrow_mut(&mut cell.element)
    }

    public fun destroy<Element>(cell: Cell<Element>): Element {
        let Cell { element } = cell;
        option::destroy_some(element)
    }
}
