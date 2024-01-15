import {
  FieldsWithTypes,
  Type,
  compressSuiType,
} from "../../../../_framework/util";
import { Guardian } from "../guardian/structs";
import { bcs } from "@mysten/bcs";

/* ============================== GovernanceWitness =============================== */

export function isGovernanceWitness(type: Type): boolean {
  type = compressSuiType(type);
  return (
    type ===
    "0x5306f64e312b581766351c07af79c72fcb1cd25147157fdc2f8ad76de9a3fb6a::update_guardian_set::GovernanceWitness"
  );
}

export interface GovernanceWitnessFields {
  dummyField: boolean;
}

export class GovernanceWitness {
  static readonly $typeName =
    "0x5306f64e312b581766351c07af79c72fcb1cd25147157fdc2f8ad76de9a3fb6a::update_guardian_set::GovernanceWitness";
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

/* ============================== GuardianSetAdded =============================== */

export function isGuardianSetAdded(type: Type): boolean {
  type = compressSuiType(type);
  return (
    type ===
    "0x5306f64e312b581766351c07af79c72fcb1cd25147157fdc2f8ad76de9a3fb6a::update_guardian_set::GuardianSetAdded"
  );
}

export interface GuardianSetAddedFields {
  newIndex: number;
}

export class GuardianSetAdded {
  static readonly $typeName =
    "0x5306f64e312b581766351c07af79c72fcb1cd25147157fdc2f8ad76de9a3fb6a::update_guardian_set::GuardianSetAdded";
  static readonly $numTypeParams = 0;

  static get bcs() {
    return bcs.struct("GuardianSetAdded", {
      new_index: bcs.u32(),
    });
  }

  readonly newIndex: number;

  constructor(newIndex: number) {
    this.newIndex = newIndex;
  }

  static fromFields(fields: Record<string, any>): GuardianSetAdded {
    return new GuardianSetAdded(fields.new_index);
  }

  static fromFieldsWithTypes(item: FieldsWithTypes): GuardianSetAdded {
    if (!isGuardianSetAdded(item.type)) {
      throw new Error("not a GuardianSetAdded type");
    }
    return new GuardianSetAdded(item.fields.new_index);
  }

  static fromBcs(data: Uint8Array): GuardianSetAdded {
    return GuardianSetAdded.fromFields(GuardianSetAdded.bcs.parse(data));
  }
}

/* ============================== UpdateGuardianSet =============================== */

export function isUpdateGuardianSet(type: Type): boolean {
  type = compressSuiType(type);
  return (
    type ===
    "0x5306f64e312b581766351c07af79c72fcb1cd25147157fdc2f8ad76de9a3fb6a::update_guardian_set::UpdateGuardianSet"
  );
}

export interface UpdateGuardianSetFields {
  newIndex: number;
  guardians: Array<Guardian>;
}

export class UpdateGuardianSet {
  static readonly $typeName =
    "0x5306f64e312b581766351c07af79c72fcb1cd25147157fdc2f8ad76de9a3fb6a::update_guardian_set::UpdateGuardianSet";
  static readonly $numTypeParams = 0;

  static get bcs() {
    return bcs.struct("UpdateGuardianSet", {
      new_index: bcs.u32(),
      guardians: bcs.vector(Guardian.bcs),
    });
  }

  readonly newIndex: number;
  readonly guardians: Array<Guardian>;

  constructor(fields: UpdateGuardianSetFields) {
    this.newIndex = fields.newIndex;
    this.guardians = fields.guardians;
  }

  static fromFields(fields: Record<string, any>): UpdateGuardianSet {
    return new UpdateGuardianSet({
      newIndex: fields.new_index,
      guardians: fields.guardians.map((item: any) => Guardian.fromFields(item)),
    });
  }

  static fromFieldsWithTypes(item: FieldsWithTypes): UpdateGuardianSet {
    if (!isUpdateGuardianSet(item.type)) {
      throw new Error("not a UpdateGuardianSet type");
    }
    return new UpdateGuardianSet({
      newIndex: item.fields.new_index,
      guardians: item.fields.guardians.map((item: any) =>
        Guardian.fromFieldsWithTypes(item)
      ),
    });
  }

  static fromBcs(data: Uint8Array): UpdateGuardianSet {
    return UpdateGuardianSet.fromFields(UpdateGuardianSet.bcs.parse(data));
  }
}
