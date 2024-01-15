import {
  FieldsWithTypes,
  Type,
  compressSuiType,
} from "../../../../_framework/util";
import { DataSource } from "../data-source/structs";
import { bcs } from "@mysten/bcs";

/* ============================== DataSources =============================== */

export function isDataSources(type: Type): boolean {
  type = compressSuiType(type);
  return (
    type ===
    "0x8d97f1cd6ac663735be08d1d2b6d02a159e711586461306ce60a2b7a6a565a9e::set_data_sources::DataSources"
  );
}

export interface DataSourcesFields {
  sources: Array<DataSource>;
}

export class DataSources {
  static readonly $typeName =
    "0x8d97f1cd6ac663735be08d1d2b6d02a159e711586461306ce60a2b7a6a565a9e::set_data_sources::DataSources";
  static readonly $numTypeParams = 0;

  static get bcs() {
    return bcs.struct("DataSources", {
      sources: bcs.vector(DataSource.bcs),
    });
  }

  readonly sources: Array<DataSource>;

  constructor(sources: Array<DataSource>) {
    this.sources = sources;
  }

  static fromFields(fields: Record<string, any>): DataSources {
    return new DataSources(
      fields.sources.map((item: any) => DataSource.fromFields(item))
    );
  }

  static fromFieldsWithTypes(item: FieldsWithTypes): DataSources {
    if (!isDataSources(item.type)) {
      throw new Error("not a DataSources type");
    }
    return new DataSources(
      item.fields.sources.map((item: any) =>
        DataSource.fromFieldsWithTypes(item)
      )
    );
  }

  static fromBcs(data: Uint8Array): DataSources {
    return DataSources.fromFields(DataSources.bcs.parse(data));
  }
}
