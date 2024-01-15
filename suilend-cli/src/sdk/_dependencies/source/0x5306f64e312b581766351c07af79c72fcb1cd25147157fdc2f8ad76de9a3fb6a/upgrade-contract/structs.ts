import {
  FieldsWithTypes,
  Type,
  compressSuiType,
} from "../../../../_framework/util";
import { ID } from "../../0x2/object/structs";
import { Bytes32 } from "../bytes32/structs";
import { bcs } from "@mysten/bcs";

/* ============================== ContractUpgraded =============================== */

export function isContractUpgraded(type: Type): boolean {
  type = compressSuiType(type);
  return (
    type ===
    "0x5306f64e312b581766351c07af79c72fcb1cd25147157fdc2f8ad76de9a3fb6a::upgrade_contract::ContractUpgraded"
  );
}

export interface ContractUpgradedFields {
  oldContract: string;
  newContract: string;
}

export class ContractUpgraded {
  static readonly $typeName =
    "0x5306f64e312b581766351c07af79c72fcb1cd25147157fdc2f8ad76de9a3fb6a::upgrade_contract::ContractUpgraded";
  static readonly $numTypeParams = 0;

  static get bcs() {
    return bcs.struct("ContractUpgraded", {
      old_contract: ID.bcs,
      new_contract: ID.bcs,
    });
  }

  readonly oldContract: string;
  readonly newContract: string;

  constructor(fields: ContractUpgradedFields) {
    this.oldContract = fields.oldContract;
    this.newContract = fields.newContract;
  }

  static fromFields(fields: Record<string, any>): ContractUpgraded {
    return new ContractUpgraded({
      oldContract: ID.fromFields(fields.old_contract).bytes,
      newContract: ID.fromFields(fields.new_contract).bytes,
    });
  }

  static fromFieldsWithTypes(item: FieldsWithTypes): ContractUpgraded {
    if (!isContractUpgraded(item.type)) {
      throw new Error("not a ContractUpgraded type");
    }
    return new ContractUpgraded({
      oldContract: item.fields.old_contract,
      newContract: item.fields.new_contract,
    });
  }

  static fromBcs(data: Uint8Array): ContractUpgraded {
    return ContractUpgraded.fromFields(ContractUpgraded.bcs.parse(data));
  }
}

/* ============================== GovernanceWitness =============================== */

export function isGovernanceWitness(type: Type): boolean {
  type = compressSuiType(type);
  return (
    type ===
    "0x5306f64e312b581766351c07af79c72fcb1cd25147157fdc2f8ad76de9a3fb6a::upgrade_contract::GovernanceWitness"
  );
}

export interface GovernanceWitnessFields {
  dummyField: boolean;
}

export class GovernanceWitness {
  static readonly $typeName =
    "0x5306f64e312b581766351c07af79c72fcb1cd25147157fdc2f8ad76de9a3fb6a::upgrade_contract::GovernanceWitness";
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

/* ============================== UpgradeContract =============================== */

export function isUpgradeContract(type: Type): boolean {
  type = compressSuiType(type);
  return (
    type ===
    "0x5306f64e312b581766351c07af79c72fcb1cd25147157fdc2f8ad76de9a3fb6a::upgrade_contract::UpgradeContract"
  );
}

export interface UpgradeContractFields {
  digest: Bytes32;
}

export class UpgradeContract {
  static readonly $typeName =
    "0x5306f64e312b581766351c07af79c72fcb1cd25147157fdc2f8ad76de9a3fb6a::upgrade_contract::UpgradeContract";
  static readonly $numTypeParams = 0;

  static get bcs() {
    return bcs.struct("UpgradeContract", {
      digest: Bytes32.bcs,
    });
  }

  readonly digest: Bytes32;

  constructor(digest: Bytes32) {
    this.digest = digest;
  }

  static fromFields(fields: Record<string, any>): UpgradeContract {
    return new UpgradeContract(Bytes32.fromFields(fields.digest));
  }

  static fromFieldsWithTypes(item: FieldsWithTypes): UpgradeContract {
    if (!isUpgradeContract(item.type)) {
      throw new Error("not a UpgradeContract type");
    }
    return new UpgradeContract(Bytes32.fromFieldsWithTypes(item.fields.digest));
  }

  static fromBcs(data: Uint8Array): UpgradeContract {
    return UpgradeContract.fromFields(UpgradeContract.bcs.parse(data));
  }
}
