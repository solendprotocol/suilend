import {
  FieldsWithTypes,
  Type,
  compressSuiType,
} from "../../../../_framework/util";
import { UID } from "../../0x2/object/structs";
import { UpgradeCap } from "../../0x2/package/structs";
import { Table } from "../../0x2/table/structs";
import { ConsumedVAAs } from "../consumed-vaas/structs";
import { ExternalAddress } from "../external-address/structs";
import { FeeCollector } from "../fee-collector/structs";
import { bcs } from "@mysten/bcs";
import { SuiClient, SuiParsedData } from "@mysten/sui.js/client";

/* ============================== LatestOnly =============================== */

export function isLatestOnly(type: Type): boolean {
  type = compressSuiType(type);
  return (
    type ===
    "0x5306f64e312b581766351c07af79c72fcb1cd25147157fdc2f8ad76de9a3fb6a::state::LatestOnly"
  );
}

export interface LatestOnlyFields {
  dummyField: boolean;
}

export class LatestOnly {
  static readonly $typeName =
    "0x5306f64e312b581766351c07af79c72fcb1cd25147157fdc2f8ad76de9a3fb6a::state::LatestOnly";
  static readonly $numTypeParams = 0;

  static get bcs() {
    return bcs.struct("LatestOnly", {
      dummy_field: bcs.bool(),
    });
  }

  readonly dummyField: boolean;

  constructor(dummyField: boolean) {
    this.dummyField = dummyField;
  }

  static fromFields(fields: Record<string, any>): LatestOnly {
    return new LatestOnly(fields.dummy_field);
  }

  static fromFieldsWithTypes(item: FieldsWithTypes): LatestOnly {
    if (!isLatestOnly(item.type)) {
      throw new Error("not a LatestOnly type");
    }
    return new LatestOnly(item.fields.dummy_field);
  }

  static fromBcs(data: Uint8Array): LatestOnly {
    return LatestOnly.fromFields(LatestOnly.bcs.parse(data));
  }
}

/* ============================== State =============================== */

export function isState(type: Type): boolean {
  type = compressSuiType(type);
  return (
    type ===
    "0x5306f64e312b581766351c07af79c72fcb1cd25147157fdc2f8ad76de9a3fb6a::state::State"
  );
}

export interface StateFields {
  id: string;
  governanceChain: number;
  governanceContract: ExternalAddress;
  guardianSetIndex: number;
  guardianSets: Table;
  guardianSetSecondsToLive: number;
  consumedVaas: ConsumedVAAs;
  feeCollector: FeeCollector;
  upgradeCap: UpgradeCap;
}

export class State {
  static readonly $typeName =
    "0x5306f64e312b581766351c07af79c72fcb1cd25147157fdc2f8ad76de9a3fb6a::state::State";
  static readonly $numTypeParams = 0;

  static get bcs() {
    return bcs.struct("State", {
      id: UID.bcs,
      governance_chain: bcs.u16(),
      governance_contract: ExternalAddress.bcs,
      guardian_set_index: bcs.u32(),
      guardian_sets: Table.bcs,
      guardian_set_seconds_to_live: bcs.u32(),
      consumed_vaas: ConsumedVAAs.bcs,
      fee_collector: FeeCollector.bcs,
      upgrade_cap: UpgradeCap.bcs,
    });
  }

  readonly id: string;
  readonly governanceChain: number;
  readonly governanceContract: ExternalAddress;
  readonly guardianSetIndex: number;
  readonly guardianSets: Table;
  readonly guardianSetSecondsToLive: number;
  readonly consumedVaas: ConsumedVAAs;
  readonly feeCollector: FeeCollector;
  readonly upgradeCap: UpgradeCap;

  constructor(fields: StateFields) {
    this.id = fields.id;
    this.governanceChain = fields.governanceChain;
    this.governanceContract = fields.governanceContract;
    this.guardianSetIndex = fields.guardianSetIndex;
    this.guardianSets = fields.guardianSets;
    this.guardianSetSecondsToLive = fields.guardianSetSecondsToLive;
    this.consumedVaas = fields.consumedVaas;
    this.feeCollector = fields.feeCollector;
    this.upgradeCap = fields.upgradeCap;
  }

  static fromFields(fields: Record<string, any>): State {
    return new State({
      id: UID.fromFields(fields.id).id,
      governanceChain: fields.governance_chain,
      governanceContract: ExternalAddress.fromFields(
        fields.governance_contract
      ),
      guardianSetIndex: fields.guardian_set_index,
      guardianSets: Table.fromFields(
        [
          `u32`,
          `0x5306f64e312b581766351c07af79c72fcb1cd25147157fdc2f8ad76de9a3fb6a::guardian_set::GuardianSet`,
        ],
        fields.guardian_sets
      ),
      guardianSetSecondsToLive: fields.guardian_set_seconds_to_live,
      consumedVaas: ConsumedVAAs.fromFields(fields.consumed_vaas),
      feeCollector: FeeCollector.fromFields(fields.fee_collector),
      upgradeCap: UpgradeCap.fromFields(fields.upgrade_cap),
    });
  }

  static fromFieldsWithTypes(item: FieldsWithTypes): State {
    if (!isState(item.type)) {
      throw new Error("not a State type");
    }
    return new State({
      id: item.fields.id.id,
      governanceChain: item.fields.governance_chain,
      governanceContract: ExternalAddress.fromFieldsWithTypes(
        item.fields.governance_contract
      ),
      guardianSetIndex: item.fields.guardian_set_index,
      guardianSets: Table.fromFieldsWithTypes(item.fields.guardian_sets),
      guardianSetSecondsToLive: item.fields.guardian_set_seconds_to_live,
      consumedVaas: ConsumedVAAs.fromFieldsWithTypes(item.fields.consumed_vaas),
      feeCollector: FeeCollector.fromFieldsWithTypes(item.fields.fee_collector),
      upgradeCap: UpgradeCap.fromFieldsWithTypes(item.fields.upgrade_cap),
    });
  }

  static fromBcs(data: Uint8Array): State {
    return State.fromFields(State.bcs.parse(data));
  }

  static fromSuiParsedData(content: SuiParsedData) {
    if (content.dataType !== "moveObject") {
      throw new Error("not an object");
    }
    if (!isState(content.type)) {
      throw new Error(
        `object at ${(content.fields as any).id} is not a State object`
      );
    }
    return State.fromFieldsWithTypes(content);
  }

  static async fetch(client: SuiClient, id: string): Promise<State> {
    const res = await client.getObject({ id, options: { showContent: true } });
    if (res.error) {
      throw new Error(
        `error fetching State object at id ${id}: ${res.error.code}`
      );
    }
    if (
      res.data?.content?.dataType !== "moveObject" ||
      !isState(res.data.content.type)
    ) {
      throw new Error(`object at id ${id} is not a State object`);
    }
    return State.fromFieldsWithTypes(res.data.content);
  }
}
