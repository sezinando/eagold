#property strict
#property version   "0.056"
#property description "EAGOLD - BUY/SELL independent machines - Rules 1 to 7"

input int    MagicNumber              = 1001;
input double Lot                      = 0.01;
input double Multiplier               = 1.10;
input int    DigitsLots               = 2;
input double LotIncrement             = 0.02;
input double MaxOpenLot               = 3.00;
input double TakeProfit               = 5.00;
input double SellProfit               = 30.00;
input double BasketLoss               = 100.00;
input int    SpreadLimit              = 100;
input int    WaitSeconds              = 0;
input double FirstStep                = 160.0;
input double MiniGrid1                = 250.0;
input double SmartGrid1               = 80.0;
input double MiniGrid2                = 80.0;
input double SmartGrid2               = 60.0;
input double PendingStepTrail         = 50.0;
input int    MaxTrades                = 2000;
input bool   EnableCloseBy            = false;
input double BuyProgressionTolerance  = 10.0;

string EA_NAME = "EAGOLD";
bool BuyInitialCycleStarted = false;
bool SellInitialCycleStarted = false;

double PointsToPrice(double points){ return(points * Point); }
double NormalizePrice(double price){ return(NormalizeDouble(price, Digits)); }
double NormalizeLot(double lot)
{
   if(lot < Lot) lot = Lot;
   if(MaxOpenLot > 0.0 && lot > MaxOpenLot) lot = MaxOpenLot;
   return(NormalizeDouble(lot, DigitsLots));
}
bool IsEAGOLDOrder(){ return(OrderSymbol() == Symbol() && OrderMagicNumber() == MagicNumber); }

int CountOrdersByType(int type)
{
   int count = 0;
   for(int i=OrdersTotal()-1; i>=0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(!IsEAGOLDOrder()) continue;
      if(OrderType() == type) count++;
   }
   return(count);
}
int CountDirectionPositions(int direction){ return(CountOrdersByType(direction == OP_BUY ? OP_BUY : OP_SELL)); }
int CountDirectionPending(int direction){ return(CountOrdersByType(direction == OP_BUY ? OP_BUYSTOP : OP_SELLSTOP)); }

double DirectionBasketProfit(int direction)
{
   int type = (direction == OP_BUY ? OP_BUY : OP_SELL);
   double total = 0.0;
   for(int i=OrdersTotal()-1; i>=0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(!IsEAGOLDOrder() || OrderType() != type) continue;
      total += OrderProfit();
   }
   return(total);
}

int SendPending(int type, double price, double lots, string comment)
{
   RefreshRates();
   double stopLevel = MarketInfo(Symbol(), MODE_STOPLEVEL) * Point;
   price = NormalizePrice(price);
   lots = NormalizeLot(lots);
   if(type == OP_BUYSTOP && price <= Ask + stopLevel) return(-1);
   if(type == OP_SELLSTOP && price >= Bid - stopLevel) return(-1);
   ResetLastError();
   int ticket = OrderSend(Symbol(), type, lots, price, 0, 0, 0, comment, MagicNumber, 0, clrNONE);
   if(ticket < 0)
      Print(EA_NAME, " OrderSend failed. type=", type, " price=", DoubleToString(price, Digits), " lot=", DoubleToString(lots, DigitsLots), " comment=", comment, " error=", GetLastError());
   else
      Print(EA_NAME, " pending created. ticket=", ticket, " type=", type, " price=", DoubleToString(price, Digits), " lot=", DoubleToString(lots, DigitsLots), " comment=", comment);
   return(ticket);
}

bool DeletePendingOrder(int ticket)
{
   if(!OrderSelect(ticket, SELECT_BY_TICKET, MODE_TRADES)) return(false);
   if(!IsEAGOLDOrder()) return(false);
   int type = OrderType();
   if(type != OP_BUYSTOP && type != OP_SELLSTOP) return(false);
   ResetLastError();
   if(!OrderDelete(ticket))
   {
      Print(EA_NAME, " pending delete failed. ticket=", ticket, " error=", GetLastError());
      return(false);
   }
   return(true);
}

bool CloseMarketOrder(int ticket)
{
   if(!OrderSelect(ticket, SELECT_BY_TICKET, MODE_TRADES)) return(false);
   if(!IsEAGOLDOrder()) return(false);
   int type = OrderType();
   if(type != OP_BUY && type != OP_SELL) return(false);
   RefreshRates();
   double price = (type == OP_BUY ? Bid : Ask);
   ResetLastError();
   if(!OrderClose(ticket, OrderLots(), NormalizePrice(price), 0, clrNONE))
   {
      Print(EA_NAME, " market close failed. ticket=", ticket, " type=", type, " error=", GetLastError());
      return(false);
   }
   return(true);
}

// ============================================================
// RULE 1 - FIRST STOP ORDERS / R1 EXCLUSIVE IDENTITY
// ============================================================
void BuyCreateFirstOrder()
{
   if(BuyInitialCycleStarted) return;
   if(CountDirectionPositions(OP_BUY) > 0) return;
   if(CountDirectionPending(OP_BUY) > 0) return;
   RefreshRates();
   int ticket = SendPending(OP_BUYSTOP, Ask + PointsToPrice(FirstStep), Lot, "EAGOLD R1 FIRST BUY");
   if(ticket > 0) BuyInitialCycleStarted = true;
}

void SellCreateFirstOrder()
{
   if(SellInitialCycleStarted) return;
   if(CountDirectionPositions(OP_SELL) > 0) return;
   if(CountDirectionPending(OP_SELL) > 0) return;
   RefreshRates();
   int ticket = SendPending(OP_SELLSTOP, Bid - PointsToPrice(FirstStep), Lot, "EAGOLD R1 FIRST SELL");
   if(ticket > 0) SellInitialCycleStarted = true;
}

// ============================================================
// RULE 2 + RULE 3 - RECOVERY
// R2 is evaluated from the LAST ACTIVATED market position.
// It does not use a pending order as the reference.
// Trigger is STRICTLY greater than 2x SmartGrid1 in the adverse
// direction. The new Recovery STOP remains 1x SmartGrid1 from
// the last activated position.
// A recovery pending is blocked only when a Recovery STOP of the
// same direction already exists; other STOP categories do not
// invalidate the R2 trigger.
// ============================================================
bool GetLatestActivatedPosition(int direction, double &latestPrice, double &latestLot, int &latestTicket)
{
   int type = (direction == OP_BUY ? OP_BUY : OP_SELL);
   latestPrice = 0.0;
   latestLot = NormalizeLot(Lot);
   latestTicket = -1;
   datetime latestTime = 0;
   bool found = false;
   for(int i=OrdersTotal()-1; i>=0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(!IsEAGOLDOrder() || OrderType() != type) continue;
      datetime t = OrderOpenTime();
      int ticket = OrderTicket();
      if(!found || t > latestTime || (t == latestTime && ticket > latestTicket))
      {
         found = true;
         latestTime = t;
         latestPrice = OrderOpenPrice();
         latestLot = OrderLots();
         latestTicket = ticket;
      }
   }
   return(found);
}

bool HasRecoveryPending(int direction)
{
   string tag = (direction == OP_BUY ? "EAGOLD BUY RECOVERY" : "EAGOLD SELL RECOVERY");
   int type = (direction == OP_BUY ? OP_BUYSTOP : OP_SELLSTOP);
   for(int i=OrdersTotal()-1; i>=0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(!IsEAGOLDOrder() || OrderType() != type) continue;
      if(StringFind(OrderComment(), tag, 0) >= 0) return(true);
   }
   return(false);
}

double NextRecoveryLot(double previousLot)
{
   if(previousLot <= 0.0) return(NormalizeLot(Lot));
   return(NormalizeLot((previousLot * Multiplier) + LotIncrement));
}

void BuyRecovery()
{
   if(SmartGrid1 <= 0.0) return;
   if(CountDirectionPositions(OP_BUY) <= 0) return;
   if(HasRecoveryPending(OP_BUY)) return;

   double lastPrice=0.0, lastLot=NormalizeLot(Lot);
   int lastTicket=-1;
   if(!GetLatestActivatedPosition(OP_BUY, lastPrice, lastLot, lastTicket)) return;

   RefreshRates();
   double trigger = lastPrice - PointsToPrice(2.0 * SmartGrid1);

   // R2 BUY: price must move strictly MORE than 2x SmartGrid1 below
   // the last activated BUY position.
   if(Bid >= trigger) return;

   double newStop = NormalizePrice(lastPrice - PointsToPrice(SmartGrid1));
   double stopLevel = MarketInfo(Symbol(), MODE_STOPLEVEL) * Point;
   if(newStop <= Ask + stopLevel)
   {
      Print(EA_NAME, " BUY R2: trigger reached but Recovery BUY STOP is invalid at current market. lastTicket=", lastTicket,
            " lastPrice=", DoubleToString(lastPrice, Digits),
            " Bid=", DoubleToString(Bid, Digits),
            " Ask=", DoubleToString(Ask, Digits),
            " stop=", DoubleToString(newStop, Digits));
      return;
   }

   double nextLot = NextRecoveryLot(lastLot);
   Print(EA_NAME, " BUY R2/R3 AUTHORIZED. lastTicket=", lastTicket,
         " lastPrice=", DoubleToString(lastPrice, Digits),
         " lastLot=", DoubleToString(lastLot, DigitsLots),
         " trigger=", DoubleToString(trigger, Digits),
         " Bid=", DoubleToString(Bid, Digits),
         " stop=", DoubleToString(newStop, Digits),
         " nextLot=", DoubleToString(nextLot, DigitsLots));
   SendPending(OP_BUYSTOP, newStop, nextLot, "EAGOLD BUY RECOVERY");
}

void SellRecovery()
{
   if(SmartGrid1 <= 0.0) return;
   if(CountDirectionPositions(OP_SELL) <= 0) return;
   if(HasRecoveryPending(OP_SELL)) return;

   double lastPrice=0.0, lastLot=NormalizeLot(Lot);
   int lastTicket=-1;
   if(!GetLatestActivatedPosition(OP_SELL, lastPrice, lastLot, lastTicket)) return;

   RefreshRates();
   double trigger = lastPrice + PointsToPrice(2.0 * SmartGrid1);

   // R2 SELL: price must move strictly MORE than 2x SmartGrid1 above
   // the last activated SELL position.
   if(Ask <= trigger) return;

   double newStop = NormalizePrice(lastPrice + PointsToPrice(SmartGrid1));
   double stopLevel = MarketInfo(Symbol(), MODE_STOPLEVEL) * Point;
   if(newStop >= Bid - stopLevel)
   {
      Print(EA_NAME, " SELL R2: trigger reached but Recovery SELL STOP is invalid at current market. lastTicket=", lastTicket,
            " lastPrice=", DoubleToString(lastPrice, Digits),
            " Bid=", DoubleToString(Bid, Digits),
            " Ask=", DoubleToString(Ask, Digits),
            " stop=", DoubleToString(newStop, Digits));
      return;
   }

   double nextLot = NextRecoveryLot(lastLot);
   Print(EA_NAME, " SELL R2/R3 AUTHORIZED. lastTicket=", lastTicket,
         " lastPrice=", DoubleToString(lastPrice, Digits),
         " lastLot=", DoubleToString(lastLot, DigitsLots),
         " trigger=", DoubleToString(trigger, Digits),
         " Ask=", DoubleToString(Ask, Digits),
         " stop=", DoubleToString(newStop, Digits),
         " nextLot=", DoubleToString(nextLot, DigitsLots));
   SendPending(OP_SELLSTOP, newStop, nextLot, "EAGOLD SELL RECOVERY");
}

// ============================================================
// RULE 6 - TRAILING OF RECOVERY STOP ORDERS ONLY
// ============================================================
void TrailRecoveryStopOrders()
{
   if(SmartGrid1 <= 0.0 || PendingStepTrail <= 0.0) return;
   double trailDistance = PointsToPrice(2.0 * SmartGrid1);
   double trailStep = PointsToPrice(PendingStepTrail);
   double stopLevel = MarketInfo(Symbol(), MODE_STOPLEVEL) * Point;

   for(int i=OrdersTotal()-1; i>=0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(!IsEAGOLDOrder()) continue;
      int type = OrderType();
      if(type != OP_BUYSTOP && type != OP_SELLSTOP) continue;
      string comment = OrderComment();
      if(StringFind(comment, "EAGOLD BUY RECOVERY", 0) < 0 && StringFind(comment, "EAGOLD SELL RECOVERY", 0) < 0) continue;
      RefreshRates();
      double current = OrderOpenPrice();
      double desired = current;
      double movement = 0.0;
      if(type == OP_SELLSTOP)
      {
         double distance = Bid - current;
         if(distance <= trailDistance) continue;
         desired = NormalizePrice(Bid - trailDistance);
         movement = desired - current;
         if(movement < trailStep || desired <= current || desired >= Bid - stopLevel) continue;
      }
      else
      {
         double distance = current - Ask;
         if(distance <= trailDistance) continue;
         desired = NormalizePrice(Ask + trailDistance);
         movement = current - desired;
         if(movement < trailStep || desired >= current || desired <= Ask + stopLevel) continue;
      }
      int ticket = OrderTicket();
      ResetLastError();
      if(!OrderModify(ticket, desired, 0, 0, 0, clrNONE))
         Print(EA_NAME, " RULE 6: STOP TRAIL FAILED. ticket=", ticket, " error=", GetLastError());
      else
         Print(EA_NAME, " RULE 6: STOP TRAIL. ticket=", ticket, " from=", DoubleToString(current, Digits), " to=", DoubleToString(desired, Digits));
   }
}

// ============================================================
// RULE 7 - TRAILING OF R1 FIRST STOP ORDERS
// ============================================================
void TrailR1FirstStopOrders()
{
   if(FirstStep <= 0.0 || PendingStepTrail <= 0.0) return;
   double trailDistance = PointsToPrice(FirstStep);
   double trailStep = PointsToPrice(PendingStepTrail);
   double activationDistance = trailDistance + trailStep;
   double stopLevel = MarketInfo(Symbol(), MODE_STOPLEVEL) * Point;

   for(int i=OrdersTotal()-1; i>=0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(!IsEAGOLDOrder()) continue;
      int type = OrderType();
      if(type != OP_BUYSTOP && type != OP_SELLSTOP) continue;
      string comment = OrderComment();
      if(type == OP_BUYSTOP && StringFind(comment, "EAGOLD R1 FIRST BUY", 0) < 0) continue;
      if(type == OP_SELLSTOP && StringFind(comment, "EAGOLD R1 FIRST SELL", 0) < 0) continue;
      RefreshRates();
      double current = OrderOpenPrice();
      double desired = current;
      double movement = 0.0;
      if(type == OP_SELLSTOP)
      {
         double distance = Bid - current;
         if(distance < activationDistance) continue;
         desired = NormalizePrice(Bid - trailDistance);
         movement = desired - current;
         if(movement < trailStep || desired <= current || desired >= Bid - stopLevel) continue;
      }
      else
      {
         double distance = current - Ask;
         if(distance < activationDistance) continue;
         desired = NormalizePrice(Ask + trailDistance);
         movement = current - desired;
         if(movement < trailStep || desired >= current || desired <= Ask + stopLevel) continue;
      }
      int ticket = OrderTicket();
      ResetLastError();
      if(!OrderModify(ticket, desired, 0, 0, 0, clrNONE))
         Print(EA_NAME, " RULE 7: R1 FIRST STOP TRAIL FAILED. ticket=", ticket, " error=", GetLastError());
      else
         Print(EA_NAME, " RULE 7: R1 FIRST STOP TRAIL. ticket=", ticket, " from=", DoubleToString(current, Digits), " to=", DoubleToString(desired, Digits));
   }
}

// ============================================================
// RULE 4 - SINGLE POSITION TAKE PROFIT + REENTRY
// ============================================================
void BuyCreateReentryAfterSingleTP(){ RefreshRates(); SendPending(OP_BUYSTOP, Ask + PointsToPrice(MiniGrid1), Lot, "EAGOLD BUY TP REENTRY"); }
void SellCreateReentryAfterSingleTP(){ RefreshRates(); SendPending(OP_SELLSTOP, Bid - PointsToPrice(MiniGrid1), Lot, "EAGOLD SELL TP REENTRY"); }

void BuySingleTakeProfit()
{
   if(TakeProfit <= 0.0 || CountDirectionPositions(OP_BUY) != 1) return;
   for(int i=OrdersTotal()-1; i>=0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(!IsEAGOLDOrder() || OrderType() != OP_BUY) continue;
      double profit = OrderProfit();
      if(profit < TakeProfit) continue;
      int ticket = OrderTicket();
      if(CloseMarketOrder(ticket))
      {
         Print(EA_NAME, " BUY RULE 4: TakeProfit reached. ticket=", ticket, " profit=", DoubleToString(profit, 2));
         BuyCreateReentryAfterSingleTP();
      }
      break;
   }
}

void SellSingleTakeProfit()
{
   if(TakeProfit <= 0.0 || CountDirectionPositions(OP_SELL) != 1) return;
   for(int i=OrdersTotal()-1; i>=0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(!IsEAGOLDOrder() || OrderType() != OP_SELL) continue;
      double profit = OrderProfit();
      if(profit < TakeProfit) continue;
      int ticket = OrderTicket();
      if(CloseMarketOrder(ticket))
      {
         Print(EA_NAME, " SELL RULE 4: TakeProfit reached. ticket=", ticket, " profit=", DoubleToString(profit, 2));
         SellCreateReentryAfterSingleTP();
      }
      break;
   }
}

// ============================================================
// RULE 5 - BASKET CLOSE
// ============================================================
bool CloseAllDirectionPending(int direction)
{
   int type = (direction == OP_BUY ? OP_BUYSTOP : OP_SELLSTOP);
   bool ok = true;
   for(int i=OrdersTotal()-1; i>=0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(!IsEAGOLDOrder() || OrderType() != type) continue;
      if(!DeletePendingOrder(OrderTicket())) ok = false;
   }
   return(ok);
}

void BuyBasketClose()
{
   int count = CountDirectionPositions(OP_BUY);
   if(count <= 1 || TakeProfit <= 0.0) return;
   double target = count * TakeProfit;
   if(DirectionBasketProfit(OP_BUY) < target) return;
   Print(EA_NAME, " BUY RULE 5: basket target reached. count=", count, " target=", DoubleToString(target, 2));
   for(int i=OrdersTotal()-1; i>=0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(!IsEAGOLDOrder() || OrderType() != OP_BUY) continue;
      CloseMarketOrder(OrderTicket());
   }
   CloseAllDirectionPending(OP_BUY);
}

void SellBasketClose()
{
   int count = CountDirectionPositions(OP_SELL);
   if(count <= 1 || TakeProfit <= 0.0) return;
   double target = count * TakeProfit;
   if(DirectionBasketProfit(OP_SELL) < target) return;
   Print(EA_NAME, " SELL RULE 5: basket target reached. count=", count, " target=", DoubleToString(target, 2));
   for(int i=OrdersTotal()-1; i>=0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(!IsEAGOLDOrder() || OrderType() != OP_SELL) continue;
      CloseMarketOrder(OrderTicket());
   }
   CloseAllDirectionPending(OP_SELL);
}

void BuyMachine(){ BuyBasketClose(); BuySingleTakeProfit(); BuyRecovery(); BuyCreateFirstOrder(); }
void SellMachine(){ SellBasketClose(); SellSingleTakeProfit(); SellRecovery(); SellCreateFirstOrder(); }

int OnInit()
{
   Print(EA_NAME, " v0.056 initialized. R1 unchanged; R2 uses last activated position and strict >2x SmartGrid1 trigger; R6 unchanged; R7 unchanged. Multiplier=", DoubleToString(Multiplier,2), " LotIncrement=", DoubleToString(LotIncrement,DigitsLots));
   BuyCreateFirstOrder();
   SellCreateFirstOrder();
   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason){}

void OnTick()
{
   BuyMachine();
   SellMachine();
   TrailRecoveryStopOrders();
   TrailR1FirstStopOrders();
}
