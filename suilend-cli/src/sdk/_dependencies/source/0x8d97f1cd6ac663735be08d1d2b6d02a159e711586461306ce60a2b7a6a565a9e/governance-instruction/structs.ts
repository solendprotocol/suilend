import {
  FieldsWithTypes,
  Type,
  compressSuiType,
} from "../../../../_framework/util";
import { GovernanceAction } from "../governance-action/structs";
import { bcs } from "@mysten/bcs";

/* ============================== GovernanceInstruction =============================== */

export function isGovernanceInstruction(type: Type): boolean {
  type = compressSuiType(type);
  return (
    type ===
    "0x8d97f1cd6ac663735be08d1d2b6d02a159e711586461306ce60a2b7a6a565a9e::governance_instruction::GovernanceInstruction"
  );
}

export interface GovernanceInstructionFields {
  module: number;
  action: GovernanceAction;
  targetChainId: bigint;
  payload: Array<number>;
}

export class GovernanceInstruction {
  static readonly $typeName =
    "0x8d97f1cd6ac663735be08d1d2b6d02a159e711586461306ce60a2b7a6a565a9e::governance_instruction::GovernanceInstruction";
  static readonly $numTypeParams = 0;

  static get bcs() {
    return bcs.struct("GovernanceInstruction", {
      module_: bcs.u8(),
      action: GovernanceAction.bcs,
      target_chain_id: bcs.u64(),
      payload: bcs.vector(bcs.u8()),
    });
  }

  readonly module: number;
  readonly action: GovernanceAction;
  readonly targetChainId: bigint;
  readonly payload: Array<number>;

  constructor(fields: GovernanceInstructionFields) {
    this.module = fields.module;
    this.action = fields.action;
    this.targetChainId = fields.targetChainId;
    this.payload = fields.payload;
  }

  static fromFields(fields: Record<string, any>): GovernanceInstruction {
    return new GovernanceInstruction({
      module: fields.module_,
      action: GovernanceAction.fromFields(fields.action),
      targetChainId: BigInt(fields.target_chain_id),
      payload: fields.payload.map((item: any) => item),
    });
  }

  static fromFieldsWithTypes(item: FieldsWithTypes): GovernanceInstruction {
    if (!isGovernanceInstruction(item.type)) {
      throw new Error("not a GovernanceInstruction type");
    }
    return new GovernanceInstruction({
      module: item.fields.module_,
      action: GovernanceAction.fromFieldsWithTypes(item.fields.action),
      targetChainId: BigInt(item.fields.target_chain_id),
      payload: item.fields.payload.map((item: any) => item),
    });
  }

  static fromBcs(data: Uint8Array): GovernanceInstruction {
    return GovernanceInstruction.fromFields(
      GovernanceInstruction.bcs.parse(data)
    );
  }
}
