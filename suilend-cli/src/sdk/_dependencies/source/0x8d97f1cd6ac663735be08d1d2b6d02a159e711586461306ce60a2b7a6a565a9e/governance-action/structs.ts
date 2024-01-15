import {
  FieldsWithTypes,
  Type,
  compressSuiType,
} from "../../../../_framework/util";
import { bcs } from "@mysten/bcs";

/* ============================== GovernanceAction =============================== */

export function isGovernanceAction(type: Type): boolean {
  type = compressSuiType(type);
  return (
    type ===
    "0x8d97f1cd6ac663735be08d1d2b6d02a159e711586461306ce60a2b7a6a565a9e::governance_action::GovernanceAction"
  );
}

export interface GovernanceActionFields {
  value: number;
}

export class GovernanceAction {
  static readonly $typeName =
    "0x8d97f1cd6ac663735be08d1d2b6d02a159e711586461306ce60a2b7a6a565a9e::governance_action::GovernanceAction";
  static readonly $numTypeParams = 0;

  static get bcs() {
    return bcs.struct("GovernanceAction", {
      value: bcs.u8(),
    });
  }

  readonly value: number;

  constructor(value: number) {
    this.value = value;
  }

  static fromFields(fields: Record<string, any>): GovernanceAction {
    return new GovernanceAction(fields.value);
  }

  static fromFieldsWithTypes(item: FieldsWithTypes): GovernanceAction {
    if (!isGovernanceAction(item.type)) {
      throw new Error("not a GovernanceAction type");
    }
    return new GovernanceAction(item.fields.value);
  }

  static fromBcs(data: Uint8Array): GovernanceAction {
    return GovernanceAction.fromFields(GovernanceAction.bcs.parse(data));
  }
}
