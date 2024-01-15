import { initLoaderIfNeeded } from "../../../../_framework/init-source";
import { structClassLoaderSource } from "../../../../_framework/loader";
import {
  FieldsWithTypes,
  Type,
  compressSuiType,
  parseTypeName,
} from "../../../../_framework/util";
import { Table } from "../../0x2/table/structs";
import { BcsType, bcs } from "@mysten/bcs";

/* ============================== Set =============================== */

export function isSet(type: Type): boolean {
  type = compressSuiType(type);
  return type.startsWith(
    "0x8d97f1cd6ac663735be08d1d2b6d02a159e711586461306ce60a2b7a6a565a9e::set::Set<"
  );
}

export interface SetFields<A> {
  keys: Array<A>;
  elems: Table;
}

export class Set<A> {
  static readonly $typeName =
    "0x8d97f1cd6ac663735be08d1d2b6d02a159e711586461306ce60a2b7a6a565a9e::set::Set";
  static readonly $numTypeParams = 1;

  static get bcs() {
    return <A extends BcsType<any>>(A: A) =>
      bcs.struct(`Set<${A.name}>`, {
        keys: bcs.vector(A),
        elems: Table.bcs,
      });
  }

  readonly $typeArg: Type;

  readonly keys: Array<A>;
  readonly elems: Table;

  constructor(typeArg: Type, fields: SetFields<A>) {
    this.$typeArg = typeArg;

    this.keys = fields.keys;
    this.elems = fields.elems;
  }

  static fromFields<A>(typeArg: Type, fields: Record<string, any>): Set<A> {
    initLoaderIfNeeded();

    return new Set(typeArg, {
      keys: fields.keys.map((item: any) =>
        structClassLoaderSource.fromFields(typeArg, item)
      ),
      elems: Table.fromFields(
        [
          `${typeArg}`,
          `0x8d97f1cd6ac663735be08d1d2b6d02a159e711586461306ce60a2b7a6a565a9e::set::Unit`,
        ],
        fields.elems
      ),
    });
  }

  static fromFieldsWithTypes<A>(item: FieldsWithTypes): Set<A> {
    initLoaderIfNeeded();

    if (!isSet(item.type)) {
      throw new Error("not a Set type");
    }
    const { typeArgs } = parseTypeName(item.type);

    return new Set(typeArgs[0], {
      keys: item.fields.keys.map((item: any) =>
        structClassLoaderSource.fromFieldsWithTypes(typeArgs[0], item)
      ),
      elems: Table.fromFieldsWithTypes(item.fields.elems),
    });
  }

  static fromBcs<A>(typeArg: Type, data: Uint8Array): Set<A> {
    initLoaderIfNeeded();

    const typeArgs = [typeArg];

    return Set.fromFields(
      typeArg,
      Set.bcs(structClassLoaderSource.getBcsType(typeArgs[0])).parse(data)
    );
  }
}

/* ============================== Unit =============================== */

export function isUnit(type: Type): boolean {
  type = compressSuiType(type);
  return (
    type ===
    "0x8d97f1cd6ac663735be08d1d2b6d02a159e711586461306ce60a2b7a6a565a9e::set::Unit"
  );
}

export interface UnitFields {
  dummyField: boolean;
}

export class Unit {
  static readonly $typeName =
    "0x8d97f1cd6ac663735be08d1d2b6d02a159e711586461306ce60a2b7a6a565a9e::set::Unit";
  static readonly $numTypeParams = 0;

  static get bcs() {
    return bcs.struct("Unit", {
      dummy_field: bcs.bool(),
    });
  }

  readonly dummyField: boolean;

  constructor(dummyField: boolean) {
    this.dummyField = dummyField;
  }

  static fromFields(fields: Record<string, any>): Unit {
    return new Unit(fields.dummy_field);
  }

  static fromFieldsWithTypes(item: FieldsWithTypes): Unit {
    if (!isUnit(item.type)) {
      throw new Error("not a Unit type");
    }
    return new Unit(item.fields.dummy_field);
  }

  static fromBcs(data: Uint8Array): Unit {
    return Unit.fromFields(Unit.bcs.parse(data));
  }
}
