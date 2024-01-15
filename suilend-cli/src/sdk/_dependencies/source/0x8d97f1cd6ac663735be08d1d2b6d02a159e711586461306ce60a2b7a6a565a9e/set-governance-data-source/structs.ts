import {
  FieldsWithTypes,
  Type,
  compressSuiType,
} from "../../../../_framework/util";
import { ExternalAddress } from "../../0x5306f64e312b581766351c07af79c72fcb1cd25147157fdc2f8ad76de9a3fb6a/external-address/structs";
import { bcs } from "@mysten/bcs";

/* ============================== GovernanceDataSource =============================== */

export function isGovernanceDataSource(type: Type): boolean {
  type = compressSuiType(type);
  return (
    type ===
    "0x8d97f1cd6ac663735be08d1d2b6d02a159e711586461306ce60a2b7a6a565a9e::set_governance_data_source::GovernanceDataSource"
  );
}

export interface GovernanceDataSourceFields {
  emitterChainId: bigint;
  emitterAddress: ExternalAddress;
  initialSequence: bigint;
}

export class GovernanceDataSource {
  static readonly $typeName =
    "0x8d97f1cd6ac663735be08d1d2b6d02a159e711586461306ce60a2b7a6a565a9e::set_governance_data_source::GovernanceDataSource";
  static readonly $numTypeParams = 0;

  static get bcs() {
    return bcs.struct("GovernanceDataSource", {
      emitter_chain_id: bcs.u64(),
      emitter_address: ExternalAddress.bcs,
      initial_sequence: bcs.u64(),
    });
  }

  readonly emitterChainId: bigint;
  readonly emitterAddress: ExternalAddress;
  readonly initialSequence: bigint;

  constructor(fields: GovernanceDataSourceFields) {
    this.emitterChainId = fields.emitterChainId;
    this.emitterAddress = fields.emitterAddress;
    this.initialSequence = fields.initialSequence;
  }

  static fromFields(fields: Record<string, any>): GovernanceDataSource {
    return new GovernanceDataSource({
      emitterChainId: BigInt(fields.emitter_chain_id),
      emitterAddress: ExternalAddress.fromFields(fields.emitter_address),
      initialSequence: BigInt(fields.initial_sequence),
    });
  }

  static fromFieldsWithTypes(item: FieldsWithTypes): GovernanceDataSource {
    if (!isGovernanceDataSource(item.type)) {
      throw new Error("not a GovernanceDataSource type");
    }
    return new GovernanceDataSource({
      emitterChainId: BigInt(item.fields.emitter_chain_id),
      emitterAddress: ExternalAddress.fromFieldsWithTypes(
        item.fields.emitter_address
      ),
      initialSequence: BigInt(item.fields.initial_sequence),
    });
  }

  static fromBcs(data: Uint8Array): GovernanceDataSource {
    return GovernanceDataSource.fromFields(
      GovernanceDataSource.bcs.parse(data)
    );
  }
}
