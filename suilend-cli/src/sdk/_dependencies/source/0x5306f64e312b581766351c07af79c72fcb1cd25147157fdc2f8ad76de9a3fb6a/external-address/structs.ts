import {
  FieldsWithTypes,
  Type,
  compressSuiType,
} from "../../../../_framework/util";
import { Bytes32 } from "../bytes32/structs";
import { bcs } from "@mysten/bcs";

/* ============================== ExternalAddress =============================== */

export function isExternalAddress(type: Type): boolean {
  type = compressSuiType(type);
  return (
    type ===
    "0x5306f64e312b581766351c07af79c72fcb1cd25147157fdc2f8ad76de9a3fb6a::external_address::ExternalAddress"
  );
}

export interface ExternalAddressFields {
  value: Bytes32;
}

export class ExternalAddress {
  static readonly $typeName =
    "0x5306f64e312b581766351c07af79c72fcb1cd25147157fdc2f8ad76de9a3fb6a::external_address::ExternalAddress";
  static readonly $numTypeParams = 0;

  static get bcs() {
    return bcs.struct("ExternalAddress", {
      value: Bytes32.bcs,
    });
  }

  readonly value: Bytes32;

  constructor(value: Bytes32) {
    this.value = value;
  }

  static fromFields(fields: Record<string, any>): ExternalAddress {
    return new ExternalAddress(Bytes32.fromFields(fields.value));
  }

  static fromFieldsWithTypes(item: FieldsWithTypes): ExternalAddress {
    if (!isExternalAddress(item.type)) {
      throw new Error("not a ExternalAddress type");
    }
    return new ExternalAddress(Bytes32.fromFieldsWithTypes(item.fields.value));
  }

  static fromBcs(data: Uint8Array): ExternalAddress {
    return ExternalAddress.fromFields(ExternalAddress.bcs.parse(data));
  }
}
