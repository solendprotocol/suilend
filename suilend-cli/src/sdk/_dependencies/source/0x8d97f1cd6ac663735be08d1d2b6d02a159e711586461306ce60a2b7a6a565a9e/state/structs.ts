import {
  FieldsWithTypes,
  Type,
  compressSuiType,
} from "../../../../_framework/util";
import { UID } from "../../0x2/object/structs";
import { UpgradeCap } from "../../0x2/package/structs";
import { ConsumedVAAs } from "../../0x5306f64e312b581766351c07af79c72fcb1cd25147157fdc2f8ad76de9a3fb6a/consumed-vaas/structs";
import { DataSource } from "../data-source/structs";
import { bcs, fromHEX, toHEX } from "@mysten/bcs";
import { SuiClient, SuiParsedData } from "@mysten/sui.js/client";

/* ============================== LatestOnly =============================== */

export function isLatestOnly(type: Type): boolean {
  type = compressSuiType(type);
  return (
    type ===
    "0x8d97f1cd6ac663735be08d1d2b6d02a159e711586461306ce60a2b7a6a565a9e::state::LatestOnly"
  );
}

export interface LatestOnlyFields {
  dummyField: boolean;
}

export class LatestOnly {
  static readonly $typeName =
    "0x8d97f1cd6ac663735be08d1d2b6d02a159e711586461306ce60a2b7a6a565a9e::state::LatestOnly";
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
    "0x8d97f1cd6ac663735be08d1d2b6d02a159e711586461306ce60a2b7a6a565a9e::state::State"
  );
}

export interface StateFields {
  id: string;
  governanceDataSource: DataSource;
  stalePriceThreshold: bigint;
  baseUpdateFee: bigint;
  feeRecipientAddress: string;
  lastExecutedGovernanceSequence: bigint;
  consumedVaas: ConsumedVAAs;
  upgradeCap: UpgradeCap;
}

export class State {
  static readonly $typeName =
    "0x8d97f1cd6ac663735be08d1d2b6d02a159e711586461306ce60a2b7a6a565a9e::state::State";
  static readonly $numTypeParams = 0;

  static get bcs() {
    return bcs.struct("State", {
      id: UID.bcs,
      governance_data_source: DataSource.bcs,
      stale_price_threshold: bcs.u64(),
      base_update_fee: bcs.u64(),
      fee_recipient_address: bcs
        .bytes(32)
        .transform({
          input: (val: string) => fromHEX(val),
          output: (val: Uint8Array) => toHEX(val),
        }),
      last_executed_governance_sequence: bcs.u64(),
      consumed_vaas: ConsumedVAAs.bcs,
      upgrade_cap: UpgradeCap.bcs,
    });
  }

  readonly id: string;
  readonly governanceDataSource: DataSource;
  readonly stalePriceThreshold: bigint;
  readonly baseUpdateFee: bigint;
  readonly feeRecipientAddress: string;
  readonly lastExecutedGovernanceSequence: bigint;
  readonly consumedVaas: ConsumedVAAs;
  readonly upgradeCap: UpgradeCap;

  constructor(fields: StateFields) {
    this.id = fields.id;
    this.governanceDataSource = fields.governanceDataSource;
    this.stalePriceThreshold = fields.stalePriceThreshold;
    this.baseUpdateFee = fields.baseUpdateFee;
    this.feeRecipientAddress = fields.feeRecipientAddress;
    this.lastExecutedGovernanceSequence = fields.lastExecutedGovernanceSequence;
    this.consumedVaas = fields.consumedVaas;
    this.upgradeCap = fields.upgradeCap;
  }

  static fromFields(fields: Record<string, any>): State {
    return new State({
      id: UID.fromFields(fields.id).id,
      governanceDataSource: DataSource.fromFields(
        fields.governance_data_source
      ),
      stalePriceThreshold: BigInt(fields.stale_price_threshold),
      baseUpdateFee: BigInt(fields.base_update_fee),
      feeRecipientAddress: `0x${fields.fee_recipient_address}`,
      lastExecutedGovernanceSequence: BigInt(
        fields.last_executed_governance_sequence
      ),
      consumedVaas: ConsumedVAAs.fromFields(fields.consumed_vaas),
      upgradeCap: UpgradeCap.fromFields(fields.upgrade_cap),
    });
  }

  static fromFieldsWithTypes(item: FieldsWithTypes): State {
    if (!isState(item.type)) {
      throw new Error("not a State type");
    }
    return new State({
      id: item.fields.id.id,
      governanceDataSource: DataSource.fromFieldsWithTypes(
        item.fields.governance_data_source
      ),
      stalePriceThreshold: BigInt(item.fields.stale_price_threshold),
      baseUpdateFee: BigInt(item.fields.base_update_fee),
      feeRecipientAddress: `0x${item.fields.fee_recipient_address}`,
      lastExecutedGovernanceSequence: BigInt(
        item.fields.last_executed_governance_sequence
      ),
      consumedVaas: ConsumedVAAs.fromFieldsWithTypes(item.fields.consumed_vaas),
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

/* ============================== CurrentDigest =============================== */

export function isCurrentDigest(type: Type): boolean {
  type = compressSuiType(type);
  return (
    type ===
    "0x8d97f1cd6ac663735be08d1d2b6d02a159e711586461306ce60a2b7a6a565a9e::state::CurrentDigest"
  );
}

export interface CurrentDigestFields {
  dummyField: boolean;
}

export class CurrentDigest {
  static readonly $typeName =
    "0x8d97f1cd6ac663735be08d1d2b6d02a159e711586461306ce60a2b7a6a565a9e::state::CurrentDigest";
  static readonly $numTypeParams = 0;

  static get bcs() {
    return bcs.struct("CurrentDigest", {
      dummy_field: bcs.bool(),
    });
  }

  readonly dummyField: boolean;

  constructor(dummyField: boolean) {
    this.dummyField = dummyField;
  }

  static fromFields(fields: Record<string, any>): CurrentDigest {
    return new CurrentDigest(fields.dummy_field);
  }

  static fromFieldsWithTypes(item: FieldsWithTypes): CurrentDigest {
    if (!isCurrentDigest(item.type)) {
      throw new Error("not a CurrentDigest type");
    }
    return new CurrentDigest(item.fields.dummy_field);
  }

  static fromBcs(data: Uint8Array): CurrentDigest {
    return CurrentDigest.fromFields(CurrentDigest.bcs.parse(data));
  }
}
