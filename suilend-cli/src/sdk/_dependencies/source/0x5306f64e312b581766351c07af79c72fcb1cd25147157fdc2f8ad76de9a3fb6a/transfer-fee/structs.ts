import {
  FieldsWithTypes,
  Type,
  compressSuiType,
} from "../../../../_framework/util";
import { bcs, fromHEX, toHEX } from "@mysten/bcs";

/* ============================== GovernanceWitness =============================== */

export function isGovernanceWitness(type: Type): boolean {
  type = compressSuiType(type);
  return (
    type ===
    "0x5306f64e312b581766351c07af79c72fcb1cd25147157fdc2f8ad76de9a3fb6a::transfer_fee::GovernanceWitness"
  );
}

export interface GovernanceWitnessFields {
  dummyField: boolean;
}

export class GovernanceWitness {
  static readonly $typeName =
    "0x5306f64e312b581766351c07af79c72fcb1cd25147157fdc2f8ad76de9a3fb6a::transfer_fee::GovernanceWitness";
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

/* ============================== TransferFee =============================== */

export function isTransferFee(type: Type): boolean {
  type = compressSuiType(type);
  return (
    type ===
    "0x5306f64e312b581766351c07af79c72fcb1cd25147157fdc2f8ad76de9a3fb6a::transfer_fee::TransferFee"
  );
}

export interface TransferFeeFields {
  amount: bigint;
  recipient: string;
}

export class TransferFee {
  static readonly $typeName =
    "0x5306f64e312b581766351c07af79c72fcb1cd25147157fdc2f8ad76de9a3fb6a::transfer_fee::TransferFee";
  static readonly $numTypeParams = 0;

  static get bcs() {
    return bcs.struct("TransferFee", {
      amount: bcs.u64(),
      recipient: bcs
        .bytes(32)
        .transform({
          input: (val: string) => fromHEX(val),
          output: (val: Uint8Array) => toHEX(val),
        }),
    });
  }

  readonly amount: bigint;
  readonly recipient: string;

  constructor(fields: TransferFeeFields) {
    this.amount = fields.amount;
    this.recipient = fields.recipient;
  }

  static fromFields(fields: Record<string, any>): TransferFee {
    return new TransferFee({
      amount: BigInt(fields.amount),
      recipient: `0x${fields.recipient}`,
    });
  }

  static fromFieldsWithTypes(item: FieldsWithTypes): TransferFee {
    if (!isTransferFee(item.type)) {
      throw new Error("not a TransferFee type");
    }
    return new TransferFee({
      amount: BigInt(item.fields.amount),
      recipient: `0x${item.fields.recipient}`,
    });
  }

  static fromBcs(data: Uint8Array): TransferFee {
    return TransferFee.fromFields(TransferFee.bcs.parse(data));
  }
}
