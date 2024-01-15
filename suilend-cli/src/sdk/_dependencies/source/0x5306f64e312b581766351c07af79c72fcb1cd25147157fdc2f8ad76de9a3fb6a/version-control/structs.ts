import {
  FieldsWithTypes,
  Type,
  compressSuiType,
} from "../../../../_framework/util";
import { bcs } from "@mysten/bcs";

/* ============================== V__0_2_0 =============================== */

export function isV__0_2_0(type: Type): boolean {
  type = compressSuiType(type);
  return (
    type ===
    "0x5306f64e312b581766351c07af79c72fcb1cd25147157fdc2f8ad76de9a3fb6a::version_control::V__0_2_0"
  );
}

export interface V__0_2_0Fields {
  dummyField: boolean;
}

export class V__0_2_0 {
  static readonly $typeName =
    "0x5306f64e312b581766351c07af79c72fcb1cd25147157fdc2f8ad76de9a3fb6a::version_control::V__0_2_0";
  static readonly $numTypeParams = 0;

  static get bcs() {
    return bcs.struct("V__0_2_0", {
      dummy_field: bcs.bool(),
    });
  }

  readonly dummyField: boolean;

  constructor(dummyField: boolean) {
    this.dummyField = dummyField;
  }

  static fromFields(fields: Record<string, any>): V__0_2_0 {
    return new V__0_2_0(fields.dummy_field);
  }

  static fromFieldsWithTypes(item: FieldsWithTypes): V__0_2_0 {
    if (!isV__0_2_0(item.type)) {
      throw new Error("not a V__0_2_0 type");
    }
    return new V__0_2_0(item.fields.dummy_field);
  }

  static fromBcs(data: Uint8Array): V__0_2_0 {
    return V__0_2_0.fromFields(V__0_2_0.bcs.parse(data));
  }
}

/* ============================== V__DUMMY =============================== */

export function isV__DUMMY(type: Type): boolean {
  type = compressSuiType(type);
  return (
    type ===
    "0x5306f64e312b581766351c07af79c72fcb1cd25147157fdc2f8ad76de9a3fb6a::version_control::V__DUMMY"
  );
}

export interface V__DUMMYFields {
  dummyField: boolean;
}

export class V__DUMMY {
  static readonly $typeName =
    "0x5306f64e312b581766351c07af79c72fcb1cd25147157fdc2f8ad76de9a3fb6a::version_control::V__DUMMY";
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
