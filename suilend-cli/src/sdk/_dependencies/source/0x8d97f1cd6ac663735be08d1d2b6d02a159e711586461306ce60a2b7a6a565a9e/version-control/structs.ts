import {
  FieldsWithTypes,
  Type,
  compressSuiType,
} from "../../../../_framework/util";
import { bcs } from "@mysten/bcs";

/* ============================== V__DUMMY =============================== */

export function isV__DUMMY(type: Type): boolean {
  type = compressSuiType(type);
  return (
    type ===
    "0x8d97f1cd6ac663735be08d1d2b6d02a159e711586461306ce60a2b7a6a565a9e::version_control::V__DUMMY"
  );
}

export interface V__DUMMYFields {
  dummyField: boolean;
}

export class V__DUMMY {
  static readonly $typeName =
    "0x8d97f1cd6ac663735be08d1d2b6d02a159e711586461306ce60a2b7a6a565a9e::version_control::V__DUMMY";
  static readonly $numTypeParams = 0;

  static get bcs() {
    return bcs.struct("V__DUMMY", {
      dummy_field: bcs.bool(),
    });
  }

  readonly dummyField: boolean;

  constructor(dummyField: boolean) {
    this.dummyField = dummyField;
  }

  static fromFields(fields: Record<string, any>): V__DUMMY {
    return new V__DUMMY(fields.dummy_field);
  }

  static fromFieldsWithTypes(item: FieldsWithTypes): V__DUMMY {
    if (!isV__DUMMY(item.type)) {
      throw new Error("not a V__DUMMY type");
    }
    return new V__DUMMY(item.fields.dummy_field);
  }

  static fromBcs(data: Uint8Array): V__DUMMY {
    return V__DUMMY.fromFields(V__DUMMY.bcs.parse(data));
  }
}

/* ============================== V__0_1_1 =============================== */

export function isV__0_1_1(type: Type): boolean {
  type = compressSuiType(type);
  return (
    type ===
    "0x8d97f1cd6ac663735be08d1d2b6d02a159e711586461306ce60a2b7a6a565a9e::version_control::V__0_1_1"
  );
}

export interface V__0_1_1Fields {
  dummyField: boolean;
}

export class V__0_1_1 {
  static readonly $typeName =
    "0x8d97f1cd6ac663735be08d1d2b6d02a159e711586461306ce60a2b7a6a565a9e::version_control::V__0_1_1";
  static readonly $numTypeParams = 0;

  static get bcs() {
    return bcs.struct("V__0_1_1", {
      dummy_field: bcs.bool(),
    });
  }

  readonly dummyField: boolean;

  constructor(dummyField: boolean) {
    this.dummyField = dummyField;
  }

  static fromFields(fields: Record<string, any>): V__0_1_1 {
    return new V__0_1_1(fields.dummy_field);
  }

  static fromFieldsWithTypes(item: FieldsWithTypes): V__0_1_1 {
    if (!isV__0_1_1(item.type)) {
      throw new Error("not a V__0_1_1 type");
    }
    return new V__0_1_1(item.fields.dummy_field);
  }

  static fromBcs(data: Uint8Array): V__0_1_1 {
    return V__0_1_1.fromFields(V__0_1_1.bcs.parse(data));
  }
}

/* ============================== V__0_1_2 =============================== */

export function isV__0_1_2(type: Type): boolean {
  type = compressSuiType(type);
  return (
    type ===
    "0x8d97f1cd6ac663735be08d1d2b6d02a159e711586461306ce60a2b7a6a565a9e::version_control::V__0_1_2"
  );
}

export interface V__0_1_2Fields {
  dummyField: boolean;
}

export class V__0_1_2 {
  static readonly $typeName =
    "0x8d97f1cd6ac663735be08d1d2b6d02a159e711586461306ce60a2b7a6a565a9e::version_control::V__0_1_2";
  static readonly $numTypeParams = 0;

  static get bcs() {
    return bcs.struct("V__0_1_2", {
      dummy_field: bcs.bool(),
    });
  }

  readonly dummyField: boolean;

  constructor(dummyField: boolean) {
    this.dummyField = dummyField;
  }

  static fromFields(fields: Record<string, any>): V__0_1_2 {
    return new V__0_1_2(fields.dummy_field);
  }

  static fromFieldsWithTypes(item: FieldsWithTypes): V__0_1_2 {
    if (!isV__0_1_2(item.type)) {
      throw new Error("not a V__0_1_2 type");
    }
    return new V__0_1_2(item.fields.dummy_field);
  }

  static fromBcs(data: Uint8Array): V__0_1_2 {
    return V__0_1_2.fromFields(V__0_1_2.bcs.parse(data));
  }
}
