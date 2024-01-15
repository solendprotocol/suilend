import * as decimal from "./decimal/structs";
import * as lendingMarket from "./lending-market/structs";
import * as obligation from "./obligation/structs";
import * as reserve from "./reserve/structs";
import { StructClassLoader } from "../_framework/loader";

export function registerClasses(loader: StructClassLoader) {
  loader.register(decimal.Decimal);
  loader.register(reserve.Price);
  loader.register(reserve.CToken);
  loader.register(reserve.InterestRateModel);
  loader.register(reserve.Reserve);
  loader.register(reserve.ReserveConfig);
  loader.register(reserve.ReserveTreasury);
  loader.register(obligation.Borrow);
  loader.register(obligation.Deposit);
  loader.register(obligation.Key);
  loader.register(obligation.Obligation);
  loader.register(obligation.RefreshedTicket);
  loader.register(lendingMarket.Name);
  loader.register(lendingMarket.LendingMarket);
  loader.register(lendingMarket.LendingMarketOwnerCap);
  loader.register(lendingMarket.ObligationOwnerCap);
}
