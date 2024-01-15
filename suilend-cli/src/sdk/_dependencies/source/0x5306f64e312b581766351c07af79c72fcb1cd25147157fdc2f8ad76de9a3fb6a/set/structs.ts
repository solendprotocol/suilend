import {
  FieldsWithTypes,
  Type,
  compressSuiType,
  parseTypeName,
} from "../../../../_framework/util";
import { Table } from "../../0x2/table/structs";
import { bcs } from "@mysten/bcs";

/* ============================== Empty =============================== */

export function isEmpty(type: Type): boolean {
  type = compressSuiType(type);
  return (
    type ===
    "0x5306f64e312b581766351c07af79c72fcb1cd25147157fdc2f8ad76de9a3fb6a::set::Empty"
  );
}

export interface EmptyFields {
  dummyField: boolean;
}

export class Empty {
  static readonly $typeName =
    "0x5306f64e312b581766351c07af79c72fcb1cd25147157fdc2f8ad76de9a3fb6a::set::Empty";
  static readonly $numTypeParams = 0;

  static get bcs() {
    return bcs.struct("Empty", {
      dummy_field: bcs.bool(),
    });
  }

  readonly dummyField: boolean;

  constructor(dummyField: boolean) {
    this.dummyField = dummyField;
  }

  static fromFields(fields: Record<string, any>): Empty {
    return new Empty(fields.dummy_field);
  }

  static fromFieldsWithTypes(item: FieldsWithTypes): Empty {
    if (!isEmpty(item.type)) {
      throw new Error("not a Empty type");
    }
    return new Empty(item.fields.dummy_field);
  }

  static fromBcs(data: Uint8Array): Empty {
    return Empty.fromFields(Empty.bcs.parse(data));
  }
}

/* ============================== Set =============================== */

export function isSet(type: Type): boolean {
  type = compressSuiType(type);
  return type.startsWith(
    "0x5306f64e312b581766351c07af79c72fcb1cd25147157fdc2f8ad76de9a3fb6a::set::Set<"
  );
}

export interface SetFields {
  items: Table;
}

export class Set {
  static readonly $typeName =
    "0x5306f64e312b581766351c07af79c72fcb1cd25147157fdc2f8ad76de9a3fb6a::set::Set";
  static readonly $numTypeParams = 1;

  static get bcs() {
    return bcs.struct("Set", {
      items: Table.bcs,
    });
  }

  readonly $typeArg: Type;

  readonly items: Table;

  constructor(typeArg: Type, items: Table) {
    this.$typeArg = typeArg;

    this.items = items;
  }

  static fromFields(typeArg: Type, fields: Record<string, any>): Set {
    return new Set(
      typeArg,
      Table.fromFields(
        [
          `${typeArg}`,
          `0x5306f64e312b581766351c07af79c72fcb1cd25147157fdc2f8ad76de9a3fb6a::set::Empty`,
        ],
        fields.items
      )
    );
  }

  static fromFieldsWithTypes(item: FieldsWithTypes): Set {
    if (!isSet(item.type)) {
      throw new Error("not a Set type");
    }
    const { typeArgs } = parseTypeName(item.type);

    return new Set(typeArgs[0], Table.fromFieldsWithTypes(item.fields.items));
  }

  static fromBcs(typeArg: Type, data: Uint8Array): Set {
    return Set.fromFields(typeArg, Set.bcs.parse(data));
  }
}
