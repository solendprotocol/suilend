import {
  FieldsWithTypes,
  Type,
  compressSuiType,
} from "../../../../_framework/util";
import { bcs } from "@mysten/bcs";

/* ============================== Bytes32 =============================== */

export function isBytes32(type: Type): boolean {
  type = compressSuiType(type);
  return (
    type ===
    "0x5306f64e312b581766351c07af79c72fcb1cd25147157fdc2f8ad76de9a3fb6a::bytes32::Bytes32"
  );
}

export interface Bytes32Fields {
  data: Array<number>;
}

export class Bytes32 {
  static readonly $typeName =
    "0x5306f64e312b581766351c07af79c72fcb1cd25147157fdc2f8ad76de9a3fb6a::bytes32::Bytes32";
  static readonly $numTypeParams = 0;

  static get bcs() {
    return bcs.struct("Bytes32", {
      data: bcs.vector(bcs.u8()),
    });
  }

  readonly data: Array<number>;

  constructor(data: Array<number>) {
    this.data = data;
  }

  static fromFields(fields: Record<string, any>): Bytes32 {
    return new Bytes32(fields.data.map((item: any) => item));
  }

  static fromFieldsWithTypes(item: FieldsWithTypes): Bytes32 {
    if (!isBytes32(item.type)) {
      throw new Error("not a Bytes32 type");
    }
    return new Bytes32(item.fields.data.map((item: any) => item));
  }

  static fromBcs(data: Uint8Array): Bytes32 {
    return Bytes32.fromFields(Bytes32.bcs.parse(data));
  }
}
