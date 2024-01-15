import {
  FieldsWithTypes,
  Type,
  compressSuiType,
} from "../../../../_framework/util";
import { bcs } from "@mysten/bcs";

/* ============================== GovernanceWitness =============================== */

export function isGovernanceWitness(type: Type): boolean {
  type = compressSuiType(type);
  return (
    type ===
    "0x5306f64e312b581766351c07af79c72fcb1cd25147157fdc2f8ad76de9a3fb6a::set_fee::GovernanceWitness"
  );
}

export interface GovernanceWitnessFields {
  dummyField: boolean;
}

export class GovernanceWitness {
  static readonly $typeName =
    "0x5306f64e312b581766351c07af79c72fcb1cd25147157fdc2f8ad76de9a3fb6a::set_fee::GovernanceWitness";
  static readonly $numTypeParams = 0;

  static get bcs() {
    return bcs.struct("GovernanceWitness", {
      dummy_field: bcs.bool(),
    });
  }

  readonly dummyField: boolean;

  constructor(dummyField: boolean) {
    this.dummyField = dummyField;
  }

  static fromFields(fields: Record<string, any>): GovernanceWitness {
    return new GovernanceWitness(fields.dummy_field);
  }

  static fromFieldsWithTypes(item: FieldsWithTypes): GovernanceWitness {
    if (!isGovernanceWitness(item.type)) {
      throw new Error("not a GovernanceWitness type");
    }
    return new GovernanceWitness(item.fields.dummy_field);
  }

  static fromBcs(data: Uint8Array): GovernanceWitness {
    return GovernanceWitness.fromFields(GovernanceWitness.bcs.parse(data));
  }
}

/* ============================== SetFee =============================== */

export function isSetFee(type: Type): boolean {
  type = compressSuiType(type);
  return (
    type ===
    "0x5306f64e312b581766351c07af79c72fcb1cd25147157fdc2f8ad76de9a3fb6a::set_fee::SetFee"
  );
}

export interface SetFeeFields {
  amount: bigint;
}

export class SetFee {
  static readonly $typeName =
    "0x5306f64e312b581766351c07af79c72fcb1cd25147157fdc2f8ad76de9a3fb6a::set_fee::SetFee";
  static readonly $numTypeParams = 0;

  static get bcs() {
    return bcs.struct("SetFee", {
      amount: bcs.u64(),
    });
  }

  readonly amount: bigint;

  constructor(amount: bigint) {
    this.amount = amount;
  }

  static fromFields(fields: Record<string, any>): SetFee {
    return new SetFee(BigInt(fields.amount));
  }

  static fromFieldsWithTypes(item: FieldsWithTypes): SetFee {
    if (!isSetFee(item.type)) {
      throw new Error("not a SetFee type");
    }
    return new SetFee(BigInt(item.fields.amount));
  }

  static fromBcs(data: Uint8Array): SetFee {
    return SetFee.fromFields(SetFee.bcs.parse(data));
  }
}
