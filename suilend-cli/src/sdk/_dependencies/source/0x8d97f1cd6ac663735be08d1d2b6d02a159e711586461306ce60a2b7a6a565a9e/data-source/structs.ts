import {
  FieldsWithTypes,
  Type,
  compressSuiType,
} from "../../../../_framework/util";
import { ExternalAddress } from "../../0x5306f64e312b581766351c07af79c72fcb1cd25147157fdc2f8ad76de9a3fb6a/external-address/structs";
import { bcs } from "@mysten/bcs";

/* ============================== DataSource =============================== */

export function isDataSource(type: Type): boolean {
  type = compressSuiType(type);
  return (
    type ===
    "0x8d97f1cd6ac663735be08d1d2b6d02a159e711586461306ce60a2b7a6a565a9e::data_source::DataSource"
  );
}

export interface DataSourceFields {
  emitterChain: bigint;
  emitterAddress: ExternalAddress;
}

export class DataSource {
  static readonly $typeName =
    "0x8d97f1cd6ac663735be08d1d2b6d02a159e711586461306ce60a2b7a6a565a9e::data_source::DataSource";
  static readonly $numTypeParams = 0;

  static get bcs() {
    return bcs.struct("DataSource", {
      emitter_chain: bcs.u64(),
      emitter_address: ExternalAddress.bcs,
    });
  }

  readonly emitterChain: bigint;
  readonly emitterAddress: ExternalAddress;

  constructor(fields: DataSourceFields) {
    this.emitterChain = fields.emitterChain;
    this.emitterAddress = fields.emitterAddress;
  }

  static fromFields(fields: Record<string, any>): DataSource {
    return new DataSource({
      emitterChain: BigInt(fields.emitter_chain),
      emitterAddress: ExternalAddress.fromFields(fields.emitter_address),
    });
  }

  static fromFieldsWithTypes(item: FieldsWithTypes): DataSource {
    if (!isDataSource(item.type)) {
      throw new Error("not a DataSource type");
    }
    return new DataSource({
      emitterChain: BigInt(item.fields.emitter_chain),
      emitterAddress: ExternalAddress.fromFieldsWithTypes(
        item.fields.emitter_address
      ),
    });
  }

  static fromBcs(data: Uint8Array): DataSource {
    return DataSource.fromFields(DataSource.bcs.parse(data));
  }
}
