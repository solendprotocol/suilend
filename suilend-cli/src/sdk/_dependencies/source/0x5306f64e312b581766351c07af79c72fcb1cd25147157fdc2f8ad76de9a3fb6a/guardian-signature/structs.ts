import {
  FieldsWithTypes,
  Type,
  compressSuiType,
} from "../../../../_framework/util";
import { Bytes32 } from "../bytes32/structs";
import { bcs } from "@mysten/bcs";

/* ============================== GuardianSignature =============================== */

export function isGuardianSignature(type: Type): boolean {
  type = compressSuiType(type);
  return (
    type ===
    "0x5306f64e312b581766351c07af79c72fcb1cd25147157fdc2f8ad76de9a3fb6a::guardian_signature::GuardianSignature"
  );
}

export interface GuardianSignatureFields {
  r: Bytes32;
  s: Bytes32;
  recoveryId: number;
  index: number;
}

export class GuardianSignature {
  static readonly $typeName =
    "0x5306f64e312b581766351c07af79c72fcb1cd25147157fdc2f8ad76de9a3fb6a::guardian_signature::GuardianSignature";
  static readonly $numTypeParams = 0;

  static get bcs() {
    return bcs.struct("GuardianSignature", {
      r: Bytes32.bcs,
      s: Bytes32.bcs,
      recovery_id: bcs.u8(),
      index: bcs.u8(),
    });
  }

  readonly r: Bytes32;
  readonly s: Bytes32;
  readonly recoveryId: number;
  readonly index: number;

  constructor(fields: GuardianSignatureFields) {
    this.r = fields.r;
    this.s = fields.s;
    this.recoveryId = fields.recoveryId;
    this.index = fields.index;
  }

  static fromFields(fields: Record<string, any>): GuardianSignature {
    return new GuardianSignature({
      r: Bytes32.fromFields(fields.r),
      s: Bytes32.fromFields(fields.s),
      recoveryId: fields.recovery_id,
      index: fields.index,
    });
  }

  static fromFieldsWithTypes(item: FieldsWithTypes): GuardianSignature {
    if (!isGuardianSignature(item.type)) {
      throw new Error("not a GuardianSignature type");
    }
    return new GuardianSignature({
      r: Bytes32.fromFieldsWithTypes(item.fields.r),
      s: Bytes32.fromFieldsWithTypes(item.fields.s),
      recoveryId: item.fields.recovery_id,
      index: item.fields.index,
    });
  }

  static fromBcs(data: Uint8Array): GuardianSignature {
    return GuardianSignature.fromFields(GuardianSignature.bcs.parse(data));
  }
}
