import {
  FieldsWithTypes,
  Type,
  compressSuiType,
} from "../../../../_framework/util";
import { Guardian } from "../guardian/structs";
import { bcs } from "@mysten/bcs";

/* ============================== GuardianSet =============================== */

export function isGuardianSet(type: Type): boolean {
  type = compressSuiType(type);
  return (
    type ===
    "0x5306f64e312b581766351c07af79c72fcb1cd25147157fdc2f8ad76de9a3fb6a::guardian_set::GuardianSet"
  );
}

export interface GuardianSetFields {
  index: number;
  guardians: Array<Guardian>;
  expirationTimestampMs: bigint;
}

export class GuardianSet {
  static readonly $typeName =
    "0x5306f64e312b581766351c07af79c72fcb1cd25147157fdc2f8ad76de9a3fb6a::guardian_set::GuardianSet";
  static readonly $numTypeParams = 0;

  static get bcs() {
    return bcs.struct("GuardianSet", {
      index: bcs.u32(),
      guardians: bcs.vector(Guardian.bcs),
      expiration_timestamp_ms: bcs.u64(),
    });
  }

  readonly index: number;
  readonly guardians: Array<Guardian>;
  readonly expirationTimestampMs: bigint;

  constructor(fields: GuardianSetFields) {
    this.index = fields.index;
    this.guardians = fields.guardians;
    this.expirationTimestampMs = fields.expirationTimestampMs;
  }

  static fromFields(fields: Record<string, any>): GuardianSet {
    return new GuardianSet({
      index: fields.index,
      guardians: fields.guardians.map((item: any) => Guardian.fromFields(item)),
      expirationTimestampMs: BigInt(fields.expiration_timestamp_ms),
    });
  }

  static fromFieldsWithTypes(item: FieldsWithTypes): GuardianSet {
    if (!isGuardianSet(item.type)) {
      throw new Error("not a GuardianSet type");
    }
    return new GuardianSet({
      index: item.fields.index,
      guardians: item.fields.guardians.map((item: any) =>
        Guardian.fromFieldsWithTypes(item)
      ),
      expirationTimestampMs: BigInt(item.fields.expiration_timestamp_ms),
    });
  }

  static fromBcs(data: Uint8Array): GuardianSet {
    return GuardianSet.fromFields(GuardianSet.bcs.parse(data));
  }
}
