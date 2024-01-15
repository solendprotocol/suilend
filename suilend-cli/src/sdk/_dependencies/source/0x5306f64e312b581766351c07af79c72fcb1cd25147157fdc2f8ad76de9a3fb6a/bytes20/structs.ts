import {
  FieldsWithTypes,
  Type,
  compressSuiType,
} from "../../../../_framework/util";
import { bcs } from "@mysten/bcs";

/* ============================== Bytes20 =============================== */

export function isBytes20(type: Type): boolean {
  type = compressSuiType(type);
  return (
    type ===
    "0x5306f64e312b581766351c07af79c72fcb1cd25147157fdc2f8ad76de9a3fb6a::bytes20::Bytes20"
  );
}

export interface Bytes20Fields {
  data: Array<number>;
}

export class Bytes20 {
  static readonly $typeName =
    "0x5306f64e312b581766351c07af79c72fcb1cd25147157fdc2f8ad76de9a3fb6a::bytes20::Bytes20";
  static readonly $numTypeParams = 0;

  static get bcs() {
    return bcs.struct("Bytes20", {
      data: bcs.vector(bcs.u8()),
    });
  }

  readonly data: Array<number>;

  constructor(data: Array<number>) {
    this.data = data;
  }

  static fromFields(fields: Record<string, any>): Bytes20 {
    return new Bytes20(fields.data.map((item: any) => item));
  }

  static fromFieldsWithTypes(item: FieldsWithTypes): Bytes20 {
    if (!isBytes20(item.type)) {
      throw new Error("not a Bytes20 type");
    }
    return new Bytes20(item.fields.data.map((item: any) => item));
  }

  static fromBcs(data: Uint8Array): Bytes20 {
    return Bytes20.fromFields(Bytes20.bcs.parse(data));
  }
}
